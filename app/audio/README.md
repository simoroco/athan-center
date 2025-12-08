# 🔊 Dossier Audio

Ce dossier contient les fichiers audio d'athan qui seront joués lors des appels à la prière.

## 📥 Comment ajouter un fichier audio

### Méthode 1 : Téléchargement direct

Placez simplement votre fichier MP3 ou WAV dans ce dossier.

```bash
cp /chemin/vers/votre/athan.mp3 audio/
```

### Méthode 2 : Téléchargement depuis Internet

```bash
cd audio
wget URL_DE_VOTRE_ATHAN -O athan.mp3
```

## 🎵 Sources recommandées

### Sites Web

1. **Islamic Finder**
   - URL : https://www.islamicfinder.org/islamic-audio/
   - Format : MP3
   - Variété : Différents muezzins et styles

2. **Muslim Pro**
   - URL : https://www.muslimpro.com/
   - Inclut plusieurs options

3. **YouTube**
   - Recherchez : "Adhan Makkah MP3" ou "Athan Madinah"
   - Convertissez avec un outil YouTube to MP3

### Exemples de recherche

- "Adhan Makkah MP3 download"
- "Sheikh Ali Ahmed Mulla Athan"
- "Mishary Rashid Alafasy Adhan"
- "Ibrahim Al Arkani Athan"

## 📋 Formats supportés

- **MP3** (.mp3) - Recommandé
- **WAV** (.wav) - Meilleure qualité mais fichiers plus gros

## ⚙️ Spécifications recommandées

Pour une meilleure qualité audio :

- **Bitrate** : 192 kbps ou plus
- **Sample Rate** : 44.1 kHz
- **Channels** : Stereo (2 channels)
- **Durée** : 2-5 minutes typiquement

## 🔄 Conversion de fichiers

### Convertir WAV en MP3

```bash
ffmpeg -i athan.wav -codec:a libmp3lame -qscale:a 2 athan.mp3
```

### Convertir vidéo YouTube en MP3

```bash
# Installer youtube-dl
pip install youtube-dl

# Télécharger et convertir
youtube-dl -x --audio-format mp3 URL_YOUTUBE
```

### Ajuster le volume

```bash
# Augmenter de 10 dB
ffmpeg -i athan.mp3 -af "volume=10dB" athan_loud.mp3

# Réduire de 5 dB
ffmpeg -i athan.mp3 -af "volume=-5dB" athan_soft.mp3
```

### Normaliser le volume

```bash
# Normaliser le volume
ffmpeg -i athan.mp3 -af loudnorm athan_normalized.mp3
```

### Couper le début/fin

```bash
# Commencer à 5 secondes et prendre 3 minutes
ffmpeg -i athan.mp3 -ss 00:00:05 -t 00:03:00 -acodec copy athan_trimmed.mp3
```

## 📝 Exemples de fichiers

Vous pouvez avoir plusieurs fichiers pour différentes prières :

```
audio/
├── athan_makkah.mp3      # Athan de La Mecque
├── athan_madinah.mp3     # Athan de Médine
├── athan_egypt.mp3       # Style égyptien
└── athan_short.mp3       # Version courte
```

Puis sélectionnez le fichier désiré dans les paramètres de l'application.

## 🎛️ Tester votre audio

### Depuis le terminal

```bash
# Avec mpg123 (MP3)
mpg123 audio/athan.mp3

# Avec aplay (WAV)
aplay audio/athan.wav

# Avec ffplay
ffplay -nodisp -autoexit audio/athan.mp3
```

### Depuis l'application

1. Ouvrez Athan Center
2. Allez dans **Paramètres** (⚙️)
3. Section **Audio**
4. Cliquez sur **🔊 Tester l'Athan**

## ✅ Vérifier la qualité

```bash
# Informations sur le fichier
ffprobe audio/athan.mp3

# Ou avec file
file audio/athan.mp3

# Ou avec mediainfo
mediainfo audio/athan.mp3
```

## 🔧 Dépannage

### Le fichier ne joue pas

```bash
# Vérifier que le fichier est valide
ffmpeg -v error -i audio/athan.mp3 -f null -

# Si erreur, reconvertir
ffmpeg -i audio/athan.mp3 -codec:a libmp3lame -b:a 192k audio/athan_fixed.mp3
```

### Le son est déformé

- Vérifiez que le fichier n'est pas corrompu
- Essayez de le reconvertir
- Utilisez un bitrate plus élevé (256 kbps)

### Le fichier est trop gros

```bash
# Réduire la taille (qualité moindre)
ffmpeg -i athan.mp3 -b:a 128k athan_compressed.mp3
```

## 📊 Exemples de fichiers populaires

| Nom | Durée | Description |
|-----|-------|-------------|
| Athan Makkah | 3-4 min | Athan de la Grande Mosquée de La Mecque |
| Athan Madinah | 3-4 min | Athan de la Mosquée du Prophète |
| Sheikh Mishary | 2-3 min | Style mélodieux |
| Athan Egyptien | 3-5 min | Style traditionnel égyptien |

## 💡 Conseils

- **Testez toujours** votre fichier avant la première utilisation
- **Sauvegardez** vos fichiers préférés
- **Normalisez** le volume pour éviter les surprises
- **Nommez** vos fichiers de manière descriptive

## 📚 Ressources

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Audio File Format Specifications](https://en.wikipedia.org/wiki/Audio_file_format)
- [Islamic Audio Resources](https://www.islamicfinder.org/)

---

**Pour plus d'aide, consultez AUDIO_SETUP.md dans le dossier racine**
