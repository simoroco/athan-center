#!/bin/sh
set -e

echo "🚀 Starting Athan Center container..."

# Note: HOST_IP and HOST_HOSTNAME are passed via docker-compose environment
# In host network mode (Linux), these are optional (server.js reads from interfaces)
# In bridge mode (macOS/Windows), these should be set by the start script

if [ -n "$HOST_IP" ]; then
    echo "✅ Using provided HOST_IP: $HOST_IP"
fi

if [ -n "$HOST_HOSTNAME" ]; then
    echo "✅ Using provided HOST_HOSTNAME: $HOST_HOSTNAME"
fi

# Initialize audio directory if empty
if [ ! "$(ls -A /app/audio)" ]; then
    echo "📂 Audio directory is empty, copying files from image..."
    cp -r /app/audio_seed/* /app/audio/
    echo "✅ Audio files copied successfully"
else
    echo "✅ Audio directory already populated"
    
    # Copy missing subdirectories (e.g., system folder added in updates)
    for subdir in /app/audio_seed/*/; do
        dirname=$(basename "$subdir")
        if [ ! -d "/app/audio/$dirname" ]; then
            echo "📂 Copying new subdirectory: $dirname"
            cp -r "$subdir" "/app/audio/$dirname"
            echo "✅ $dirname copied successfully"
        fi
    done
fi

# Initialize data directory if empty or only contains .gitkeep/README
DATA_FILES=$(find /app/data -type f ! -name '.gitkeep' ! -name 'README.md' | wc -l)
if [ "$DATA_FILES" -eq 0 ]; then
    echo "📂 Data directory is empty, copying seed database..."
    if [ -f /app/data_seed/prayer.db ]; then
        cp /app/data_seed/prayer.db /app/data/
        echo "✅ Seed database copied successfully"
    fi
else
    echo "✅ Data directory already contains files"
fi

echo "🎉 Initialization complete, starting application..."

# Configure ALSA to use the correct audio card
# Try to detect USB audio card, fallback to card 0
echo "🔊 Configuring ALSA audio..."

# Find USB audio card number (usually card 2 for USB devices)
USB_CARD=$(aplay -l 2>/dev/null | grep -i "USB\|Jabra\|Speaker" | head -1 | sed -n 's/card \([0-9]\).*/\1/p')

# If no USB card found, use card 0 (HDMI)
if [ -z "$USB_CARD" ]; then
    echo "⚠️  No USB audio card detected, using card 0 (HDMI)"
    USB_CARD=0
else
    echo "✅ USB audio card detected: card $USB_CARD"
fi

# Create ALSA configuration file to use the detected card
cat > /root/.asoundrc << EOF
pcm.!default {
    type hw
    card $USB_CARD
}
ctl.!default {
    type hw
    card $USB_CARD
}
EOF

echo "✅ ALSA configured to use card $USB_CARD"

# Set AUDIODRIVER to force sox to use ALSA directly
export AUDIODRIVER=alsa
echo "✅ AUDIODRIVER set to: $AUDIODRIVER"

# Test audio configuration
echo "🔊 Testing audio configuration..."
if aplay -l 2>/dev/null | grep -q "card"; then
    echo "✅ Audio devices detected:"
    aplay -l 2>/dev/null | grep "card"
else
    echo "⚠️  No audio devices detected by aplay"
fi

# Execute the main command (node server.js)
exec "$@"
