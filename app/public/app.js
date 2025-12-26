// API configuration
const API_BASE = window.location.origin;

// ===== SERVER TIME SYNCHRONIZATION MODULE =====
// This module ensures that the client always uses the server's time
// instead of the local browser time, preventing issues with time zones and clock drift
let serverTimeOffset = 0; // Difference in milliseconds between server and client time
let lastSyncTime = 0; // When we last synchronized with the server

// Get the current time synchronized with the server
function getServerSyncedDate() {
    return new Date(Date.now() + serverTimeOffset);
}

// Synchronize client time with server time
async function syncTimeWithServer() {
    try {
        const clientRequestTime = Date.now();
        const response = await fetch(`${API_BASE}/api/server-time`);
        const clientReceiveTime = Date.now();
        const data = await response.json();

        // Calculate round-trip time (network latency)
        const roundTripTime = clientReceiveTime - clientRequestTime;

        // Estimate server time at the moment we received the response
        // by adding half the round-trip time to account for network delay
        const estimatedServerTime = data.timestampMs + (roundTripTime / 2);

        // Calculate offset: how much time to add to local time to get server time
        serverTimeOffset = estimatedServerTime - clientReceiveTime;
        lastSyncTime = clientReceiveTime;


        return data;
    } catch (error) {
        console.error('❌ Failed to sync time with server:', error);
        // If sync fails, keep using previous offset (or 0 if first sync)
        return null;
    }
}

// Application state
let currentDate = getServerSyncedDate();
let nextPrayer = null;
let countdownInterval = null;
let lastPlayedPrayer = null; // Avoid replaying the same athan twice
let audioElement = null; // Audio element for browser playback
let currentVolume = 0.5; // Default volume set to 50% (0.0-1.0)
let autoplayUnlockHandler = null;
let autoplayPromptShown = false;
let prayerTimeReachedAt = null; // Track when prayer time was reached (for 15-minute display)
let currentPrayerInProgress = null; // Track the complete prayer object currently in progress
let isRealPrayerAudio = false; // Track if current audio is a real prayer (not test/startup)
let isReloadingPrayer = false; // Prevent multiple simultaneous prayer reloads
let isLoadingPrayers = false; // Prevent multiple simultaneous loadPrayers() calls
let lastSystemTime = Date.now(); // Track system time to detect time changes
let serverQuranNotificationShown = false; // Track if server Quran notification is being displayed

// Utility function to format date as YYYY-MM-DD using local time (avoiding timezone issues)
function formatDateLocal(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

// ===== FLOATING AUDIO NOTIFICATION BANNER =====
// Show the floating notification banner for non-prayer audio
function showAudioNotification(message) {
    const banner = document.getElementById('audioNotificationBanner');
    const textElement = document.getElementById('audioNotificationText');

    if (banner && textElement) {
        textElement.textContent = message;
        banner.style.display = 'block';
    }
}

// Hide the floating notification banner
function hideAudioNotification() {
    const banner = document.getElementById('audioNotificationBanner');

    if (banner) {
        banner.style.display = 'none';
    }
}

// Initialization
document.addEventListener('DOMContentLoaded', async () => {
    // FIRST: Synchronize time with server before doing anything else
    await syncTimeWithServer();

    // Initialize lastPlayedPrayer to prevent playing audio for prayers that already passed
    // when the page is loaded after their time
    initializeLastPlayedPrayer();

    // Load prayers FIRST and wait for it to complete before starting countdown
    await loadPrayers();

    // Setup event listeners BEFORE loading settings to ensure functions are defined
    setupEventListeners();

    loadSettings().then(async () => {
        // Check server audio support AFTER loading settings
        await loadAudioSupport();  // This may force audio_output to 'browser'

        // Start checking athan time after loading settings
        checkAthanTime();
        // Also check Friday Quran
        checkFridayQuran();
    });
    loadAudioDevices();  // Load available audio cards
    loadScheduleMatrix();  // Unified schedule matrix
    loadAudioFiles();
    loadQuranFiles();
    initializeFridayQuranTime();
    loadServerTime();
    loadUpdateInfo();
    initAccordion();  // Initialize accordion after all content is loaded

    // Start countdown AFTER prayers are loaded to ensure nextPrayerCard has correct data
    startCountdown();
    playOnPageLoad();

    // Refresh prayers every minute
    setInterval(() => {
        loadPrayers();
    }, 60000);

    // Check athan time every 5 seconds to ensure we don't miss the 1-minute window
    // Backend triggers exactly at prayer time, frontend must check frequently enough to catch it
    setInterval(() => {
        checkAthanTime();
    }, 5000);

    // Check Friday Quran every 5 seconds as well
    setInterval(() => {
        checkFridayQuran();
    }, 5000);

    // Refresh update info every minute
    setInterval(() => {
        loadUpdateInfo();
    }, 60000);

    // Re-synchronize with server every 5 minutes to prevent clock drift
    setInterval(async () => {
        await syncTimeWithServer();
        // After re-sync, reload prayers to ensure we're using the correct time
        loadPrayers();
        loadNextPrayer();
    }, 5 * 60 * 1000); // 5 minutes

    // Detect system time changes every 10 seconds
    // If the system time jumps by more than expected, re-sync immediately
    setInterval(() => {
        const now = Date.now();
        const expectedElapsed = 10000; // 10 seconds interval
        const actualElapsed = now - lastSystemTime;
        const timeDrift = Math.abs(actualElapsed - expectedElapsed);

        // If drift is more than 5 seconds, the system time probably changed
        if (timeDrift > 5000) {
            // Force immediate re-sync and reload
            syncTimeWithServer().then(() => {
                loadPrayers();
                loadNextPrayer();
                // Reset cached times
                prayerTimeReachedAt = null;
                currentPrayerInProgress = null;
            });
        }

        lastSystemTime = now;
    }, 10000);

    // Update server time display every second (using synced time)
    setInterval(() => {
        updateServerTimeDisplay();
    }, 1000);

    // Update date buttons every minute
    setInterval(() => {
        updateDateButtons();
    }, 60000);

    // Refresh skip next status every minute to detect when backend resets the flag
    setInterval(() => {
        checkSkipNextStatus();
    }, 60000);
});

// Initialize lastPlayedPrayer to mark all past prayers as already played
async function initializeLastPlayedPrayer() {
    try {
        const now = getServerSyncedDate();
        const today = formatDateLocal(now);
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

        // Get all prayers for today
        const response = await fetch(`${API_BASE}/api/prayers/${today}`);
        const prayers = await response.json();

        // Mark any prayer that has passed (even by 1 second) to prevent audio playback on page load
        // Audio should only play if the user is already on the page when prayer time arrives
        let lastPastPrayer = null;
        for (const prayer of prayers) {
            if (prayer.prayer_time <= currentTime) {
                lastPastPrayer = prayer;
            }
        }

        if (lastPastPrayer) {
            const prayerKey = `${today}-${lastPastPrayer.prayer_name}`;
            lastPlayedPrayer = prayerKey; // Mark the most recent past prayer as played
        }
    } catch (error) {
        console.error('Error initializing lastPlayedPrayer:', error);
    }
}

// Play startup sound in browser
function playStartupSoundInBrowser() {
    try {

        // Ensure this is NOT marked as real prayer audio
        isRealPrayerAudio = false;

        // Create audio element if it doesn't exist
        if (!audioElement) {
            audioElement = new Audio();

            // Event listeners for audio playback
            audioElement.addEventListener('play', () => {
                disableAllButtons();
            });

            audioElement.addEventListener('ended', () => {
                enableAllButtons();
            });

            audioElement.addEventListener('pause', () => {
                enableAllButtons();
            });

            audioElement.addEventListener('error', (e) => {
                console.error('[Audio] ❌ Error event triggered:', e);
                console.error('[Audio] Error details:', {
                    code: e.target?.error?.code,
                    message: e.target?.error?.message,
                    src: e.target?.src
                });
                enableAllButtons();
            });

            audioElement.addEventListener('loadstart', () => {
            });

            audioElement.addEventListener('canplay', () => {
            });

        } else {
        }

        const startupAudioPath = `${API_BASE}/audio/system/startup.mp3`;

        audioElement.src = startupAudioPath;

        // Browser volume is always 100% (1.0) - server volume is controlled by slider
        audioElement.volume = 1.0;

        audioElement.play()
            .then(() => {
            })
            .catch(err => {
                console.error('[playStartupSoundInBrowser] ❌ ❌ ❌ PLAY FAILED!');
                console.error('[playStartupSoundInBrowser] Error name:', err.name);
                console.error('[playStartupSoundInBrowser] Error message:', err.message);
                console.error('[playStartupSoundInBrowser] Full error:', err);

                if (err.name === 'NotAllowedError') {
                } else if (err.name === 'NotSupportedError') {
                } else {
                }
            });
    } catch (error) {
        console.error('[playStartupSoundInBrowser] ❌ FATAL ERROR:', error);
        console.error('[playStartupSoundInBrowser] Error stack:', error.stack);
    }
}

// Play audio when the page loads
async function playOnPageLoad() {
    try {

        // Get settings to check if page load audio is enabled
        const settings = await fetch(`${API_BASE}/api/settings`).then(r => r.json());


        // Check if play_on_page_load is enabled
        if (settings.play_on_page_load !== '1') {
            return;
        }


        // IMPORTANT: Page load audio should ONLY play in the browser, never on the server
        // Server audio only plays at Docker container startup (not on page load)
        // This ensures the correct behavior for all audio_output options:
        // - 'browser': plays in browser only (on page load)
        // - 'server': no audio on page load (server audio only at Docker startup)
        // - 'both': plays in browser on page load + server audio at Docker startup

        // Play in browser (if audio_output allows it)
        if (settings.audio_output === 'browser' || settings.audio_output === 'both') {
            playStartupSoundInBrowser();
        } else {
        }


    } catch (error) {
        console.error('[playOnPageLoad] ❌ FATAL ERROR:', error);
        console.error('[playOnPageLoad] Error stack:', error.stack);
    }
}

// Check skip next status and update UI
async function checkSkipNextStatus() {
    try {
        const skipBtn = document.getElementById('skipNextBtn');
        const muteAlert = document.getElementById('muteAlertBanner');

        const today = getServerSyncedDate();
        const todayStr = formatDateLocal(today);
        const tomorrow = getServerSyncedDate();
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowStr = formatDateLocal(tomorrow);
        const currentDateStr = formatDateLocal(currentDate);

        const skipResponse = await fetch(`${API_BASE}/api/skip-next`);
        const skipData = await skipResponse.json();

        let isMuted = false;
        let muteType = null;
        let mutedPrayerName = null;

        // Check if skip_next is active
        if (skipData.skip) {
            isMuted = true;
            muteType = 'manual';
        }

        // Check if next prayer is disabled in general settings
        if (nextPrayer && nextPrayer.prayer_name) {
            const settingsResponse = await fetch(`${API_BASE}/api/prayer-settings/${nextPrayer.prayer_name}`);
            const settingsData = await settingsResponse.json();

            if (settingsData && settingsData.enabled === 0) {
                isMuted = true;
                muteType = 'general';
                mutedPrayerName = nextPrayer.prayer_name;
            }
        }

        // Determine if we should show banners and enable button based on date
        const isViewingToday = currentDateStr === todayStr;
        const isViewingTomorrow = currentDateStr === tomorrowStr;
        const currentTime = today.toTimeString().split(' ')[0].substring(0, 5);

        // Check if Isha prayer has passed today
        let ishaHasPassed = false;
        try {
            const todayPrayersResponse = await fetch(`${API_BASE}/api/prayers/${todayStr}`);
            const todayPrayers = await todayPrayersResponse.json();
            const ishaPrayer = todayPrayers.find(p => p.prayer_name === 'Isha');
            if (ishaPrayer && currentTime > ishaPrayer.prayer_time) {
                ishaHasPassed = true;
            }
        } catch (error) {
            console.error('Error checking Isha time:', error);
        }

        // Button and banner should ONLY be visible when nextPrayerCard is shown
        // Same logic as nextPrayerCard: today OR (tomorrow if Isha has passed)
        const shouldShow = isViewingToday || (isViewingTomorrow && ishaHasPassed);

        if (!shouldShow) {
            // Not the right date - hide both button AND banner completely
            muteAlert.style.display = 'none';
            skipBtn.style.display = 'none';
            return;
        }

        // Show the button (nextPrayerCard is visible)
        skipBtn.style.display = 'block';
        skipBtn.classList.remove('disabled');
        skipBtn.style.pointerEvents = 'auto';
        skipBtn.title = '';

        // Show banner if prayer is muted
        const shouldShowBanner = isMuted;

        if (!shouldShowBanner) {
            // Hide banner but keep button enabled
            muteAlert.style.display = 'none';
            return;
        }

        // Show mute alert banner with appropriate message
        if (muteType === 'manual') {
            const prayerLabel = nextPrayer && nextPrayer.prayer_name
                ? getPrayerName(nextPrayer.prayer_name)
                : '';
            if (prayerLabel) {
                muteAlert.textContent = `🔇 Next athan (${prayerLabel}) is muted`;
            } else {
                muteAlert.textContent = '🔇 Next athan is muted';
            }
        } else if (muteType === 'general') {
            muteAlert.textContent = `🔇 ${getPrayerName(mutedPrayerName)} athan is muted (general settings)`;
        }
        muteAlert.style.display = 'block';
        muteAlert.dataset.muteType = muteType;
        muteAlert.dataset.prayerName = mutedPrayerName || '';

        // Grey out the skip button if already muted
        skipBtn.classList.add('disabled');
        skipBtn.style.pointerEvents = 'none';
    } catch (error) {
        console.error('Error checking skip next status:', error);
    }
}

function handleAutoplayBlocked() {
    if (autoplayUnlockHandler) {
        return;
    }

    const cleanup = () => {
        document.removeEventListener('click', autoplayUnlockHandler);
        document.removeEventListener('touchstart', autoplayUnlockHandler);
        autoplayUnlockHandler = null;
    };

    autoplayUnlockHandler = () => {
        if (!audioElement) {
            cleanup();
            return;
        }

        audioElement.play().then(() => {
            cleanup();
        }).catch(err => {
            console.error('Athan playback still blocked after interaction:', err);
            cleanup();
        });
    };

    document.addEventListener('click', autoplayUnlockHandler, { once: true });
    document.addEventListener('touchstart', autoplayUnlockHandler, { once: true });

    if (!autoplayPromptShown) {
        autoplayPromptShown = true;
        alert('Your browser blocked autoplay. Tap or click once to start the athan audio.');
    } else {
    }
}

// Check if it's time for Friday Quran
async function checkFridayQuran() {
    try {
        const response = await fetch(`${API_BASE}/api/check-friday-quran`);
        const data = await response.json();

        // Show notification banner if server is playing Quran (for server-only audio output)
        if (data.serverPlayingQuran) {
            if (!serverQuranNotificationShown) {
                showAudioNotification('Al Kahf Sourat recitation playing');
                serverQuranNotificationShown = true;
            }
        } else {
            // Server stopped playing - hide notification if it was shown
            if (serverQuranNotificationShown) {
                hideAudioNotification();
                serverQuranNotificationShown = false;
            }
        }

        if (data.shouldPlay && data.type === 'friday_quran') {
            // Play Quran in browser
            playQuranInBrowser(data.quranFile);
        }
    } catch (error) {
        // Silent error - don't spam console
    }
}

// Check if it's time for athan
async function checkAthanTime() {
    try {
        const now = getServerSyncedDate();
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);

        const response = await fetch(`${API_BASE}/api/check-athan-time`);
        const data = await response.json();


        if (data.shouldPlay) {
            // Create a unique identifier for this prayer (date + name)
            const today = formatDateLocal(getServerSyncedDate());
            const prayerKey = `${today}-${data.prayerName}`;


            // Prevent replaying the same athan
            if (lastPlayedPrayer !== prayerKey) {
                playAthanInBrowser(data.audioFile, data.prayerName);
                lastPlayedPrayer = prayerKey;
            } else {
            }
        }
    } catch (error) {
        // Silent error - don't spam console when server is unreachable
    }
}

