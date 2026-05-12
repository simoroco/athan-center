#!/usr/bin/env bash

# Athan Center - Unified launcher
# - On local workstation (macOS / non-RPi Linux / Windows): runs Node directly.
#   Falls back to Docker if local launch fails.
# - On production (Raspberry Pi 5 / RPi family): runs via Docker Compose.
# Cleans up any previous session, then opens the browser on the access URL.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
HTTP_PORT=7777
HTTPS_PORT=7778
WAIT_TIMEOUT=45
PID_FILE="$SCRIPT_DIR/.athan-center.pid"
LOG_FILE="$SCRIPT_DIR/.athan-center.log"

OS="$(uname -s)"

color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
info()  { color "1;36" "ℹ️  $1"; }
ok()    { color "1;32" "✅ $1"; }
warn()  { color "1;33" "⚠️  $1"; }
err()   { color "1;31" "❌ $1"; }

# ---------- detection ----------

is_raspberry_pi() {
    if [ -r /proc/device-tree/model ]; then
        grep -qi "raspberry pi" /proc/device-tree/model && return 0
    fi
    if [ -r /proc/cpuinfo ]; then
        grep -qi "raspberry pi\|bcm2" /proc/cpuinfo && return 0
    fi
    return 1
}

detect_lan_ip() {
    case "$OS" in
        Darwin)
            ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1
            ;;
        Linux)
            if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
                hostname -I | awk '{print $1}'
            else
                ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127/ {sub("/.*","",$2); print $2; exit}'
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# ---------- cleanup ----------

kill_port() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        local pids
        pids=$(lsof -ti tcp:"$port" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            info "Killing process(es) listening on :$port → $pids"
            # shellcheck disable=SC2086
            kill -9 $pids 2>/dev/null || true
        fi
    elif command -v fuser >/dev/null 2>&1; then
        fuser -k "${port}/tcp" 2>/dev/null || true
    fi
}

cleanup_previous() {
    info "Cleaning up previous session..."

    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            info "Stopping previous Node process (PID $old_pid)..."
            kill -9 "$old_pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi

    kill_port "$HTTP_PORT"
    kill_port "$HTTPS_PORT"

    if command -v docker >/dev/null 2>&1; then
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^athan-center$'; then
            info "Stopping existing 'athan-center' Docker container..."
            (cd "$SCRIPT_DIR" && (docker compose down >/dev/null 2>&1 || docker-compose down >/dev/null 2>&1)) || true
            docker rm -f athan-center >/dev/null 2>&1 || true
        fi
    fi

    ok "Cleanup done."
}

# ---------- wait / browser ----------

wait_ready() {
    info "Waiting for HTTP server on :$HTTP_PORT (timeout ${WAIT_TIMEOUT}s)..."
    local elapsed=0
    while [ "$elapsed" -lt "$WAIT_TIMEOUT" ]; do
        if curl -sf -o /dev/null --max-time 2 "http://localhost:${HTTP_PORT}/"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

open_browser() {
    local url="$1"
    case "$OS" in
        Darwin) open "$url" >/dev/null 2>&1 || true ;;
        Linux)
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$url" >/dev/null 2>&1 || true
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) start "" "$url" >/dev/null 2>&1 || true ;;
    esac
}

print_access() {
    local lan_ip
    lan_ip="$(detect_lan_ip)"
    local local_url="http://localhost:${HTTP_PORT}"
    echo
    color "1;32" "🕌 Athan Center is up"
    echo "   Local:   $local_url"
    if [ -n "$lan_ip" ]; then
        echo "   Network: http://${lan_ip}:${HTTP_PORT}"
    fi
    echo "   Logs:    $LOG_FILE"
    echo
}

# ---------- launchers ----------

