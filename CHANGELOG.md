# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New API endpoint `/api/next-prayer-text` for natural language prayer information
  - Supports French and English languages
  - Returns next prayer with time remaining in human-readable format
- Calendar button now displays weekday name in English
  - Shows "Today (DD/MM)" for current day
  - Shows weekday name for other days (e.g., "Saturday (27/12)")
- Triple-state prayer check system
  - Click once: Orange check mark
  - Click twice: Green check mark
  - Click third time: Remove check mark
- Prayer name "Fajr" now displays as "Fajr | Sobh"

### Changed
- Improved README structure and content
- Enhanced API documentation
- Updated screenshots section to use animated GIF

### Fixed
- Calendar button date display consistency

## [3.0.1] - 2025-01-XX

### Added
- Initial stable release
- Automatic Athan playback at prayer times
- Prayer times display with real-time countdown
- Customizable location via ICS link
- Per-prayer enable/disable settings
- One-time skip functionality
- Responsive web interface
- REST API for remote control
- Automatic daily prayer times update
- Configuration export/import
- Docker deployment support
- Friday Quran recitation scheduling
- Dark mode support
- Multi-device audio output (server/browser/both)
- Volume control with separate Fajr volume
- Audio device selection for Raspberry Pi
- Prayer schedule matrix (5 prayers × 7 days)
- Weekday mute functionality

### Technical
- Node.js backend with Express.js
- SQLite database for data persistence
- HTML5/CSS3/JavaScript frontend
- Docker containerization
- Audio playback via sox/alsa/play-sound
- Scheduling with node-cron and node-schedule

## [3.0.0] - 2024-12-XX

### Added
- Major refactoring and improvements
- Enhanced UI/UX
- Better error handling
- Improved documentation

## [2.0.0] - 2024-XX-XX

### Added
- Docker support
- REST API
- Configuration management

## [1.0.0] - 2024-XX-XX

### Added
- Initial release
- Basic prayer times display
- Athan playback functionality

---

## Release Notes

### How to Upgrade

1. **Backup your configuration**
   ```bash
   # Export your settings from the web interface
   ```

2. **Pull the latest version**
   ```bash
   git pull origin main
   # OR
   docker pull simoroco/athan-center:latest
   ```

3. **Restart the application**
   ```bash
   npm run dev
   # OR
   docker-compose restart
   ```

### Breaking Changes

None in current version.

### Deprecations

None in current version.

---

**Note:** For detailed commit history, see the [GitHub commits page](https://github.com/simoroco/athan-center/commits/main).
