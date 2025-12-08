#!/bin/bash

# Script pour télécharger un fichier athan par défaut
# Ce script aide les utilisateurs à obtenir rapidement un fichier audio

echo "🔊 Téléchargement d'un fichier Athan"
echo "====================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Créer le dossier audio s'il n'existe pas
mkdir -p audio

echo "Choisissez un athan à télécharger :"
echo ""
echo "1) Athan de La Mecque (Sheikh Ali Ahmed Mulla)"
echo "2) Athan de Médine (Sheikh Muhammad Ayyub)"
echo "3) Athan Égyptien (Sheikh Nasser Al-Qatami)"
echo "4) Télécharger depuis une URL personnalisée"
echo "5) Annuler"
echo ""
read -p "Votre choix (1-5): " choice

case $choice in
    1)
        echo -e "${YELLOW}Option 1 sélectionnée${NC}"
        echo "Pour des raisons de droits d'auteur, veuillez télécharger manuellement :"
        echo "1. Visitez : https://www.islamicfinder.org/islamic-audio/"
        echo "2. Recherchez 'Adhan Makkah' ou 'Sheikh Ali Ahmed Mulla'"
        echo "3. Téléchargez le fichier MP3"
        echo "4. Placez-le dans le dossier audio/ avec le nom athan.mp3"
        ;;
    2)
        echo -e "${YELLOW}Option 2 sélectionnée${NC}"
        echo "Pour des raisons de droits d'auteur, veuillez télécharger manuellement :"
        echo "1. Visitez : https://www.islamicfinder.org/islamic-audio/"
        echo "2. Recherchez 'Adhan Madinah' ou 'Sheikh Muhammad Ayyub'"
        echo "3. Téléchargez le fichier MP3"
        echo "4. Placez-le dans le dossier audio/ avec le nom athan.mp3"
        ;;
    3)
        echo -e "${YELLOW}Option 3 sélectionnée${NC}"
        echo "Pour des raisons de droits d'auteur, veuillez télécharger manuellement :"
        echo "1. Visitez : https://www.islamicfinder.org/islamic-audio/"
        echo "2. Recherchez 'Sheikh Nasser Al-Qatami'"
        echo "3. Téléchargez le fichier MP3"
        echo "4. Placez-le dans le dossier audio/ avec le nom athan.mp3"
        ;;
    4)
        echo ""
        read -p "Entrez l'URL du fichier MP3 : " url
        if [ ! -z "$url" ]; then
            echo "Téléchargement en cours..."
            if wget "$url" -O audio/athan.mp3; then
                echo -e "${GREEN}✓ Fichier téléchargé avec succès !${NC}"
                echo "Le fichier a été enregistré dans audio/athan.mp3"
            else
                echo "Erreur lors du téléchargement"
                exit 1
            fi
        else
            echo "URL vide, annulation"
            exit 1
        fi
        ;;
    5)
        echo "Annulation"
        exit 0
        ;;
    *)
        echo "Choix invalide"
        exit 1
        ;;
esac

echo ""
echo "📚 Ressources recommandées pour télécharger des athans :"
echo ""
echo "1. Islamic Finder"
echo "   https://www.islamicfinder.org/islamic-audio/"
echo ""
echo "2. Muslim Pro"
echo "   https://www.muslimpro.com/"
echo ""
echo "3. YouTube (avec convertisseur YouTube to MP3)"
echo "   Recherchez : 'Adhan Makkah MP3' ou 'Athan Madinah'"
echo ""
echo "4. Zikr Reminder"
echo "   https://www.zikriya.com/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Après avoir téléchargé votre fichier :"
echo "1. Renommez-le en 'athan.mp3'"
echo "2. Placez-le dans le dossier audio/"
echo "3. Ou gardez le nom original et sélectionnez-le dans les paramètres"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
