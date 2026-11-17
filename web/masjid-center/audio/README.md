# 🔊 Audio Folder

This folder contains the athan audio files that will be played during prayer calls.

## 📥 How to add an audio file

### Method 1: Direct copy

Simply place your MP3 or WAV file in this folder.

```bash
cp /path/to/your/athan.mp3 audio/
```

### Method 2: Download from the Internet

```bash
cd audio
wget YOUR_ATHAN_URL -O athan.mp3
```

## 🎵 Recommended sources

### Websites

1. **Islamic Finder**
   - URL: https://www.islamicfinder.org/islamic-audio/
   - Format: MP3
   - Variety: Different muezzins and styles

2. **Muslim Pro**
   - URL: https://www.muslimpro.com/
   - Includes several options

3. **YouTube**
   - Search for: "Adhan Makkah MP3" or "Athan Madinah"
   - Convert with a YouTube to MP3 tool

### Search examples

- "Adhan Makkah MP3 download"
- "Sheikh Ali Ahmed Mulla Athan"
- "Mishary Rashid Alafasy Adhan"
- "Ibrahim Al Arkani Athan"

## 📋 Supported formats

- **MP3** (.mp3) - Recommended
- **WAV** (.wav) - Better quality but larger files

## ⚙️ Recommended specifications

For better audio quality:

- **Bitrate**: 192 kbps or higher
- **Sample Rate**: 44.1 kHz
- **Channels**: Stereo (2 channels)
- **Duration**: typically 2-5 minutes

## 🔄 File conversion

### Convert WAV to MP3

```bash
ffmpeg -i athan.wav -codec:a libmp3lame -qscale:a 2 athan.mp3
```

### Convert YouTube video to MP3

```bash
# Install youtube-dl
pip install youtube-dl

# Download and convert
youtube-dl -x --audio-format mp3 YOUTUBE_URL
```

### Adjust the volume

```bash
# Increase by 10 dB
ffmpeg -i athan.mp3 -af "volume=10dB" athan_loud.mp3

# Decrease by 5 dB
ffmpeg -i athan.mp3 -af "volume=-5dB" athan_soft.mp3
```

### Normalize the volume

```bash
# Normalize the volume
ffmpeg -i athan.mp3 -af loudnorm athan_normalized.mp3
```

### Trim the beginning/end

```bash
# Start at 5 seconds and take 3 minutes
ffmpeg -i athan.mp3 -ss 00:00:05 -t 00:03:00 -acodec copy athan_trimmed.mp3
```

## 📝 File examples

You can have multiple files for different prayers:

```
audio/
├── athan_makkah.mp3      # Makkah athan
├── athan_madinah.mp3     # Madinah athan
├── athan_egypt.mp3       # Egyptian style
└── athan_short.mp3       # Short version
```

Then select the desired file in the application settings.

## 🎛️ Test your audio

### From the terminal

```bash
# With mpg123 (MP3)
mpg123 audio/athan.mp3

# With aplay (WAV)
aplay audio/athan.wav

# With ffplay
ffplay -nodisp -autoexit audio/athan.mp3
```

### From the application

1. Open Masjid Center
2. Go to **Settings** (⚙️)
3. **Audio** section
4. Click **🔊 Test Athan**

## ✅ Check the quality

```bash
# File information
ffprobe audio/athan.mp3

# Or with file
file audio/athan.mp3

# Or with mediainfo
mediainfo audio/athan.mp3
```

## 🔧 Troubleshooting

### The file won't play

```bash
# Check that the file is valid
ffmpeg -v error -i audio/athan.mp3 -f null -

# If it fails, reconvert
ffmpeg -i audio/athan.mp3 -codec:a libmp3lame -b:a 192k audio/athan_fixed.mp3
```

### The sound is distorted

- Check that the file is not corrupted
- Try reconverting it
- Use a higher bitrate (256 kbps)

### The file is too large

```bash
# Reduce the size (lower quality)
ffmpeg -i athan.mp3 -b:a 128k athan_compressed.mp3
```

## 📊 Popular file examples

| Name | Duration | Description |
|------|----------|-------------|
| Athan Makkah | 3-4 min | Athan from the Grand Mosque of Makkah |
| Athan Madinah | 3-4 min | Athan from the Prophet's Mosque |
| Sheikh Mishary | 2-3 min | Melodious style |
| Egyptian Athan | 3-5 min | Traditional Egyptian style |

## 💡 Tips

- **Always test** your file before first use
- **Back up** your favorite files
- **Normalize** the volume to avoid surprises
- **Name** your files descriptively

## 📚 Resources

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [Audio File Format Specifications](https://en.wikipedia.org/wiki/Audio_file_format)
- [Islamic Audio Resources](https://www.islamicfinder.org/)

---

**For more help, see AUDIO_SETUP.md in the root folder**