// Disable all buttons during athan playback
function disableAllButtons() {
    const buttons = document.querySelectorAll('button');
    buttons.forEach(button => {
        // Don't disable the stop audio button and settings button (always keep them active)
        if (button.id === 'stopAudioBtn' || button.id === 'settingsBtn') {
            return;
        }
        button.dataset.wasDisabled = button.disabled ? 'true' : 'false';
        button.disabled = true;
        button.classList.add('audio-playing-disabled');
    });
}

// Re-enable all buttons after athan playback
function enableAllButtons() {
    const buttons = document.querySelectorAll('button');
    buttons.forEach(button => {
        // Stop audio button and settings button are always active, skip them
        if (button.id === 'stopAudioBtn' || button.id === 'settingsBtn') {
            return;
        }
        if (button.dataset.wasDisabled !== 'true') {
            button.disabled = false;
        }
        button.classList.remove('audio-playing-disabled');
    });

    // Reset prayer audio flag
    isRealPrayerAudio = false;

    // Note: nextPrayerCard animation is controlled by startCountdown(), not by audio playback
}

// Play athan in the browser
function playAthanInBrowser(audioFile, prayerName) {
    try {
        const nextPrayerCard = document.getElementById('nextPrayerCard');

        // Mark as real prayer audio ONLY if it's not a test
        // Real prayers: Fajr | Sobh, Dohr, Asr, Maghrib, Isha
        isRealPrayerAudio = (prayerName !== 'Test' && prayerName !== 'Startup' && prayerName !== 'PageLoad');

        // Create audio element if it doesn't exist
        if (!audioElement) {
            audioElement = new Audio();

            // Event listeners for audio playback
            audioElement.addEventListener('play', () => {
                disableAllButtons();
            });

            audioElement.addEventListener('ended', () => {
                enableAllButtons();
                // Hide notification banner when audio ends (for non-prayer audio)
                if (!isRealPrayerAudio) {
                    hideAudioNotification();
                }
            });

            audioElement.addEventListener('pause', () => {
                enableAllButtons();
                // Note: Don't hide banner on pause - user might have manually paused
            });

            audioElement.addEventListener('error', (e) => {
                console.error('[Audio] Error event triggered:', e);
                enableAllButtons();
                // Hide notification banner on error
                hideAudioNotification();
            });
        }

        // Browser volume is always 100% (1.0) - server volume is controlled by slider
        audioElement.volume = 1.0;

        // Show floating notification banner for non-prayer audio (Test)
        if (prayerName === 'Test') {
            showAudioNotification('Test Athan web playing (30s preview)');
        }

        // Load and play audio
        audioElement.src = `${API_BASE}/api/audio/${audioFile}`;
        audioElement.play().catch(err => {
            console.error('[playAthanInBrowser] ❌ Failed to play audio:', err);
            // Note: Some browsers block autoplay without interaction
            handleAutoplayBlocked();
        });
    } catch (error) {
        console.error('Error in playAthanInBrowser:', error);
    }
}

// Play Quran in the browser
function playQuranInBrowser(quranFile, isTest = false) {
    try {
        // Quran recitation is NOT a prayer athan, so don't animate nextPrayerCard
        isRealPrayerAudio = false;

        // Create audio element if it doesn't exist
        if (!audioElement) {
            audioElement = new Audio();

            // Event listeners for audio playback
            audioElement.addEventListener('play', () => {
                disableAllButtons();
            });

            audioElement.addEventListener('ended', () => {
                enableAllButtons();
                // Hide notification banner when audio ends
                hideAudioNotification();
            });

            // REMOVED pause listener - it conflicts with stopAllAudio()
            // enableAllButtons() is called by stopAllAudio() or ended event

            audioElement.addEventListener('error', (e) => {
                console.error('[Audio] Error event triggered:', e);
                enableAllButtons();
                // Hide notification banner on error
                hideAudioNotification();
            });
        }

        // Browser volume is always 100% (1.0) - server volume is controlled by slider
        audioElement.volume = 1.0;

        // Show floating notification banner for Quran recitation
        const message = isTest
            ? 'Test web Quran recitation playing (30s preview)'
            : 'Al Kahf Sourat recitation playing';
        showAudioNotification(message);

        // Load and play audio
        audioElement.src = `${API_BASE}/api/quran/${quranFile}`;
        audioElement.load(); // Force reload of the source
        audioElement.play().catch(err => {
            console.error('[playQuranInBrowser] ❌ Failed to play audio:', err);
            handleAutoplayBlocked();
        });
    } catch (error) {
        console.error('Error in playQuranInBrowser:', error);
    }
}

// Play full Quran recitation (user-triggered)
async function playFullQuran() {
    try {
        const quranFile = document.getElementById('fridayQuranFile').value;

        if (!quranFile) {
            alert('No Quran file selected');
            return;
        }

        // Get audio output setting
        const settings = await fetch(`${API_BASE}/api/settings`).then(r => r.json());
        const audioOutput = settings.audio_output || 'both';

        // Play on server if audio_output allows it (full recitation, not test)
        if (audioOutput === 'server' || audioOutput === 'both') {
            try {
                await fetch(`${API_BASE}/api/trigger-friday-quran`);
                console.log('[playFullQuran] Server playback triggered');

                // Show notification banner for server-only playback
                if (audioOutput === 'server') {
                    showAudioNotification('Al Kahf Sourat recitation playing');
                }
            } catch (serverError) {
                console.error('[playFullQuran] Server playback failed:', serverError);
                // Don't alert - continue with browser playback if available
            }
        }

        // Play in browser if audio_output allows it (full recitation, not test)
        if (audioOutput === 'browser' || audioOutput === 'both') {
            playQuranInBrowser(quranFile, false);
        }

    } catch (error) {
        console.error('Error in playFullQuran:', error);
        alert('Error playing Quran recitation: ' + error.message);
    }
}

// Generate yearly calendar
function generateYearCalendar(year) {
    const calendarGrid = document.getElementById('calendarGrid');
    const currentYearSpan = document.getElementById('currentYear');
    currentYearSpan.textContent = year;

    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'];
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    const today = getServerSyncedDate();
    const todayStr = formatDateLocal(today);
    const selectedStr = formatDateLocal(currentDate);

    let html = '';

    for (let month = 0; month < 12; month++) {
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const daysInMonth = lastDay.getDate();
        const startingDayOfWeek = firstDay.getDay();

        html += `
            <div class="calendar-month">
                <div class="calendar-month-header">${monthNames[month]} ${year}</div>
                <div class="calendar-weekdays">
                    ${weekdays.map(day => `<div class="calendar-weekday">${day}</div>`).join('')}
                </div>
                <div class="calendar-days">
        `;

        // Empty cells for days before month starts
        for (let i = 0; i < startingDayOfWeek; i++) {
            html += '<div class="calendar-day empty"></div>';
        }

        // Days of the month
        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(year, month, day);
            // Format date as YYYY-MM-DD using local date to avoid timezone issues
            const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
            let classes = 'calendar-day';

            if (dateStr === todayStr) {
                classes += ' today';
            }
            if (dateStr === selectedStr) {
                classes += ' selected';
            }

            html += `<div class="${classes}" data-date="${dateStr}">${day}</div>`;
        }

        html += `
                </div>
            </div>
        `;
    }

    calendarGrid.innerHTML = html;

    // Add click handlers to all calendar days
    document.querySelectorAll('.calendar-day:not(.empty)').forEach(dayElement => {
        dayElement.addEventListener('click', () => {
            const selectedDate = dayElement.dataset.date;
            currentDate = new Date(selectedDate + 'T12:00:00');
            loadPrayers();
            document.getElementById('calendarModal').style.display = 'none';
        });
    });
}

// Stop all audio playback (both server and browser)
async function stopAllAudio() {
    try {
        // Stop browser audio completely
        if (audioElement) {
            audioElement.pause();
            audioElement.currentTime = 0;
            // Don't clear src - it causes issues with replaying audio
            // Just pause and reset is enough
        }

        // Stop server audio via API (GET request)
        const response = await fetch(`${API_BASE}/api/stop-audio`);
        const data = await response.json();

        // Hide audio notification banner
        hideAudioNotification();

        // Re-enable buttons
        enableAllButtons();

        console.log('[stopAllAudio] ✅ All audio stopped successfully');

    } catch (error) {
        console.error('[stopAllAudio] ❌ Error stopping audio:', error);
        // Still try to clean up UI even if API call fails
        hideAudioNotification();
        enableAllButtons();
    }
}

// Initialize accordion for settings sections
function initAccordion() {
    const sections = document.querySelectorAll('.settings-section');

    sections.forEach((section, index) => {
        // Wrap existing content
        const header = section.querySelector('h3');
        if (!header) return;

        const headerText = header.textContent;
        const content = Array.from(section.childNodes).filter(node => node !== header);

        // Clear section
        section.innerHTML = '';

        // Create header wrapper
        const headerWrapper = document.createElement('div');
        headerWrapper.className = 'settings-section-header';
        if (index === 0) headerWrapper.classList.add('active'); // First section open by default

        const newHeader = document.createElement('h3');
        newHeader.textContent = headerText;

        const toggle = document.createElement('span');
        toggle.className = 'section-toggle';
        toggle.textContent = '▼';

        headerWrapper.appendChild(newHeader);
        headerWrapper.appendChild(toggle);

        // Create content wrapper
        const contentWrapper = document.createElement('div');
        contentWrapper.className = 'settings-section-content';
        if (index === 0) contentWrapper.classList.add('active'); // First section open by default
        content.forEach(node => contentWrapper.appendChild(node));

        // Add click listener
        headerWrapper.addEventListener('click', () => {
            const isActive = headerWrapper.classList.contains('active');

            // Close all sections
            document.querySelectorAll('.settings-section-header').forEach(h => h.classList.remove('active'));
            document.querySelectorAll('.settings-section-content').forEach(c => c.classList.remove('active'));

            // Open clicked section if it wasn't active
            if (!isActive) {
                headerWrapper.classList.add('active');
                contentWrapper.classList.add('active');
            }
        });

        section.appendChild(headerWrapper);
        section.appendChild(contentWrapper);
    });
}

