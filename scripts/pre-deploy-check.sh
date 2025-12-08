#!/bin/bash

# Script de vérification pré-déploiement
# Vérifie que tout est en place avant de déployer

echo "🔍 Vérification Pré-Déploiement Athan Center"
echo "============================================="
echo ""

# Compteurs
ERRORS=0
WARNINGS=0

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonction de vérification
check() {
    local test_name=$1
    local test_cmd=$2
    
    echo -n "Vérification: $test_name... "
    
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ ÉCHEC${NC}"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

warn() {
    local msg=$1
    echo -e "${YELLOW}⚠ ATTENTION:${NC} $msg"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    local msg=$1
    echo -e "${GREEN}ℹ${NC} $msg"
}

# Séparateur
section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 1. Vérifications des dépendances
section "1. Dépendances Système"

check "Docker installé" "command -v docker"
check "Docker Compose installé" "command -v docker-compose"
check "Git installé" "command -v git"
check "Node.js installé" "command -v node"
check "npm installé" "command -v npm"

# 2. Vérifications des fichiers
section "2. Fichiers Principaux"

check "server.js existe" "test -f server.js"
check "package.json existe" "test -f package.json"
check "Dockerfile existe" "test -f Dockerfile"
check "docker-compose.yml existe" "test -f docker-compose.yml"
check "public/index.html existe" "test -f public/index.html"
check "public/styles.css existe" "test -f public/styles.css"
check "public/app.js existe" "test -f public/app.js"

# 3. Vérifications des dossiers
section "3. Structure des Dossiers"

check "Dossier audio/ existe" "test -d audio"
check "Dossier data/ existe" "test -d data"
check "Dossier public/ existe" "test -d public"

# 4. Vérifications audio
section "4. Configuration Audio"

if ls audio/*.mp3 >/dev/null 2>&1 || ls audio/*.wav >/dev/null 2>&1; then
    info "Fichiers audio trouvés:"
    ls -lh audio/*.mp3 audio/*.wav 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
else
    warn "Aucun fichier audio trouvé dans audio/"
    echo "  Téléchargez un fichier athan.mp3 et placez-le dans audio/"
fi

# 5. Vérifications des permissions
section "5. Permissions"

check "setup.sh exécutable" "test -x setup.sh"
check "test-api.sh exécutable" "test -x test-api.sh"
check "download-athan.sh exécutable" "test -x download-athan.sh"

# 6. Vérifications Docker
section "6. Configuration Docker"

check "Docker daemon actif" "docker ps"
check "Port 7777 disponible" "! lsof -i :7777"

# 7. Vérifications de syntaxe
section "7. Validation de Syntaxe"

if command -v node > /dev/null; then
    check "Syntaxe server.js valide" "node -c server.js"
    check "Syntaxe app.js valide" "node -c public/app.js"
fi

# 8. Vérifications réseau
section "8. Configuration Réseau"

info "Adresse IP locale: $(hostname -I | awk '{print $1}')"
info "Hostname: $(hostname)"

# 9. Vérifications système
section "9. Ressources Système"

if command -v free > /dev/null; then
    TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
    AVAILABLE_MEM=$(free -h | grep Mem | awk '{print $7}')
    info "Mémoire totale: $TOTAL_MEM"
    info "Mémoire disponible: $AVAILABLE_MEM"
fi

if command -v df > /dev/null; then
    DISK_AVAILABLE=$(df -h . | tail -1 | awk '{print $4}')
    info "Espace disque disponible: $DISK_AVAILABLE"
fi

# 10. Vérifications des périphériques audio
section "10. Périphériques Audio"

if test -e /dev/snd; then
    info "Périphériques audio détectés:"
    ls -la /dev/snd/ | tail -n +4 | awk '{print "  - " $9}'
    
    if command -v aplay > /dev/null; then
        check "ALSA fonctionnel" "aplay -l"
    else
        warn "aplay non installé (optionnel)"
    fi
else
    warn "Aucun périphérique audio détecté (/dev/snd)"
fi

# 11. Documentation
section "11. Documentation"

DOCS=("README.md" "QUICKSTART.md" "AUDIO_SETUP.md" "DEPLOYMENT.md" "TROUBLESHOOTING.md")
for doc in "${DOCS[@]}"; do
    check "Documentation $doc" "test -f $doc"
done

# Résumé final
section "📊 Résumé"

echo ""
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Tout est prêt pour le déploiement !${NC}"
    echo ""
    echo "Commandes de déploiement:"
    echo "  docker-compose up -d        # Démarrer l'application"
    echo "  make start                  # Ou avec make"
    echo "  ./setup.sh                  # Ou avec le script d'installation"
    echo ""
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Prêt avec $WARNINGS avertissement(s)${NC}"
    echo ""
    echo "Vous pouvez déployer, mais vérifiez les avertissements ci-dessus."
    echo ""
else
    echo -e "${RED}✗ $ERRORS erreur(s) détectée(s)${NC}"
    echo -e "${YELLOW}⚠ $WARNINGS avertissement(s)${NC}"
    echo ""
    echo "Corrigez les erreurs avant de déployer."
    echo ""
    exit 1
fi

echo "Pour plus d'aide, consultez:"
echo "  - README.md pour la documentation complète"
echo "  - QUICKSTART.md pour un guide rapide"
echo "  - TROUBLESHOOTING.md en cas de problème"
echo ""
