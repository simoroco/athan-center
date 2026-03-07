const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const schedule = require('node-schedule');
const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');
const axios = require('axios');
const ical = require('ical');
const player = require('play-sound')({});
const { spawn } = require('child_process');
const os = require('os');
const ExcelJS = require('exceljs');

const app = express();
const PORT = 7777;

// ===== LOGGING UTILITY WITH TIMESTAMP =====
function getTimestamp() {
    const now = new Date();
    return now.toISOString().replace('T', ' ').substring(0, 19);
}

function log(...args) {
    console.log(`[${getTimestamp()}]`, ...args);
}

function logError(...args) {
    console.error(`[${getTimestamp()}] ERROR:`, ...args);
}

function logWarn(...args) {
    console.warn(`[${getTimestamp()}] WARN:`, ...args);
}

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Database initialization
log('🚀 Starting Athan Center server initialization...');
const dbPath = path.join(__dirname, 'data', 'prayer.db');
if (!fs.existsSync(path.join(__dirname, 'data'))) {
    log('📂 Creating data directory...');
    fs.mkdirSync(path.join(__dirname, 'data'), { recursive: true });
}

log(`📊 Initializing database at: ${dbPath}`);
const db = new Database(dbPath);
log('✅ Database connected successfully');

// Create tables
db.exec(`
    CREATE TABLE IF NOT EXISTS prayers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        prayer_name TEXT NOT NULL,
        prayer_time TEXT NOT NULL,
        UNIQUE(date, prayer_name)
    );

    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS prayer_settings (
        prayer_name TEXT PRIMARY KEY,
        enabled INTEGER DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS skip_next (
        id INTEGER PRIMARY KEY,
        skip INTEGER DEFAULT 0,
        last_skipped_prayer TEXT DEFAULT NULL,
        last_skipped_date TEXT DEFAULT NULL
    );

    CREATE TABLE IF NOT EXISTS update_info (
        id INTEGER PRIMARY KEY,
        last_update TEXT,
        prayers_count INTEGER DEFAULT 0,
        city_name TEXT,
        next_update TEXT
    );

    CREATE TABLE IF NOT EXISTS muted_weekdays (
        weekday INTEGER PRIMARY KEY,
        muted INTEGER DEFAULT 0,
        CHECK(weekday >= 0 AND weekday <= 6)
    );

    CREATE TABLE IF NOT EXISTS friday_quran_trigger (
        id INTEGER PRIMARY KEY,
        should_play INTEGER DEFAULT 0,
        last_played_date TEXT DEFAULT NULL,
        last_played_time TEXT DEFAULT NULL
    );

    CREATE TABLE IF NOT EXISTS prayer_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prayer_name TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        enabled INTEGER DEFAULT 1,
        UNIQUE(prayer_name, day_of_week),
        CHECK(day_of_week >= 0 AND day_of_week <= 6)
    );

    CREATE TABLE IF NOT EXISTS prayer_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        prayer_name TEXT NOT NULL,
        checked INTEGER DEFAULT 0,
        checked_at TEXT DEFAULT NULL,
        UNIQUE(date, prayer_name)
    );

    CREATE TABLE IF NOT EXISTS daily_activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        activity_name TEXT NOT NULL,
        checked INTEGER DEFAULT 0,
        checked_at TEXT DEFAULT NULL,
        UNIQUE(date, activity_name)
    );

    CREATE TABLE IF NOT EXISTS hijri_dates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gregorian_date TEXT NOT NULL UNIQUE,
        hijri_year INTEGER NOT NULL,
        hijri_month INTEGER NOT NULL,
        hijri_day INTEGER NOT NULL,
        hijri_month_name TEXT NOT NULL,
        is_ramadan INTEGER DEFAULT 0
    );
`);

// Initialize friday_quran_trigger
db.prepare('INSERT OR IGNORE INTO friday_quran_trigger (id, should_play, last_played_date, last_played_time) VALUES (1, 0, NULL, NULL)').run();

// Initialize default settings
const initSettings = db.prepare('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)');
initSettings.run('ics_url', 'https://prayerwebcal.dsultan.com/ics/La_Mecque/cq=0:csr=0:ct=0:ee=0:qs=0:srs=0:ss=0:sus=0:ts=0:tz=Asia%2FRiyadh:x=21.421:y=39.827');
initSettings.run('audio_file', 'Masjid Al-Haram.mp3'); // Default Athan audio file
initSettings.run('play_on_startup', '1');
initSettings.run('play_on_page_load', '0');
initSettings.run('audio_output', 'both'); // Options: 'server', 'browser', 'both'
initSettings.run('volume', '50'); // Default volume at 50%
initSettings.run('audio_card', 'auto'); // Auto-detect or specific card number (0, 1, 2, etc.)
initSettings.run('friday_quran_enabled', '0'); // Friday Quran recitation
initSettings.run('friday_quran_time', '07:00'); // Default time 7:00 AM
initSettings.run('friday_quran_file', 'Sourat Al Kahf - Hani Arrifai.mp3'); // Default Quran audio file
initSettings.run('dark_mode', '0'); // Dark mode disabled by default
initSettings.run('fajr_volume', '50'); // Default Fajr volume at 50% (same as main volume)
initSettings.run('sync_fajr_volume', '0'); // Sync Fajr volume disabled by default (independent volume)

// Prayer name mapping: WebCal ICS names → Internal database names
function mapPrayerNameFromWebCal(webCalName) {
    const mapping = {
        'Fajr': 'Fajr | Sobh',
        'Dhuhr': 'Dohr',
        'Asr': 'Asr',
        'Maghrib': 'Maghrib',
        'Isha': 'Isha'
    };
    return mapping[webCalName] || webCalName;
}

// NOTE: prayer_settings table is DEPRECATED - kept for backward compatibility only
// All prayer enable/disable logic now uses prayer_schedule matrix
const prayerNames = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

// Initialize prayer schedule (5 prayers × 7 days = 35 entries, all enabled by default)
// day_of_week: 0=Monday, 1=Tuesday, 2=Wednesday, 3=Thursday, 4=Friday, 5=Saturday, 6=Sunday
const initPrayerSchedule = db.prepare('INSERT OR IGNORE INTO prayer_schedule (prayer_name, day_of_week, enabled) VALUES (?, ?, 1)');
for (let day = 0; day <= 6; day++) {
    prayerNames.forEach(prayerName => {
        initPrayerSchedule.run(prayerName, day);
    });
}
log('✅ Prayer schedule matrix initialized: 5 prayers × 7 days = 35 entries');

// Initialize skip_next with migration for new columns
// First, check if the new columns exist
const skipNextColumns = db.pragma('table_info(skip_next)');
const hasLastSkippedPrayer = skipNextColumns.some(col => col.name === 'last_skipped_prayer');
const hasLastSkippedDate = skipNextColumns.some(col => col.name === 'last_skipped_date');

// Add new columns if they don't exist
if (!hasLastSkippedPrayer) {
    log('Adding last_skipped_prayer column to skip_next table...');
    db.prepare('ALTER TABLE skip_next ADD COLUMN last_skipped_prayer TEXT DEFAULT NULL').run();
}
if (!hasLastSkippedDate) {
    log('Adding last_skipped_date column to skip_next table...');
    db.prepare('ALTER TABLE skip_next ADD COLUMN last_skipped_date TEXT DEFAULT NULL').run();
}

// Initialize skip_next row
db.prepare('INSERT OR IGNORE INTO skip_next (id, skip, last_skipped_prayer, last_skipped_date) VALUES (1, 0, NULL, NULL)').run();

// Initialize update_info
db.prepare('INSERT OR IGNORE INTO update_info (id, last_update, prayers_count, city_name, next_update) VALUES (1, NULL, 0, NULL, NULL)').run();

// State variables for scheduled jobs
let scheduledJobs = [];
let currentAudioPlayer = null;
let currentAudioType = null; // Track what type of audio is playing: 'quran', 'athan', 'startup', 'test', null
let fridayQuranJob = null;

// System time tracking for drift detection
let lastSystemTime = Date.now();

// Audio support cache to avoid testing during playback
let audioSupportCache = null;
let audioSupportCacheTime = 0;
const AUDIO_SUPPORT_CACHE_DURATION = 60000; // 1 minute cache

// Initialize muted_weekdays (0=Sunday, 1=Monday, ..., 6=Saturday)
const weekdays = [0, 1, 2, 3, 4, 5, 6];
const initWeekday = db.prepare('INSERT OR IGNORE INTO muted_weekdays (weekday, muted) VALUES (?, 0)');
weekdays.forEach(day => initWeekday.run(day));

// Verify and log current weekday mute status
log('\n===== WEEKDAY MUTE STATUS =====');
const currentWeekdayMutes = db.prepare('SELECT * FROM muted_weekdays ORDER BY weekday').all();
const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
currentWeekdayMutes.forEach(day => {
    const status = day.muted === 1 ? '❌ MUTED' : '✅ ENABLED';
    log(`  ${weekdayNames[day.weekday]}: ${status}`);
});
log('===============================\n');

// Automatically correct any weekday mute status to ensure none are muted by default
currentWeekdayMutes.forEach(day => {
    if (day.muted === 1) {
        log(`Correcting weekday mute status for ${weekdayNames[day.weekday]} from MUTED to ENABLED`);
        db.prepare('UPDATE muted_weekdays SET muted = 0 WHERE weekday = ?').run(day.weekday);
    }
});

// Set default ICS URL if empty or not properly configured
const currentIcsUrl = db.prepare('SELECT value FROM settings WHERE key = ?').get('ics_url');
if (!currentIcsUrl || !currentIcsUrl.value || currentIcsUrl.value.trim() === '') {
    db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(
        'ics_url',
        'https://prayerwebcal.dsultan.com/ics/La_Mecque/cq=0:csr=0:ct=0:ee=0:qs=0:srs=0:ss=0:sus=0:ts=0:tz=Asia%2FRiyadh:x=21.421:y=39.827'
    );
    log('ICS URL was empty, set to default: La Mecque (Makkah)');
}