// Programmatically open a specific settings section in the accordion
function openSettingsSection(sectionId) {
    const section = document.getElementById(sectionId);
    if (!section) return;

    const header = section.querySelector('.settings-section-header');
    const content = section.querySelector('.settings-section-content');
    if (!header || !content) return;

    document.querySelectorAll('.settings-section-header').forEach(h => h.classList.remove('active'));
    document.querySelectorAll('.settings-section-content').forEach(c => c.classList.remove('active'));

    header.classList.add('active');
    content.classList.add('active');
}

// Open the URL from a curl command shown in a <code> block
function openUrlFromCurlCode(codeElement) {
    if (!codeElement) {
        return;
    }

    const text = codeElement.textContent || '';

    // Expected formats:
    //   curl -X POST http://ip:port/api/endpoint
    //   curl http://ip:port/api/endpoint
    const match = text.match(/https?:\/\/[^\s"']+/i);
    if (!match) {
        return;
    }

    const url = match[0];

    try {
        window.open(url, '_blank');
    } catch (error) {
        console.error('Error opening URL from curl code:', error);
    }
}

// Set up event listeners
function setupEventListeners() {
    // Audio notification banner - click on content to stop audio
    const audioNotificationBanner = document.getElementById('audioNotificationBanner');
    if (audioNotificationBanner) {
        const audioContent = audioNotificationBanner.querySelector('.audio-notification-content');
        if (audioContent) {
            audioContent.addEventListener('click', async (e) => {
                // If clicking on close button, don't stop audio (handled separately)
                if (e.target.id === 'audioNotificationClose') {
                    return;
                }
                // Click on banner content = stop all audio
                await stopAllAudio();
            });
        }
    }

    // Audio notification banner close button - just hide, don't stop audio
    const audioNotificationClose = document.getElementById('audioNotificationClose');
    if (audioNotificationClose) {
        audioNotificationClose.addEventListener('click', (e) => {
            e.stopPropagation(); // Prevent content click event
            hideAudioNotification();
        });
    }

    // Date navigation
    document.getElementById('prevDay').addEventListener('click', () => {
        currentDate.setDate(currentDate.getDate() - 1);
        loadPrayers();
    });

    document.getElementById('todayBtn').addEventListener('click', () => {
        currentDate = getServerSyncedDate();
        loadPrayers();
    });

    document.getElementById('nextDay').addEventListener('click', () => {
        currentDate.setDate(currentDate.getDate() + 1);
        loadPrayers();
    });

    // Calendar modal
    const calendarModal = document.getElementById('calendarModal');
    const calendarBtn = document.getElementById('calendarBtn');
    const closeCalendar = document.getElementById('closeCalendar');
    let calendarYear = getServerSyncedDate().getFullYear();

    calendarBtn.onclick = () => {
        calendarYear = currentDate.getFullYear();
        generateYearCalendar(calendarYear);
        calendarModal.style.display = 'block';
    };

    closeCalendar.onclick = () => {
        calendarModal.style.display = 'none';
    };

    window.addEventListener('click', (event) => {
        if (event.target === calendarModal) {
            calendarModal.style.display = 'none';
        }
    });

    document.getElementById('prevYear').addEventListener('click', () => {
        calendarYear--;
        generateYearCalendar(calendarYear);
    });

    document.getElementById('nextYear').addEventListener('click', () => {
        calendarYear++;
        generateYearCalendar(calendarYear);
    });

    // Settings modal
    const modal = document.getElementById('settingsModal');
    const btn = document.getElementById('settingsBtn');
    const closeSettings = document.getElementById('closeSettings');

    btn.onclick = () => {
        modal.style.display = 'block';
    };

    closeSettings.onclick = () => {
        modal.style.display = 'none';
    };

    window.addEventListener('click', (event) => {
        if (event.target === modal) {
            modal.style.display = 'none';
        }
    });

    // Close modals with Escape key
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' || event.key === 'Esc') {
            if (calendarModal.style.display === 'block') {
                calendarModal.style.display = 'none';
            }
            if (modal.style.display === 'block') {
                modal.style.display = 'none';
            }
        }
    });

    // Weekday mute banner click to unmute
    const weekdayMuteBanner = document.getElementById('weekdayMuteBanner');
    if (weekdayMuteBanner) {
        weekdayMuteBanner.addEventListener('click', async () => {
            try {
                const today = getServerSyncedDate();
                const todayWeekday = today.getDay(); // 0=Sunday ... 6=Saturday
                const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

                // Toggle the weekday to unmute (set muted=0)
                await fetch(`${API_BASE}/api/muted-weekdays/${todayWeekday}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ muted: 0 })
                });

                // Refresh the banner and other UI elements
                await updateWeekdayMuteBanner();
                await loadWeekdaySettings();
                await checkSkipNextStatus();

            } catch (error) {
                console.error('Error unmuting weekday:', error);
                alert('Error unmuting the day. Please try again.');
            }
        });
    }

    // Stop audio button
    const stopAudioBtn = document.getElementById('stopAudioBtn');
    if (stopAudioBtn) {
        stopAudioBtn.addEventListener('click', async () => {
            await stopAllAudio();
        });
    }

    // Update location
    document.getElementById('updateLocationBtn').addEventListener('click', async () => {
        const icsUrl = document.getElementById('icsUrl').value;
        if (!icsUrl) {
            alert('Please enter a valid ICS URL');
            return;
        }

        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'ics_url', value: icsUrl })
            });
            alert('Location updated. Prayer times will refresh shortly.');
            setTimeout(() => {
                loadPrayers();
                loadUpdateInfo();
            }, 2000);
        } catch (error) {
            alert('Error while updating: ' + error.message);
        }
    });

    // Update audio file
    document.getElementById('audioFile').addEventListener('change', async (e) => {
        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'audio_file', value: e.target.value })
            });
        } catch (error) {
            console.error('Error updating audio file:', error);
        }
    });

    // Volume control
    const volumeSlider = document.getElementById('volumeSlider');
    const volumeValue = document.getElementById('volumeValue');
    const volumeWarning = document.getElementById('volumeWarning');

    function updateVolumeWarning(volume) {
        if (!volumeSlider || !volumeWarning) return;

        if (volume > 100) {
            volumeWarning.style.display = 'block';
            volumeSlider.style.background = 'linear-gradient(to right, #8B0000 0%, #a30000 100%)';
            volumeSlider.classList.add('volume-high');
        } else {
            volumeWarning.style.display = 'none';
            volumeSlider.style.background = 'linear-gradient(to right, #27ae60 0%, #1e8449 100%)';
            volumeSlider.classList.remove('volume-high');
        }
    }

    window.updateVolumeWarning = updateVolumeWarning;

    function setVolumeSliderEnabled(isEnabled) {
        if (!volumeSlider) return;
        const volumeLabel = volumeSlider.closest('.form-group')?.querySelector('label');
        volumeSlider.disabled = !isEnabled;
        volumeSlider.style.opacity = isEnabled ? '1' : '0.5';
        volumeSlider.style.cursor = isEnabled ? 'pointer' : 'not-allowed';
        if (volumeLabel) {
            volumeLabel.style.color = isEnabled ? '' : '#999';
        }
    }

    window.setVolumeSliderEnabled = setVolumeSliderEnabled;

    // Initialize slider background
    updateVolumeWarning(parseInt(volumeSlider.value));

    volumeSlider.addEventListener('input', (e) => {
        const volume = parseInt(e.target.value);
        volumeValue.textContent = volume;
        updateVolumeWarning(volume);
        // Note: Browser volume is always 100%, slider controls server volume only
    });

    volumeSlider.addEventListener('change', async (e) => {
        const volume = e.target.value;
        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'volume', value: volume })
            });

            // If Fajr volume is synced (checkbox unchecked), update it too
            const syncFajrVolumeCheckbox = document.getElementById('syncFajrVolume');
            if (syncFajrVolumeCheckbox && !syncFajrVolumeCheckbox.checked) {
                const fajrVolumeSlider = document.getElementById('fajrVolumeSlider');
                const fajrVolumeValue = document.getElementById('fajrVolumeValue');
                if (fajrVolumeSlider && fajrVolumeValue) {
                    fajrVolumeSlider.value = volume;
                    fajrVolumeValue.textContent = volume;
                    updateFajrVolumeWarning(parseInt(volume));
                }
            }
        } catch (error) {
            console.error('Error updating volume:', error);
        }
    });

    // Fajr volume control
    const fajrVolumeSlider = document.getElementById('fajrVolumeSlider');
    const fajrVolumeValue = document.getElementById('fajrVolumeValue');
    const fajrVolumeWarning = document.getElementById('fajrVolumeWarning');
    const syncFajrVolumeCheckbox = document.getElementById('syncFajrVolume');

    function updateFajrVolumeWarning(volume) {
        if (!fajrVolumeSlider || !fajrVolumeWarning) return;

        if (volume > 100) {
            fajrVolumeWarning.style.display = 'block';
            fajrVolumeSlider.style.background = 'linear-gradient(to right, #8B0000 0%, #a30000 100%)';
            fajrVolumeSlider.classList.add('volume-high');
        } else {
            fajrVolumeWarning.style.display = 'none';
            fajrVolumeSlider.style.background = 'linear-gradient(to right, #27ae60 0%, #1e8449 100%)';
            fajrVolumeSlider.classList.remove('volume-high');
        }
    }

    window.updateFajrVolumeWarning = updateFajrVolumeWarning;

    function setFajrVolumeSliderEnabled(isEnabled) {
        if (!fajrVolumeSlider) return;
        const fajrVolumeLabel = fajrVolumeSlider.previousElementSibling && fajrVolumeSlider.previousElementSibling.tagName === 'LABEL'
            ? fajrVolumeSlider.previousElementSibling
            : null;
        fajrVolumeSlider.disabled = !isEnabled;
        fajrVolumeSlider.style.opacity = isEnabled ? '1' : '0.5';
        fajrVolumeSlider.style.cursor = isEnabled ? 'pointer' : 'not-allowed';
        if (fajrVolumeLabel) {
            fajrVolumeLabel.style.color = isEnabled ? '' : '#999';
        }
    }

    window.setFajrVolumeSliderEnabled = setFajrVolumeSliderEnabled;

    function setSyncFajrVolumeCheckboxEnabled(isEnabled) {
        if (!syncFajrVolumeCheckbox) return;
        const checkboxLabel = syncFajrVolumeCheckbox.closest('.prayer-toggle')?.querySelector('span');
        syncFajrVolumeCheckbox.disabled = !isEnabled;
        const toggleSwitch = syncFajrVolumeCheckbox.closest('.toggle-switch');
        if (toggleSwitch) {
            toggleSwitch.style.opacity = isEnabled ? '1' : '0.5';
            toggleSwitch.style.cursor = isEnabled ? 'pointer' : 'not-allowed';
        }
        if (checkboxLabel) {
            checkboxLabel.style.color = isEnabled ? '' : '#999';
        }
    }

    window.setSyncFajrVolumeCheckboxEnabled = setSyncFajrVolumeCheckboxEnabled;

    // Initialize Fajr slider background
    if (fajrVolumeSlider) {
        updateFajrVolumeWarning(parseInt(fajrVolumeSlider.value));
    }

    if (fajrVolumeSlider) {
        fajrVolumeSlider.addEventListener('input', (e) => {
            const volume = parseInt(e.target.value);
            fajrVolumeValue.textContent = volume;
            updateFajrVolumeWarning(volume);
        });

        fajrVolumeSlider.addEventListener('change', async (e) => {
            const volume = e.target.value;
            try {
                await fetch(`${API_BASE}/api/settings`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: 'fajr_volume', value: volume })
                });
            } catch (error) {
                console.error('Error updating Fajr volume:', error);
            }
        });
    }

    // Sync Fajr volume checkbox (checked = independent volume, unchecked = synced with main)
    if (syncFajrVolumeCheckbox) {
        syncFajrVolumeCheckbox.addEventListener('change', async (e) => {
            const useIndependentVolume = e.target.checked;
            try {
                await fetch(`${API_BASE}/api/settings`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: 'sync_fajr_volume', value: useIndependentVolume ? '1' : '0' })
                });

                // Enable/disable Fajr volume slider based on independent status AND server audio availability
                const audioOutput = document.getElementById('audioOutput').value;
                const isServerEnabled = audioOutput !== 'browser';
                // Fajr slider is enabled only if server is enabled AND independent volume is active
                setFajrVolumeSliderEnabled(isServerEnabled && useIndependentVolume);

                // If switching to synced mode, update Fajr volume to match main volume
                if (!useIndependentVolume && volumeSlider && fajrVolumeSlider && fajrVolumeValue) {
                    const mainVolume = volumeSlider.value;
                    fajrVolumeSlider.value = mainVolume;
                    fajrVolumeValue.textContent = mainVolume;
                    updateFajrVolumeWarning(parseInt(mainVolume));

                    // Save the synced value to database
                    await fetch(`${API_BASE}/api/settings`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ key: 'fajr_volume', value: mainVolume })
                    });
                }
            } catch (error) {
                console.error('Error updating sync Fajr volume setting:', error);
            }
        });
    }

    // Audio card selection
    document.getElementById('audioCard').addEventListener('change', async (e) => {
        const audioCard = e.target.value;
        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'audio_card', value: audioCard })
            });

            if (audioCard === 'auto') {
            } else {
            }
        } catch (error) {
            console.error('[Audio Device] ❌ Error updating audio card:', error);
            alert('⚠️ Error updating audio card: ' + error.message);
        }
    });

    // Test athan playback (WEB ONLY - browser playback)
    document.getElementById('testAthanBtn').addEventListener('click', async () => {
        try {
            // Retrieve the selected audio file
            const audioFile = document.getElementById('audioFile').value;

            if (!audioFile) {
                alert('No audio file selected');
                return;
            }


            // Play ONLY in the browser (not on server)
            playAthanInBrowser(audioFile, 'Test');

            // Stop browser test playback after 30 seconds
            setTimeout(() => {
                if (audioElement && !audioElement.paused) {
                    audioElement.pause();
                    audioElement.currentTime = 0;
                    hideAudioNotification();
                }
            }, 30000);

        } catch (error) {
            alert('Error during test: ' + error.message);
        }
    });

    // Update Friday Quran file
    document.getElementById('fridayQuranFile').addEventListener('change', async (e) => {
        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'friday_quran_file', value: e.target.value })
            });
        } catch (error) {
            console.error('Error updating Friday Quran file:', error);
        }
    });

    // Update Friday Quran time (hour)
    document.getElementById('fridayQuranHour').addEventListener('change', async (e) => {
        try {
            const hour = e.target.value;
            const minute = document.getElementById('fridayQuranMinute').value;
            const time = `${hour}:${minute}`;
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'friday_quran_time', value: time })
            });
        } catch (error) {
            console.error('Error updating Friday Quran time:', error);
        }
    });

    // Update Friday Quran time (minute)
    document.getElementById('fridayQuranMinute').addEventListener('change', async (e) => {
        try {
            const hour = document.getElementById('fridayQuranHour').value;
            const minute = e.target.value;
            const time = `${hour}:${minute}`;
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'friday_quran_time', value: time })
            });
        } catch (error) {
            console.error('Error updating Friday Quran time:', error);
        }
    });

    // Test Quran playback (WEB ONLY - browser playback)
    document.getElementById('testQuranBtn').addEventListener('click', async () => {
        try {
            const quranFile = document.getElementById('fridayQuranFile').value;

            if (!quranFile) {
                alert('No Quran file selected');
                return;
            }


            // Play ONLY in the browser (not on server)
            playQuranInBrowser(quranFile, true);

            // Stop browser Quran test playback after 30 seconds
            setTimeout(() => {
                if (audioElement && !audioElement.paused) {
                    audioElement.pause();
                    audioElement.currentTime = 0;
                    hideAudioNotification();
                }
            }, 30000);

        } catch (error) {
            alert('Error during test: ' + error.message);
        }
    });

    // Play full Quran recitation (user-triggered)
    document.getElementById('playFullQuranBtn').addEventListener('click', async () => {
        await playFullQuran();
    });

    // Test Athan playback on server only (30 seconds)
    document.getElementById('testAthanServerBtn').addEventListener('click', async () => {
        try {
            const audioFile = document.getElementById('audioFile').value;

            if (!audioFile) {
                alert('No audio file selected');
                return;
            }

            const response = await fetch(`${API_BASE}/api/test-athan-server`);
            const data = await response.json();

            if (data.success) {
                // Show notification banner for server test
                showAudioNotification('Test Athan server playing (30s preview)');
                // Hide notification after 30 seconds
                setTimeout(() => {
                    hideAudioNotification();
                }, 30000);
            } else {
                alert('Error: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            alert('Error during server test: ' + error.message);
        }
    });

    // Test Quran playback on server only (30 seconds)
    document.getElementById('testQuranServerBtn').addEventListener('click', async () => {
        try {
            const quranFile = document.getElementById('fridayQuranFile').value;

            if (!quranFile) {
                alert('No Quran file selected');
                return;
            }

            const response = await fetch(`${API_BASE}/api/test-quran-server`);
            const data = await response.json();

            if (data.success) {
                // Show notification banner for server test
                showAudioNotification('Test Quran recitation server playing (30s preview)');
                // Hide notification after 30 seconds
                setTimeout(() => {
                    hideAudioNotification();
                }, 30000);
            } else {
                alert('Error: ' + (data.error || 'Unknown error'));
            }
        } catch (error) {
            alert('Error during server test: ' + error.message);
        }
    });

    // Force prayer times update
    document.getElementById('forceUpdateBtn').addEventListener('click', async () => {
        try {
            const response = await fetch(`${API_BASE}/api/update-prayers`, { method: 'POST' });
            const data = await response.json();

            if (data.success) {
                setTimeout(() => {
                    loadPrayers();
                    loadUpdateInfo();
                }, 2000);
            } else {
                alert('Error updating prayer times: ' + (data.message || 'Unknown error'));
            }
        } catch (error) {
            alert('Error while updating: ' + error.message);
        }
    });

    // Export configuration
    document.getElementById('exportConfigBtn').addEventListener('click', async () => {
        try {
            const response = await fetch(`${API_BASE}/api/settings/export`);
            const csvData = await response.text();

            // Create download link
            const blob = new Blob([csvData], { type: 'text/csv' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `athan-center-config-${getServerSyncedDate().toISOString().split('T')[0]}.csv`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);

            alert('Configuration exported successfully!');
        } catch (error) {
            alert('Error exporting configuration: ' + error.message);
        }
    });

    // Import configuration
    const importConfigFile = document.getElementById('importConfigFile');
    document.getElementById('importConfigBtn').addEventListener('click', () => {
        importConfigFile.click();
    });

    importConfigFile.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        if (confirm('This will replace your current configuration. Continue?')) {
            try {
                const csvData = await file.text();
                const response = await fetch(`${API_BASE}/api/settings/import`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ csvData })
                });
                const data = await response.json();

                if (data.success) {
                    alert(data.message + '\n\nThe page will now reload.');
                    // Full page reload to ensure all settings are properly applied
                    window.location.reload();
                } else {
                    alert('Error: ' + (data.error || 'Unknown error'));
                }
            } catch (error) {
                alert('Error importing configuration: ' + error.message);
            }
        }

        // Reset file input
        importConfigFile.value = '';
    });

    // Reset all prayer checks
    document.getElementById('resetPrayerChecksBtn').addEventListener('click', async () => {
        const confirmed = confirm(
            '⚠️ Are you sure you want to reset all prayer checks?\n\n' +
            'This will remove all check marks (✓) from all prayers in the database.\n\n' +
            'This action cannot be undone.'
        );

        if (confirmed) {
            try {
                const response = await fetch(`${API_BASE}/api/prayer-checks/reset`, {
                    method: 'POST'
                });
                const data = await response.json();

                if (data.success) {
                    alert('✅ All prayer checks have been reset!');
                    loadPrayers(); // Reload to remove check marks
                } else {
                    alert('❌ Error: ' + (data.error || 'Unknown error'));
                }
            } catch (error) {
                alert('❌ Error resetting prayer checks: ' + error.message);
            }
        }
    });

    // Restore default configuration
    document.getElementById('restoreDefaultsBtn').addEventListener('click', async () => {
        const confirmed = confirm(
            '⚠️ WARNING: This will reset ALL settings to their default values!\n\n' +
            'This includes:\n' +
            '• Location (Mecca)\n' +
            '• Audio files and volume\n' +
            '• All prayer settings\n' +
            '• Weekday mute settings\n' +
            '• Friday Quran settings\n\n' +
            'Are you sure you want to continue?'
        );

        if (confirmed) {
            try {
                const response = await fetch(`${API_BASE}/api/settings/restore-defaults`, {
                    method: 'POST'
                });
                const data = await response.json();

                if (data.success) {
                    alert('✅ Configuration restored to defaults!\n\nThe page will now reload.');
                    window.location.reload();
                } else {
                    alert('❌ Error: ' + (data.error || 'Unknown error'));
                }
            } catch (error) {
                alert('❌ Error restoring default configuration: ' + error.message);
            }
        }
    });

    // Allow users to cancel mute by clicking the banner
    const muteAlertBanner = document.getElementById('muteAlertBanner');
    if (muteAlertBanner) {
        muteAlertBanner.addEventListener('click', async () => {
            try {
                const muteType = muteAlertBanner.dataset.muteType;
                const prayerName = muteAlertBanner.dataset.prayerName;

                if (muteType === 'manual') {
                    // Reset skip_next for manual mute
                    await fetch(`${API_BASE}/api/skip-next/reset`, { method: 'POST' });
                    checkSkipNextStatus();
                    // After unmuting, check if weekday banner should appear
                    await updateWeekdayMuteBanner();
                } else if (muteType === 'general' && prayerName) {
                    // Open settings modal and scroll to Athan call section
                    const modal = document.getElementById('settingsModal');
                    const modalContent = modal.querySelector('.modal-content');
                    const athanSection = document.getElementById('athanCallSection');

                    modal.style.display = 'block';

                    // Wait for modal to be visible, then scroll to Athan call section within modal
                    setTimeout(() => {
                        if (athanSection && modalContent) {
                            openSettingsSection('athanCallSection');
                            const sectionTop = athanSection.offsetTop - modalContent.offsetTop;
                            modalContent.scrollTo({ top: sectionTop - 20, behavior: 'smooth' });
                        }
                    }, 100);
                    return;
                }
            } catch (error) {
                alert('Error: ' + error.message);
            }
        });
    }

    // Skip next athan
    document.getElementById('skipNextBtn').addEventListener('click', async () => {
        try {
            // Check if next prayer is already muted in the schedule matrix
            if (nextPrayer && nextPrayer.prayer_name) {
                const scheduleResponse = await fetch(`${API_BASE}/api/prayer-schedule`);
                const schedule = await scheduleResponse.json();
                const jsDay = getServerSyncedDate().getDay();
                const dayIndex = (jsDay + 6) % 7;
                const entry = schedule.find(s => s.prayer_name === nextPrayer.prayer_name && s.day_of_week === dayIndex);

                if (entry && entry.enabled === 0) {
                    alert(`${getPrayerName(nextPrayer.prayer_name)} is already muted in the schedule. Please use the settings to unmute it.`);
                    return;
                }
            }

            await fetch(`${API_BASE}/api/skip-next`, { method: 'POST' });
            checkSkipNextStatus();
            // After muting, hide weekday banner if it was shown (priority logic)
            await updateWeekdayMuteBanner();
        } catch (error) {
            alert('Error: ' + error.message);
        }
    });

    // Stop all audio when clicking on next prayer card during playback
    const nextPrayerCard = document.getElementById('nextPrayerCard');
    if (nextPrayerCard) {
        nextPrayerCard.addEventListener('click', async () => {
            // Check if audio is playing in browser
            const isAudioPlaying = (audioElement && !audioElement.paused);

            if (isAudioPlaying) {
                await stopAllAudio();
            }
        });
    }

    // Dark mode toggle
    document.getElementById('darkModeToggle').addEventListener('change', async (e) => {
        const isDarkMode = e.target.checked;
        try {
            await fetch(`${API_BASE}/api/settings`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ key: 'dark_mode', value: isDarkMode ? '1' : '0' })
            });
            applyDarkMode(isDarkMode);
        } catch (error) {
            console.error('Error updating dark mode:', error);
        }
    });

    // Make Audio control & API curl snippets clickable (open their URL)
    const testAthanServerCommand = document.getElementById('testAthanServerCommand');
    if (testAthanServerCommand) {
        testAthanServerCommand.style.cursor = 'pointer';
        testAthanServerCommand.title = 'Open this API URL in a new tab';
        testAthanServerCommand.addEventListener('click', () => {
            openUrlFromCurlCode(testAthanServerCommand);
        });
    }

    const testQuranServerCommand = document.getElementById('testQuranServerCommand');
    if (testQuranServerCommand) {
        testQuranServerCommand.style.cursor = 'pointer';
        testQuranServerCommand.title = 'Open this API URL in a new tab';
        testQuranServerCommand.addEventListener('click', () => {
            openUrlFromCurlCode(testQuranServerCommand);
        });
    }

    const muteCommand = document.getElementById('muteCommand');
    if (muteCommand) {
        muteCommand.style.cursor = 'pointer';
        muteCommand.title = 'Open this API URL in a new tab';
        muteCommand.addEventListener('click', () => {
            openUrlFromCurlCode(muteCommand);
        });
    }

    const unmuteCommand = document.getElementById('unmuteCommand');
    if (unmuteCommand) {
        unmuteCommand.style.cursor = 'pointer';
        unmuteCommand.title = 'Open this API URL in a new tab';
        unmuteCommand.addEventListener('click', () => {
            openUrlFromCurlCode(unmuteCommand);
        });
    }

    const stopAudioCommand = document.getElementById('stopAudioCommand');
    if (stopAudioCommand) {
        stopAudioCommand.style.cursor = 'pointer';
        stopAudioCommand.title = 'Open this API URL in a new tab';
        stopAudioCommand.addEventListener('click', () => {
            openUrlFromCurlCode(stopAudioCommand);
        });
    }

    const nextPrayerTextCommand = document.getElementById('nextPrayerTextCommand');
    if (nextPrayerTextCommand) {
        nextPrayerTextCommand.style.cursor = 'pointer';
        nextPrayerTextCommand.title = 'Open this API URL in a new tab';
        nextPrayerTextCommand.addEventListener('click', () => {
            openUrlFromCurlCode(nextPrayerTextCommand);
        });
    }
}

// Apply or remove dark mode
function applyDarkMode(isDarkMode) {
    if (isDarkMode) {
        document.body.classList.add('dark-mode');
    } else {
        document.body.classList.remove('dark-mode');
    }
}

// Update date displays in navigation buttons
function updateDateButtons() {
    const today = getServerSyncedDate();
    const todayStr = today.toLocaleDateString('en-GB', {
        day: '2-digit',
        month: '2-digit'
    });

    const currentDateStr = currentDate.toLocaleDateString('en-GB', {
        day: '2-digit',
        month: '2-digit'
    });

    const todayDateElement = document.getElementById('todayDate');
    const currentDateElement = document.getElementById('currentDate');
    const calendarBtn = document.getElementById('calendarBtn');
    const todayBtn = document.getElementById('todayBtn');

    if (todayDateElement) {
        todayDateElement.textContent = todayStr;
    }

    if (currentDateElement) {
        currentDateElement.textContent = currentDateStr;
    }

    // Update calendar button with weekday name
    if (calendarBtn) {
        const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const currentWeekday = weekdayNames[currentDate.getDay()];
        const todayFormatted = formatDateLocal(today);
        const currentFormatted = formatDateLocal(currentDate);
        
        if (todayFormatted === currentFormatted) {
            calendarBtn.innerHTML = `📅 Today (<br><span class="btn-date">${currentDateStr}</span>)`;
        } else {
            calendarBtn.innerHTML = `📅 ${currentWeekday} (<br><span class="btn-date">${currentDateStr}</span>)`;
        }
    }

    // Disable todayBtn when viewing today's prayers
    if (todayBtn) {
        const todayFormatted = formatDateLocal(today);
        const currentFormatted = formatDateLocal(currentDate);
        
        if (todayFormatted === currentFormatted) {
            // Viewing today - disable button
            todayBtn.disabled = true;
            todayBtn.style.opacity = '0.5';
            todayBtn.style.cursor = 'not-allowed';
        } else {
            // Viewing another day - enable button
            todayBtn.disabled = false;
            todayBtn.style.opacity = '1';
            todayBtn.style.cursor = 'pointer';
        }
    }
}

// Load prayers
async function loadPrayers() {
    // Prevent multiple simultaneous calls
    if (isLoadingPrayers) {
        return;
    }

    isLoadingPrayers = true;
    try {
        // Format date as YYYY-MM-DD using local date to avoid timezone issues
        const dateStr = formatDateLocal(currentDate);
        const response = await fetch(`${API_BASE}/api/prayers/${dateStr}`);
        const prayers = await response.json();

        displayPrayers(prayers);
        updateDateButtons();
        await updateWeekdayMuteBanner();

        // Determine if we should show next prayer card
        const today = getServerSyncedDate();
        const todayStr = formatDateLocal(today);
        const tomorrow = getServerSyncedDate();
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowStr = formatDateLocal(tomorrow);
        const currentTime = today.toTimeString().split(' ')[0].substring(0, 5);

        const isViewingToday = dateStr === todayStr;
        const isViewingTomorrow = dateStr === tomorrowStr;

        // Check if Isha prayer has passed today
        let ishaHasPassed = false;
        if (isViewingToday || isViewingTomorrow) {
            try {
                const todayPrayersResponse = await fetch(`${API_BASE}/api/prayers/${todayStr}`);
                const todayPrayers = await todayPrayersResponse.json();
                const ishaPrayer = todayPrayers.find(p => p.prayer_name === 'Isha');
                if (ishaPrayer && currentTime > ishaPrayer.prayer_time) {
                    ishaHasPassed = true;
                }
            } catch (error) {
                console.error('Error checking Isha time:', error);
            }
        }

        if (isViewingToday) {
            // Always load and show next prayer when viewing today
            await loadNextPrayerData();
            if (nextPrayer) {
                // Validate that nextPrayer is coherent with today's prayers
                const isValid = await validateNextPrayer(nextPrayer, prayers);
                if (isValid) {
                    displayNextPrayer(nextPrayer);
                    checkSkipNextStatus();
                } else {
                    hideNextPrayerCard();
                    // Retry after 5 seconds in case of temporary backend issue
                    setTimeout(() => {
                        loadPrayers();
                    }, 5000);
                }
            } else {
                hideNextPrayerCard();
            }
        } else if (isViewingTomorrow && ishaHasPassed) {
            // When viewing tomorrow AND Isha has passed, show next prayer card
            await loadNextPrayerData();
            if (nextPrayer) {
                displayNextPrayer(nextPrayer);
                checkSkipNextStatus();
            } else {
                hideNextPrayerCard();
            }
        } else {
            // All other cases - hide card
            hideNextPrayerCard();
        }
    } catch (error) {
        console.error('Error loading prayers:', error);
    } finally {
        // Always reset the flag to allow future calls
        isLoadingPrayers = false;
    }
}

// Render prayer list
async function displayPrayers(prayers) {
    const prayersList = document.getElementById('prayersList');
    const now = getServerSyncedDate();
    const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);
    const today = formatDateLocal(now);
    const selectedDate = formatDateLocal(currentDate);
    const isFutureDate = selectedDate > today;

    if (prayers.length === 0) {
        prayersList.innerHTML = '<p style="text-align: center; color: #6c757d; padding: 20px;">No prayers available for this date</p>';
        return;
    }

    // Load prayer checks for the selected date (only for today/past)
    let prayerChecks = {};
    if (!isFutureDate) {
        try {
            const checksResponse = await fetch(`${API_BASE}/api/prayer-checks/${selectedDate}`);
            const checks = await checksResponse.json();
            checks.forEach(check => {
                prayerChecks[check.prayer_name] = check.checked; // Store the actual value (0, 1, or 2)
            });
        } catch (error) {
            console.error('Error loading prayer checks:', error);
        }
    }

    prayersList.innerHTML = prayers.map(prayer => {
        const isPast = selectedDate < today || (selectedDate === today && prayer.prayer_time < currentTime);
        const prayerClass = isPast ? 'prayer-item past' : 'prayer-item';
        const checkState = prayerChecks[prayer.prayer_name] || 0;
        
        // Generate check mark based on state: 0=none, 1=green, 2=orange
        let checkMark = '';
        if (checkState === 1) {
            checkMark = '<span class="prayer-check-mark">✓</span>';
        } else if (checkState === 2) {
            checkMark = '<span class="prayer-redcheck-mark">✓</span>';
        }
        
        const canToggle = !isFutureDate;
        const itemStyle = canToggle ? 'cursor: pointer;' : 'cursor: not-allowed;';

        return `
            <div class="${prayerClass}" data-date="${selectedDate}" data-prayer="${prayer.prayer_name}" data-can-toggle="${canToggle}" style="${itemStyle}">
                <div class="prayer-name">${checkMark}${getPrayerName(prayer.prayer_name)}</div>
                <div class="prayer-time">${prayer.prayer_time}</div>
            </div>
        `;
    }).join('');

    // Add click event listeners to toggle prayer checks (only for today/past)
    if (!isFutureDate) {
        document.querySelectorAll('.prayer-item[data-can-toggle="true"]').forEach(item => {
            item.addEventListener('click', async function () {
                const date = this.getAttribute('data-date');
                const prayerName = this.getAttribute('data-prayer');

                try {
                    await fetch(`${API_BASE}/api/prayer-checks/toggle`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ date, prayer_name: prayerName })
                    });

                    // Reload prayers to update the check mark
                    loadPrayers();
                } catch (error) {
                    console.error('Error toggling prayer check:', error);
                }
            });
        });
    }
}

// Validate that nextPrayer is coherent with today's prayers list
async function validateNextPrayer(nextPrayerToValidate, todayPrayers) {
    try {
        const now = getServerSyncedDate();
        const currentTime = now.toTimeString().split(' ')[0].substring(0, 5);
        const today = formatDateLocal(now);

        // Only validate if nextPrayer is for today
        if (nextPrayerToValidate.date !== today) {
            return true;
        }

        // Filter main 5 prayers only
        const mainPrayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
        const mainPrayersToday = todayPrayers.filter(p => mainPrayers.includes(p.prayer_name));


        // Check if there's any main prayer between now and nextPrayer that was skipped
        for (const prayer of mainPrayersToday) {
            // Prayer must be:
            // 1. After current time (not yet passed)
            // 2. Before nextPrayer time (should have been returned instead)
            if (prayer.prayer_time > currentTime && prayer.prayer_time < nextPrayerToValidate.prayer_time) {
                console.error(`[validateNextPrayer] ❌ VALIDATION FAILED: ${prayer.prayer_name} at ${prayer.prayer_time} was skipped!`);
                return false;
            }
        }

        return true;
    } catch (error) {
        console.error('Error validating next prayer:', error);
        return false; // Fail safe: hide card if validation fails
    }
}

// Load next upcoming prayer data (without displaying)
async function loadNextPrayerData() {
    try {
        const response = await fetch(`${API_BASE}/api/prayers/next/upcoming`);
        const data = await response.json();
        nextPrayer = data;

        if (nextPrayer) {
        } else {
        }
    } catch (error) {
        console.error('Error loading next prayer:', error);
        nextPrayer = null;
    }
}

// Legacy function kept for compatibility
async function loadNextPrayer() {
    await loadNextPrayerData();
    if (nextPrayer) {
        displayNextPrayer(nextPrayer);
    } else {
        hideNextPrayerCard();
    }
    checkSkipNextStatus();
}

// Display the next prayer card
function displayNextPrayer(prayer) {
    // Validate that prayer has all required data before displaying
    if (!prayer || !prayer.prayer_name || !prayer.prayer_time || !prayer.date) {
        hideNextPrayerCard();
        return;
    }

    const card = document.getElementById('nextPrayerCard');

    // Update content BEFORE showing the card to avoid flashing empty data
    document.querySelector('.next-prayer-name').textContent = getPrayerName(prayer.prayer_name);
    document.querySelector('.next-prayer-time').textContent = prayer.prayer_time;

    // Only show the card after content is updated
    card.style.display = 'block';

}

// Hide the next prayer card
function hideNextPrayerCard() {
    const card = document.getElementById('nextPrayerCard');
    card.style.display = 'none';

    // Also hide mute button and banner when card is hidden
    const skipBtn = document.getElementById('skipNextBtn');
    const muteAlert = document.getElementById('muteAlertBanner');
    if (skipBtn) skipBtn.style.display = 'none';
    if (muteAlert) muteAlert.style.display = 'none';
}

// Start the countdown timer
function startCountdown() {
    if (countdownInterval) {
        clearInterval(countdownInterval);
    }

    countdownInterval = setInterval(() => {
        // Don't update if nextPrayer is not loaded or card is not visible
        if (!nextPrayer) {
            return;
        }

        const card = document.getElementById('nextPrayerCard');
        if (!card || card.style.display === 'none') {
            // Card is hidden, don't try to update it
            return;
        }

        const now = getServerSyncedDate();
        const prayerDateTime = new Date(`${nextPrayer.date}T${nextPrayer.prayer_time}:00`);
        const diff = prayerDateTime - now; // Positive = future, Negative = past
        const diffSeconds = Math.floor(Math.abs(diff) / 1000);

        // If prayer is more than 60 seconds in the past and we're NOT in the 15-minute window,
        // reload immediately to get the correct next prayer
        if (diff < -60 * 1000 && !prayerTimeReachedAt && !isReloadingPrayer) {
            isReloadingPrayer = true;
            loadNextPrayer().then(() => {
                isReloadingPrayer = false;
            });
            return;
        }

        // Check if we're currently in the 15-minute "Time to pray" window
        if (prayerTimeReachedAt && currentPrayerInProgress) {
            const timeSincePrayerTime = now - prayerTimeReachedAt;
            const fifteenMinutes = 15 * 60 * 1000;

            if (timeSincePrayerTime < fifteenMinutes) {
                // Still within 15-minute window - keep showing the current prayer with "Time to pray"
                document.querySelector('.next-prayer-label').textContent = 'Time to pray';
                document.querySelector('.next-prayer-name').textContent = getPrayerName(currentPrayerInProgress.prayer_name);
                document.querySelector('.next-prayer-time').textContent = currentPrayerInProgress.prayer_time;

                const remainingMs = fifteenMinutes - timeSincePrayerTime;
                const remainingMinutes = Math.floor(remainingMs / (1000 * 60));
                const remainingSeconds = Math.floor((remainingMs % (1000 * 60)) / 1000);
                document.querySelector('.next-prayer-countdown').textContent =
                    `${remainingMinutes}m ${remainingSeconds}s remaining`;
                return;
            } else {
                // 15 minutes have passed, reset and load the actual next prayer
                if (!isReloadingPrayer) {

                    // Stop animation on nextPrayerCard
                    const nextPrayerCard = document.getElementById('nextPrayerCard');
                    if (nextPrayerCard) {
                        nextPrayerCard.classList.remove('playing-athan');
                    }

                    prayerTimeReachedAt = null;
                    currentPrayerInProgress = null;
                    isReloadingPrayer = true;
                    loadNextPrayer().then(() => {
                        isReloadingPrayer = false;
                    });
                }
                return;
            }
        }

        // Logic according to diff:
        // - If diff > 0: Show "Next Prayer" with countdown (even if 1 second before)
        // - If diff <= 0 and >= -60s: Show "Time to pray" and play audio (ONLY when time has arrived or passed)
        // - If diff < -60s: Reload to get actual next prayer

        if (diff > 0) {
            // Prayer time hasn't arrived yet - show normal countdown
            document.querySelector('.next-prayer-label').textContent = 'Next Prayer';
            const hours = Math.floor(diff / (1000 * 60 * 60));
            const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
            const seconds = Math.floor((diff % (1000 * 60)) / 1000);

            document.querySelector('.next-prayer-countdown').textContent =
                `In ${hours}h ${minutes}m ${seconds}s`;
        }
        else if (diff <= 0 && diff >= -60 * 1000) {
            // Prayer time has arrived or passed (within first 60 seconds) - "Time to pray" window
            if (!prayerTimeReachedAt) {
                // First time entering this window - mark the moment and trigger audio
                prayerTimeReachedAt = now;
                currentPrayerInProgress = { ...nextPrayer };

                // Start animation on nextPrayerCard (independent of audio settings)
                const nextPrayerCard = document.getElementById('nextPrayerCard');
                if (nextPrayerCard) {
                    nextPrayerCard.classList.add('playing-athan');
                }

                // Trigger audio check (will respect lastPlayedPrayer to avoid replaying)
                checkAthanTime();
            }

            document.querySelector('.next-prayer-label').textContent = 'Time to pray';
            document.querySelector('.next-prayer-name').textContent = getPrayerName(nextPrayer.prayer_name);
            document.querySelector('.next-prayer-time').textContent = nextPrayer.prayer_time;
            document.querySelector('.next-prayer-countdown').textContent = '15m 0s remaining';
        }
        else {
            // More than 60 seconds past prayer time - reload to get actual next prayer
            if (!isReloadingPrayer) {

                // Stop animation on nextPrayerCard
                const nextPrayerCard = document.getElementById('nextPrayerCard');
                if (nextPrayerCard) {
                    nextPrayerCard.classList.remove('playing-athan');
                }

                prayerTimeReachedAt = null;
                currentPrayerInProgress = null;
                isReloadingPrayer = true;
                loadNextPrayer().then(() => {
                    isReloadingPrayer = false;
                });
            }
        }
    }, 1000);
}

// Check if ICS configuration exists
function checkIcsConfiguration() {
    const icsUrl = document.getElementById('icsUrl').value;
    const icsInput = document.getElementById('icsUrl');
    const icsLabel = document.getElementById('icsLabel');

    // Check if the URL is empty or still the default Les Lilas link
    const isDefaultUrl = icsUrl.includes('Les_Lilas_Les_Lilas_France');
    const isEmpty = !icsUrl || icsUrl.trim() === '';

    if (isEmpty || isDefaultUrl) {
        // Open the settings modal
        const modal = document.getElementById('settingsModal');
        modal.style.display = 'block';

        // Highlight the field
        icsInput.classList.add('ics-missing');
        icsLabel.classList.add('ics-missing-label');

        // Scroll to the ICS field
        setTimeout(() => {
            icsInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
            icsInput.focus();
        }, 300);

        // Remove highlight once the user starts typing
        icsInput.addEventListener('input', function removeAnimation() {
            icsInput.classList.remove('ics-missing');
            icsLabel.classList.remove('ics-missing-label');
            icsInput.removeEventListener('input', removeAnimation);
        }, { once: true });
    }
}

// Load available audio devices
async function loadAudioDevices() {
    try {
        const response = await fetch(`${API_BASE}/api/audio/devices`);
        const data = await response.json();

        const audioCardSelect = document.getElementById('audioCard');
        const audioDeviceHelp = document.getElementById('audioDeviceHelp');

        // Clear existing options except "auto"
        audioCardSelect.innerHTML = '<option value="auto">Auto-detect (USB/HDMI)</option>';

        // Add detected devices
        if (data.devices && data.devices.length > 0) {
            data.devices.forEach(device => {
                const option = document.createElement('option');
                option.value = device.card;
                option.textContent = `${device.displayName} (card ${device.card})`;
                audioCardSelect.appendChild(option);
            });

            // Restore default help text when devices are present
            if (audioDeviceHelp) {
                audioDeviceHelp.innerHTML = `Select which audio output to use on the server.<br>Auto-detect prioritizes USB devices, then HDMI.`;
            }
        } else {
            // No devices detected: likely Windows/macOS Docker Desktop or server without /dev/snd
            if (audioDeviceHelp) {
                audioDeviceHelp.innerHTML = `No server audio devices detected.<br>` +
                    `On Windows/macOS with Docker Desktop, please use <strong>Web app only</strong> as audio output.`;
            }

            // Disable volume sliders when no server audio is available
            if (window.setVolumeSliderEnabled) {
                window.setVolumeSliderEnabled(false);
            }
            if (window.setSyncFajrVolumeCheckboxEnabled) {
                window.setSyncFajrVolumeCheckboxEnabled(false);
            }
            if (window.setFajrVolumeSliderEnabled) {
                window.setFajrVolumeSliderEnabled(false);
            }
        }
    } catch (error) {
        console.error('Error loading audio devices:', error);
        const audioDeviceHelp = document.getElementById('audioDeviceHelp');
        if (audioDeviceHelp) {
            audioDeviceHelp.innerHTML = `Unable to detect server audio devices.<br>` +
                `On Windows/macOS with Docker Desktop, please use <strong>Web app only</strong> as audio output.`;
        }

        // Disable volume sliders on error (likely no server audio)
        if (window.setVolumeSliderEnabled) {
            window.setVolumeSliderEnabled(false);
        }
        if (window.setSyncFajrVolumeCheckboxEnabled) {
            window.setSyncFajrVolumeCheckboxEnabled(false);
        }
        if (window.setFajrVolumeSliderEnabled) {
            window.setFajrVolumeSliderEnabled(false);
        }
    }
}

// Load general settings
async function loadSettings() {
    try {
        const response = await fetch(`${API_BASE}/api/settings`);
        const settings = await response.json();

        if (settings.ics_url) {
            document.getElementById('icsUrl').value = settings.ics_url;
        }

        // Update audio toggles
        if (settings.play_on_startup) {
            document.getElementById('playOnStartup').checked = settings.play_on_startup === '1';
        }

        if (settings.play_on_page_load) {
            document.getElementById('playOnPageLoad').checked = settings.play_on_page_load === '1';
        }

        // Update audio output
        if (settings.audio_output) {
            document.getElementById('audioOutput').value = settings.audio_output;
            if (window.setVolumeSliderEnabled) {
                window.setVolumeSliderEnabled(settings.audio_output !== 'browser');
            }
        }

        // Update audio card selection
        if (settings.audio_card) {
            document.getElementById('audioCard').value = settings.audio_card;
        }

        // Update volume slider
        if (settings.volume) {
            const volumePercent = parseInt(settings.volume);
            document.getElementById('volumeSlider').value = volumePercent;
            document.getElementById('volumeValue').textContent = volumePercent;
            if (typeof updateVolumeWarning === 'function') {
                updateVolumeWarning(volumePercent);
            }
            // Note: Browser volume is always 100% (1.0), slider controls server volume only
        }

        // Update Fajr volume slider
        if (settings.fajr_volume) {
            const fajrVolumePercent = parseInt(settings.fajr_volume);
            const fajrVolumeSlider = document.getElementById('fajrVolumeSlider');
            const fajrVolumeValue = document.getElementById('fajrVolumeValue');
            if (fajrVolumeSlider && fajrVolumeValue) {
                fajrVolumeSlider.value = fajrVolumePercent;
                fajrVolumeValue.textContent = fajrVolumePercent;
                if (typeof updateFajrVolumeWarning === 'function') {
                    updateFajrVolumeWarning(fajrVolumePercent);
                }
            }
        }

        // Update sync Fajr volume checkbox (checked = independent volume, unchecked = synced)
        if (settings.sync_fajr_volume !== undefined) {
            const syncFajrVolumeCheckbox = document.getElementById('syncFajrVolume');
            if (syncFajrVolumeCheckbox) {
                const useIndependentVolume = settings.sync_fajr_volume === '1';
                syncFajrVolumeCheckbox.checked = useIndependentVolume;

                const audioOutput = settings.audio_output || 'both';
                const isServerEnabled = audioOutput !== 'browser';

                // Enable/disable Fajr volume checkbox based on server audio availability
                if (typeof setSyncFajrVolumeCheckboxEnabled === 'function') {
                    setSyncFajrVolumeCheckboxEnabled(isServerEnabled);
                }

                // Enable/disable Fajr volume slider based on independent status AND server audio availability
                if (typeof setFajrVolumeSliderEnabled === 'function') {
                    // Fajr slider is enabled only if server is enabled AND independent volume is active
                    setFajrVolumeSliderEnabled(isServerEnabled && useIndependentVolume);
                }
            }
        }

        // Update Friday Quran settings
        if (settings.friday_quran_enabled !== undefined) {
            document.getElementById('fridayQuranEnabled').checked = settings.friday_quran_enabled === '1';
        }
        if (settings.friday_quran_time) {
            const [hour, minute] = settings.friday_quran_time.split(':');
            document.getElementById('fridayQuranHour').value = hour;
            document.getElementById('fridayQuranMinute').value = minute;
        }

        // Update dark mode
        if (settings.dark_mode !== undefined) {
            const isDarkMode = settings.dark_mode === '1';
            document.getElementById('darkModeToggle').checked = isDarkMode;
            applyDarkMode(isDarkMode);
        }
    } catch (error) {
        console.error('Error loading settings:', error);
    }
}

// Update audio output setting
async function updateAudioOutput(value) {
    try {
        await fetch(`${API_BASE}/api/settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key: 'audio_output', value: value })
        });

        const isServerEnabled = value !== 'browser';

        // Enable/disable main volume slider
        if (window.setVolumeSliderEnabled) {
            window.setVolumeSliderEnabled(isServerEnabled);
        }

        // Enable/disable Fajr volume checkbox
        if (window.setSyncFajrVolumeCheckboxEnabled) {
            window.setSyncFajrVolumeCheckboxEnabled(isServerEnabled);
        }

        // Enable/disable Fajr volume slider (only if server enabled AND independent volume active)
        const syncFajrVolumeCheckbox = document.getElementById('syncFajrVolume');
        if (window.setFajrVolumeSliderEnabled && syncFajrVolumeCheckbox) {
            const useIndependentVolume = syncFajrVolumeCheckbox.checked;
            // Fajr slider is enabled only if server is enabled AND independent volume is active
            window.setFajrVolumeSliderEnabled(isServerEnabled && useIndependentVolume);
        }
    } catch (error) {
        console.error('Error updating audio output:', error);
    }
}

