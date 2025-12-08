#!/usr/bin/env bash

# Athan Center - Multi-OS Deployment Script
# Automatically detects OS and configures network mode and host information

set -e

echo "🕌 Athan Center - Starting deployment..."
echo ""

# Detect OS
OS=$(uname -s)
echo "🔍 Detected OS: $OS"

if [ "$OS" = "Linux" ]; then
    # ===== LINUX MODE =====
    echo "✅ Linux detected - using host network mode"
    echo ""
    
    # Use host network mode for best performance
    export NETWORK_MODE=host
    
    # Optional: Let the container auto-detect from host interfaces
    # Or you can uncomment these to explicitly set values:
    # export HOST_HOSTNAME=$(hostname)
    # export HOST_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || echo "")
    
    echo "📋 Configuration:"
    echo "   Network mode: host"
    echo "   IP detection: automatic (from host network interfaces)"
    echo ""
    
else
    # ===== macOS / Windows MODE =====
    echo "✅ macOS/Windows detected - using bridge network mode"
    echo ""
    
    # Use bridge network mode (Docker Desktop requirement)
    export NETWORK_MODE=bridge
    
    # Detect hostname
    if [ "$OS" = "Darwin" ]; then
        # macOS
        HOST_HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
    else
        # Windows (Git Bash, WSL, etc.)
        HOST_HOSTNAME=$(hostname)
    fi
    
    # Detect IP address
    if [ "$OS" = "Darwin" ]; then
        # macOS - get first non-loopback IPv4
        HOST_IP=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
    else
        # Windows/WSL - try multiple methods
        HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [ -z "$HOST_IP" ]; then
            HOST_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1 | head -1)
        fi
    fi
    
    # Fallback if detection failed
    if [ -z "$HOST_IP" ]; then
        HOST_IP="host.docker.internal"
        echo "⚠️  Could not detect IP, using fallback: $HOST_IP"
    fi
    
    export HOST_HOSTNAME
    export HOST_IP
    
    echo "📋 Configuration:"
    echo "   Network mode: bridge"
    echo "   Hostname: $HOST_HOSTNAME"
    echo "   IP Address: $HOST_IP"
    echo ""
fi

# Start Docker Compose
echo "🚀 Starting Docker container..."
docker-compose up -d

echo ""
echo "✅ Athan Center started successfully!"
echo ""

if [ "$OS" = "Linux" ]; then
    echo "📱 Access the web interface:"
    echo "   Local:  http://localhost:7777"
    echo "   Network: http://$(hostname -I | awk '{print $1}'):7777"
else
    echo "📱 Access the web interface:"
    echo "   Local:  http://localhost:7777"
    echo "   Network: http://$HOST_IP:7777"
fi

echo ""
echo "📊 View logs: docker-compose logs -f"
echo "🛑 Stop: docker-compose down"
echo ""