// Utility function to format date as YYYY-MM-DD using local time (avoiding timezone issues)
function formatDateLocal(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

// Get server IP address (uses HOST_IP from entrypoint if available)
function getServerIPAddress() {
    // Use HOST_IP from environment (detected by entrypoint from Docker gateway)
    if (process.env.HOST_IP) {
        return process.env.HOST_IP;
    }

    // Fallback: get container IP from network interfaces
    const interfaces = os.networkInterfaces();
    for (const ifaceName of Object.keys(interfaces)) {
        for (const iface of interfaces[ifaceName]) {
            // Skip internal (loopback) and non-IPv4 addresses
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1'; // Fallback to localhost
}

// Extract the city name from the ICS URL
function extractCityFromIcsUrl(url) {
    try {
        // Format: https://prayerwebcal.dsultan.com/ics/City_Name_Country/...
        const match = url.match(/\/ics\/([^\/]+)/);
        if (match && match[1]) {
            // Replace underscores with spaces
            return decodeURIComponent(match[1].replace(/_/g, ' '));
        }
        return 'Not configured';
    } catch (error) {
        return 'Not configured';
    }
}

// Calculate the next update time (today or tomorrow at 7 PM)
function getNextUpdateTime() {
    const now = new Date();
    const next = new Date();
    next.setHours(19, 0, 0, 0);

    // If 7 PM already passed, schedule for tomorrow
    if (now >= next) {
        next.setDate(next.getDate() + 1);
    }

    return next.toISOString();
}

// Fetch prayer times from the ICS feed
async function fetchPrayerTimes() {
    try {
        const urlRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('ics_url');
        const icsUrl = urlRow.value;

        log('Fetching prayer times from:', icsUrl);

        // Extract city name
        const cityName = extractCityFromIcsUrl(icsUrl);
        const response = await axios.get(icsUrl);
        const events = ical.parseICS(response.data);

        // Keep historical data and replace only future prayers (today onward)
        const today = new Date();
        const todayStr = formatDateLocal(today);

        // Remove future prayers (from today onward)
        db.prepare('DELETE FROM prayers WHERE date >= ?').run(todayStr);
        log(`Kept historical prayers before ${todayStr}`);

        const insertPrayer = db.prepare('INSERT OR REPLACE INTO prayers (date, prayer_name, prayer_time) VALUES (?, ?, ?)');

        // Only store the next three months
        const threeMonthsLater = new Date();
        threeMonthsLater.setMonth(threeMonthsLater.getMonth() + 3);
        const threeMonthsStr = formatDateLocal(threeMonthsLater);

        let insertedCount = 0;
        for (let k in events) {
            if (events.hasOwnProperty(k)) {
                const ev = events[k];
                if (ev.type === 'VEVENT') {
                    const webCalPrayerName = ev.summary;
                    // Map WebCal name to internal database name
                    const prayerName = mapPrayerNameFromWebCal(webCalPrayerName);
                    const prayerTime = new Date(ev.start);
                    const date = formatDateLocal(prayerTime);
                    const time = prayerTime.toTimeString().split(' ')[0].substring(0, 5);

                    // Insert prayers within the next three months
                    if (date >= todayStr && date <= threeMonthsStr) {
                        insertPrayer.run(date, prayerName, time);
                        insertedCount++;
                    }
                }
            }
        }

        log(`Prayer times updated successfully: ${insertedCount} prayers inserted for the next 3 months`);

        // Update metadata
        const now = new Date().toISOString();
        const nextUpdate = getNextUpdateTime();
        db.prepare('UPDATE update_info SET last_update = ?, prayers_count = ?, city_name = ?, next_update = ? WHERE id = 1')
            .run(now, insertedCount, cityName, nextUpdate);

        scheduleAthanCalls();
        return true;
    } catch (error) {
        logError('Error fetching prayer times:', error.message);
        return false;
    }
}

// Schedule future athan calls
function scheduleAthanCalls() {
    // Cancel previously scheduled jobs
    scheduledJobs.forEach(job => {
        if (job.cancel) job.cancel();
    });
    scheduledJobs = [];

    const today = new Date();
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const todayStr = formatDateLocal(today);
    const tomorrowStr = formatDateLocal(tomorrow);

    // Only schedule the 5 main prayers (same filter as frontend)
    const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
    const prayers = db.prepare(`
        SELECT * FROM prayers 
        WHERE date IN (?, ?) AND prayer_name IN (?, ?, ?, ?, ?)
        ORDER BY date, prayer_time
    `).all(todayStr, tomorrowStr, ...mainPrayers);

    log(`[scheduleAthanCalls] Found ${prayers.length} main prayers for today and tomorrow`);

    let scheduled = 0;
    let skipped = 0;

    prayers.forEach(prayer => {
        const prayerDateTime = new Date(`${prayer.date}T${prayer.prayer_time}:00`);
        const now = new Date();

        if (prayerDateTime > now) {
            const job = schedule.scheduleJob(prayerDateTime, () => {
                log(`[Backend Schedule] Triggering athan for ${prayer.prayer_name} at exact time`);
                playAthan(prayer.prayer_name);
            });
            scheduledJobs.push(job);
            scheduled++;
            log(`✅ Scheduled athan for ${prayer.prayer_name} at ${prayerDateTime}`);
        } else {
            skipped++;
            log(`⏭️ Skipped ${prayer.prayer_name} at ${prayer.prayer_time} (already passed)`);
        }
    });

    log(`[scheduleAthanCalls] Summary: ${scheduled} scheduled, ${skipped} skipped (already passed)`);
}

// Helper function to update .asoundrc with selected audio card
function updateAsoundrc(audioCard) {
    const fs = require('fs');
    const asoundrcPath = '/root/.asoundrc';

    if (audioCard === 'auto') {
        log('[updateAsoundrc] Using auto-detect mode (card from entrypoint.sh)');
        return; // Don't modify .asoundrc, use what entrypoint.sh created
    }

    const asoundrcContent = `pcm.!default {
    type hw
    card ${audioCard}
}
ctl.!default {
    type hw
    card ${audioCard}
}`;

    try {
        fs.writeFileSync(asoundrcPath, asoundrcContent);
        log(`[updateAsoundrc] ✅ Updated .asoundrc to use card ${audioCard}`);
    } catch (error) {
        logError(`[updateAsoundrc] ❌ Error updating .asoundrc:`, error);
    }
}

// Helper function to build sox play command arguments
function buildSoxArgs(volumeLevel, audioPath, additionalArgs = []) {
    const args = [];

    // Get selected audio card from settings
    const audioCardRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_card');
    const audioCard = audioCardRow ? audioCardRow.value : 'auto';

    log(`[buildSoxArgs] Selected audio card from DB: ${audioCard}`);

    // Update .asoundrc with selected card (if not auto)
    updateAsoundrc(audioCard);

    // Add volume
    args.push('-v', volumeLevel);

    // Add audio file path
    args.push(audioPath);

    // Add any additional arguments (like 'trim', '0', '30')
    if (additionalArgs.length > 0) {
        args.push(...additionalArgs);
    }

    log(`[buildSoxArgs] Sox command: play ${args.join(' ')}`);

    // Create environment with AUDIODRIVER set to alsa
    // This forces sox to use ALSA directly instead of libao
    const env = {
        ...process.env,
        AUDIODRIVER: 'alsa'
    };
    log(`[buildSoxArgs] AUDIODRIVER: ${env.AUDIODRIVER}`);

    return { args, env };
}

// Play startup sound (server-side)
function playStartupSound() {
    try {
        const fs = require('fs');
        const startupAudioPath = path.join(__dirname, 'audio', 'system', 'startup.mp3');

        // Check audio output setting
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';

        // Only play on server if audio_output is 'server' or 'both'
        if (audioOutput !== 'server' && audioOutput !== 'both') {
            log('[playStartupSound] ⏭️ Skipped (audio_output is browser only)');
            return;
        }

        // Check if file exists and is not empty
        if (!fs.existsSync(startupAudioPath)) {
            log(`[playStartupSound] ℹ️ Startup audio file not found: ${startupAudioPath}`);
            log('[playStartupSound] Please add a valid startup.mp3 file to audio/system/ directory');
            return;
        }

        const fileStats = fs.statSync(startupAudioPath);
        if (fileStats.size === 0) {
            log(`[playStartupSound] ⚠️ Startup audio file is empty (0 bytes)`);
            log('[playStartupSound] Please replace with a valid MP3 file');
            return;
        }

        // Get volume (x4: 100% on UI = 400% on server)
        const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
        const volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2); // x4 multiplier

        log(`[playStartupSound] 🔊 Playing startup sound: ${startupAudioPath} (${fileStats.size} bytes) at UI volume ${volumePercent}% (server: ${volumeLevel}x)`);

        const { args, env } = buildSoxArgs(volumeLevel, startupAudioPath, []);

        log(`[playStartupSound] 🔧 DEBUG - Full command: play ${args.join(' ')}`);

        currentAudioPlayer = spawn('play', args, { env });

        // Capture stdout
        currentAudioPlayer.stdout.on('data', (data) => {
            log(`[playStartupSound] 📤 STDOUT: ${data.toString().trim()}`);
        });

        // Capture stderr (error messages from sox)
        currentAudioPlayer.stderr.on('data', (data) => {
            logError(`[playStartupSound] 📥 STDERR: ${data.toString().trim()}`);
        });

        currentAudioPlayer.on('error', (err) => {
            logError(`[playStartupSound] ❌ Error spawning process:`, err);
            currentAudioPlayer = null;
        });

        currentAudioPlayer.on('close', (code) => {
            if (code !== 0) {
                logError(`[playStartupSound] ❌ Startup sound process exited with code ${code}`);
                log('[playStartupSound] 💡 Tip: Make sure startup.mp3 is a valid audio file');
            } else {
                log(`[playStartupSound] ✅ Startup sound finished successfully`);
            }
            currentAudioPlayer = null;
        });
    } catch (error) {
        logError('[playStartupSound] Error playing startup sound:', error);
    }
}

// Play athan (server-side)
function playAthan(prayerName) {
    try {
        // Bypass checks for special events (Startup, PageLoad, Test)
        const isSpecialEvent = ['Startup', 'PageLoad', 'Test'].includes(prayerName);

        if (!isSpecialEvent) {
            // Convert JS day (0=Sunday) to our matrix day (0=Monday...6=Sunday)
            const jsDay = new Date().getDay();
            const dayIndex = (jsDay + 6) % 7; // 0=Monday, 1=Tuesday, ..., 6=Sunday
            const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

            // Check prayer_schedule matrix (unified control)
            const scheduleEntry = db.prepare('SELECT enabled FROM prayer_schedule WHERE prayer_name = ? AND day_of_week = ?')
                .get(prayerName, dayIndex);
            if (scheduleEntry && scheduleEntry.enabled === 0) {
                log(`[playAthan] ❌ ${prayerName} disabled for ${dayNames[dayIndex]} in schedule matrix`);
                return;
            }

            // Confirm the next athan isn't skipped (mute next athan)
            const skipNext = db.prepare('SELECT skip FROM skip_next WHERE id = 1').get();
            const currentDate = new Date().toISOString().split('T')[0];

            if (skipNext && skipNext.skip === 1) {
                log(`[playAthan] ❌ Skipping athan for ${prayerName} (skip_next flag set)`);
                db.prepare('UPDATE skip_next SET skip = 0, last_skipped_prayer = ?, last_skipped_date = ? WHERE id = 1').run(prayerName, currentDate);
                return;
            }

            log(`[playAthan] ✅ All checks passed for ${prayerName} on ${dayNames[dayIndex]}, proceeding with playback...`);
        }

        // Determine playback target
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';

        // Only play server-side if configured for server or both
        if (audioOutput === 'browser') {
            log(`Audio output set to browser only, skipping server playback for ${prayerName}`);
            return;
        }

        const audioFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_file');
        const audioFile = audioFileRow ? audioFileRow.value : 'Masjid Al-Haram.mp3';
        const audioPath = path.join(__dirname, 'audio', 'athan', audioFile);

        // Retrieve volume (0-100)
        // For Fajr prayer, check if we should use the specific Fajr volume
        let volumePercent = 50;
        if (prayerName === 'Fajr | Sobh') {
            // Check if Fajr volume is independent (not synced with main volume)
            const syncFajrVolumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('sync_fajr_volume');
            const useFajrVolume = syncFajrVolumeRow ? syncFajrVolumeRow.value === '1' : false;

            if (useFajrVolume) {
                // Use specific Fajr volume
                const fajrVolumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('fajr_volume');
                volumePercent = fajrVolumeRow ? parseInt(fajrVolumeRow.value) : 50;
                log(`[playAthan] Using specific Fajr volume: ${volumePercent}%`);
            } else {
                // Use main volume (synced)
                const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
                volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
                log(`[playAthan] Using synced main volume for Fajr: ${volumePercent}%`);
            }
        } else {
            // Use main volume for all other prayers
            const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
            volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        }

        // Convert 0-100 to 0.0-4.0 for sox (x4: 100% on UI = 400% on server)
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2);

        if (fs.existsSync(audioPath)) {
            log(`[playAthan] 🔊 BACKEND AUDIO PLAYING for ${prayerName}: ${audioPath} at UI volume ${volumePercent}% (server: ${volumeLevel}x)`);

            // Use sox play command with -v for volume control and selected audio card
            // For test athan, only play the first 30 seconds
            const additionalArgs = prayerName === 'Test' ? ['trim', '0', '30'] : [];
            const { args, env } = buildSoxArgs(volumeLevel, audioPath, additionalArgs);

            log(`[playAthan] 🔧 DEBUG - Full command: play ${args.join(' ')}`);
            log(`[playAthan] 🔧 DEBUG - Audio file exists: ${fs.existsSync(audioPath)}`);
            log(`[playAthan] 🔧 DEBUG - Audio file size: ${fs.statSync(audioPath).size} bytes`);

            currentAudioPlayer = spawn('play', args, { env });

            // Capture stdout
            currentAudioPlayer.stdout.on('data', (data) => {
                log(`[playAthan] 📤 STDOUT: ${data.toString().trim()}`);
            });

            // Capture stderr (error messages from sox)
            currentAudioPlayer.stderr.on('data', (data) => {
                logError(`[playAthan] 📥 STDERR: ${data.toString().trim()}`);
            });

            currentAudioPlayer.on('error', (err) => {
                logError(`[playAthan] ❌ Error spawning process:`, err);
                currentAudioPlayer = null;
            });

            currentAudioPlayer.on('close', (code) => {
                if (code !== 0) {
                    logError(`[playAthan] ❌ Athan process exited with code ${code}`);
                } else {
                    log(`[playAthan] ✅ Athan finished successfully for ${prayerName}`);
                }
                currentAudioPlayer = null;
            });
        } else {
            logError(`Audio file not found: ${audioPath}`);
        }
    } catch (error) {
        logError('Error playing athan:', error);
    }
}

// Function to play Quran recitation
function playQuran() {
    try {
        log('[playQuran] ========== PLAYING QURAN ==========');
        log('[playQuran] 📖 Starting Friday Quran recitation...');

        // Get audio output setting
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';
        log(`[playQuran] Audio output setting: ${audioOutput}`);

        // Set trigger for browser playback if needed
        if (audioOutput === 'browser' || audioOutput === 'both') {
            const now = new Date();
            const currentDate = now.toISOString().split('T')[0];
            const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

            db.prepare('UPDATE friday_quran_trigger SET should_play = 1, last_played_date = ?, last_played_time = ? WHERE id = 1')
                .run(currentDate, currentTime);
            log(`[playQuran] ✅ Browser trigger set for ${currentDate} ${currentTime}`);
        }

        // Only play server-side if configured for server or both
        if (audioOutput === 'browser') {
            log('[playQuran] ❌ Audio output set to browser only, skipping server playback for Quran');
            return;
        }

        const quranFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
        const quranFile = quranFileRow ? quranFileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3';
        const quranPath = path.join(__dirname, 'audio', 'coran', quranFile);
        log(`[playQuran] Quran file: ${quranFile}`);
        log(`[playQuran] Full path: ${quranPath}`);

        // Retrieve volume (x4: 100% on UI = 400% on server)
        const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
        const volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2);
        log(`[playQuran] Volume: UI ${volumePercent}% -> Server ${volumeLevel}x (x4 multiplier)`);

        if (fs.existsSync(quranPath)) {
            log(`[playQuran] ✅ File exists, starting playback...`);
            log(`[playQuran] 🔊 BACKEND QURAN PLAYING: ${quranPath}`);

            // Use sox play command with -v for volume control and selected audio card
            const { args, env } = buildSoxArgs(volumeLevel, quranPath);
            log(`[playQuran] Sox args: ${JSON.stringify(args)}`);

            currentAudioPlayer = spawn('play', args, { env });
            currentAudioType = 'quran'; // Track that Quran is playing

            currentAudioPlayer.stdout.on('data', (data) => {
                log(`[playQuran] stdout: ${data}`);
            });

            currentAudioPlayer.stderr.on('data', (data) => {
                log(`[playQuran] stderr: ${data}`);
            });

            currentAudioPlayer.on('error', (err) => {
                logError('[playQuran] ❌ Error playing Quran:', err);
                currentAudioPlayer = null;
                currentAudioType = null;
            });

            currentAudioPlayer.on('close', (code) => {
                if (code !== 0) {
                    logError(`[playQuran] ❌ Quran process exited with code ${code}`);
                } else {
                    log('[playQuran] ✅ Quran recitation finished successfully');
                }
                currentAudioPlayer = null;
                currentAudioType = null;
            });
        } else {
            logError(`[playQuran] ❌ Quran file NOT FOUND: ${quranPath}`);
            // List available files in the directory
            const coranDir = path.join(__dirname, 'audio', 'coran');
            if (fs.existsSync(coranDir)) {
                const files = fs.readdirSync(coranDir);
                log(`[playQuran] Available files in ${coranDir}:`, files);
            } else {
                logError(`[playQuran] Coran directory does not exist: ${coranDir}`);
            }
        }
    } catch (error) {
        logError('[playQuran] ❌ Exception:', error);
    }
    log('[playQuran] ==========================================');
}

