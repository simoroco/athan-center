#!/bin/bash
# Generate a simple test startup sound using sox
# This creates a pleasant chime sound (C major chord)

echo "🔊 Generating test startup sound..."

# Check if sox is installed
if ! command -v sox &> /dev/null; then
    echo "❌ sox is not installed. Please install it:"
    echo "   macOS: brew install sox"
    echo "   Ubuntu/Debian: sudo apt-get install sox"
    echo "   Alpine: apk add sox"
    exit 1
fi

# Generate a pleasant chime sound (C major chord: C-E-G)
# 0.5 seconds long with fade in/out
sox -n -r 44100 -c 2 startup.mp3 \
    synth 0.5 pluck C4 \
    synth 0.5 pluck E4 : synth 0.5 pluck G4 : \
    fade t 0.05 0.5 0.2 \
    gain -n -3

echo "✅ Test startup sound generated: startup.mp3"
echo "   Duration: 0.5 seconds"
echo "   Format: MP3, 44.1kHz, stereo"
echo ""
echo "You can replace this with your own startup.mp3 file"
