# Deployment Guide

Complete deployment guide for Athan Center on various platforms.

## Table of Contents

- [Quick Start](#quick-start)
- [Docker Deployment](#docker-deployment)
- [Raspberry Pi Setup](#raspberry-pi-setup)
- [Manual Installation](#manual-installation)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

The fastest way to get started with Athan Center.

### Using Docker (Recommended)

```bash
# Pull the latest image
docker pull simoroco/athan-center:latest

# Run the container
docker run -d \
  --name athan-center \
  -p 7777:7777 \
  -v athan-data:/app/data \
  --restart unless-stopped \
  simoroco/athan-center:latest
```

Access the web interface at `http://localhost:7777`

### Using npm

```bash
# Clone the repository
git clone https://github.com/simoroco/athan-center.git
cd athan-center/app

# Install dependencies
npm install

# Start the application
npm start
```

---

## Docker Deployment

### Prerequisites

- Docker installed
- Docker Compose (optional but recommended)
- Audio device access (for server audio on Linux)

### Docker Compose (Recommended)

Create a `docker-compose.yml` file:

```yaml
version: '3.8'

services:
  athan-center:
    image: simoroco/athan-center:latest
    container_name: athan-center
    ports:
      - "7777:7777"
    volumes:
      - ./data:/app/data
      - ./audio:/app/audio
    devices:
      - /dev/snd:/dev/snd  # For audio on Linux
    environment:
      - TZ=Europe/Paris  # Set your timezone
    restart: unless-stopped
```

Start the service:

```bash
docker-compose up -d
```

### Docker Run Command

```bash
docker run -d \
  --name athan-center \
  -p 7777:7777 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/audio:/app/audio \
  --device /dev/snd:/dev/snd \
  -e TZ=Europe/Paris \
  --restart unless-stopped \
  simoroco/athan-center:latest
```

### Platform-Specific Notes

#### Linux
- Audio device `/dev/snd` is required for server audio
- Run with `--privileged` if audio issues occur
- Ensure user has audio group permissions

#### macOS
- Remove `--device /dev/snd:/dev/snd` (not needed)
- Server audio not supported, use browser audio only
- Docker Desktop required

#### Windows
- Remove `--device /dev/snd:/dev/snd` (not needed)
- Server audio not supported, use browser audio only
- Docker Desktop required
- Use PowerShell or WSL2 for commands

---

## Raspberry Pi Setup

Perfect for a dedicated Athan device!

### Hardware Requirements

- Raspberry Pi 3/4/5 (recommended: Pi 4 with 2GB+ RAM)
- MicroSD card (16GB minimum)
- Speakers or audio output device
- Power supply
- Network connection (WiFi or Ethernet)

### Step-by-Step Setup

#### 1. Install Raspberry Pi OS

```bash
# Use Raspberry Pi Imager
# Choose: Raspberry Pi OS Lite (64-bit) for headless setup
# Or: Raspberry Pi OS with Desktop for GUI
```

#### 2. Initial Configuration

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose -y

# Reboot
sudo reboot
```

#### 3. Configure Audio

```bash
# Test audio output
speaker-test -t wav -c 2

# List audio devices
aplay -l

# Set default audio device (if needed)
sudo nano /etc/asound.conf
```

Add to `/etc/asound.conf`:
```
defaults.pcm.card 1
defaults.ctl.card 1
```

#### 4. Deploy Athan Center

```bash
# Create directory
mkdir ~/athan-center
cd ~/athan-center

# Create docker-compose.yml
nano docker-compose.yml
```

Paste the Docker Compose configuration from above, then:

```bash
# Start the service
docker-compose up -d

# Check logs
docker-compose logs -f
```

#### 5. Auto-start on Boot

Docker Compose with `restart: unless-stopped` handles this automatically.

#### 6. Access the Interface

- Local: `http://raspberrypi.local:7777`
- Network: `http://RASPBERRY_PI_IP:7777`

### Audio Optimization for Raspberry Pi

```bash
# Increase audio buffer (if crackling occurs)
sudo nano /boot/config.txt
```

Add:
```
audio_pwm_mode=2
```

Reboot after changes.

---

## Manual Installation

For development or custom setups.

### Prerequisites

- Node.js >= 16.0.0
- npm or yarn
- Git
- sox (for server audio on Linux)

### Installation Steps

#### 1. Install Node.js

**Ubuntu/Debian:**
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

**macOS:**
```bash
brew install node
```

**Windows:**
Download from [nodejs.org](https://nodejs.org/)

#### 2. Install Audio Dependencies (Linux only)

```bash
sudo apt install -y sox libsox-fmt-all alsa-utils
```

#### 3. Clone and Install

```bash
# Clone repository
git clone https://github.com/simoroco/athan-center.git
cd athan-center/app

# Install dependencies
npm install

# Start development server
npm run dev

# Or start production server
npm start
```

#### 4. Configure as System Service (Linux)

Create `/etc/systemd/system/athan-center.service`:

```ini
[Unit]
Description=Athan Center
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/athan-center/app
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable athan-center
sudo systemctl start athan-center
sudo systemctl status athan-center
```

---

## Configuration

### Initial Setup

1. Access the web interface: `http://YOUR_IP:7777`
2. Go to Settings (⚙️ button)
3. Configure your location:
   - Visit [Prayer WebCal](https://prayerwebcal.dsultan.com/)
   - Generate your ICS link
   - Paste it in Athan Center settings
   - Click "Load ICS link with athans times"

### Audio Configuration

#### Server Audio (Linux/Raspberry Pi)
- Select audio output device
- Adjust volume (0-200%)
- Test with "Test server Athan" button

#### Browser Audio (All platforms)
- Works on any device with a web browser
- Volume controlled by browser/device
- Requires browser tab to be open

#### Both (Recommended)
- Plays on server speakers AND browser
- Redundancy ensures athan is heard
- Best for mosque/home setups

### Prayer Schedule

Configure which prayers play on which days:
- Use the schedule matrix in settings
- Enable/disable per prayer per day
- Or use "All" tab for weekly settings

### Friday Quran

- Enable Friday Quran recitation
- Set time (e.g., 07:00)
- Upload Sourat Al Kahf audio file to `/audio/coran/`

---

## Troubleshooting

### Audio Issues

**No sound on Raspberry Pi:**
```bash
# Check audio devices
aplay -l

# Test audio
speaker-test -t wav -c 2

# Check volume
alsamixer

# Restart service
docker-compose restart
```

**Crackling/distorted audio:**
- Reduce volume below 100%
- Check audio buffer settings
- Use better quality audio files
- Ensure adequate power supply (Pi)

### Network Issues

**Cannot access web interface:**
```bash
# Check if service is running
docker ps
# Or for manual install:
sudo systemctl status athan-center

# Check port
sudo netstat -tulpn | grep 7777

# Check firewall
sudo ufw allow 7777/tcp
```

### Prayer Times Not Updating

**Check ICS URL:**
- Verify URL is accessible
- Test in browser
- Check internet connection
- Review logs for errors

**Force update:**
- Use "Update athan times now" button in settings
- Or via API: `curl http://localhost:7777/api/update-prayers -X POST`

### Docker Issues

**Container won't start:**
```bash
# Check logs
docker logs athan-center

# Check permissions
ls -la data/

# Recreate container
docker-compose down
docker-compose up -d
```

**Audio not working in Docker:**
```bash
# Ensure audio device is mapped
docker run --device /dev/snd:/dev/snd ...

# Check container has audio access
docker exec -it athan-center aplay -l
```

### Database Issues

**Corrupt database:**
```bash
# Backup current database
cp data/prayer.db data/prayer.db.backup

# Delete and restart (will recreate)
rm data/prayer.db
docker-compose restart
```

### Performance Issues

**High CPU usage:**
- Check for infinite loops in logs
- Restart service
- Update to latest version

**High memory usage:**
- Normal: 50-150MB
- If higher: restart service
- Check for memory leaks in logs

---

## Backup and Restore

### Backup

```bash
# Backup data directory
tar -czf athan-backup-$(date +%Y%m%d).tar.gz data/

# Or just the database
cp data/prayer.db prayer-backup-$(date +%Y%m%d).db
```

### Restore

```bash
# Stop service
docker-compose down

# Restore data
tar -xzf athan-backup-20250115.tar.gz

# Start service
docker-compose up -d
```

---

## Security Considerations

### Network Security

- Run behind a firewall
- Use VPN for remote access
- Don't expose to public internet without authentication
- Use HTTPS reverse proxy (nginx/traefik) if needed

### Updates

```bash
# Docker
docker-compose pull
docker-compose up -d

# Manual
cd athan-center
git pull
cd app
npm install
npm restart
```

---

## Advanced Configuration

### Custom Audio Files

Place audio files in:
- Athan: `/app/audio/athan/`
- Quran: `/app/audio/coran/`

Supported formats: MP3, WAV

### Environment Variables

```bash
# Set timezone
TZ=Asia/Riyadh

# Set port (default: 7777)
PORT=8080

# Node environment
NODE_ENV=production
```

### Reverse Proxy (nginx)

```nginx
server {
    listen 80;
    server_name athan.example.com;

    location / {
        proxy_pass http://localhost:7777;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

---

## Support

- **Documentation:** [README.md](./README.md)
- **API Docs:** [API.md](./API.md)
- **Issues:** [GitHub Issues](https://github.com/simoroco/athan-center/issues)
- **Contributing:** [CONTRIBUTING.md](./CONTRIBUTING.md)

---

**May Allah make this deployment easy for you** 🤲