ensure_deps() {
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not found in PATH."
        return 1
    fi

    local missing
    missing=$(cd "$APP_DIR" && node -e '
        const pkg = require("./package.json");
        const fs = require("fs");
        const path = require("path");
        const missing = Object.keys(pkg.dependencies || {})
            .filter(d => !fs.existsSync(path.join("node_modules", d, "package.json")));
        console.log(missing.join(" "));
    ' 2>/dev/null || echo "ALL")

    if [ "$missing" = "ALL" ] || [ -n "$missing" ]; then
        if [ "$missing" = "ALL" ]; then
            info "Installing npm dependencies (no node_modules)..."
        else
            info "Installing missing npm dependencies: $missing"
        fi
        (cd "$APP_DIR" && npm install --no-audit --no-fund) || return 1
    fi

    # Check native modules (better-sqlite3) ABI matches current Node
    # Must instantiate to actually load the .node binding (require alone is lazy)
    local native_check
    native_check=$(cd "$APP_DIR" && node -e 'try { const D = require("better-sqlite3"); new D(":memory:"); console.log("OK"); } catch (e) { console.log(e.code || e.message); }' 2>&1)
    if [ "$native_check" != "OK" ]; then
        info "Rebuilding native modules for current Node version..."
        (cd "$APP_DIR" && npm rebuild better-sqlite3 --no-audit --no-fund) || {
            warn "npm rebuild failed, trying full reinstall..."
            (cd "$APP_DIR" && rm -rf node_modules/better-sqlite3 && npm install better-sqlite3 --no-audit --no-fund) || return 1
        }
    fi
    return 0
}

start_local() {
    info "Starting in LOCAL mode (Node.js, no Docker)..."

    if ! command -v node >/dev/null 2>&1; then
        warn "Node.js not found in PATH."
        return 1
    fi

    ensure_deps || return 1

    : > "$LOG_FILE"
    (cd "$APP_DIR" && nohup node server.js >> "$LOG_FILE" 2>&1 & echo $! > "$PID_FILE")

    # Give Node a moment to crash on startup errors (missing module, port busy...)
    sleep 2

    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        err "Local Node process exited immediately. Tail of log:"
        tail -n 20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
        rm -f "$PID_FILE"
        return 1
    fi

    if ! wait_ready; then
        err "Local server did not respond in time. Tail of log:"
        tail -n 20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        return 1
    fi

    ok "Local mode running (PID $pid)."
    return 0
}

start_docker() {
    info "Starting in DOCKER mode..."

    if ! command -v docker >/dev/null 2>&1; then
        err "Docker is not installed. Cannot start in Docker mode."
        return 1
    fi

    local compose_cmd=""
    if docker compose version >/dev/null 2>&1; then
        compose_cmd="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
    else
        err "docker compose / docker-compose not available."
        return 1
    fi

    if [ "$OS" = "Linux" ]; then
        export NETWORK_MODE=host
    else
        export NETWORK_MODE=bridge
        if [ "$OS" = "Darwin" ]; then
            export HOST_HOSTNAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
        else
            export HOST_HOSTNAME="$(hostname)"
        fi
        export HOST_IP="$(detect_lan_ip)"
        [ -z "$HOST_IP" ] && export HOST_IP="host.docker.internal"
    fi

    (cd "$SCRIPT_DIR" && $compose_cmd up -d) || return 1

    if ! wait_ready; then
        err "Docker container did not respond in time. Check: $compose_cmd logs"
        return 1
    fi

    ok "Docker mode running."
    return 0
}

# ---------- main ----------

cd "$SCRIPT_DIR"
cleanup_previous

USE_DOCKER=0
if is_raspberry_pi; then
    info "Raspberry Pi detected → production mode (Docker)."
    USE_DOCKER=1
else
    info "Local workstation detected ($OS) → trying local Node first."
fi

started=0
if [ "$USE_DOCKER" -eq 0 ]; then
    if start_local; then
        started=1
    else
        warn "Local launch failed, falling back to Docker..."
        cleanup_previous
    fi
fi

if [ "$started" -eq 0 ]; then
    if start_docker; then
        started=1
    fi
fi

if [ "$started" -eq 0 ]; then
    err "Athan Center failed to start in both local and Docker modes."
    exit 1
fi

ACCESS_URL="http://localhost:${HTTP_PORT}"
print_access
open_browser "$ACCESS_URL"