// Load per-prayer settings
async function loadPrayerSettings() {
    try {
        const response = await fetch(`${API_BASE}/api/prayer-settings`);
        const settings = await response.json();

        const togglesContainer = document.getElementById('prayerToggles');
        togglesContainer.innerHTML = settings.map(setting => `
            <div class="prayer-toggle">
                <span>${getPrayerName(setting.prayer_name)}</span>
                <label class="toggle-switch">
                    <input type="checkbox" 
                           ${setting.enabled ? 'checked' : ''} 
                           onchange="togglePrayer('${setting.prayer_name}', this.checked)">
                    <span class="slider"></span>
                </label>
            </div>
        `).join('');
    } catch (error) {
        console.error('Error loading prayer settings:', error);
    }
}

// Toggle prayer activation
async function togglePrayer(prayerName, enabled) {
    try {
        await fetch(`${API_BASE}/api/prayer-settings/${prayerName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enabled })
        });
        // Update mute banner immediately if the next prayer was affected
        checkSkipNextStatus();
        // Update weekday banner visibility based on priority logic
        await updateWeekdayMuteBanner();
    } catch (error) {
        console.error('Error toggling prayer:', error);
    }
}

// Load muted weekdays settings
async function loadWeekdaySettings() {
    try {
        const response = await fetch(`${API_BASE}/api/muted-weekdays`);
        const weekdays = await response.json();

        const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const weekdayNamesFr = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

        const togglesContainer = document.getElementById('weekdayToggles');
        // Order display starting from Monday: 1,2,3,4,5,6,0
        const displayOrder = [1, 2, 3, 4, 5, 6, 0];
        const sortedWeekdays = displayOrder
            .map(idx => weekdays.find(day => day.weekday === idx))
            .filter(Boolean);

        togglesContainer.innerHTML = sortedWeekdays.map(day => `
            <div class="prayer-toggle">
                <span>${weekdayNames[day.weekday]}</span>
                <label class="toggle-switch">
                    <input type="checkbox" 
                           ${day.muted ? '' : 'checked'} 
                           onchange="toggleWeekday(${day.weekday}, this.checked)">
                    <span class="slider"></span>
                </label>
            </div>
        `).join('');

        // Update weekday mute banner based on current settings
        await updateWeekdayMuteBanner();
    } catch (error) {
        console.error('Error loading weekday settings:', error);
    }
}

// Current selected day tab for schedule matrix (-1 = Whole week, default)
let currentScheduleDay = -1;

// Load unified schedule matrix (5 prayers × 7 days) - Tab-based UI
async function loadScheduleMatrix() {
    try {
        console.log('[FRONTEND] Loading prayer schedule matrix from API...');
        const response = await fetch(`${API_BASE}/api/prayer-schedule`);
        const schedule = await response.json();
        console.log(`[FRONTEND] Received ${schedule.length} prayer_schedule entries from API`);

        const prayers = ['Fajr | Sobh', 'Dohr', 'Asr', 'Maghrib', 'Isha'];
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const daysFull = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

        // Build matrix lookup: matrix[prayer][day] = enabled
        const matrix = {};
        schedule.forEach(entry => {
            if (!matrix[entry.prayer_name]) matrix[entry.prayer_name] = {};
            matrix[entry.prayer_name][entry.day_of_week] = entry.enabled;
            console.log(`[FRONTEND] Matrix: ${entry.prayer_name}-${entry.day_of_week} = ${entry.enabled}`);
        });

        // Store matrix globally for toggle functions
        window.scheduleMatrix = matrix;
        console.log('[FRONTEND] Schedule matrix loaded and stored globally');

        // Generate tabs for days
        let html = '<div class="schedule-tabs">';
        html += `<button class="schedule-tab all-tab${currentScheduleDay === -1 ? ' active' : ''}" onclick="selectScheduleDay(-1)">Whole week</button>`;
        for (let d = 0; d < 7; d++) {
            html += `<button class="schedule-tab${d === currentScheduleDay ? ' active' : ''}" onclick="selectScheduleDay(${d})">${days[d]}</button>`;
        }
        html += '</div>';

        // Content for selected day
        html += '<div class="schedule-day-content">';

        if (currentScheduleDay === -1) {
            // "Whole week" tab - header
            html += `<div class="schedule-day-header">By weekdays</div>`;

            // "All prayers" toggle row (affects all prayers for all days)
            const allPrayersEnabled = prayers.every(p => [0, 1, 2, 3, 4, 5, 6].every(d => matrix[p] && matrix[p][d] !== 0));
            html += `<div class="schedule-whole-day-row">
                <span class="schedule-prayer-name">All athans</span>
                <label class="toggle-switch">
                    <input type="checkbox" ${allPrayersEnabled ? 'checked' : ''} onchange="toggleScheduleAll()">
                    <span class="slider"></span>
                </label>
            </div>`;

            // Show toggles for each prayer (affects all days)
            for (const prayer of prayers) {
                const allEnabled = [0, 1, 2, 3, 4, 5, 6].every(d => matrix[prayer] && matrix[prayer][d] !== 0);
                html += `<div class="schedule-prayer-row">
                    <span class="schedule-prayer-name">${prayer}</span>
                    <label class="toggle-switch">
                        <input type="checkbox" ${allEnabled ? 'checked' : ''} onchange="toggleSchedulePrayer('${prayer}')">
                        <span class="slider"></span>
                    </label>
                </div>`;
            }
        } else {
            // Specific day - header with day name
            html += `<div class="schedule-day-header">${daysFull[currentScheduleDay]}</div>`;

            // "Whole day" toggle row
            const dayAllEnabled = prayers.every(p => matrix[p] && matrix[p][currentScheduleDay] !== 0);
            html += `<div class="schedule-whole-day-row">
                <span class="schedule-prayer-name">Whole day</span>
                <label class="toggle-switch">
                    <input type="checkbox" ${dayAllEnabled ? 'checked' : ''} onchange="toggleScheduleDay(${currentScheduleDay})">
                    <span class="slider"></span>
                </label>
            </div>`;

            // Show toggles for each prayer
            for (const prayer of prayers) {
                const enabled = matrix[prayer] && matrix[prayer][currentScheduleDay] !== undefined ? matrix[prayer][currentScheduleDay] : 1;
                html += `<div class="schedule-prayer-row">
                    <span class="schedule-prayer-name">${prayer}</span>
                    <label class="toggle-switch">
                        <input type="checkbox" ${enabled ? 'checked' : ''} onchange="toggleScheduleCell('${prayer}', ${currentScheduleDay})">
                        <span class="slider"></span>
                    </label>
                </div>`;
            }
        }
        html += '</div>';

        document.getElementById('scheduleMatrix').innerHTML = html;
    } catch (error) {
        console.error('Error loading schedule matrix:', error);
    }
}

// Select a day tab
function selectScheduleDay(day) {
    currentScheduleDay = day;
    loadScheduleMatrix();
}

// Toggle a single cell in the schedule
async function toggleScheduleCell(prayer, day) {
    try {
        const response = await fetch(`${API_BASE}/api/prayer-schedule`);
        const schedule = await response.json();
        const entry = schedule.find(s => s.prayer_name === prayer && s.day_of_week === day);
        const currentEnabled = entry ? entry.enabled : 1;

        await fetch(`${API_BASE}/api/prayer-schedule`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ prayer_name: prayer, day_of_week: day, enabled: currentEnabled ? 0 : 1 })
        });
        await loadScheduleMatrix();
        checkSkipNextStatus();
    } catch (error) {
        console.error('Error toggling schedule cell:', error);
    }
}

// Toggle all days for a specific prayer (whole week)
async function toggleSchedulePrayer(prayer) {
    try {
        const response = await fetch(`${API_BASE}/api/prayer-schedule`);
        const schedule = await response.json();
        const prayerSchedule = schedule.filter(s => s.prayer_name === prayer);
        const hasDisabled = prayerSchedule.some(s => s.enabled === 0);

        await fetch(`${API_BASE}/api/prayer-schedule/bulk`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ type: 'prayer', target: prayer, enabled: hasDisabled ? 1 : 0 })
        });
        await loadScheduleMatrix();
        checkSkipNextStatus();
    } catch (error) {
        console.error('Error toggling schedule prayer:', error);
    }
}

// Toggle all prayers for a specific day (whole day)
async function toggleScheduleDay(day) {
    try {
        const response = await fetch(`${API_BASE}/api/prayer-schedule`);
        const schedule = await response.json();
        const daySchedule = schedule.filter(s => s.day_of_week === day);
        const hasDisabled = daySchedule.some(s => s.enabled === 0);

        await fetch(`${API_BASE}/api/prayer-schedule/bulk`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ type: 'day', target: day, enabled: hasDisabled ? 1 : 0 })
        });
        await loadScheduleMatrix();
        checkSkipNextStatus();
    } catch (error) {
        console.error('Error toggling schedule day:', error);
    }
}

// Toggle entire matrix (all prayers, all days)
async function toggleScheduleAll() {
    try {
        const response = await fetch(`${API_BASE}/api/prayer-schedule`);
        const schedule = await response.json();
        const hasDisabled = schedule.some(s => s.enabled === 0);
        const newValue = hasDisabled ? 1 : 0;

        // Update all days
        for (let day = 0; day < 7; day++) {
            await fetch(`${API_BASE}/api/prayer-schedule/bulk`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: 'day', target: day, enabled: newValue })
            });
        }
        await loadScheduleMatrix();
        checkSkipNextStatus();
    } catch (error) {
        console.error('Error toggling all schedule:', error);
    }
}

// Alias functions for header clicks
const toggleScheduleAllDays = toggleScheduleAll;
const toggleScheduleAllPrayers = toggleScheduleAll;

// Show or hide the weekday mute banner depending on whether the selected day is muted
async function updateWeekdayMuteBanner() {
    try {
        const banner = document.getElementById('weekdayMuteBanner');
        if (!banner) {
            return;
        }

        const response = await fetch(`${API_BASE}/api/muted-weekdays`);
        const weekdays = await response.json();

        const today = getServerSyncedDate();
        const todayStr = formatDateLocal(today);
        const currentDateStr = formatDateLocal(currentDate);

        // Only show the banner when viewing today
        if (currentDateStr !== todayStr) {
            banner.style.display = 'none';
            return;
        }

        // PRIORITY LOGIC: Check if other mute types are active
        // If skip_next or general settings mute is active, don't show weekday banner
        let hasOtherMuteActive = false;

        // Check skip_next status
        const skipResponse = await fetch(`${API_BASE}/api/skip-next`);
        const skipData = await skipResponse.json();
        if (skipData.skip) {
            hasOtherMuteActive = true;
        }

        // Check if next prayer is disabled in general settings
        if (!hasOtherMuteActive && nextPrayer && nextPrayer.prayer_name) {
            const settingsResponse = await fetch(`${API_BASE}/api/prayer-settings/${nextPrayer.prayer_name}`);
            const settingsData = await settingsResponse.json();
            if (settingsData && settingsData.enabled === 0) {
                hasOtherMuteActive = true;
            }
        }

        // If another mute type has priority, hide the weekday banner
        if (hasOtherMuteActive) {
            banner.style.display = 'none';
            return;
        }

        // Otherwise, show weekday banner if today is muted
        const todayWeekday = today.getDay(); // 0=Sunday ... 6=Saturday
        const todaySettings = weekdays.find(day => day.weekday === todayWeekday);

        if (todaySettings && todaySettings.muted === 1) {
            banner.style.display = 'block';
        } else {
            banner.style.display = 'none';
        }
    } catch (error) {
        console.error('Error updating weekday mute banner:', error);
    }
}

// Toggle weekday mute status
async function toggleWeekday(weekday, enabled) {
    try {
        // Invert logic: enabled (checked) = muted: 0, disabled (unchecked) = muted: 1
        const muted = enabled ? 0 : 1;
        await fetch(`${API_BASE}/api/muted-weekdays/${weekday}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ muted })
        });

        // Refresh weekday mute banner after a change
        await updateWeekdayMuteBanner();
    } catch (error) {
        console.error('Error toggling weekday:', error);
    }
}

