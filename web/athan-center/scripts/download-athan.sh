#!/bin/bash

# Script to download a default athan file
# This script helps users quickly get an audio file

echo "🔊 Athan File Download"
echo "====================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create the audio folder if it doesn't exist
mkdir -p audio

echo "Choose an athan to download:"
echo ""
echo "1) Makkah Athan (Sheikh Ali Ahmed Mulla)"
echo "2) Madinah Athan (Sheikh Muhammad Ayyub)"
echo "3) Egyptian Athan (Sheikh Nasser Al-Qatami)"
echo "4) Download from a custom URL"
echo "5) Cancel"
echo ""
read -p "Your choice (1-5): " choice

case $choice in
    1)
        echo -e "${YELLOW}Option 1 selected${NC}"
        echo "For copyright reasons, please download manually:"
        echo "1. Visit: https://www.islamicfinder.org/islamic-audio/"
        echo "2. Search for 'Adhan Makkah' or 'Sheikh Ali Ahmed Mulla'"
        echo "3. Download the MP3 file"
        echo "4. Place it in the audio/ folder named athan.mp3"
        ;;
    2)
        echo -e "${YELLOW}Option 2 selected${NC}"
        echo "For copyright reasons, please download manually:"
        echo "1. Visit: https://www.islamicfinder.org/islamic-audio/"
        echo "2. Search for 'Adhan Madinah' or 'Sheikh Muhammad Ayyub'"
        echo "3. Download the MP3 file"
        echo "4. Place it in the audio/ folder named athan.mp3"
        ;;
    3)
        echo -e "${YELLOW}Option 3 selected${NC}"
        echo "For copyright reasons, please download manually:"
        echo "1. Visit: https://www.islamicfinder.org/islamic-audio/"
        echo "2. Search for 'Sheikh Nasser Al-Qatami'"
        echo "3. Download the MP3 file"
        echo "4. Place it in the audio/ folder named athan.mp3"
        ;;
    4)
        echo ""
        read -p "Enter the MP3 file URL: " url
        if [ ! -z "$url" ]; then
            echo "Downloading..."
            if wget "$url" -O audio/athan.mp3; then
                echo -e "${GREEN}✓ File downloaded successfully!${NC}"
                echo "The file was saved to audio/athan.mp3"
            else
                echo "Error while downloading"
                exit 1
            fi
        else
            echo "Empty URL, cancelling"
            exit 1
        fi
        ;;
    5)
        echo "Cancelled"
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "📚 Recommended resources to download athans:"
echo ""
echo "1. Islamic Finder"
echo "   https://www.islamicfinder.org/islamic-audio/"
echo ""
echo "2. Muslim Pro"
echo "   https://www.muslimpro.com/"
echo ""
echo "3. YouTube (with a YouTube to MP3 converter)"
echo "   Search for: 'Adhan Makkah MP3' or 'Athan Madinah'"
echo ""
echo "4. Zikr Reminder"
echo "   https://www.zikriya.com/"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "After downloading your file:"
echo "1. Rename it to 'athan.mp3'"
echo "2. Place it in the audio/ folder"
echo "3. Or keep the original name and select it in the settings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
