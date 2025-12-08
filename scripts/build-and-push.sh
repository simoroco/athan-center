#!/bin/bash

# Script de build et push de l'image Docker Athan Center
# Ce script build l'image pour ARM64 (Raspberry Pi) et AMD64 (x86)
# puis la pousse sur Docker Hub

set -e  # Arrêter en cas d'erreur

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

# Vérifier que tous les fichiers audio existent
echo "🔍 Vérification des fichiers audio..."
echo ""
echo "Fichiers Athan:"
ls -lh app/audio/athan/
echo ""
echo "Fichiers Quran:"
ls -lh app/audio/coran/
echo ""
echo "Fichiers System:"
ls -lh app/audio/system/
echo ""

if [ ! -f "app/audio/system/startup.mp3" ]; then
    echo "❌ ERREUR: Le fichier startup.mp3 est manquant!"
    echo "   Créez-le avec: cp 'app/audio/athan/Omar Hisham Al Arabi.mp3' app/audio/system/startup.mp3"
    exit 1
fi

echo "✅ Tous les fichiers audio sont présents"
echo ""

# Build de l'image (avec logs détaillés de la copie audio)
echo "🔨 Building Docker image..."
echo "   Cette opération peut prendre plusieurs minutes..."
echo ""

docker buildx build \
    --platform linux/arm64,linux/amd64 \
    -t $IMAGE_NAME:$VERSION \
    -t $IMAGE_NAME:$LATEST_TAG \
    --push \
    app/

echo ""
echo "✅ Build et push terminés avec succès!"
echo ""
echo "📦 Images poussées:"
echo "   - $IMAGE_NAME:$VERSION"
echo "   - $IMAGE_NAME:$LATEST_TAG"
echo ""
echo "🎉 Vous pouvez maintenant déployer sur le Raspberry Pi avec:"
echo "   docker compose pull"
echo "   docker compose up -d --force-recreate"
echo ""