// Toggle a general setting
async function toggleSetting(key, enabled) {
    try {
        await fetch(`${API_BASE}/api/settings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key, value: enabled ? '1' : '0' })
        });
    } catch (error) {
        console.error(`Error toggling setting ${key}:`, error);
    }
}

// Load update information
async function loadUpdateInfo() {
    try {
        const response = await fetch(`${API_BASE}/api/update-info`);
        const info = await response.json();

        // Display city name
        document.getElementById('updateCity').textContent = info.city_name || 'Not configured';

        // Display last update timestamp
        if (info.last_update) {
            const lastUpdateDate = new Date(info.last_update);
            const formattedDate = lastUpdateDate.toLocaleDateString('en-GB', {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            });
            const formattedTime = lastUpdateDate.toLocaleTimeString('en-GB', {
                hour: '2-digit',
                minute: '2-digit'
            });
            document.getElementById('lastUpdate').textContent = `${formattedDate} at ${formattedTime}`;

            // Display number of prayers retrieved
            if (info.prayers_count > 0) {
                document.getElementById('prayersCount').textContent = ` (${info.prayers_count} prayers retrieved)`;
            }
        } else {
            document.getElementById('lastUpdate').textContent = 'Never';
            document.getElementById('prayersCount').textContent = '';
        }

        // Display next scheduled update
        if (info.next_update) {
            const nextUpdateDate = new Date(info.next_update);
            const formattedDate = nextUpdateDate.toLocaleDateString('en-GB', {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            });
            const formattedTime = nextUpdateDate.toLocaleTimeString('en-GB', {
                hour: '2-digit',
                minute: '2-digit'
            });
            document.getElementById('nextUpdate').textContent = `${formattedDate} at ${formattedTime}`;
        } else {
            document.getElementById('nextUpdate').textContent = 'Not scheduled';
        }
    } catch (error) {
        console.error('Error loading update info:', error);
        document.getElementById('updateCity').textContent = 'Load error';
        document.getElementById('lastUpdate').textContent = 'Load error';
        document.getElementById('nextUpdate').textContent = 'Load error';
    }
}

// Load server audio support status and disable/enable UI elements accordingly
async function loadAudioSupport() {
    try {
        const response = await fetch(`${API_BASE}/api/audio-support`);
        const data = await response.json();


        // Update display
        const supportElement = document.getElementById('serverAudioSupport');
        supportElement.textContent = data.message;
        supportElement.style.color = data.color;

        // If audio is NOT supported, disable server audio elements
        if (!data.supported) {

            // Force audio output to "Web app only" and disable the dropdown
            const audioOutputSelect = document.getElementById('audioOutput');
            if (audioOutputSelect) {
                // Force to browser-only mode
                audioOutputSelect.value = 'browser';
                audioOutputSelect.disabled = true;
                audioOutputSelect.style.opacity = '0.5';
                audioOutputSelect.style.cursor = 'not-allowed';

                // Update setting on server
                await fetch(`${API_BASE}/api/settings`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: 'audio_output', value: 'browser' })
                });

                // Add warning message if not already present
                let warningMsg = audioOutputSelect.parentElement.querySelector('.audio-output-warning');
                if (!warningMsg) {
                    warningMsg = document.createElement('p');
                    warningMsg.className = 'help-text audio-output-warning';
                    warningMsg.style.cssText = 'margin-top: 5px; font-size: 0.85em; color: #8B0000; font-weight: 600;';
                    warningMsg.innerHTML = '⚠️ Server audio not available. Forced to "Web app only" mode.';
                    audioOutputSelect.parentElement.appendChild(warningMsg);
                }
            }

            // Disable Server audio device dropdown
            const audioCardSelect = document.getElementById('audioCard');
            if (audioCardSelect) {
                audioCardSelect.disabled = true;
                audioCardSelect.style.opacity = '0.5';
                audioCardSelect.style.cursor = 'not-allowed';
            }

            if (window.setVolumeSliderEnabled) {
                window.setVolumeSliderEnabled(false);
            }

            // Disable Fajr volume checkbox
            if (window.setSyncFajrVolumeCheckboxEnabled) {
                window.setSyncFajrVolumeCheckboxEnabled(false);
            }

            // Disable Fajr volume slider
            if (window.setFajrVolumeSliderEnabled) {
                window.setFajrVolumeSliderEnabled(false);
            }

            // Disable Server startup sound toggle
            const playOnStartupToggle = document.getElementById('playOnStartup');
            if (playOnStartupToggle) {
                playOnStartupToggle.disabled = true;
                playOnStartupToggle.parentElement.style.opacity = '0.5';
                playOnStartupToggle.parentElement.style.cursor = 'not-allowed';
                // Also gray out the label text
                const labelSpan = playOnStartupToggle.closest('.prayer-toggle')?.querySelector('span');
                if (labelSpan) {
                    labelSpan.style.color = '#999';
                }
            }

            // Disable Test server Athan button
            const testAthanServerBtn = document.getElementById('testAthanServerBtn');
            if (testAthanServerBtn) {
                testAthanServerBtn.disabled = true;
                testAthanServerBtn.style.opacity = '0.5';
                testAthanServerBtn.style.cursor = 'not-allowed';
                testAthanServerBtn.style.background = '#999';
            }

            // Disable Test server Quran button
            const testQuranServerBtn = document.getElementById('testQuranServerBtn');
            if (testQuranServerBtn) {
                testQuranServerBtn.disabled = true;
                testQuranServerBtn.style.opacity = '0.5';
                testQuranServerBtn.style.cursor = 'not-allowed';
                testQuranServerBtn.style.background = '#999';
            }

            // Gray out the label for Server audio device
            const audioCardLabel = document.getElementById('audioCardLabel');
            if (audioCardLabel) {
                audioCardLabel.style.color = '#999';
            }
        } else {
            // Audio IS supported - ensure dropdown is enabled
            const audioOutputSelect = document.getElementById('audioOutput');
            if (audioOutputSelect) {
                audioOutputSelect.disabled = false;
                audioOutputSelect.style.opacity = '1';
                audioOutputSelect.style.cursor = 'pointer';

                // Remove warning message if present
                const warningMsg = audioOutputSelect.parentElement.querySelector('.audio-output-warning');
                if (warningMsg) {
                    warningMsg.remove();
                }
            }

            if (window.setVolumeSliderEnabled) {
                const settings = await (await fetch(`${API_BASE}/api/settings`)).json();
                const audioOutput = settings.audio_output || 'both';
                const isServerEnabled = audioOutput !== 'browser';
                window.setVolumeSliderEnabled(isServerEnabled);

                // Enable/disable Fajr volume checkbox
                if (window.setSyncFajrVolumeCheckboxEnabled) {
                    window.setSyncFajrVolumeCheckboxEnabled(isServerEnabled);
                }

                // Enable/disable Fajr volume slider based on checkbox state
                const syncFajrVolumeCheckbox = document.getElementById('syncFajrVolume');
                if (window.setFajrVolumeSliderEnabled && syncFajrVolumeCheckbox) {
                    const useIndependentVolume = syncFajrVolumeCheckbox.checked;
                    window.setFajrVolumeSliderEnabled(isServerEnabled && useIndependentVolume);
                }
            }
        }

    } catch (error) {
        console.error('[loadAudioSupport] Error loading audio support:', error);
        document.getElementById('serverAudioSupport').textContent = 'Load error';
        document.getElementById('serverAudioSupport').style.color = '#8B0000';
    }
}

// Update server time display using synced time (no fetch needed)
function updateServerTimeDisplay() {
    try {
        const syncedTime = getServerSyncedDate();
        const hours = String(syncedTime.getHours()).padStart(2, '0');
        const minutes = String(syncedTime.getMinutes()).padStart(2, '0');
        const seconds = String(syncedTime.getSeconds()).padStart(2, '0');

        const serverTimeValue = document.getElementById('serverTimeValue');
        if (serverTimeValue) {
            serverTimeValue.textContent = `${hours}:${minutes}:${seconds}`;
        }

        const serverDateValue = document.getElementById('serverDateValue');
        if (serverDateValue) {
            const weekdayFormatter = new Intl.DateTimeFormat('en-US', { weekday: 'long' });
            const weekday = weekdayFormatter.format(syncedTime);
            const day = String(syncedTime.getDate()).padStart(2, '0');
            const month = String(syncedTime.getMonth() + 1).padStart(2, '0');
            const year = syncedTime.getFullYear();
            serverDateValue.textContent = `${weekday} ${day}/${month}/${year}`;
        }
    } catch (error) {
        console.error('Error updating server time display:', error);
    }
}

// Load server info (IP, mute command) - called once at startup
async function loadServerTime() {
    try {
        const response = await fetch(`${API_BASE}/api/server-time`);
        const data = await response.json();

        const serverIpValue = document.getElementById('serverIpValue');
        if (serverIpValue && data.ip) {
            serverIpValue.textContent = data.ip;
        }

        const serverHostnameValue = document.getElementById('serverHostnameValue');
        if (serverHostnameValue && data.hostname) {
            serverHostnameValue.textContent = data.hostname;
        }

        const muteCommandElement = document.getElementById('muteCommand');
        if (muteCommandElement) {
            try {
                const muteCommandUrl = new URL(`${API_BASE}/api/mute-next-athan`);
                if (data.ip) {
                    muteCommandUrl.hostname = data.ip;
                }
                muteCommandElement.textContent = `curl ${muteCommandUrl.href}`;
            } catch (urlError) {
                console.error('Error building mute command URL:', urlError);
                muteCommandElement.textContent = 'Error';
            }
        }

        const unmuteCommandElement = document.getElementById('unmuteCommand');
        if (unmuteCommandElement) {
            try {
                const unmuteCommandUrl = new URL(`${API_BASE}/api/skip-next/reset`);
                if (data.ip) {
                    unmuteCommandUrl.hostname = data.ip;
                }
                unmuteCommandElement.textContent = `curl ${unmuteCommandUrl.href}`;
            } catch (urlError) {
                console.error('Error building unmute command URL:', urlError);
                unmuteCommandElement.textContent = 'Error';
            }
        }

        const stopAudioCommandElement = document.getElementById('stopAudioCommand');
        if (stopAudioCommandElement) {
            try {
                const stopAudioCommandUrl = new URL(`${API_BASE}/api/stop-audio`);
                if (data.ip) {
                    stopAudioCommandUrl.hostname = data.ip;
                }
                stopAudioCommandElement.textContent = `curl ${stopAudioCommandUrl.href}`;
            } catch (urlError) {
                console.error('Error building stop audio command URL:', urlError);
                stopAudioCommandElement.textContent = 'Error';
            }
        }

        const testAthanServerCommandElement = document.getElementById('testAthanServerCommand');
        if (testAthanServerCommandElement) {
            try {
                const testAthanServerUrl = new URL(`${API_BASE}/api/test-athan-server`);
                if (data.ip) {
                    testAthanServerUrl.hostname = data.ip;
                }
                testAthanServerCommandElement.textContent = `curl ${testAthanServerUrl.href}`;
            } catch (urlError) {
                console.error('Error building test athan server command URL:', urlError);
                testAthanServerCommandElement.textContent = 'Error';
            }
        }

        const testQuranServerCommandElement = document.getElementById('testQuranServerCommand');
        if (testQuranServerCommandElement) {
            try {
                const testQuranServerUrl = new URL(`${API_BASE}/api/test-quran-server`);
                if (data.ip) {
                    testQuranServerUrl.hostname = data.ip;
                }
                testQuranServerCommandElement.textContent = `curl ${testQuranServerUrl.href}`;
            } catch (urlError) {
                console.error('Error building test quran server command URL:', urlError);
                testQuranServerCommandElement.textContent = 'Error';
            }
        }

        const nextPrayerTextCommandElement = document.getElementById('nextPrayerTextCommand');
        if (nextPrayerTextCommandElement) {
            try {
                const nextPrayerTextUrl = new URL(`${API_BASE}/api/next-prayer-text?lang=FR`);
                if (data.ip) {
                    nextPrayerTextUrl.hostname = data.ip;
                }
                nextPrayerTextCommandElement.textContent = `curl ${nextPrayerTextUrl.href}`;
            } catch (urlError) {
                console.error('Error building next prayer text command URL:', urlError);
                nextPrayerTextCommandElement.textContent = 'Error';
            }
        }
    } catch (error) {
        console.error('Error loading server time:', error);
        const serverTimeValue = document.getElementById('serverTimeValue');
        if (serverTimeValue) {
            serverTimeValue.textContent = 'Error';
        }
        const serverIpValue = document.getElementById('serverIpValue');
        if (serverIpValue) {
            serverIpValue.textContent = 'Error';
        }
        const serverHostnameValue = document.getElementById('serverHostnameValue');
        if (serverHostnameValue) {
            serverHostnameValue.textContent = 'Error';
        }
        const muteCommandElement = document.getElementById('muteCommand');
        if (muteCommandElement) {
            muteCommandElement.textContent = 'Error';
        }
        const unmuteCommandElement = document.getElementById('unmuteCommand');
        if (unmuteCommandElement) {
            unmuteCommandElement.textContent = 'Error';
        }
        const stopAudioCommandElement = document.getElementById('stopAudioCommand');
        if (stopAudioCommandElement) {
            stopAudioCommandElement.textContent = 'Error';
        }
        const testAthanServerCommandElement = document.getElementById('testAthanServerCommand');
        if (testAthanServerCommandElement) {
            testAthanServerCommandElement.textContent = 'Error';
        }
        const testQuranServerCommandElement = document.getElementById('testQuranServerCommand');
        if (testQuranServerCommandElement) {
            testQuranServerCommandElement.textContent = 'Error';
        }
    }
}

// Remove file extension from display name
function getAudioDisplayName(filename) {
    // Remove .mp3, .wav, etc. extensions
    return filename.replace(/\.(mp3|wav|ogg|m4a|flac|aac)$/i, '');
}

// Load available audio files
async function loadAudioFiles() {
    try {
        const response = await fetch(`${API_BASE}/api/audio-files`);
        const files = await response.json();

        const audioSelect = document.getElementById('audioFile');
        const currentSettings = await fetch(`${API_BASE}/api/settings`).then(r => r.json());

        audioSelect.innerHTML = files.map(file => `
            <option value="${file}" ${currentSettings.audio_file === file ? 'selected' : ''}>
                ${getAudioDisplayName(file)}
            </option>
        `).join('');

        if (files.length === 0) {
            audioSelect.innerHTML = '<option>No audio files found</option>';
        }
    } catch (error) {
        console.error('Error loading audio files:', error);
    }
}

// Load available Quran files
async function loadQuranFiles() {
    try {
        const response = await fetch(`${API_BASE}/api/quran-files`);
        const files = await response.json();

        const quranSelect = document.getElementById('fridayQuranFile');
        const currentSettings = await fetch(`${API_BASE}/api/settings`).then(r => r.json());

        quranSelect.innerHTML = files.map(file => `
            <option value="${file}" ${currentSettings.friday_quran_file === file ? 'selected' : ''}>
                ${getAudioDisplayName(file)}
            </option>
        `).join('');

        if (files.length === 0) {
            quranSelect.innerHTML = '<option>No Quran files found</option>';
        }
    } catch (error) {
        console.error('Error loading Quran files:', error);
    }
}

// Initialize Friday Quran time dropdowns
function initializeFridayQuranTime() {
    // Populate hours (06-21)
    const hourSelect = document.getElementById('fridayQuranHour');
    for (let h = 6; h <= 21; h++) {
        const hourStr = h.toString().padStart(2, '0');
        const option = document.createElement('option');
        option.value = hourStr;
        option.textContent = hourStr;
        hourSelect.appendChild(option);
    }
    // Set default to 07
    hourSelect.value = '07';

    // Populate minutes (00, 05, 10, ..., 55)
    const minuteSelect = document.getElementById('fridayQuranMinute');
    for (let m = 0; m <= 55; m += 5) {
        const minuteStr = m.toString().padStart(2, '0');
        const option = document.createElement('option');
        option.value = minuteStr;
        option.textContent = minuteStr;
        minuteSelect.appendChild(option);
    }
    // Set default to 00
    minuteSelect.value = '00';
}

// Get the display name for a prayer
function getPrayerName(name) {
    const names = {
        'Fajr | Sobh': 'Fajr | Sobh',
        'Dohr': 'Dohr',
        'Asr': 'Asr',
        'Maghrib': 'Maghrib',
        'Isha': 'Isha',
        'Sunrise': 'Sunrise',
        'Sunset': 'Sunset',
        '🌅 Sunrise': 'Sunrise',
        '🌄 Sunset': 'Sunset',
        'Tahajjud': 'Tahajjud',
        'Qiyam': 'Qiyam'
    };
    return names[name] || name;
}

// Expose functions globally for inline handlers
window.togglePrayer = togglePrayer;
window.toggleWeekday = toggleWeekday;