// Cron job - Every day at midnight
cron.schedule('0 0 * * *', () => {
    log('Running daily prayer times update...');
    fetchPrayerTimes();
    log('Running daily Hijri dates update...');
    updateHijriDates();
}, {
    timezone: "Europe/Paris"
});

// Function to schedule Friday Quran recitation
function scheduleFridayQuran() {
    const now = new Date();
    log(`[scheduleFridayQuran] ========== FRIDAY QURAN SCHEDULING ==========`);
    log(`[scheduleFridayQuran] Current server time: ${now.toISOString()} (${now.toLocaleString('fr-FR', { timeZone: 'Europe/Paris' })})`);
    log(`[scheduleFridayQuran] Current day of week: ${now.getDay()} (0=Sun, 5=Fri)`);

    // Destroy existing job if any
    if (fridayQuranJob) {
        if (typeof fridayQuranJob.stop === 'function') {
            fridayQuranJob.stop();
        } else if (typeof fridayQuranJob.destroy === 'function') {
            fridayQuranJob.destroy();
        }
        fridayQuranJob = null;
        log('[scheduleFridayQuran] Cancelled existing Friday Quran job');
    }

    // Check if Friday Quran is enabled
    const enabledRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_enabled');
    const enabled = enabledRow && enabledRow.value === '1';
    log(`[scheduleFridayQuran] Enabled setting: ${enabledRow ? enabledRow.value : 'not found'} -> ${enabled ? 'ENABLED' : 'DISABLED'}`);

    if (!enabled) {
        log('[scheduleFridayQuran] ❌ Friday Quran is DISABLED - no job scheduled');
        return;
    }

    // Get the configured time
    const timeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_time');
    const time = timeRow ? timeRow.value : '07:00';
    const [hourStr, minuteStr] = time.split(':');
    // Parse as integers to remove leading zeros (cron format requires numeric values)
    const hour = parseInt(hourStr, 10);
    const minute = parseInt(minuteStr, 10);
    log(`[scheduleFridayQuran] Configured time: ${time} (hour: ${hour}, minute: ${minute})`);

    // Get the configured Quran file
    const quranFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
    const quranFile = quranFileRow ? quranFileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3';
    log(`[scheduleFridayQuran] Configured Quran file: ${quranFile}`);

    // Schedule cron job for Friday (5 in cron format) at the specified time
    // Format: minute hour day-of-month month day-of-week
    const cronExpression = `${minute} ${hour} * * 5`;
    log(`[scheduleFridayQuran] ✅ Scheduling Friday Quran for every Friday at ${hour}:${minute.toString().padStart(2, '0')} (cron: ${cronExpression})`);
    log(`[scheduleFridayQuran] Timezone: Europe/Paris`);

    fridayQuranJob = cron.schedule(cronExpression, () => {
        const triggerTime = new Date();
        log(`[scheduleFridayQuran] ========== FRIDAY QURAN TRIGGERED ==========`);
        log(`[scheduleFridayQuran] 🕌 Trigger time: ${triggerTime.toISOString()} (${triggerTime.toLocaleString('fr-FR', { timeZone: 'Europe/Paris' })})`);
        log(`[scheduleFridayQuran] Day of week: ${triggerTime.getDay()} (expected: 5 = Friday)`);
        playQuran();
    }, {
        timezone: "Europe/Paris"
    });

    log(`[scheduleFridayQuran] ✅ Friday Quran job created successfully`);
    log(`[scheduleFridayQuran] Next execution: Every Friday at ${time} (Europe/Paris)`);
    log(`[scheduleFridayQuran] ==============================================`);
}

// Initialize Friday Quran schedule on startup
scheduleFridayQuran();

// API Routes

