#!/bin/bash

# Automatic installation script for Masjid Center
# For Raspberry Pi 5

set -e

echo "🕌 Masjid Center Installation"
echo "================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions for messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed
info "Checking Docker..."
if ! command -v docker &> /dev/null; then
    warn "Docker is not installed. Installing..."
    curl -sSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    info "Docker installed successfully"
    warn "You must restart your session for the changes to take effect"
    warn "Run 'newgrp docker' or log out and back in"
else
    info "Docker is already installed"
fi

# Check Docker Compose
info "Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    warn "Docker Compose is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y docker-compose
    info "Docker Compose installed successfully"
else
    info "Docker Compose is already installed"
fi

# Create required directories
info "Creating directories..."
mkdir -p data audio

# Check if an audio file exists
if [ ! "$(ls -A audio/*.mp3 2>/dev/null)" ]; then
    warn "No audio file found in the audio/ folder"
    echo ""
    echo "Do you want to download a default athan file? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Downloading Makkah athan..."
        # Note: Replace this URL with a valid one
        warn "Please download an athan file manually and place it in audio/"
        warn "Recommended sources:"
        echo "  - https://www.islamicfinder.org/islamic-audio/"
        echo "  - Search for 'Adhan Makkah' on YouTube and convert to MP3"
    fi
fi

# Check audio permissions
info "Checking audio permissions..."
if ! groups $USER | grep -q '\baudio\b'; then
    warn "Adding user to the audio group..."
    sudo usermod -aG audio $USER
    warn "You must restart your session for the changes to take effect"
fi

# Timezone configuration
info "Timezone configuration..."
echo "Current timezone: $(timedatectl | grep "Time zone" | awk '{print $3}')"
echo "Is this correct? (y/n)"
read -r tz_response
if [[ ! "$tz_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Enter your timezone (e.g. Europe/Paris):"
    read -r timezone
    if [ ! -z "$timezone" ]; then
        sed -i "s|TZ=.*|TZ=$timezone|" docker-compose.yml
        info "Timezone updated: $timezone"
    fi
fi

# Build and start the container
info "Building and starting the Docker container..."
if docker-compose up -d --build; then
    info "Container started successfully!"
else
    error "Error while starting the container"
    exit 1
fi

# Wait for the server to start
info "Waiting for the server to start..."
sleep 5

# Check if the container is running
if docker ps | grep -q masjid-center; then
    info "✅ The application is running!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Installation completed successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📱 Access the application:"
    echo "   Local: http://localhost:7777"
    echo "   Network: http://$(hostname -I | awk '{print $1}'):7777"
    echo ""
    echo "📚 Documentation:"
    echo "   - README.md : Full documentation"
    echo "   - QUICKSTART.md : Quick start guide"
    echo "   - AUDIO_SETUP.md : Audio configuration"
    echo ""
    echo "🔧 Useful commands:"
    echo "   - docker-compose logs -f : View logs"
    echo "   - docker-compose restart : Restart"
    echo "   - docker-compose down : Stop"
    echo ""
    echo "⚠️  Don't forget:"
    echo "   1. Add an audio file in audio/"
    echo "   2. Configure your location in the settings"
    echo "   3. Test the audio before the first prayer"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    error "The container is not starting correctly"
    echo "Check the logs with: docker-compose logs"
    exit 1
fi
