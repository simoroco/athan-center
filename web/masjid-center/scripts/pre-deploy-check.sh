#!/bin/bash

# Pre-deployment verification script
# Checks that everything is in place before deploying

echo "🔍 Masjid Center Pre-Deployment Check"
echo "============================================="
echo ""

# Counters
ERRORS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check function
check() {
    local test_name=$1
    local test_cmd=$2
    
    echo -n "Checking: $test_name... "
    
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

warn() {
    local msg=$1
    echo -e "${YELLOW}⚠ WARNING:${NC} $msg"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    local msg=$1
    echo -e "${GREEN}ℹ${NC} $msg"
}

# Separator
section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 1. Dependency checks
section "1. System Dependencies"

check "Docker installed" "command -v docker"
check "Docker Compose installed" "command -v docker-compose"
check "Git installed" "command -v git"
check "Node.js installed" "command -v node"
check "npm installed" "command -v npm"

# 2. File checks
section "2. Main Files"

check "server.js exists" "test -f server.js"
check "package.json exists" "test -f package.json"
check "Dockerfile exists" "test -f Dockerfile"
check "docker-compose.yml exists" "test -f docker-compose.yml"
check "public/index.html exists" "test -f public/index.html"
check "public/styles.css exists" "test -f public/styles.css"
check "public/app.js exists" "test -f public/app.js"

# 3. Folder checks
section "3. Folder Structure"

check "audio/ folder exists" "test -d audio"
check "data/ folder exists" "test -d data"
check "public/ folder exists" "test -d public"

# 4. Audio checks
section "4. Audio Configuration"

if ls audio/*.mp3 >/dev/null 2>&1 || ls audio/*.wav >/dev/null 2>&1; then
    info "Audio files found:"
    ls -lh audio/*.mp3 audio/*.wav 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
else
    warn "No audio file found in audio/"
    echo "  Download an athan.mp3 file and place it in audio/"
fi

# 5. Permission checks
section "5. Permissions"

check "setup.sh executable" "test -x setup.sh"
check "test-api.sh executable" "test -x test-api.sh"
check "download-athan.sh executable" "test -x download-athan.sh"

# 6. Docker checks
section "6. Docker Configuration"

check "Docker daemon active" "docker ps"
check "Port 7777 available" "! lsof -i :7777"

# 7. Syntax checks
section "7. Syntax Validation"

if command -v node > /dev/null; then
    check "server.js syntax valid" "node -c server.js"
    check "app.js syntax valid" "node -c public/app.js"
fi

# 8. Network checks
section "8. Network Configuration"

info "Local IP address: $(hostname -I | awk '{print $1}')"
info "Hostname: $(hostname)"

# 9. System checks
section "9. System Resources"

if command -v free > /dev/null; then
    TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
    AVAILABLE_MEM=$(free -h | grep Mem | awk '{print $7}')
    info "Total memory: $TOTAL_MEM"
    info "Available memory: $AVAILABLE_MEM"
fi

if command -v df > /dev/null; then
    DISK_AVAILABLE=$(df -h . | tail -1 | awk '{print $4}')
    info "Available disk space: $DISK_AVAILABLE"
fi

# 10. Audio device checks
section "10. Audio Devices"

if test -e /dev/snd; then
    info "Audio devices detected:"
    ls -la /dev/snd/ | tail -n +4 | awk '{print "  - " $9}'
    
    if command -v aplay > /dev/null; then
        check "ALSA functional" "aplay -l"
    else
        warn "aplay not installed (optional)"
    fi
else
    warn "No audio device detected (/dev/snd)"
fi

# 11. Documentation
section "11. Documentation"

DOCS=("README.md" "QUICKSTART.md" "AUDIO_SETUP.md" "DEPLOYMENT.md" "TROUBLESHOOTING.md")
for doc in "${DOCS[@]}"; do
    check "Documentation $doc" "test -f $doc"
done

# Final summary
section "📊 Summary"

echo ""
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Everything is ready for deployment!${NC}"
    echo ""
    echo "Deployment commands:"
    echo "  docker-compose up -d        # Start the application"
    echo "  make start                  # Or with make"
    echo "  ./setup.sh                  # Or with the install script"
    echo ""
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Ready with $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can deploy, but review the warnings above."
    echo ""
else
    echo -e "${RED}✗ $ERRORS error(s) detected${NC}"
    echo -e "${YELLOW}⚠ $WARNINGS warning(s)${NC}"
    echo ""
    echo "Fix the errors before deploying."
    echo ""
    exit 1
fi

echo "For more help, see:"
echo "  - README.md for full documentation"
echo "  - QUICKSTART.md for a quick guide"
echo "  - TROUBLESHOOTING.md if you run into issues"
echo ""
