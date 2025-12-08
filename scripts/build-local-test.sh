#!/bin/bash

# Script de build LOCAL pour tester l'image avant de pusher
# Ce script build uniquement pour la plateforme locale (rapide)

set -e

echo "🧪 Building Athan Center Docker Image (LOCAL TEST)..."
echo ""

# Vérifier que startup.mp3 existe
echo "🔍 Vérification des fichiers audio..."
if [ ! -f "app/audio/system/startup.mp3" ]; then
    echo "❌ ERREUR: Le fichier startup.mp3 est manquant!"
    exit 1
fi

echo "✅ startup.mp3 trouvé ($(du -h app/audio/system/startup.mp3 | cut -f1))"
echo ""

# Build local (plateforme actuelle uniquement)
echo "🔨 Building local image..."
DOCKER_BUILDKIT=0 docker build -t athan-center:test app/

echo ""
echo "✅ Build local terminé!"
echo ""
echo "📋 Vérification du contenu de l'image..."
echo ""

# Vérifier que les fichiers audio sont bien dans l'image
echo "🔍 Contenu de /app/audio_seed/ dans l'image:"
docker run --rm athan-center:test ls -lR /app/audio_seed/

echo ""
echo "🔍 Vérification spécifique du fichier startup.mp3:"
docker run --rm athan-center:test ls -lh /app/audio_seed/system/startup.mp3

echo ""
echo "✅ Vérification terminée!"
echo ""
echo "🎉 Si tout est OK, vous pouvez pusher avec:"
echo "   ./build-and-push.sh"
echo ""
