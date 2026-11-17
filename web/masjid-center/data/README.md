# 💾 Data Folder

This folder contains the Masjid Center SQLite database.

## 📁 Contents

- `prayer.db` - SQLite database (created automatically)

## 🗄️ Database Structure

### Table `prayers`
Stores the prayer times for each day.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Auto-incremented identifier |
| date | TEXT | Date in YYYY-MM-DD format |
| prayer_name | TEXT | Prayer name (Fajr, Dhuhr, etc.) |
| prayer_time | TEXT | Time in HH:MM format |

**Index**: UNIQUE(date, prayer_name)

### Table `settings`
Global application settings.

| Column | Type | Description |
|--------|------|-------------|
| key | TEXT | Setting key (PRIMARY KEY) |
| value | TEXT | Setting value |

**Default settings**:
- `ics_url`: ICS calendar URL
- `location_type`: Location type (url, gps, city, wifi)
- `audio_file`: Athan audio file name

### Table `prayer_settings`
Activation configuration for each prayer.

| Column | Type | Description |
|--------|------|-------------|
| prayer_name | TEXT | Prayer name (PRIMARY KEY) |
| enabled | INTEGER | 1 = enabled, 0 = disabled |

### Table `skip_next`
Manages one-time skipping of the next athan.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Always 1 (PRIMARY KEY) |
| skip | INTEGER | 1 = skip active, 0 = normal |

## 🔍 Accessing the Database

### From the Docker container

```bash
# Enter the container
docker exec -it masjid-center /bin/bash

# Open the database
sqlite3 /app/data/prayer.db

# Example queries
sqlite> .tables                          # List tables
sqlite> SELECT * FROM prayers LIMIT 5;   # View a few prayers
sqlite> SELECT * FROM settings;          # View settings
sqlite> .exit                            # Exit
```

### From the host (if SQLite is installed)

```bash
sqlite3 data/prayer.db
```

## 📊 Useful Queries

### View today's prayers

```sql
SELECT * FROM prayers 
WHERE date = date('now', 'localtime') 
ORDER BY prayer_time;
```

### Count stored prayers

```sql
SELECT COUNT(*) FROM prayers;
```

### View prayers for a specific date

```sql
SELECT * FROM prayers 
WHERE date = '2024-11-10' 
ORDER BY prayer_time;
```

### See which prayers are enabled

```sql
SELECT prayer_name, 
       CASE WHEN enabled = 1 THEN 'Enabled' ELSE 'Disabled' END as status
FROM prayer_settings;
```

### View all settings

```sql
SELECT * FROM settings;
```

### Clean up old prayers (> 6 months)

```sql
DELETE FROM prayers 
WHERE date < date('now', '-6 months');

VACUUM;  -- Optimize the database
```

## 💾 Backup and Restore

### Create a backup

```bash
# Simple backup
cp data/prayer.db data/prayer.db.backup

# Backup with date
cp data/prayer.db data/prayer.db.$(date +%Y%m%d)

# Compressed backup
tar -czf backup-prayer-$(date +%Y%m%d).tar.gz data/prayer.db
```

### Restore a backup

```bash
# Stop the application
docker-compose down

# Restore
cp data/prayer.db.backup data/prayer.db

# Restart
docker-compose up -d
```

### Export to CSV

```bash
sqlite3 data/prayer.db <<EOF
.headers on
.mode csv
.output prayers_export.csv
SELECT * FROM prayers;
.quit
EOF
```

### Import from CSV

```bash
sqlite3 data/prayer.db <<EOF
.mode csv
.import prayers_import.csv prayers
.quit
EOF
```

## 🔧 Maintenance

### Optimize the database

```sql
-- Rebuild indexes
REINDEX;

-- Optimize space
VACUUM;

-- Analyze for statistics
ANALYZE;
```

### Check integrity

```sql
PRAGMA integrity_check;
```

### View database size

```bash
ls -lh data/prayer.db
```

### Statistics

```sql
-- Number of prayers per month
SELECT strftime('%Y-%m', date) as month, COUNT(*) as count
FROM prayers
GROUP BY month
ORDER BY month DESC;

-- Number of prayers per name
SELECT prayer_name, COUNT(*) as count
FROM prayers
GROUP BY prayer_name;
```

## ⚠️ Warnings

### Do not modify manually

The database is managed automatically by the application. Manual changes can cause issues.

### Regular backups

Back up the database regularly, especially:
- Before an update
- Before modifying settings
- At least once a month

### Permissions

Make sure the Docker container has the right permissions:

```bash
sudo chown -R 1000:1000 data/
chmod 644 data/prayer.db
```

## 🔄 Migration

If you are migrating to a new server:

1. **Back up**:
```bash
cp data/prayer.db /path/to/backup/
```

2. **Transfer**:
```bash
scp data/prayer.db user@new-server:/path/to/masjid-center/data/
```

3. **Verify**:
```bash
# On the new server
sqlite3 data/prayer.db "SELECT COUNT(*) FROM prayers;"
```

## 📈 Monitoring

### Database size

```bash
# Monitor growth
watch -n 60 'ls -lh data/prayer.db'
```

### Last modification

```bash
stat data/prayer.db
```

## 🐛 Troubleshooting

### The database is corrupted

```bash
# 1. Stop the application
docker-compose down

# 2. Check integrity
sqlite3 data/prayer.db "PRAGMA integrity_check;"

# 3. If corrupted, restore from backup
cp data/prayer.db.backup data/prayer.db

# 4. Restart
docker-compose up -d
```

### "database is locked" error

```bash
# Check processes using the DB
lsof data/prayer.db

# Restart the application
docker-compose restart
```

### The database is empty

```bash
# Force a prayer times update
# Via the web interface: Settings > Update prayer times now

# Or via API
curl -X POST http://localhost:7777/api/update-prayers
```

## 📚 Resources

- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [SQL Tutorial](https://www.w3schools.com/sql/)
- [SQLite Browser](https://sqlitebrowser.org/) - Graphical interface for SQLite

---

**Note**: This file is created automatically on the application's first startup.
