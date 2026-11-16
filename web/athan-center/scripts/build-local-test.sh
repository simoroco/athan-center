#!/bin/bash

# LOCAL build script to test the image before pushing
# This script builds only for the local platform (fast)

set -e

echo "🧪 Building Athan Center Docker Image (LOCAL TEST)..."
echo ""

# Check that startup.mp3 exists
echo "🔍 Checking audio files..."
if [ ! -f "audio/system/startup.mp3" ]; then
    echo "❌ ERROR: The startup.mp3 file is missing!"
    exit 1
fi

echo "✅ startup.mp3 found ($(du -h audio/system/startup.mp3 | cut -f1))"
echo ""

# Local build (current platform only)
echo "🔨 Building local image..."
DOCKER_BUILDKIT=0 docker build -t athan-center:test .

echo ""
echo "✅ Local build finished!"
echo ""
echo "📋 Checking image contents..."
echo ""

# Check that the audio files are in the image
echo "🔍 Contents of /app/audio_seed/ in the image:"
docker run --rm athan-center:test ls -lR /app/audio_seed/

echo ""
echo "🔍 Specific check for the startup.mp3 file:"
docker run --rm athan-center:test ls -lh /app/audio_seed/system/startup.mp3

echo ""
echo "✅ Check complete!"
echo ""
echo "🎉 If everything is OK, you can push with:"
echo "   ./build-and-push.sh"
echo ""
