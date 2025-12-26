# Athan Center API Documentation

Complete REST API documentation for Athan Center.

Base URL: `http://YOUR_SERVER_IP:7777/api`

## Table of Contents

- [Prayer Times](#prayer-times)
- [Prayer Checks](#prayer-checks)
- [Settings](#settings)
- [Prayer Schedule](#prayer-schedule)
- [Audio Control](#audio-control)
- [Mute Control](#mute-control)
- [Server Information](#server-information)

---

## Prayer Times

### Get Prayers for a Specific Date

Get all prayers for a given date.

**Endpoint:** `GET /api/prayers/:date`

**Parameters:**
- `date` (path) - Date in YYYY-MM-DD format

**Example:**
```bash
curl http://localhost:7777/api/prayers/2025-01-15
```

**Response:**
```json
[
  {
    "id": 1,
    "date": "2025-01-15",
    "prayer_name": "Fajr",
    "prayer_time": "06:30"
  },
  {
    "id": 2,
    "date": "2025-01-15",
    "prayer_name": "Dhuhr",
    "prayer_time": "12:45"
  }
]
```

---

### Get Next Upcoming Prayer

Get the next prayer that is strictly in the future.

**Endpoint:** `GET /api/prayers/next/upcoming`

**Example:**
```bash
curl http://localhost:7777/api/prayers/next/upcoming
```

**Response:**
```json
{
  "id": 3,
  "date": "2025-01-15",
  "prayer_name": "Asr",
  "prayer_time": "15:30"
}
```

---

### Get Next Prayer as Natural Language Text

Get the next prayer information in natural language format.

**Endpoint:** `GET /api/next-prayer-text`

**Query Parameters:**
- `lang` (optional) - Language code (FR or EN, default: FR)

**Examples:**
```bash
# French (default)
curl http://localhost:7777/api/next-prayer-text

# English
curl http://localhost:7777/api/next-prayer-text?lang=EN
```

**Response (French):**
```
Salat Al Fajr est à 06:30, il reste 2 heures et 15 minutes avant l'athan
```

**Response (English):**
```
Salat Al Fajr is at 06:30, 2 hours and 15 minutes remaining before athan
```

**Special Cases:**
- If no prayers are configured: `Athan Center doit être configuré` (FR) or `Athan Center must be configured` (EN)
- Automatically returns tomorrow's first prayer if all today's prayers have passed

---

## Prayer Checks

### Get Prayer Checks for a Date

Get all prayer check statuses for a specific date.

**Endpoint:** `GET /api/prayer-checks/:date`

**Parameters:**
- `date` (path) - Date in YYYY-MM-DD format

**Example:**
```bash
curl http://localhost:7777/api/prayer-checks/2025-01-15
```

**Response:**
```json
[
  {
    "id": 1,
    "date": "2025-01-15",
    "prayer_name": "Fajr",
    "checked": 1,
    "checked_at": "2025-01-15T06:35:00.000Z"
  }
]
```

**Check States:**
- `0` - Unchecked
- `1` - Green check mark
- `2` - Orange check mark

---

### Toggle Prayer Check

Toggle the check state of a prayer (cycles through: unchecked → orange → green → unchecked).

**Endpoint:** `POST /api/prayer-checks/toggle`

**Body:**
```json
{
  "date": "2025-01-15",
  "prayer_name": "Fajr"
}
```

**Example:**
```bash
curl -X POST http://localhost:7777/api/prayer-checks/toggle \
  -H "Content-Type: application/json" \
  -d '{"date":"2025-01-15","prayer_name":"Fajr"}'
```

**Response:**
```json
{
  "success": true,
  "checked": 2
}
```

---

### Reset All Prayer Checks

Remove all prayer check marks from the database.

**Endpoint:** `POST /api/prayer-checks/reset`

**Example:**
```bash
curl -X POST http://localhost:7777/api/prayer-checks/reset
```

**Response:**
```json
{
  "success": true,
  "message": "All prayer checks have been reset"
}
```

---

## Settings

### Get All Settings

Retrieve all application settings.

**Endpoint:** `GET /api/settings`

**Example:**
```bash
curl http://localhost:7777/api/settings
```

**Response:**
```json
{
  "ics_url": "https://prayerwebcal.dsultan.com/ics/...",
  "audio_file": "Masjid Al-Haram.mp3",
  "audio_output": "both",
  "volume": "50",
  "dark_mode": "0"
}
```

---

### Update a Setting

Update a specific setting value.

**Endpoint:** `POST /api/settings`

**Body:**
```json
{
  "key": "volume",
  "value": "75"
}
```

**Example:**
```bash
curl -X POST http://localhost:7777/api/settings \
  -H "Content-Type: application/json" \
  -d '{"key":"volume","value":"75"}'
```

---

## Prayer Schedule

### Get Prayer Schedule Matrix

Get the complete prayer schedule (5 prayers × 7 days).

**Endpoint:** `GET /api/prayer-schedule`

**Example:**
```bash
curl http://localhost:7777/api/prayer-schedule
```

**Response:**
```json
[
  {
    "id": 1,
    "prayer_name": "Fajr",
    "day_of_week": 0,
    "enabled": 1
  }
]
```

**Day of Week:**
- `0` - Monday
- `1` - Tuesday
- `2` - Wednesday
- `3` - Thursday
- `4` - Friday
- `5` - Saturday
- `6` - Sunday

---

### Update Prayer Schedule Cell

Update a specific prayer/day combination.

**Endpoint:** `POST /api/prayer-schedule`

**Body:**
```json
{
  "prayer_name": "Fajr",
  "day_of_week": 0,
  "enabled": 1
}
```

---

### Bulk Update Prayer Schedule

Update an entire row (all days for one prayer) or column (all prayers for one day).

**Endpoint:** `POST /api/prayer-schedule/bulk`

**Body (update all days for Fajr):**
```json
{
  "type": "prayer",
  "target": "Fajr",
  "enabled": 1
}
```

**Body (update all prayers for Monday):**
```json
{
  "type": "day",
  "target": 0,
  "enabled": 1
}
```

---

## Audio Control

### Stop All Audio

Stop all currently playing audio (athan, Quran, tests).

**Endpoint:** `GET /api/stop-audio`

**Example:**
```bash
curl http://localhost:7777/api/stop-audio
```

---

### Test Athan on Server

Play a 30-second athan sample on server speakers.

**Endpoint:** `GET /api/test-athan-server`

**Example:**
```bash
curl http://localhost:7777/api/test-athan-server
```

---

### Test Quran on Server

Play a 30-second Quran sample on server speakers.

**Endpoint:** `GET /api/test-quran-server`

**Example:**
```bash
curl http://localhost:7777/api/test-quran-server
```

---

### Trigger Friday Quran

Manually trigger Friday Quran recitation.

**Endpoint:** `GET /api/trigger-friday-quran`

**Example:**
```bash
curl http://localhost:7777/api/trigger-friday-quran
```

---

## Mute Control

### Mute Next Athan

Skip the next upcoming athan.

**Endpoint:** `GET /api/mute-next-athan`

**Example:**
```bash
curl http://localhost:7777/api/mute-next-athan
```

**Response:**
```json
{
  "success": true,
  "message": "Next athan (Asr on 2025-01-15) will be muted"
}
```

---

### Unmute Next Athan

Cancel the mute and allow the next athan to play.

**Endpoint:** `GET /api/skip-next/reset`

**Example:**
```bash
curl http://localhost:7777/api/skip-next/reset
```

---

### Get Mute Status

Check if the next athan is muted.

**Endpoint:** `GET /api/skip-next`

**Example:**
```bash
curl http://localhost:7777/api/skip-next
```

**Response:**
```json
{
  "skip": true
}
```

---

## Server Information

### Get Server Time

Get current server time and system information.

**Endpoint:** `GET /api/server-time`

**Example:**
```bash
curl http://localhost:7777/api/server-time
```

**Response:**
```json
{
  "timestamp": "2025-01-15T10:30:45.123Z",
  "timestampMs": 1705318245123,
  "date": "15/01/2025",
  "time": "10:30:45",
  "ip": "192.168.1.100",
  "hostname": "raspberrypi"
}
```

---

### Get Update Information

Get information about prayer times updates.

**Endpoint:** `GET /api/update-info`

**Example:**
```bash
curl http://localhost:7777/api/update-info
```

**Response:**
```json
{
  "last_update": "2025-01-15T00:00:00.000Z",
  "prayers_count": 450,
  "city_name": "Mecca",
  "next_update": "2025-01-16T00:00:00.000Z"
}
```

---

### Force Prayer Times Update

Manually trigger a prayer times update from the ICS source.

**Endpoint:** `POST /api/update-prayers`

**Example:**
```bash
curl -X POST http://localhost:7777/api/update-prayers
```

---

### Get Audio Support Status

Check if server audio is supported on the current system.

**Endpoint:** `GET /api/audio-support`

**Example:**
```bash
curl http://localhost:7777/api/audio-support
```

**Response:**
```json
{
  "supported": true,
  "message": "Server audio is supported"
}
```

---

## Integration Examples

### Home Assistant

```yaml
# configuration.yaml
rest_command:
  mute_next_athan:
    url: "http://192.168.1.100:7777/api/mute-next-athan"
    method: GET
  
  stop_athan:
    url: "http://192.168.1.100:7777/api/stop-audio"
    method: GET

sensor:
  - platform: rest
    name: Next Prayer
    resource: "http://192.168.1.100:7777/api/next-prayer-text?lang=EN"
    scan_interval: 60
```

### Node-RED

```json
[
  {
    "id": "http_request",
    "type": "http request",
    "url": "http://192.168.1.100:7777/api/next-prayer-text?lang=FR",
    "method": "GET"
  }
]
```

### Python Script

```python
import requests

# Get next prayer
response = requests.get('http://192.168.1.100:7777/api/next-prayer-text?lang=FR')
print(response.text)

# Mute next athan
requests.get('http://192.168.1.100:7777/api/mute-next-athan')
```

---

## Error Handling

All endpoints return appropriate HTTP status codes:

- `200` - Success
- `400` - Bad Request
- `404` - Not Found
- `500` - Internal Server Error

Error responses include a message:

```json
{
  "error": "Error message description"
}
```

---

## Rate Limiting

Currently, there are no rate limits on API endpoints. However, it's recommended to:

- Cache responses when possible
- Avoid excessive polling (use reasonable intervals like 60 seconds)
- Use webhooks or scheduled tasks instead of continuous polling

---

**For questions or issues, please open an issue on [GitHub](https://github.com/simoroco/athan-center/issues).**