// POST - Trigger audio on page load
// DEPRECATED: This endpoint is no longer used
// Page load audio now plays ONLY in the browser (never on server)
// Server audio only plays at Docker container startup
app.post('/api/play-on-page-load', (req, res) => {
    try {
        log('[DEPRECATED] /api/play-on-page-load endpoint called - this endpoint is no longer used');
        log('[DEPRECATED] Page load audio now plays only in browser, not on server');
        res.json({
            success: false,
            message: 'This endpoint is deprecated. Page load audio plays only in browser.'
        });
    } catch (error) {
        logError('Error in play-on-page-load:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve prayers for a given date
app.get('/api/prayers/:date', (req, res) => {
    try {
        const { date } = req.params;
        const prayers = db.prepare('SELECT * FROM prayers WHERE date = ? ORDER BY prayer_time').all(date);
        res.json(prayers);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve prayer checks for a given date
app.get('/api/prayer-checks/:date', (req, res) => {
    try {
        const { date } = req.params;
        const checks = db.prepare('SELECT * FROM prayer_checks WHERE date = ?').all(date);
        res.json(checks);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve prayer checks for a year range
app.get('/api/prayer-checks-range', (req, res) => {
    try {
        const { year } = req.query;
        if (!year) {
            return res.status(400).json({ error: 'year parameter is required' });
        }

        const startDate = `${year}-01-01`;
        const endDate = `${year}-12-31`;

        const checks = db.prepare(`
            SELECT date, prayer_name, checked 
            FROM prayer_checks 
            WHERE date >= ? AND date <= ?
        `).all(startDate, endDate);

        res.json({ success: true, checks });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Toggle prayer check
// Supports 3 states: 0 (unchecked) → 2 (orange) → 1 (green) → 0 (unchecked)
app.post('/api/prayer-checks/toggle', (req, res) => {
    try {
        const { date, prayer_name } = req.body;

        // Get current check status
        const currentCheck = db.prepare('SELECT checked FROM prayer_checks WHERE date = ? AND prayer_name = ?').get(date, prayer_name);

        // Triple-state toggle logic: 0 → 2 (orange) → 1 (green) → 0
        let newChecked;
        if (!currentCheck || currentCheck.checked === 0) {
            newChecked = 2; // First click: orange
        } else if (currentCheck.checked === 2) {
            newChecked = 1; // Second click: green
        } else {
            newChecked = 0; // Third click: unchecked
        }

        const checkedAt = newChecked !== 0 ? new Date().toISOString() : null;

        // Insert or update
        db.prepare(`
            INSERT INTO prayer_checks (date, prayer_name, checked, checked_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(date, prayer_name) DO UPDATE SET
                checked = excluded.checked,
                checked_at = excluded.checked_at
        `).run(date, prayer_name, newChecked, checkedAt);

        res.json({ success: true, checked: newChecked });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Reset all prayer checks and daily activities
app.post('/api/prayer-checks/reset', (req, res) => {
    try {
        db.prepare('DELETE FROM prayer_checks').run();
        db.prepare('DELETE FROM daily_activities').run();
        res.json({ success: true, message: 'All prayer checks and daily activities have been reset' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ===== DAILY ACTIVITIES APIs =====

// GET - Retrieve daily activities for a given date
app.get('/api/daily-activities/:date', (req, res) => {
    try {
        const { date } = req.params;
        const activities = db.prepare('SELECT * FROM daily_activities WHERE date = ?').all(date);
        res.json(activities);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Toggle daily activity check
// Supports 3 states: 0 (unchecked) → 2 (orange) → 1 (green) → 0 (unchecked)
app.post('/api/daily-activities/toggle', (req, res) => {
    try {
        const { date, activity_name } = req.body;

        // Get current check status
        const currentCheck = db.prepare('SELECT checked FROM daily_activities WHERE date = ? AND activity_name = ?').get(date, activity_name);

        // Triple-state toggle logic: 0 → 2 (orange) → 1 (green) → 0
        let newChecked;
        if (!currentCheck || currentCheck.checked === 0) {
            newChecked = 2; // First click: orange
        } else if (currentCheck.checked === 2) {
            newChecked = 1; // Second click: green
        } else {
            newChecked = 0; // Third click: unchecked
        }

        const checkedAt = newChecked !== 0 ? new Date().toISOString() : null;

        // Insert or update
        db.prepare(`
            INSERT INTO daily_activities (date, activity_name, checked, checked_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(date, activity_name) DO UPDATE SET
                checked = excluded.checked,
                checked_at = excluded.checked_at
        `).run(date, activity_name, newChecked, checkedAt);

        res.json({ success: true, checked: newChecked });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ===== HIJRI DATES APIs =====

// Function to fetch Hijri dates from API
async function fetchHijriDates(startDate, endDate) {
    try {
        log(`📅 Fetching Hijri dates from ${formatDateLocal(startDate)} to ${formatDateLocal(endDate)}`);
        const dates = [];
        const current = new Date(startDate);
        const end = new Date(endDate);
        let successCount = 0;
        let errorCount = 0;

        while (current <= end) {
            const dateStr = formatDateLocal(current);
            const [year, month, day] = dateStr.split('-');

            try {
                // Use gToH endpoint with DD-MM-YYYY format
                const url = `https://api.aladhan.com/v1/gToH/${day}-${month}-${year}`;
                const response = await axios.get(url, { timeout: 5000 });

                if (response.data && response.data.code === 200 && response.data.data && response.data.data.hijri) {
                    const hijri = response.data.data.hijri;

                    dates.push({
                        gregorian_date: dateStr,
                        hijri_year: parseInt(hijri.year),
                        hijri_month: parseInt(hijri.month.number),
                        hijri_day: parseInt(hijri.day),
                        hijri_month_name: hijri.month.en,
                        is_ramadan: hijri.month.number === 9 || hijri.month.number === '9' ? 1 : 0
                    });
                    successCount++;

                    // Log first successful fetch
                    if (successCount === 1) {
                        log(`✅ First Hijri date fetched: ${dateStr} = ${hijri.day} ${hijri.month.en} ${hijri.year} (Ramadan: ${hijri.month.number === 9 || hijri.month.number === '9'})`);
                    }
                }
                // Rate limiting: wait 100ms between requests
                await new Promise(resolve => setTimeout(resolve, 100));
            } catch (error) {
                errorCount++;
                // Log first error with details
                if (errorCount === 1) {
                    logError(`❌ First Hijri API error for ${dateStr}:`, error.message);
                }
                // Only log every 50th error to avoid spam
                if (errorCount % 50 === 0) {
                    logError(`Hijri API errors: ${errorCount} failed, ${successCount} succeeded`);
                }
                // If rate limited (429), wait longer
                if (error.response && error.response.status === 429) {
                    await new Promise(resolve => setTimeout(resolve, 2000));
                }
            }
            current.setDate(current.getDate() + 1);
        }

        log(`✅ Hijri dates fetch completed: ${successCount} succeeded, ${errorCount} failed out of ${successCount + errorCount} total`);
        return dates;
    } catch (error) {
        logError('❌ Error in fetchHijriDates:', error);
        return [];
    }
}

// Function to update Hijri dates in database
async function updateHijriDates() {
    try {
        log('🌙 Starting Hijri dates update...');

        // Get dates for 2 years in the past and 1 year in the future
        const today = new Date();
        const twoYearsAgo = new Date();
        twoYearsAgo.setFullYear(today.getFullYear() - 2);
        const oneYearLater = new Date();
        oneYearLater.setFullYear(today.getFullYear() + 1);

        log(`📆 Date range: ${formatDateLocal(twoYearsAgo)} to ${formatDateLocal(oneYearLater)}`);

        const hijriDates = await fetchHijriDates(twoYearsAgo, oneYearLater);

        if (hijriDates.length > 0) {
            const insertStmt = db.prepare(`
                INSERT OR REPLACE INTO hijri_dates 
                (gregorian_date, hijri_year, hijri_month, hijri_day, hijri_month_name, is_ramadan)
                VALUES (?, ?, ?, ?, ?, ?)
            `);

            let ramadanCount = 0;
            hijriDates.forEach(date => {
                insertStmt.run(
                    date.gregorian_date,
                    date.hijri_year,
                    date.hijri_month,
                    date.hijri_day,
                    date.hijri_month_name,
                    date.is_ramadan
                );
                if (date.is_ramadan === 1) ramadanCount++;
            });

            log(`✅ Hijri dates updated successfully: ${hijriDates.length} dates inserted (${ramadanCount} Ramadan days)`);

            // Verify data in database
            const dbCount = db.prepare('SELECT COUNT(*) as count FROM hijri_dates').get();
            const ramadanDbCount = db.prepare('SELECT COUNT(*) as count FROM hijri_dates WHERE is_ramadan = 1').get();
            log(`📊 Database verification: ${dbCount.count} total dates, ${ramadanDbCount.count} Ramadan dates`);
        } else {
            log('⚠️ No Hijri dates fetched');
        }
    } catch (error) {
        logError('❌ Error updating Hijri dates:', error);
    }
}

// GET - Retrieve Ramadan weeks for statistics
app.get('/api/hijri/ramadan-weeks', (req, res) => {
    try {
        const ramadanDates = db.prepare(`
            SELECT gregorian_date, hijri_year 
            FROM hijri_dates 
            WHERE is_ramadan = 1
            ORDER BY gregorian_date
        `).all();

        res.json({ success: true, ramadan_dates: ramadanDates });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Manual trigger for Hijri dates update (for testing)
app.post('/api/hijri/update', async (req, res) => {
    try {
        log('🔧 Manual Hijri update triggered');
        await updateHijriDates();
        res.json({ success: true, message: 'Hijri dates update completed' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ===== STATISTICS APIs =====

// Helper function to get week number (ISO week, Monday = start of week)
function getWeekNumber(date) {
    const d = new Date(date);
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() + 4 - (d.getDay() || 7));
    const yearStart = new Date(d.getFullYear(), 0, 1);
    const weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    return { year: d.getFullYear(), week: weekNo };
}

// GET - Prayer statistics for last 104 weeks (2 years)
app.get('/api/statistics/prayers', (req, res) => {
    try {
        const today = new Date();
        const twoYearsAgo = new Date();
        twoYearsAgo.setFullYear(today.getFullYear() - 2);

        const startDate = formatDateLocal(twoYearsAgo);
        const endDate = formatDateLocal(today);

        // Get all prayer checks for the period
        const prayerChecks = db.prepare(`
            SELECT date, prayer_name, checked
            FROM prayer_checks
            WHERE date >= ? AND date <= ?
            ORDER BY date
        `).all(startDate, endDate);

        // Get all prayers for the period to know which prayers existed
        const allPrayers = db.prepare(`
            SELECT date, prayer_name
            FROM prayers
            WHERE date >= ? AND date <= ?
            AND prayer_name IN ('Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha')
            ORDER BY date
        `).all(startDate, endDate);

        // Group by week
        const weeklyStats = {};

        allPrayers.forEach(prayer => {
            const weekInfo = getWeekNumber(prayer.date);
            const weekKey = `${weekInfo.year}-W${String(weekInfo.week).padStart(2, '0')}`;

            if (!weeklyStats[weekKey]) {
                weeklyStats[weekKey] = {
                    week: weekKey,
                    year: weekInfo.year,
                    weekNumber: weekInfo.week,
                    not_done: 0,
                    on_time: 0,
                    late: 0,
                    total_prayers: 0
                };
            }

            weeklyStats[weekKey].total_prayers++;

            // Find if this prayer was checked
            const check = prayerChecks.find(c => c.date === prayer.date && c.prayer_name === prayer.prayer_name);

            if (!check || check.checked === 0) {
                weeklyStats[weekKey].not_done++;
            } else if (check.checked === 1) {
                weeklyStats[weekKey].on_time++;
            } else if (check.checked === 2) {
                weeklyStats[weekKey].late++;
            }
        });

        // Convert to array and calculate percentages
        const statsArray = Object.values(weeklyStats).map(week => ({
            ...week,
            on_time_percent: week.total_prayers > 0 ? (week.on_time / week.total_prayers * 100).toFixed(1) : 0,
            total_completed_percent: week.total_prayers > 0 ? ((week.on_time + week.late) / week.total_prayers * 100).toFixed(1) : 0
        }));

        res.json({ success: true, statistics: statsArray });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Daily activities statistics for last 104 weeks (2 years)
app.get('/api/statistics/activities', (req, res) => {
    try {
        const today = new Date();
        const twoYearsAgo = new Date();
        twoYearsAgo.setFullYear(today.getFullYear() - 2);

        const startDate = formatDateLocal(twoYearsAgo);
        const endDate = formatDateLocal(today);

        // Get all activity checks for the period
        const activityChecks = db.prepare(`
            SELECT date, activity_name, checked
            FROM daily_activities
            WHERE date >= ? AND date <= ?
            ORDER BY date
        `).all(startDate, endDate);

        // Generate all possible dates and activities
        const weeklyStats = {};
        const activities = ['Read Coran', 'Tasbih & Dikr'];

        const current = new Date(twoYearsAgo);
        const end = new Date(today);

        while (current <= end) {
            const dateStr = formatDateLocal(current);
            const weekInfo = getWeekNumber(dateStr);
            const weekKey = `${weekInfo.year}-W${String(weekInfo.week).padStart(2, '0')}`;

            if (!weeklyStats[weekKey]) {
                weeklyStats[weekKey] = {
                    week: weekKey,
                    year: weekInfo.year,
                    weekNumber: weekInfo.week,
                    not_done: 0,
                    on_time: 0,
                    late: 0,
                    total_activities: 0
                };
            }

            activities.forEach(activity => {
                weeklyStats[weekKey].total_activities++;

                const check = activityChecks.find(c => c.date === dateStr && c.activity_name === activity);

                if (!check || check.checked === 0) {
                    weeklyStats[weekKey].not_done++;
                } else if (check.checked === 1) {
                    weeklyStats[weekKey].on_time++;
                } else if (check.checked === 2) {
                    weeklyStats[weekKey].late++;
                }
            });

            current.setDate(current.getDate() + 1);
        }

        // Convert to array and calculate percentages
        const statsArray = Object.values(weeklyStats).map(week => ({
            ...week,
            on_time_percent: week.total_activities > 0 ? (week.on_time / week.total_activities * 100).toFixed(1) : 0,
            total_completed_percent: week.total_activities > 0 ? ((week.on_time + week.late) / week.total_activities * 100).toFixed(1) : 0
        }));

        res.json({ success: true, statistics: statsArray });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Export statistics to Excel
app.get('/api/statistics/export-excel', async (req, res) => {
    try {
        const workbook = new ExcelJS.Workbook();

        // Fetch prayer statistics
        const prayerStatsResponse = await axios.get(`http://localhost:${PORT}/api/statistics/prayers`);
        const prayerStats = prayerStatsResponse.data.statistics;

        // Fetch activity statistics
        const activityStatsResponse = await axios.get(`http://localhost:${PORT}/api/statistics/activities`);
        const activityStats = activityStatsResponse.data.statistics;

        // Fetch Ramadan weeks
        const ramadanResponse = await axios.get(`http://localhost:${PORT}/api/hijri/ramadan-weeks`);
        const ramadanDates = ramadanResponse.data.ramadan_dates;

        // Create Ramadan weeks set
        const ramadanWeeks = new Set();
        ramadanDates.forEach(rd => {
            const weekInfo = getWeekNumber(rd.gregorian_date);
            ramadanWeeks.add(`${weekInfo.year}-W${String(weekInfo.week).padStart(2, '0')}`);
        });

        // Sheet 1: Prayer Statistics
        const prayerSheet = workbook.addWorksheet('Prayer Statistics');
        prayerSheet.columns = [
            { header: 'Week', key: 'week', width: 15 },
            { header: 'Year', key: 'year', width: 10 },
            { header: 'Week Number', key: 'weekNumber', width: 15 },
            { header: 'Not Done', key: 'not_done', width: 12 },
            { header: 'On Time', key: 'on_time', width: 18 },
            { header: 'Late', key: 'late', width: 15 },
            { header: 'Total Prayers', key: 'total_prayers', width: 15 },
            { header: '% On Time', key: 'on_time_percent', width: 12 },
            { header: '% Completed', key: 'total_completed_percent', width: 15 },
            { header: 'Ramadan', key: 'is_ramadan', width: 12 }
        ];

        prayerStats.forEach(stat => {
            prayerSheet.addRow({
                ...stat,
                is_ramadan: ramadanWeeks.has(stat.week) ? 'Yes' : 'No'
            });
        });

        // Style header row
        prayerSheet.getRow(1).font = { bold: true };
        prayerSheet.getRow(1).fill = {
            type: 'pattern',
            pattern: 'solid',
            fgColor: { argb: 'FF27AE60' }
        };

        // Highlight Ramadan weeks
        prayerSheet.eachRow((row, rowNumber) => {
            if (rowNumber > 1 && row.getCell('is_ramadan').value === 'Yes') {
                row.getCell('week').font = { color: { argb: 'FFFF0000' }, bold: true };
            }
        });

        // Sheet 2: Activity Statistics
        const activitySheet = workbook.addWorksheet('Activity Statistics');
        activitySheet.columns = [
            { header: 'Week', key: 'week', width: 15 },
            { header: 'Year', key: 'year', width: 10 },
            { header: 'Week Number', key: 'weekNumber', width: 15 },
            { header: 'Not Done', key: 'not_done', width: 12 },
            { header: 'On Time', key: 'on_time', width: 18 },
            { header: 'Late', key: 'late', width: 15 },
            { header: 'Total Activities', key: 'total_activities', width: 18 },
            { header: '% On Time', key: 'on_time_percent', width: 12 },
            { header: '% Completed', key: 'total_completed_percent', width: 15 },
            { header: 'Ramadan', key: 'is_ramadan', width: 12 }
        ];

        activityStats.forEach(stat => {
            activitySheet.addRow({
                ...stat,
                is_ramadan: ramadanWeeks.has(stat.week) ? 'Yes' : 'No'
            });
        });

        // Style header row
        activitySheet.getRow(1).font = { bold: true };
        activitySheet.getRow(1).fill = {
            type: 'pattern',
            pattern: 'solid',
            fgColor: { argb: 'FF3498DB' }
        };

        // Highlight Ramadan weeks
        activitySheet.eachRow((row, rowNumber) => {
            if (rowNumber > 1 && row.getCell('is_ramadan').value === 'Yes') {
                row.getCell('week').font = { color: { argb: 'FFFF0000' }, bold: true };
            }
        });

        // Sheet 3: Summary
        const summarySheet = workbook.addWorksheet('Summary');
        summarySheet.addRow(['Athan Center - Statistics Export']);
        summarySheet.addRow(['Export Date:', new Date().toLocaleString()]);
        summarySheet.addRow([]);
        summarySheet.addRow(['Prayer Statistics Summary']);
        summarySheet.addRow(['Total Weeks:', prayerStats.length]);
        summarySheet.addRow(['Total Prayers Tracked:', prayerStats.reduce((sum, s) => sum + s.total_prayers, 0)]);
        summarySheet.addRow(['Total On Time:', prayerStats.reduce((sum, s) => sum + s.on_time, 0)]);
        summarySheet.addRow(['Total Late:', prayerStats.reduce((sum, s) => sum + s.late, 0)]);
        summarySheet.addRow(['Total Not Done:', prayerStats.reduce((sum, s) => sum + s.not_done, 0)]);
        summarySheet.addRow([]);
        summarySheet.addRow(['Activity Statistics Summary']);
        summarySheet.addRow(['Total Weeks:', activityStats.length]);
        summarySheet.addRow(['Total Activities Tracked:', activityStats.reduce((sum, s) => sum + s.total_activities, 0)]);
        summarySheet.addRow(['Total On Time:', activityStats.reduce((sum, s) => sum + s.on_time, 0)]);
        summarySheet.addRow(['Total Late:', activityStats.reduce((sum, s) => sum + s.late, 0)]);
        summarySheet.addRow(['Total Not Done:', activityStats.reduce((sum, s) => sum + s.not_done, 0)]);

        summarySheet.getCell('A1').font = { bold: true, size: 16 };
        summarySheet.getColumn(1).width = 30;
        summarySheet.getColumn(2).width = 20;

        // Generate Excel file
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename=athan-center-statistics-${Date.now()}.xlsx`);

        await workbook.xlsx.write(res);
        res.end();
    } catch (error) {
        logError('Error exporting Excel:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve the next upcoming prayer (only main 5 prayers)
// Returns the prayer that is strictly in the future (prayer_time > current_time)
app.get('/api/prayers/next/upcoming', (req, res) => {
    try {
        const now = new Date();
        const currentDate = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

        log(`[API] /api/prayers/next/upcoming called at ${currentTime} on ${currentDate}`);

        // Only include the 5 main prayers
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        // Debug: Show all main prayers for today
        const allMainPrayersToday = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
        `).all(currentDate, ...mainPrayers);

        log(`[API] All main prayers today:`, allMainPrayersToday.map(p => `${p.prayer_name}:${p.prayer_time}`).join(', '));

        // Find next prayer strictly in the future (prayer_time > current_time)
        // This ensures we always get the truly NEXT prayer, not the current one
        const nextPrayer = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_time > ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
            LIMIT 1
        `).get(currentDate, currentTime, ...mainPrayers);

        if (nextPrayer) {
            log(`[API] Returning next prayer: ${nextPrayer.prayer_name} at ${nextPrayer.prayer_time} on ${nextPrayer.date}`);
            res.json(nextPrayer);
        } else {
            // If none remain today, return the first main prayer tomorrow
            log(`[API] No prayers left today, looking for tomorrow...`);
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowDate = formatDateLocal(tomorrow);

            const firstPrayerTomorrow = db.prepare(`
                SELECT * FROM prayers 
                WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
                ORDER BY prayer_time
                LIMIT 1
            `).get(tomorrowDate, ...mainPrayers);

            log(`[API] Returning first prayer tomorrow: ${firstPrayerTomorrow ? firstPrayerTomorrow.prayer_name : 'null'}`);
            res.json(firstPrayerTomorrow || null);
        }
    } catch (error) {
        logError(`[API] Error in /api/prayers/next/upcoming:`, error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve next prayer as natural language text
// Supports language parameter (default: FR)
// Example: /api/next-prayer-text?lang=FR
app.get('/api/next-prayer-text', (req, res) => {
    try {
        const lang = (req.query.lang || 'FR').toUpperCase();
        const now = new Date();
        const currentDate = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

        log(`[API] /api/next-prayer-text called with lang=${lang}`);

        // Only include the 5 main prayers
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        // Find next prayer strictly in the future
        let nextPrayer = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_time > ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
            LIMIT 1
        `).get(currentDate, currentTime, ...mainPrayers);

        // If no prayer today, get first prayer tomorrow
        if (!nextPrayer) {
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowDate = formatDateLocal(tomorrow);

            nextPrayer = db.prepare(`
                SELECT * FROM prayers 
                WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
                ORDER BY prayer_time
                LIMIT 1
            `).get(tomorrowDate, ...mainPrayers);
        }

        // If no prayer found at all, return configuration message
        if (!nextPrayer) {
            if (lang === 'FR') {
                res.type('text/plain').send('Athan Center doit être configuré');
            } else {
                res.type('text/plain').send('Athan Center must be configured');
            }
            return;
        }

        // Calculate time remaining
        const prayerDateTime = new Date(`${nextPrayer.date}T${nextPrayer.prayer_time}:00`);
        const diffMs = prayerDateTime - now;
        const diffMinutes = Math.floor(diffMs / 60000);
        const hours = Math.floor(diffMinutes / 60);
        const minutes = diffMinutes % 60;

        // Format prayer name in French
        const prayerNamesFR = {
            'Fajr | Sobh': 'Fajr | Sobh',
            'Dohr': 'Dohr',
            'Asr': 'Asr',
            'Maghrib': 'Maghrib',
            'Isha': 'Isha'
        };

        const prayerName = prayerNamesFR[nextPrayer.prayer_name] || nextPrayer.prayer_name;

        // Build natural language response in French
        if (lang === 'FR') {
            let timeText = '';
            if (hours > 0 && minutes > 0) {
                const hourWord = hours === 1 ? 'heure' : 'heures';
                const minuteWord = minutes === 1 ? 'minute' : 'minutes';
                timeText = `${hours} ${hourWord} et ${minutes} ${minuteWord}`;
            } else if (hours > 0) {
                const hourWord = hours === 1 ? 'heure' : 'heures';
                timeText = `${hours} ${hourWord}`;
            } else {
                const minuteWord = minutes === 1 ? 'minute' : 'minutes';
                timeText = `${minutes} ${minuteWord}`;
            }

            const response = `Salate Al ${prayerName} est à ${nextPrayer.prayer_time}, il reste ${timeText} avant l'adhan`;
            res.type('text/plain').send(response);
        } else {
            // English fallback (for future expansion)
            let timeText = '';
            if (hours > 0 && minutes > 0) {
                const hourWord = hours === 1 ? 'hour' : 'hours';
                const minuteWord = minutes === 1 ? 'minute' : 'minutes';
                timeText = `${hours} ${hourWord} and ${minutes} ${minuteWord}`;
            } else if (hours > 0) {
                const hourWord = hours === 1 ? 'hour' : 'hours';
                timeText = `${hours} ${hourWord}`;
            } else {
                const minuteWord = minutes === 1 ? 'minute' : 'minutes';
                timeText = `${minutes} ${minuteWord}`;
            }

            const response = `Salate Al ${prayerName} is at ${nextPrayer.prayer_time}, ${timeText} remaining before adhan`;
            res.type('text/plain').send(response);
        }
    } catch (error) {
        logError(`[API] Error in /api/next-prayer-text:`, error);
        res.status(500).type('text/plain').send('Error retrieving prayer information');
    }
});

// GET - Retrieve all settings
app.get('/api/settings', (req, res) => {
    try {
        const settings = db.prepare('SELECT * FROM settings').all();
        const settingsObj = {};
        settings.forEach(s => {
            settingsObj[s.key] = s.value;
        });
        res.json(settingsObj);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Update a setting
app.post('/api/settings', (req, res) => {
    try {
        const { key, value } = req.body;
        db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(key, value);

        // If ICS URL changed, fetch new prayer times
        if (key === 'ics_url') {
            fetchPrayerTimes();
        }

        // If Friday Quran settings changed, reschedule the job
        if (key === 'friday_quran_enabled' || key === 'friday_quran_time') {
            scheduleFridayQuran();
        }

        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve per-prayer settings (now uses prayer_schedule matrix)
// Returns enabled=1 if prayer is enabled for ALL days, 0 otherwise
app.get('/api/prayer-settings', (req, res) => {
    try {
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
        const settings = mainPrayers.map(prayerName => {
            // A prayer is considered "enabled" if it's enabled for ALL 7 days
            const disabledCount = db.prepare(
                'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
            ).get(prayerName).count;
            return {
                prayer_name: prayerName,
                enabled: disabledCount === 0 ? 1 : 0
            };
        });
        res.json(settings);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve specific prayer settings (now uses prayer_schedule matrix)
// Returns enabled=1 if prayer is enabled for ALL days, 0 otherwise
app.get('/api/prayer-settings/:prayerName', (req, res) => {
    try {
        const { prayerName } = req.params;
        // A prayer is considered "enabled" if it's enabled for ALL 7 days
        const disabledCount = db.prepare(
            'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
        ).get(prayerName).count;
        res.json({
            prayer_name: prayerName,
            enabled: disabledCount === 0 ? 1 : 0
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Update prayer settings (now updates prayer_schedule matrix for ALL days)
app.post('/api/prayer-settings/:prayerName', (req, res) => {
    try {
        const { prayerName } = req.params;
        const { enabled } = req.body;
        // Update all 7 days for this prayer in the schedule matrix
        db.prepare('UPDATE prayer_schedule SET enabled = ? WHERE prayer_name = ?').run(enabled ? 1 : 0, prayerName);
        log(`[prayer-settings] Updated ${prayerName} for all days -> ${enabled ? 'enabled' : 'disabled'}`);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Retrieve muted weekdays
app.get('/api/muted-weekdays', (req, res) => {
    try {
        const mutedDays = db.prepare('SELECT * FROM muted_weekdays ORDER BY weekday').all();
        res.json(mutedDays);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Update muted weekday
app.post('/api/muted-weekdays/:weekday', (req, res) => {
    try {
        const weekday = parseInt(req.params.weekday);
        const { muted } = req.body;

        if (weekday < 0 || weekday > 6) {
            return res.status(400).json({ error: 'Invalid weekday. Must be between 0 (Sunday) and 6 (Saturday)' });
        }

        db.prepare('UPDATE muted_weekdays SET muted = ? WHERE weekday = ?').run(muted ? 1 : 0, weekday);
        log(`Weekday ${weekday} muted status updated to: ${muted ? 'muted' : 'active'}`);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== PRAYER SCHEDULE MATRIX (5 prayers × 7 days) ==========

// GET - Retrieve entire prayer schedule matrix
app.get('/api/prayer-schedule', (req, res) => {
    try {
        log('[API] GET /api/prayer-schedule - Loading prayer schedule matrix from database');
        const schedule = db.prepare('SELECT * FROM prayer_schedule ORDER BY day_of_week, prayer_name').all();
        log(`[API] Returning ${schedule.length} prayer_schedule entries to frontend`);
        schedule.forEach(entry => {
            log(`[API]   ${entry.prayer_name}-${entry.day_of_week} = ${entry.enabled}`);
        });
        res.json(schedule);
    } catch (error) {
        logError('[API] Error loading prayer schedule:', error);
        res.status(500).json({ error: error.message });
    }
});

// POST - Update specific cell in schedule matrix (prayer × day)
app.post('/api/prayer-schedule', (req, res) => {
    try {
        const { prayer_name, day_of_week, enabled } = req.body;

        if (!prayer_name || day_of_week === undefined) {
            return res.status(400).json({ error: 'prayer_name and day_of_week are required' });
        }

        if (day_of_week < 0 || day_of_week > 6) {
            return res.status(400).json({ error: 'day_of_week must be between 0 (Monday) and 6 (Sunday)' });
        }

        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
        if (!mainPrayers.includes(prayer_name)) {
            return res.status(400).json({ error: 'Invalid prayer_name. Must be one of: Fajr | Sobh, Dohr, Asr, Maghrib, Isha' });
        }

        db.prepare('UPDATE prayer_schedule SET enabled = ? WHERE prayer_name = ? AND day_of_week = ?')
            .run(enabled ? 1 : 0, prayer_name, day_of_week);

        log(`[prayer-schedule] Updated: ${prayer_name} on day ${day_of_week} -> ${enabled ? 'enabled' : 'disabled'}`);
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Bulk update: entire row (prayer for all days) or column (all prayers for a day)
app.post('/api/prayer-schedule/bulk', (req, res) => {
    try {
        const { type, target, enabled } = req.body;
        // type: 'prayer' (whole week for one prayer) or 'day' (whole day for all prayers)
        // target: prayer name or day number

        if (!type || target === undefined || enabled === undefined) {
            return res.status(400).json({ error: 'type, target, and enabled are required' });
        }

        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        if (type === 'prayer') {
            // Update all 7 days for a specific prayer (whole week column)
            if (!mainPrayers.includes(target)) {
                return res.status(400).json({ error: 'Invalid prayer name' });
            }
            db.prepare('UPDATE prayer_schedule SET enabled = ? WHERE prayer_name = ?')
                .run(enabled ? 1 : 0, target);
            log(`[prayer-schedule] Bulk update: ${target} for all days -> ${enabled ? 'enabled' : 'disabled'}`);
        } else if (type === 'day') {
            // Update all 5 prayers for a specific day (whole day row)
            const dayNum = parseInt(target);
            if (dayNum < 0 || dayNum > 6) {
                return res.status(400).json({ error: 'Invalid day number (0-6)' });
            }
            db.prepare('UPDATE prayer_schedule SET enabled = ? WHERE day_of_week = ?')
                .run(enabled ? 1 : 0, dayNum);
            log(`[prayer-schedule] Bulk update: All prayers on day ${dayNum} -> ${enabled ? 'enabled' : 'disabled'}`);
        } else {
            return res.status(400).json({ error: 'type must be "prayer" or "day"' });
        }

        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Skip next athan
app.post('/api/skip-next', (req, res) => {
    try {
        // Get next upcoming prayer (strictly in the future)
        const now = new Date();
        const currentDate = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        const nextPrayer = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_time > ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
            LIMIT 1
        `).get(currentDate, currentTime, ...mainPrayers);

        if (!nextPrayer) {
            // No prayer today, check tomorrow
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowDate = formatDateLocal(tomorrow);

            const firstPrayerTomorrow = db.prepare(`
                SELECT * FROM prayers 
                WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
                ORDER BY prayer_time
                LIMIT 1
            `).get(tomorrowDate, ...mainPrayers);

            if (firstPrayerTomorrow) {
                // Check if prayer is disabled for ALL days in the schedule matrix
                const disabledCount = db.prepare(
                    'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
                ).get(firstPrayerTomorrow.prayer_name).count;
                if (disabledCount === 7) { // Disabled for all 7 days
                    return res.status(400).json({
                        success: false,
                        message: `${firstPrayerTomorrow.prayer_name} is already muted in general settings`
                    });
                }
            }
        } else {
            // Check if prayer is disabled for ALL days in the schedule matrix
            const disabledCount = db.prepare(
                'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
            ).get(nextPrayer.prayer_name).count;
            if (disabledCount === 7) { // Disabled for all 7 days
                return res.status(400).json({
                    success: false,
                    message: `${nextPrayer.prayer_name} is already muted in general settings`
                });
            }
        }

        db.prepare('UPDATE skip_next SET skip = 1 WHERE id = 1').run();
        res.json({ success: true, message: 'Next athan will be skipped' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Public route to mute next athan
app.get('/api/mute-next-athan', (req, res) => {
    try {
        // Get next upcoming prayer (strictly in the future)
        const now = new Date();
        const currentDate = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        const nextPrayer = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_time > ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
            LIMIT 1
        `).get(currentDate, currentTime, ...mainPrayers);

        if (!nextPrayer) {
            // No prayer today, check tomorrow
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            const tomorrowDate = formatDateLocal(tomorrow);

            const firstPrayerTomorrow = db.prepare(`
                SELECT * FROM prayers 
                WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
                ORDER BY prayer_time
                LIMIT 1
            `).get(tomorrowDate, ...mainPrayers);

            if (firstPrayerTomorrow) {
                // Check if prayer is disabled for ALL days in the schedule matrix
                const disabledCount = db.prepare(
                    'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
                ).get(firstPrayerTomorrow.prayer_name).count;
                if (disabledCount === 7) { // Disabled for all 7 days
                    return res.json({
                        success: false,
                        message: `${firstPrayerTomorrow.prayer_name} is already muted in general settings`,
                        timestamp: new Date().toISOString()
                    });
                }
            }
        } else {
            // Check if prayer is disabled for ALL days in the schedule matrix
            const disabledCount = db.prepare(
                'SELECT COUNT(*) as count FROM prayer_schedule WHERE prayer_name = ? AND enabled = 0'
            ).get(nextPrayer.prayer_name).count;
            if (disabledCount === 7) { // Disabled for all 7 days
                return res.json({
                    success: false,
                    message: `${nextPrayer.prayer_name} is already muted in general settings`,
                    timestamp: new Date().toISOString()
                });
            }
        }

        db.prepare('UPDATE skip_next SET skip = 1 WHERE id = 1').run();
        res.json({
            success: true,
            message: 'Next athan has been muted successfully',
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: 'Failed to mute next athan',
            details: error.message
        });
    }
});

// POST - Reset skip next athan (unmute)
app.post('/api/skip-next/reset', (req, res) => {
    try {
        db.prepare('UPDATE skip_next SET skip = 0, last_skipped_prayer = NULL, last_skipped_date = NULL WHERE id = 1').run();
        res.json({ success: true, message: 'Next athan will play as scheduled' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Reset skip next athan (unmute) - Public API endpoint
app.get('/api/skip-next/reset', (req, res) => {
    try {
        db.prepare('UPDATE skip_next SET skip = 0, last_skipped_prayer = NULL, last_skipped_date = NULL WHERE id = 1').run();
        res.json({ success: true, message: 'Next athan will play as scheduled' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Skip next status
app.get('/api/skip-next', (req, res) => {
    try {
        const skipNext = db.prepare('SELECT skip FROM skip_next WHERE id = 1').get();
        res.json({ skip: skipNext ? skipNext.skip === 1 : false });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Force prayer times refresh
app.post('/api/update-prayers', async (req, res) => {
    try {
        const success = await fetchPrayerTimes();
        res.json({ success, message: success ? 'Prayer times updated' : 'Failed to update prayer times' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST - Test athan playback
app.post('/api/test-athan', (req, res) => {
    try {
        playAthan('Test');
        res.json({ success: true, message: 'Test athan started' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Stop all audio playback (server-side)
app.get('/api/stop-audio', (req, res) => {
    try {
        if (currentAudioPlayer) {
            log('[stop-audio] Stopping server audio playback...');
            currentAudioPlayer.kill('SIGTERM');
            currentAudioPlayer = null;
            log('[stop-audio] ✅ Server audio stopped');
            res.json({ success: true, message: 'Server audio stopped successfully' });
        } else {
            log('[stop-audio] No audio currently playing on server');
            res.json({ success: true, message: 'No audio currently playing on server' });
        }
    } catch (error) {
        logError('[stop-audio] Error stopping audio:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Test Athan playback on server (30 seconds)
app.get('/api/test-athan-server', (req, res) => {
    try {
        log('[test-athan-server] Test Athan requested (30s preview on server)');

        const audioFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_file');
        const audioFile = audioFileRow ? audioFileRow.value : 'Masjid Al-Haram.mp3';
        const audioPath = path.join(__dirname, 'audio', 'athan', audioFile);

        const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
        const volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2); // x4 multiplier

        if (!fs.existsSync(audioPath)) {
            logError(`Athan file not found for test: ${audioPath}`);
            return res.status(404).json({ error: 'Athan file not found', file: audioFile });
        }

        log(`[test-athan-server] 🔊 BACKEND ATHAN TEST PLAYING (30s): ${audioPath} at UI volume ${volumePercent}% (server: ${volumeLevel}x)`);

        // Stop any currently playing audio
        if (currentAudioPlayer) {
            currentAudioPlayer.kill('SIGTERM');
            currentAudioPlayer = null;
        }

        // Play only the first 30 seconds using sox trim with selected audio card
        const { args, env } = buildSoxArgs(volumeLevel, audioPath, ['trim', '0', '30']);
        currentAudioPlayer = spawn('play', args, { env });

        currentAudioPlayer.on('error', (err) => {
            logError('Error playing Athan test:', err);
            currentAudioPlayer = null;
        });

        currentAudioPlayer.on('close', (code) => {
            if (code !== 0) {
                logError(`Athan test process exited with code ${code}`);
            } else {
                log('Athan test (30s) finished');
            }
            currentAudioPlayer = null;
        });

        res.json({
            success: true,
            message: 'Playing Athan test on server (30 seconds)...',
            file: audioFile,
            volume: volumePercent
        });
    } catch (error) {
        logError('Error in /api/test-athan-server:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Test Quran playback on server (30 seconds)
app.get('/api/test-quran-server', (req, res) => {
    try {
        log('[test-quran-server] Test Quran requested (30s preview on server)');

        const quranFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
        const quranFile = quranFileRow ? quranFileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3';
        const quranPath = path.join(__dirname, 'audio', 'coran', quranFile);

        const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
        const volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2); // x4 multiplier

        if (!fs.existsSync(quranPath)) {
            logError(`Quran file not found for test: ${quranPath}`);
            return res.status(404).json({ error: 'Quran file not found', file: quranFile });
        }

        log(`[test-quran-server] 🔊 BACKEND QURAN TEST PLAYING (30s): ${quranPath} at UI volume ${volumePercent}% (server: ${volumeLevel}x)`);

        // Stop any currently playing audio
        if (currentAudioPlayer) {
            currentAudioPlayer.kill('SIGTERM');
            currentAudioPlayer = null;
        }

        // Play only the first 30 seconds using sox trim with selected audio card
        const { args, env } = buildSoxArgs(volumeLevel, quranPath, ['trim', '0', '30']);
        currentAudioPlayer = spawn('play', args, { env });

        currentAudioPlayer.on('error', (err) => {
            logError('Error playing Quran test:', err);
            currentAudioPlayer = null;
        });

        currentAudioPlayer.on('close', (code) => {
            if (code !== 0) {
                logError(`Quran test process exited with code ${code}`);
            } else {
                log('Quran test (30s) finished');
            }
            currentAudioPlayer = null;
        });

        res.json({
            success: true,
            message: 'Playing Quran test on server (30 seconds)...',
            file: quranFile,
            volume: volumePercent
        });
    } catch (error) {
        logError('Error in /api/test-quran-server:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Manually trigger Friday Quran (for testing)
app.get('/api/trigger-friday-quran', (req, res) => {
    try {
        log('[API] Manual Friday Quran trigger requested');
        playQuran();
        res.json({
            success: true,
            message: 'Friday Quran playback triggered manually'
        });
    } catch (error) {
        logError('Error in /api/trigger-friday-quran:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Check Friday Quran status
app.get('/api/friday-quran-status', (req, res) => {
    try {
        const enabledRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_enabled');
        const timeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_time');
        const fileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');

        const now = new Date();
        const isJobScheduled = fridayQuranJob !== null;

        res.json({
            enabled: enabledRow ? enabledRow.value === '1' : false,
            time: timeRow ? timeRow.value : '07:00',
            file: fileRow ? fileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3',
            jobScheduled: isJobScheduled,
            currentServerTime: now.toISOString(),
            currentServerTimeLocal: now.toLocaleString('fr-FR', { timeZone: 'Europe/Paris' }),
            currentDayOfWeek: now.getDay(),
            isFriday: now.getDay() === 5
        });
    } catch (error) {
        logError('Error in /api/friday-quran-status:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - List available audio devices
app.get('/api/audio/devices', (req, res) => {
    try {
        const { exec } = require('child_process');

        exec('aplay -l 2>/dev/null', (error, stdout, stderr) => {
            if (error) {
                logError('Error listing audio devices:', error);
                return res.json({ devices: [] });
            }

            const devices = [];
            const lines = stdout.split('\n');

            // Parse aplay -l output
            // Format: "card 0: vc4hdmi0 [vc4-hdmi-0], device 0: MAI PCM i2s-hifi-0 [MAI PCM i2s-hifi-0]"
            for (const line of lines) {
                const cardMatch = line.match(/^card (\d+): (\w+) \[([^\]]+)\]/);
                if (cardMatch) {
                    const cardNumber = cardMatch[1];
                    const cardId = cardMatch[2];
                    const cardName = cardMatch[3];

                    // Determine a user-friendly name
                    let displayName = cardName;
                    if (cardName.includes('hdmi')) {
                        displayName = `HDMI ${cardNumber}`;
                    } else if (cardName.includes('USB') || cardId.toLowerCase().includes('usb')) {
                        displayName = `USB: ${cardName}`;
                    }

                    devices.push({
                        card: cardNumber,
                        id: cardId,
                        name: cardName,
                        displayName: displayName
                    });
                }
            }

            res.json({ devices });
        });
    } catch (error) {
        logError('Error in /api/audio/devices:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Debug ALSA configuration
app.get('/api/audio/debug', (req, res) => {
    try {
        const { exec } = require('child_process');
        const fs = require('fs');

        const debugInfo = {
            asoundrc: null,
            aplayList: null,
            selectedCard: null,
            errors: []
        };

        // Read .asoundrc
        try {
            if (fs.existsSync('/root/.asoundrc')) {
                debugInfo.asoundrc = fs.readFileSync('/root/.asoundrc', 'utf8');
            } else {
                debugInfo.asoundrc = 'File does not exist';
            }
        } catch (err) {
            debugInfo.errors.push(`Error reading .asoundrc: ${err.message}`);
        }

        // Get selected card from DB
        const audioCardRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_card');
        debugInfo.selectedCard = audioCardRow ? audioCardRow.value : 'not set';

        // Run aplay -l
        exec('aplay -l 2>&1', (error, stdout, stderr) => {
            debugInfo.aplayList = stdout || stderr || 'No output';
            res.json(debugInfo);
        });
    } catch (error) {
        logError('Error in /api/audio/debug:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Export configuration as CSV
app.get('/api/settings/export', (req, res) => {
    try {
        log('[EXPORT] ========== STARTING CONFIGURATION EXPORT ==========');
        let csvContent = 'type,key,value\n';

        // Export general settings (includes ics_url, audio_file, friday_quran_file, volume, audio_card, play_on_startup, play_on_page_load, audio_output, dark_mode, fajr_volume, sync_fajr_volume, etc.)
        const settings = db.prepare('SELECT key, value FROM settings').all();
        log(`[EXPORT] Exporting ${settings.length} general settings`);
        settings.forEach(setting => {
            csvContent += `setting,${setting.key},${setting.value}\n`;
            log(`[EXPORT]   - ${setting.key} = ${setting.value}`);
        });

        // NOTE: prayer_setting type removed - now unified in prayer_schedule matrix
        // The old prayer_settings table is no longer exported (redundant with prayer_schedule)

        // Export weekday mute settings
        const weekdaySettings = db.prepare('SELECT weekday, muted FROM muted_weekdays').all();
        weekdaySettings.forEach(ws => {
            csvContent += `weekday_mute,${ws.weekday},${ws.muted}\n`;
        });

        // Export prayer schedule matrix (5 prayers × 7 days)
        const prayerSchedule = db.prepare('SELECT prayer_name, day_of_week, enabled FROM prayer_schedule').all();
        log(`[EXPORT] Exporting ${prayerSchedule.length} prayer_schedule entries`);
        prayerSchedule.forEach(ps => {
            csvContent += `prayer_schedule,${ps.prayer_name}-${ps.day_of_week},${ps.enabled}\n`;
            log(`[EXPORT]   - ${ps.prayer_name}-${ps.day_of_week} = ${ps.enabled}`);
        });

        // Export skip_next status
        const skipNext = db.prepare('SELECT skip FROM skip_next WHERE id = 1').get();
        if (skipNext) {
            csvContent += `skip_next,skip,${skipNext.skip}\n`;
            log(`[EXPORT] Exporting skip_next: ${skipNext.skip}`);
        }

        // Export prayer checks (all states: 0=unchecked, 1=green, 2=orange)
        const prayerChecks = db.prepare('SELECT date, prayer_name, checked, checked_at FROM prayer_checks WHERE checked > 0').all();
        log(`[EXPORT] Exporting ${prayerChecks.length} prayer checks`);
        prayerChecks.forEach(pc => {
            csvContent += `prayer_check,${pc.date}-${pc.prayer_name},${pc.checked}|${pc.checked_at || ''}
`;
            const checkState = pc.checked === 1 ? 'green' : pc.checked === 2 ? 'orange' : 'unchecked';
            log(`[EXPORT]   - ${pc.date}-${pc.prayer_name} ${checkState} (${pc.checked}) at ${pc.checked_at}`);
        });

        // Export daily activities (all states: 0=unchecked, 1=green, 2=orange)
        const dailyActivities = db.prepare('SELECT date, activity_name, checked, checked_at FROM daily_activities WHERE checked > 0').all();
        log(`[EXPORT] Exporting ${dailyActivities.length} daily activities`);
        dailyActivities.forEach(da => {
            csvContent += `daily_activity,${da.date}-${da.activity_name},${da.checked}|${da.checked_at || ''}
`;
            const checkState = da.checked === 1 ? 'green' : da.checked === 2 ? 'orange' : 'unchecked';
            log(`[EXPORT]   - ${da.date}-${da.activity_name} ${checkState} (${da.checked}) at ${da.checked_at}`);
        });

        log('[EXPORT] ========== EXPORT COMPLETED ==========');
        res.setHeader('Content-Type', 'text/csv');
        res.setHeader('Content-Disposition', 'attachment; filename=athan-center-config.csv');
        res.send(csvContent);
    } catch (error) {
        logError('Error exporting configuration:', error);
        res.status(500).json({ error: error.message });
    }
});

// POST - Import configuration from CSV
app.post('/api/settings/import', (req, res) => {
    try {
        log('[IMPORT] ========== STARTING CONFIGURATION IMPORT ==========');
        const { csvData } = req.body;

        if (!csvData) {
            logError('[IMPORT] No CSV data provided');
            return res.status(400).json({ error: 'No CSV data provided' });
        }

        const lines = csvData.split('\n').filter(line => line.trim());
        log(`[IMPORT] Total lines in CSV: ${lines.length}`);
        const headers = lines[0].split(',');

        if (headers[0] !== 'type' || headers[1] !== 'key' || headers[2] !== 'value') {
            logError('[IMPORT] Invalid CSV format');
            return res.status(400).json({ error: 'Invalid CSV format' });
        }

        let importedCount = 0;
        let prayerScheduleCount = 0;

        for (let i = 1; i < lines.length; i++) {
            const parts = lines[i].split(',');
            if (parts.length < 3) {
                log(`[IMPORT] Skipping line ${i}: not enough parts (${parts.length})`);
                continue;
            }

            const type = parts[0];
            const key = parts[1];
            const value = parts.slice(2).join(','); // Handle values with commas

            log(`[IMPORT] Line ${i}: type="${type}", key="${key}", value="${value}"`);

            try {
                if (type === 'setting') {
                    // Import general settings (includes ics_url, audio_file, friday_quran_file, volume, audio_card, play_on_startup, play_on_page_load, audio_output, dark_mode, fajr_volume, sync_fajr_volume, etc.)
                    db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(key, value);
                    log(`[IMPORT]   - Setting: ${key} = ${value}`);
                    importedCount++;
                } else if (type === 'prayer_setting') {
                    // LEGACY SUPPORT: Convert old prayer_setting to prayer_schedule
                    // If enabled=0, disable prayer for ALL 7 days; if enabled=1, enable for ALL days
                    db.prepare('UPDATE prayer_schedule SET enabled = ? WHERE prayer_name = ?')
                        .run(parseInt(value), key);
                    log(`[import] Legacy prayer_setting converted: ${key} -> ${parseInt(value) ? 'enabled' : 'disabled'} for all days`);
                    importedCount++;
                } else if (type === 'weekday_mute') {
                    db.prepare('INSERT OR REPLACE INTO muted_weekdays (weekday, muted) VALUES (?, ?)').run(parseInt(key), parseInt(value));
                    importedCount++;
                } else if (type === 'prayer_schedule') {
                    // key format: "Fajr-0" (prayer_name-day_of_week)
                    const [prayerName, dayOfWeek] = key.split('-');
                    // Use INSERT OR REPLACE to ensure the entry exists (in case the table was empty)
                    db.prepare('INSERT OR REPLACE INTO prayer_schedule (prayer_name, day_of_week, enabled) VALUES (?, ?, ?)')
                        .run(prayerName, parseInt(dayOfWeek), parseInt(value));
                    log(`[IMPORT] prayer_schedule: ${prayerName}-${dayOfWeek} = ${value}`);
                    importedCount++;
                    prayerScheduleCount++;
                } else if (type === 'skip_next' && key === 'skip') {
                    db.prepare('UPDATE skip_next SET skip = ? WHERE id = 1').run(parseInt(value));
                    importedCount++;
                } else if (type === 'prayer_check') {
                    // key format: "2025-01-15-Fajr" (date-prayer_name)
                    const [date, prayerName] = key.split('-').reduce((acc, part, idx) => {
                        if (idx < 3) {
                            acc[0] = acc[0] ? `${acc[0]}-${part}` : part;
                        } else {
                            acc[1] = acc[1] ? `${acc[1]}-${part}` : part;
                        }
                        return acc;
                    }, ['', '']);
                    // value format: "checked_state|checked_at" or just "checked_at" (legacy)
                    let checkedState = 1; // default to green for legacy imports
                    let checkedAt = value || new Date().toISOString();

                    if (value.includes('|')) {
                        const [state, timestamp] = value.split('|');
                        checkedState = parseInt(state) || 1;
                        checkedAt = timestamp || new Date().toISOString();
                    }

                    db.prepare('INSERT OR REPLACE INTO prayer_checks (date, prayer_name, checked, checked_at) VALUES (?, ?, ?, ?)')
                        .run(date, prayerName, checkedState, checkedAt);
                    const checkStateLabel = checkedState === 1 ? 'green' : checkedState === 2 ? 'orange' : 'unchecked';
                    log(`[IMPORT] prayer_check: ${date}-${prayerName} ${checkStateLabel} (${checkedState})`);
                    importedCount++;
                } else if (type === 'daily_activity') {
                    // key format: "2025-01-15-Tasbih" (date-activity_name)
                    const [date, activityName] = key.split('-').reduce((acc, part, idx) => {
                        if (idx < 3) {
                            acc[0] = acc[0] ? `${acc[0]}-${part}` : part;
                        } else {
                            acc[1] = acc[1] ? `${acc[1]} ${part}` : part;
                        }
                        return acc;
                    }, ['', '']);
                    // value format: "checked_state|checked_at"
                    let checkedState = 1;
                    let checkedAt = value || new Date().toISOString();

                    if (value.includes('|')) {
                        const [state, timestamp] = value.split('|');
                        checkedState = parseInt(state) || 1;
                        checkedAt = timestamp || new Date().toISOString();
                    }

                    db.prepare('INSERT OR REPLACE INTO daily_activities (date, activity_name, checked, checked_at) VALUES (?, ?, ?, ?)')
                        .run(date, activityName, checkedState, checkedAt);
                    const checkStateLabel = checkedState === 1 ? 'green' : checkedState === 2 ? 'orange' : 'unchecked';
                    log(`[IMPORT] daily_activity: ${date}-${activityName} ${checkStateLabel} (${checkedState})`);
                    importedCount++;
                }
            } catch (err) {
                logError(`Error importing line ${i}:`, err.message);
            }
        }

        log(`[IMPORT] Imported ${prayerScheduleCount} prayer_schedule entries`);
        log('[IMPORT] ========== VERIFYING DATABASE AFTER IMPORT ==========');

        // Verify what was actually written to database
        const verifySchedule = db.prepare('SELECT prayer_name, day_of_week, enabled FROM prayer_schedule ORDER BY day_of_week, prayer_name').all();
        log(`[IMPORT] Database now contains ${verifySchedule.length} prayer_schedule entries:`);
        verifySchedule.forEach(entry => {
            log(`[IMPORT]   DB: ${entry.prayer_name}-${entry.day_of_week} = ${entry.enabled}`);
        });

        // Re-schedule athans and Friday Quran after configuration import
        fetchPrayerTimes().then(() => {
            log('[IMPORT] Prayer times reloaded after configuration import');
        });
        scheduleFridayQuran(); // Re-schedule Friday Quran job

        log('[IMPORT] ========== IMPORT COMPLETED ==========');
        res.json({
            success: true,
            message: `Configuration imported successfully (${importedCount} settings, ${prayerScheduleCount} prayer_schedule)`,
            imported: importedCount
        });
    } catch (error) {
        logError('Error importing configuration:', error);
        res.status(500).json({ error: error.message });
    }
});

// POST - Restore default configuration
app.post('/api/settings/restore-defaults', (req, res) => {
    try {
        log('Restoring default configuration...');

        // Restore default general settings
        const updateSetting = db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)');
        updateSetting.run('ics_url', 'https://prayerwebcal.dsultan.com/ics/La_Mecque/cq=0:csr=0:ct=0:ee=0:qs=0:srs=0:ss=0:sus=0:ts=0:tz=Asia%2FRiyadh:x=21.421:y=39.827');
        updateSetting.run('audio_file', 'Masjid Al-Haram.mp3'); // Default Athan audio file
        updateSetting.run('play_on_startup', '1');
        updateSetting.run('play_on_page_load', '0');
        updateSetting.run('audio_output', 'both');
        updateSetting.run('volume', '50');
        updateSetting.run('audio_card', 'auto');
        updateSetting.run('friday_quran_enabled', '0');
        updateSetting.run('friday_quran_time', '07:00');
        updateSetting.run('friday_quran_file', 'Sourat Al Kahf - Hani Arrifai.mp3'); // Default Quran audio file
        updateSetting.run('dark_mode', '0'); // Dark mode disabled by default
        updateSetting.run('fajr_volume', '50'); // Default Fajr volume at 50%
        updateSetting.run('sync_fajr_volume', '0'); // Sync Fajr volume disabled by default (independent volume)

        // NOTE: prayer_settings table is DEPRECATED - prayer_schedule matrix handles all enable/disable logic

        // Restore default weekday settings (all unmuted)
        const updateWeekday = db.prepare('INSERT OR REPLACE INTO muted_weekdays (weekday, muted) VALUES (?, 0)');
        for (let i = 0; i <= 6; i++) {
            updateWeekday.run(i);
        }

        // Restore default prayer schedule (all enabled)
        db.prepare('UPDATE prayer_schedule SET enabled = 1').run();
        log('Prayer schedule matrix restored: all 35 entries enabled');

        // Reset skip_next
        db.prepare('UPDATE skip_next SET skip = 0, last_skipped_prayer = NULL, last_skipped_date = NULL WHERE id = 1').run();

        // Reset all prayer checks
        db.prepare('DELETE FROM prayer_checks').run();
        log('All prayer checks reset');

        // Reset all daily activities
        db.prepare('DELETE FROM daily_activities').run();
        log('All daily activities reset');

        // Re-fetch prayer times with default ICS URL and re-schedule
        fetchPrayerTimes().then(() => {
            log('Prayer times reloaded with default ICS URL');
        });
        scheduleFridayQuran();

        log('✅ Default configuration restored successfully');

        res.json({
            success: true,
            message: 'Configuration restored to defaults successfully'
        });
    } catch (error) {
        logError('Error restoring default configuration:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - List available audio files
app.get('/api/audio-files', (req, res) => {
    try {
        const audioDir = path.join(__dirname, 'audio', 'athan');
        if (!fs.existsSync(audioDir)) {
            fs.mkdirSync(audioDir, { recursive: true });
        }
        const files = fs.readdirSync(audioDir).filter(file =>
            file.endsWith('.mp3') || file.endsWith('.wav')
        );
        res.json(files);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Serve an audio file
app.get('/api/audio/:filename', (req, res) => {
    try {
        const { filename } = req.params;
        const audioPath = path.join(__dirname, 'audio', 'athan', filename);

        if (!fs.existsSync(audioPath)) {
            return res.status(404).json({ error: 'Audio file not found' });
        }

        res.sendFile(audioPath);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - List available Quran audio files
app.get('/api/quran-files', (req, res) => {
    try {
        const quranDir = path.join(__dirname, 'audio', 'coran');
        if (!fs.existsSync(quranDir)) {
            fs.mkdirSync(quranDir, { recursive: true });
        }
        const files = fs.readdirSync(quranDir).filter(file =>
            file.endsWith('.mp3') || file.endsWith('.wav')
        );
        res.json(files);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Serve a Quran audio file
app.get('/api/quran/:filename', (req, res) => {
    try {
        const { filename } = req.params;
        const quranPath = path.join(__dirname, 'audio', 'coran', filename);

        if (!fs.existsSync(quranPath)) {
            return res.status(404).json({ error: 'Quran file not found' });
        }

        res.sendFile(quranPath);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Serve audio/system files (startup sound, etc.)
app.use('/audio/system', express.static(path.join(__dirname, 'audio', 'system')));

// POST - Test Friday Quran playback (30 seconds preview)
app.post('/api/test-quran', (req, res) => {
    try {
        log('Test Quran recitation requested (30s preview)');

        // Get audio output setting
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';

        // Only play server-side if configured for server or both
        if (audioOutput === 'browser') {
            log('Audio output set to browser only, skipping server playback for Quran test');
            return res.json({ success: true, message: 'Quran test will play in browser only' });
        }

        const quranFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
        const quranFile = quranFileRow ? quranFileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3';
        const quranPath = path.join(__dirname, 'audio', 'coran', quranFile);

        const volumeRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('volume');
        const volumePercent = volumeRow ? parseInt(volumeRow.value) : 50;
        const volumeLevel = ((volumePercent / 100) * 4).toFixed(2); // x4 multiplier

        if (!fs.existsSync(quranPath)) {
            logError(`Quran file not found for test: ${quranPath}`);
            return res.status(404).json({ error: 'Quran file not found for test' });
        }

        log(`[test-quran] 🔊 BACKEND QURAN TEST PLAYING (30s): ${quranPath} at UI volume ${volumePercent}% (server: ${volumeLevel}x)`);

        // Play only the first 30 seconds using sox trim with selected audio card
        const { args, env } = buildSoxArgs(volumeLevel, quranPath, ['trim', '0', '30']);
        currentAudioPlayer = spawn('play', args, { env });

        currentAudioPlayer.on('error', (err) => {
            logError('Error playing Quran test:', err);
            currentAudioPlayer = null;
        });

        currentAudioPlayer.on('close', (code) => {
            if (code !== 0) {
                logError(`Quran test process exited with code ${code}`);
            } else {
                log('Quran test (30s) finished');
            }
            currentAudioPlayer = null;
        });

        res.json({ success: true, message: 'Playing Quran test (30 seconds)...' });
    } catch (error) {
        logError('Error in /api/test-quran:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Get update information
app.get('/api/update-info', (req, res) => {
    try {
        const updateInfo = db.prepare('SELECT * FROM update_info WHERE id = 1').get();
        res.json(updateInfo || {
            last_update: null,
            prayers_count: 0,
            city_name: 'Not configured',
            next_update: getNextUpdateTime()
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Get current server time
app.get('/api/server-time', (req, res) => {
    try {
        const now = new Date();
        res.json({
            timestamp: now.toISOString(),
            timestampMs: now.getTime(), // Unix timestamp in milliseconds for client sync
            time: now.toTimeString().split(' ')[0], // HH:MM:SS
            date: formatDateLocal(now),   // YYYY-MM-DD (local date)
            timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
            ip: getServerIPAddress(),
            hostname: process.env.HOST_HOSTNAME || os.hostname()
        });
    } catch (error) {
        logError('Error getting server time:', error);
        res.status(500).json({ error: error.message });
    }
});

// GET - Check server audio support (test actual audio playback capability)
// Uses cache to avoid testing during audio playback (prevents false negatives when ALSA device is busy)
app.get('/api/audio-support', (req, res) => {
    try {
        const platform = os.platform(); // 'linux', 'darwin' (macOS), 'win32' (Windows), etc.
        const { execSync } = require('child_process');
        const now = Date.now();

        // Check if we have a valid cached result (less than 1 minute old)
        if (audioSupportCache && (now - audioSupportCacheTime < AUDIO_SUPPORT_CACHE_DURATION)) {
            log(`[audio-support] 📦 Returning cached result (age: ${Math.round((now - audioSupportCacheTime) / 1000)}s)`);
            return res.json(audioSupportCache);
        }

        let status, message, color, supported = false;

        // If audio is currently playing, skip the playback test to avoid ALSA device busy error
        // Just check if sox exists without testing actual playback
        if (currentAudioPlayer) {
            log(`[audio-support] ⏭️ Audio currently playing, skipping playback test`);
            try {
                execSync('which play', { stdio: 'ignore' });
                // Sox exists, assume it's supported (we can't test playback while device is busy)
                supported = true;
                status = 'supported';
                message = `✅ Supported (${platform === 'linux' ? 'Linux' : platform === 'darwin' ? 'macOS' : platform} with sox)`;
                color = '#27ae60'; // Green
                log(`[audio-support] ✅ Sox found, assuming supported (playback test skipped)`);
            } catch (whichError) {
                // Sox doesn't exist
                const osName = platform === 'darwin' ? 'macOS' : platform === 'win32' ? 'Windows' : platform;
                supported = false;
                status = 'unsupported';
                message = `❌ Not supported - Sox not installed (${osName})`;
                color = '#8B0000'; // Burgundy
                log(`[audio-support] ❌ Sox not found on ${platform}`);
            }

            const result = { supported, status, message, color, platform };
            audioSupportCache = result;
            audioSupportCacheTime = now;
            return res.json(result);
        }

        // No audio playing, perform full test (check sox exists AND test actual playback)
        try {
            execSync('which play', { stdio: 'ignore' });

            // Sox is installed, now test if it can actually play audio
            // Try to play a silent test (generate 0.1 seconds of silence)
            try {
                // Test with synth command: play -n synth 0.1 sine 0 vol 0
                // This generates 0.1s of silence without needing an audio file
                // Use AUDIODRIVER=alsa to force ALSA driver
                execSync('play -n synth 0.1 sine 0 vol 0 2>/dev/null', {
                    stdio: 'ignore',
                    timeout: 2000, // 2 second timeout
                    env: { ...process.env, AUDIODRIVER: 'alsa' }
                });

                // If we reach here, audio playback works
                supported = true;
                status = 'supported';
                message = `✅ Supported (${platform === 'linux' ? 'Linux' : platform === 'darwin' ? 'macOS' : platform} with sox)`;
                color = '#27ae60'; // Green
                log(`[audio-support] ✅ Audio playback test successful on ${platform}`);

            } catch (testError) {
                // Sox exists but can't play audio
                status = 'unsupported';
                const osName = platform === 'darwin' ? 'macOS' : platform === 'win32' ? 'Windows' : platform;
                message = `❌ Not supported - Sox installed but audio playback failed (${osName})`;
                color = '#8B0000'; // Burgundy
                log(`[audio-support] ❌ Sox found but audio test failed on ${platform}:`, testError.message);
            }

        } catch (whichError) {
            // Sox/play not installed
            const osName = platform === 'darwin' ? 'macOS' : platform === 'win32' ? 'Windows' : platform;
            status = 'unsupported';
            message = `❌ Not supported - Sox not installed (${osName})`;
            color = '#8B0000'; // Burgundy
            log(`[audio-support] ❌ Sox not found on ${platform}`);
        }

        // Cache the result
        const result = { supported, status, message, color, platform };
        audioSupportCache = result;
        audioSupportCacheTime = now;
        log(`[audio-support] 💾 Result cached for ${AUDIO_SUPPORT_CACHE_DURATION / 1000}s`);

        res.json(result);
    } catch (error) {
        logError('[audio-support] Error checking audio support:', error);
        const osName = os.platform() === 'darwin' ? 'macOS' : os.platform() === 'win32' ? 'Windows' : os.platform();
        res.json({
            supported: false,
            status: 'unsupported',
            message: `❌ Not supported - Error checking audio support (${osName})`,
            color: '#8B0000',
            platform: os.platform()
        });
    }
});

// GET - Check whether the browser should play athan (only for main 5 prayers)
app.get('/api/check-athan-time', (req, res) => {
    try {
        // Check where the audio should be played
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';

        // Only play in browser if configured for browser or both
        if (audioOutput === 'server') {
            res.json({ shouldPlay: false });
            return;
        }

        // Convert JS day (0=Sunday) to our matrix day (0=Monday...6=Sunday)
        const now = new Date();
        const jsDay = now.getDay();
        const dayIndex = (jsDay + 6) % 7; // 0=Monday, 1=Tuesday, ..., 6=Sunday
        const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

        const currentDate = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

        // Only check the 5 main prayers
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];

        // Retrieve today's main prayers only
        const prayers = db.prepare(`
            SELECT * FROM prayers 
            WHERE date = ? AND prayer_name IN (?, ?, ?, ?, ?)
            ORDER BY prayer_time
        `).all(currentDate, ...mainPrayers);

        // Check if we are at or past prayer time (within 1 minute tolerance)
        const currentMinutes = parseInt(currentTime.split(':')[0]) * 60 + parseInt(currentTime.split(':')[1]);
        log(`[check-athan-time] Current time: ${currentTime} (${currentMinutes} minutes)`);

        for (const prayer of prayers) {
            const prayerMinutes = parseInt(prayer.prayer_time.split(':')[0]) * 60 + parseInt(prayer.prayer_time.split(':')[1]);
            const diff = currentMinutes - prayerMinutes;

            log(`[check-athan-time] Checking ${prayer.prayer_name} at ${prayer.prayer_time} (${prayerMinutes} minutes), diff: ${diff} minutes`);

            // Only trigger if current time >= prayer time and within 1 minute
            if (diff >= 0 && diff <= 1) {
                log(`[check-athan-time] ✅ ${prayer.prayer_name} is in trigger window (diff: ${diff} minutes)`);

                // Check if skip_next is active (mute next athan)
                // We check BOTH the flag AND the last_skipped_* fields to handle race conditions
                // where playAthan() on the server may have already consumed the flag
                const skipNext = db.prepare('SELECT skip, last_skipped_prayer, last_skipped_date FROM skip_next WHERE id = 1').get();

                // Case 1: Flag is still active (playAthan hasn't run yet)
                if (skipNext && skipNext.skip === 1) {
                    log(`[check-athan-time] ❌ Athan for ${prayer.prayer_name} is muted (skip_next flag active) - browser playback blocked`);
                    res.json({ shouldPlay: false });
                    return;
                }

                // Case 2: Flag was consumed by playAthan() but we're still in the same prayer time window
                // Check if this specific prayer was already skipped today
                if (skipNext && skipNext.last_skipped_prayer === prayer.prayer_name && skipNext.last_skipped_date === currentDate) {
                    log(`[check-athan-time] ❌ Athan for ${prayer.prayer_name} was already skipped today (last_skipped check) - browser playback blocked`);
                    res.json({ shouldPlay: false });
                    return;
                }

                // Check prayer_schedule matrix (unified control for prayer × day)
                const scheduleEntry = db.prepare('SELECT enabled FROM prayer_schedule WHERE prayer_name = ? AND day_of_week = ?')
                    .get(prayer.prayer_name, dayIndex);
                if (scheduleEntry && scheduleEntry.enabled === 0) {
                    log(`[check-athan-time] ❌ ${prayer.prayer_name} disabled for ${dayNames[dayIndex]} in schedule matrix`);
                    res.json({ shouldPlay: false });
                    return;
                }

                const audioFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_file');
                const audioFile = audioFileRow ? audioFileRow.value : 'Masjid Al-Haram.mp3';

                res.json({
                    shouldPlay: true,
                    prayerName: prayer.prayer_name,
                    audioFile: audioFile
                });
                return;
            }
        }

        res.json({ shouldPlay: false });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// GET - Check whether the browser should play Friday Quran
app.get('/api/check-friday-quran', (req, res) => {
    try {
        // Check audio output setting first
        const audioOutputRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputRow ? audioOutputRow.value : 'both';

        // Always check if server is currently playing Quran (for notification banner)
        const serverPlayingQuran = currentAudioType === 'quran';

        // Check if Friday Quran is enabled
        const enabledRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_enabled');
        if (!enabledRow || enabledRow.value !== '1') {
            // Even if disabled, return serverPlayingQuran status (for manual triggers)
            res.json({ shouldPlay: false, serverPlayingQuran });
            return;
        }

        // If audio output is server-only, browser should not play but may need to show notification
        if (audioOutput === 'server') {
            // Return serverPlayingQuran so client can show notification banner
            res.json({ shouldPlay: false, serverPlayingQuran });
            return;
        }

        // Check if today is Friday
        const now = new Date();
        const dayOfWeek = now.getDay();
        if (dayOfWeek !== 5) {
            res.json({ shouldPlay: false, serverPlayingQuran });
            return;
        }

        // Check the trigger from the database
        const trigger = db.prepare('SELECT should_play, last_played_date, last_played_time FROM friday_quran_trigger WHERE id = 1').get();

        if (trigger && trigger.should_play === 1) {
            log(`[check-friday-quran] ✅ Friday Quran trigger is active, should play in browser`);

            // Get the Quran file
            const quranFileRow = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
            const quranFile = quranFileRow ? quranFileRow.value : 'Sourat Al Kahf - Hani Arrifai.mp3';

            // Reset the trigger after sending the response
            db.prepare('UPDATE friday_quran_trigger SET should_play = 0 WHERE id = 1').run();
            log(`[check-friday-quran] ✅ Trigger consumed, reset to 0`);

            res.json({
                shouldPlay: true,
                quranFile: quranFile,
                type: 'friday_quran',
                serverPlayingQuran
            });
            return;
        }

        res.json({ shouldPlay: false, serverPlayingQuran });
    } catch (error) {
        logError('[check-friday-quran] Error:', error);
        res.status(500).json({ error: error.message });
    }
});

// Start server - listen on all network interfaces (0.0.0.0) to allow remote access
app.listen(PORT, '0.0.0.0', () => {
    const serverIP = getServerIPAddress();
    log(`Athan Center server running on port ${PORT}`);
    log(`📱 Access locally:  http://localhost:${PORT}`);
    log(`🌐 Access remotely: http://${serverIP}:${PORT}`);

    // Load initial prayer times on startup
    fetchPrayerTimes().then(() => {
        log('Initial prayer times loaded');

        // Play startup audio if enabled (with a longer delay to ensure ALSA is ready)
        // Only play on server startup if audio_output is 'server' or 'both'
        const playOnStartupSetting = db.prepare('SELECT value FROM settings WHERE key = ?').get('play_on_startup');
        const audioOutputSetting = db.prepare('SELECT value FROM settings WHERE key = ?').get('audio_output');
        const audioOutput = audioOutputSetting ? audioOutputSetting.value : 'both';

        if (playOnStartupSetting && playOnStartupSetting.value === '1') {
            if (audioOutput === 'server' || audioOutput === 'both') {
                log(`Startup audio will play in 5 seconds on server (audio_output: ${audioOutput})...`);
                setTimeout(() => {
                    log('Playing startup audio on server...');
                    playStartupSound();
                }, 5000); // Increased from 2s to 5s to allow ALSA to fully initialize
            } else {
                log(`[Startup] ⏭️ Skipped server audio (audio_output is '${audioOutput}' - browser only)`);
            }
        }
    });

    // Hijri dates will be loaded by the daily cron job at midnight
    log('Hijri dates will be updated by daily cron job');

    // Log Friday Quran status at startup
    log('\n========== FRIDAY QURAN STATUS AT STARTUP ==========');
    const fridayEnabled = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_enabled');
    const fridayTime = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_time');
    const fridayFile = db.prepare('SELECT value FROM settings WHERE key = ?').get('friday_quran_file');
    log(`Friday Quran enabled: ${fridayEnabled ? fridayEnabled.value : 'not set'}`);
    log(`Friday Quran time: ${fridayTime ? fridayTime.value : '07:00 (default)'}`);
    log(`Friday Quran file: ${fridayFile ? fridayFile.value : 'Sourat Al Kahf - Hani Arrifai.mp3 (default)'}`);
    log(`Friday Quran job scheduled: ${fridayQuranJob !== null ? '✅ YES' : '❌ NO'}`);
    log('====================================================\n');

    // Re-schedule athan calls every hour to catch any missed prayers
    // This ensures that if the server restarts after a prayer time,
    // the next prayers will still be properly scheduled
    setInterval(() => {
        log('⏰ Hourly re-scheduling of athan calls...');
        scheduleAthanCalls();
    }, 60 * 60 * 1000); // Every hour

    // System time drift detection - check every 10 seconds
    // If system time changes (NTP sync, manual adjustment, timezone change, etc.),
    // re-schedule all athan calls to ensure they trigger at the correct time
    setInterval(() => {
        const now = Date.now();
        const expectedElapsed = 10000; // 10 seconds interval
        const actualElapsed = now - lastSystemTime;
        const timeDrift = Math.abs(actualElapsed - expectedElapsed);

        // If drift is more than 5 seconds, the system time probably changed
        if (timeDrift > 5000) {
            logWarn(`⚠️ SERVER: System time change detected! Drift: ${timeDrift}ms (${(timeDrift / 1000).toFixed(1)}s)`);
            log('🔄 Re-scheduling all athan calls to sync with new system time...');

            // Re-schedule all athan calls based on new system time
            scheduleAthanCalls();

            // Also re-schedule Friday Quran if enabled
            scheduleFridayQuran();

            log('✅ Athan calls re-scheduled successfully');
        }

        lastSystemTime = now;
    }, 10000); // Check every 10 seconds
});

// Graceful shutdown handlers
process.on('SIGTERM', () => {
    log('SIGTERM received, closing database...');
    db.close();
    process.exit(0);
});

process.on('SIGINT', () => {
    log('SIGINT received, closing database...');
    db.close();
    process.exit(0);
});
