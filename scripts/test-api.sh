#!/bin/bash

# Script de test de l'API Athan Center
# Usage: ./test-api.sh [BASE_URL]
# Exemple: ./test-api.sh http://localhost:7777

BASE_URL=${1:-http://localhost:7777}

echo "🕌 Tests de l'API Athan Center"
echo "================================"
echo "URL de base: $BASE_URL"
echo ""

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonction de test
test_endpoint() {
    local method=$1
    local endpoint=$2
    local description=$3
    local data=$4
    
    echo -n "Testing $method $endpoint - $description... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X $method -H "Content-Type: application/json" -d "$data" "$BASE_URL$endpoint")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $http_code)"
        if [ ! -z "$body" ]; then
            echo "  Response: ${body:0:100}..."
        fi
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        echo "  Response: $body"
    fi
    echo ""
}

# Vérifier que le serveur est accessible
echo "Vérification de la disponibilité du serveur..."
if ! curl -s --connect-timeout 5 "$BASE_URL" > /dev/null; then
    echo -e "${RED}✗ Serveur non accessible${NC}"
    echo "Assurez-vous que l'application est démarrée avec 'docker-compose up -d'"
    exit 1
fi
echo -e "${GREEN}✓ Serveur accessible${NC}"
echo ""

# Date d'aujourd'hui
TODAY=$(date +%Y-%m-%d)

# Tests des endpoints
echo "📋 Tests des endpoints API"
echo ""

test_endpoint "GET" "/" "Page d'accueil"
test_endpoint "GET" "/api/prayers/$TODAY" "Récupérer les prières du jour"
test_endpoint "GET" "/api/prayers/next/upcoming" "Récupérer la prochaine prière"
test_endpoint "GET" "/api/settings" "Récupérer les paramètres"
test_endpoint "GET" "/api/prayer-settings" "Récupérer les paramètres de prières"
test_endpoint "GET" "/api/skip-next" "Vérifier le statut skip next"
test_endpoint "GET" "/api/audio-files" "Lister les fichiers audio"

echo ""
echo "📝 Tests d'écriture (attention: modifie les données)"
echo ""

# Demander confirmation
read -p "Voulez-vous exécuter les tests d'écriture? (o/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    test_endpoint "POST" "/api/skip-next" "Activer skip next"
    test_endpoint "POST" "/api/prayer-settings/Fajr" "Désactiver Fajr" '{"enabled": false}'
    test_endpoint "POST" "/api/prayer-settings/Fajr" "Réactiver Fajr" '{"enabled": true}'
    test_endpoint "POST" "/api/settings" "Mettre à jour un paramètre" '{"key": "test_key", "value": "test_value"}'
fi

echo ""
echo "================================"
echo "Tests terminés"
echo ""

# Afficher quelques statistiques
echo "📊 Informations supplémentaires"
echo ""

echo -n "Nombre de prières aujourd'hui: "
curl -s "$BASE_URL/api/prayers/$TODAY" | grep -o "prayer_name" | wc -l

echo -n "Nombre de fichiers audio: "
curl -s "$BASE_URL/api/audio-files" | grep -o "\.mp3\|\.wav" | wc -l

echo ""
