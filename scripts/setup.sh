#!/bin/bash

# Script d'installation automatique de Athan Center
# Pour Raspberry Pi 5

set -e

echo "🕌 Installation de Athan Center"
echo "================================"
echo ""

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher des messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier si Docker est installé
info "Vérification de Docker..."
if ! command -v docker &> /dev/null; then
    warn "Docker n'est pas installé. Installation en cours..."
    curl -sSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    info "Docker installé avec succès"
    warn "Vous devez redémarrer votre session pour que les changements prennent effet"
    warn "Exécutez 'newgrp docker' ou déconnectez-vous et reconnectez-vous"
else
    info "Docker est déjà installé"
fi

# Vérifier Docker Compose
info "Vérification de Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    warn "Docker Compose n'est pas installé. Installation en cours..."
    sudo apt-get update
    sudo apt-get install -y docker-compose
    info "Docker Compose installé avec succès"
else
    info "Docker Compose est déjà installé"
fi

# Créer les répertoires nécessaires
info "Création des répertoires..."
mkdir -p data audio

# Vérifier si un fichier audio existe
if [ ! "$(ls -A audio/*.mp3 2>/dev/null)" ]; then
    warn "Aucun fichier audio trouvé dans le dossier audio/"
    echo ""
    echo "Voulez-vous télécharger un fichier athan par défaut ? (o/n)"
    read -r response
    if [[ "$response" =~ ^([oO][uU][iI]|[oO])$ ]]; then
        info "Téléchargement de l'athan de La Mecque..."
        # Note: Remplacez cette URL par une URL valide
        warn "Veuillez télécharger manuellement un fichier athan et le placer dans audio/"
        warn "Sources recommandées:"
        echo "  - https://www.islamicfinder.org/islamic-audio/"
        echo "  - Recherchez 'Adhan Makkah' sur YouTube et convertissez en MP3"
    fi
fi

# Vérifier les permissions audio
info "Vérification des permissions audio..."
if ! groups $USER | grep -q '\baudio\b'; then
    warn "Ajout de l'utilisateur au groupe audio..."
    sudo usermod -aG audio $USER
    warn "Vous devez redémarrer votre session pour que les changements prennent effet"
fi

# Configuration du fuseau horaire
info "Configuration du fuseau horaire..."
echo "Fuseau horaire actuel : $(timedatectl | grep "Time zone" | awk '{print $3}')"
echo "Est-ce correct ? (o/n)"
read -r tz_response
if [[ ! "$tz_response" =~ ^([oO][uU][iI]|[oO])$ ]]; then
    echo "Entrez votre fuseau horaire (ex: Europe/Paris):"
    read -r timezone
    if [ ! -z "$timezone" ]; then
        sed -i "s|TZ=.*|TZ=$timezone|" docker-compose.yml
        info "Fuseau horaire mis à jour : $timezone"
    fi
fi

# Construire et démarrer le conteneur
info "Construction et démarrage du conteneur Docker..."
if docker-compose up -d --build; then
    info "Conteneur démarré avec succès !"
else
    error "Erreur lors du démarrage du conteneur"
    exit 1
fi

# Attendre que le serveur démarre
info "Attente du démarrage du serveur..."
sleep 5

# Vérifier si le conteneur est en cours d'exécution
if docker ps | grep -q athan-center; then
    info "✅ L'application est en cours d'exécution !"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Installation terminée avec succès !"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📱 Accès à l'application:"
    echo "   Local: http://localhost:7777"
    echo "   Réseau: http://$(hostname -I | awk '{print $1}'):7777"
    echo ""
    echo "📚 Documentation:"
    echo "   - README.md : Documentation complète"
    echo "   - QUICKSTART.md : Guide de démarrage rapide"
    echo "   - AUDIO_SETUP.md : Configuration audio"
    echo ""
    echo "🔧 Commandes utiles:"
    echo "   - docker-compose logs -f : Voir les logs"
    echo "   - docker-compose restart : Redémarrer"
    echo "   - docker-compose down : Arrêter"
    echo ""
    echo "⚠️  N'oubliez pas:"
    echo "   1. Ajouter un fichier audio dans audio/"
    echo "   2. Configurer votre localisation dans les paramètres"
    echo "   3. Tester l'audio avant la première prière"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    error "Le conteneur ne démarre pas correctement"
    echo "Vérifiez les logs avec: docker-compose logs"
    exit 1
fi
