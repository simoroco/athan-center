#!/bin/bash

# Build and push script for the Athan Center Docker image
# This script builds the image for ARM64 (Raspberry Pi) and AMD64 (x86)
# then pushes it to Docker Hub

set -e  # Stop on error

echo "🚀 Building Athan Center Docker Image..."
echo ""

# Variables
IMAGE_NAME="simoroco/athan-center"
VERSION="1.5.1"
LATEST_TAG="latest"

echo "📋 Configuration:"
echo "   Image: $IMAGE_NAME"
echo "   Version: $VERSION"
echo "   Platforms: linux/arm64, linux/amd64"
echo ""

# Check that all audio files exist
echo "🔍 Checking audio files..."
echo ""
echo "Athan files:"
ls -lh audio/athan/
echo ""
echo "Quran files:"
ls -lh audio/coran/
echo ""
echo "System files:"
ls -lh audio/system/
echo ""

if [ ! -f "audio/system/startup.mp3" ]; then
    echo "❌ ERROR: The startup.mp3 file is missing!"
    echo "   Create it with: cp 'audio/athan/Omar Hisham Al Arabi.mp3' audio/system/startup.mp3"
    exit 1
fi

echo "✅ All audio files are present"
echo ""

# Build the image (with detailed audio copy logs)
echo "🔨 Building Docker image..."
echo "   This operation can take several minutes..."
echo ""

docker buildx build \
    --platform linux/arm64,linux/amd64 \
    -t $IMAGE_NAME:$VERSION \
    -t $IMAGE_NAME:$LATEST_TAG \
    --push \
    .

echo ""
echo "✅ Build and push completed successfully!"
echo ""
echo "📦 Pushed images:"
echo "   - $IMAGE_NAME:$VERSION"
echo "   - $IMAGE_NAME:$LATEST_TAG"
echo ""
echo "🎉 You can now deploy on the Raspberry Pi with:"
echo "   docker compose pull"
echo "   docker compose up -d --force-recreate"
echo ""
