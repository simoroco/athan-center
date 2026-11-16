import Foundation
import SwiftUI
import Combine

// MARK: - AppStore — replicates app.js behavior against the same REST API.

@MainActor
final class AppStore: ObservableObject {

    // MARK: Configuration
    @Published var serverBase: String {
        didSet {
            UserDefaults.standard.set(serverBase, forKey: "serverBaseURL")
            api = APIClient(base: serverBase)
            Task { await boot() }
        }
    }
    private(set) var api: APIClient

    // MARK: Server clock sync (syncTimeWithServer)
    private var serverOffset: TimeInterval = 0
    @Published var serverTimeInfo: ServerTime?
    var serverNow: Date { Date().addingTimeInterval(serverOffset) }
    var serverSynced: Bool { serverTimeInfo != nil }

    // MARK: Displayed data
    @Published var selectedDate: Date
    @Published var prayers: [Prayer] = []
    @Published var prayerChecks: [String: Int] = [:]      // name -> checked
    @Published var activityChecks: [String: Int] = [:]    // name -> checked
    @Published var nextPrayer: Prayer? = nil
    @Published var cardVisible = false
    @Published var cardDateOnly = false                   // date-only placeholder mode
    @Published var settings: [String: String] = [:]
    @Published var updateInfo: UpdateInfo?
    @Published var audioSupport: AudioSupport?
    @Published var skipNext = false
    @Published var mutedWeekdays: [Int: Int] = [:]        // weekday (0=Sun) -> muted
    @Published var schedule: [ScheduleEntry] = []
    @Published var ramadanDates: Set<String> = []
    @Published var audioFiles: [String] = []
    @Published var quranFiles: [String] = []
    @Published var audioDevices: [AudioDevice] = []
    @Published var connected = false
    @Published var loadingPrayers = false
    var loadGeneration = 0
    var probing = false
    @Published var toast: String? = nil

    // MARK: Audio
    let audio = AudioManager()
    private var cancellables = Set<AnyCancellable>()
    private var lastPlayedPrayer = ""                     // "date-name" dedup key
    private var lastPlayedQuran = ""

    // MARK: Banner state
    @Published var muteAlertManual = false
    @Published var muteAlertGeneral = false

    private var loops: [Task<Void, Never>] = []
    var booted = false
    private var toastTask: Task<Void, Never>?

    init() {
        let args = ProcessInfo.processInfo.arguments
        // UI-test mode: kill animations so element frames are stable for XCUI hit-testing.
        if args.contains("-resetLocal") || args.contains("-serverBase") {
            UIView.setAnimationsEnabled(false)
        }
        let resetLocal = args.contains("-resetLocal")
        // UI-test hook: -resetLocal → behave like a fresh install.
        if resetLocal {
            LocalStore.shared.reset()
            if let bid = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bid)
            }
        }
        var saved = UserDefaults.standard.string(forKey: "serverBaseURL") ?? ""
        // UI-test hook: -serverBase <url>
        if let i = args.firstIndex(of: "-serverBase"), args.count > i + 1 {
            saved = args[i + 1]
            UserDefaults.standard.set(saved, forKey: "serverBaseURL")
        }
        if resetLocal { saved = "" }
        serverBase = saved
        api = APIClient(base: saved)
        if !saved.isEmpty {
            // Existing/legacy installs with a server URL stay in server mode.
            LocalStore.shared.snap.mode = .server
            LocalStore.shared.save()
        }
        selectedDate = Date()
        // AudioManager is a child ObservableObject: forward its changes so
        // store.audio.* reads in views (stop banner, card pulse) re-render.
        audio.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var configured: Bool { !serverBase.isEmpty }

    // MARK: - Boot

    func boot() async {
        guard !Task.isCancelled else { return }
        if isStandalone { await bootStandalone(); return }
        guard configured else { return }
        booted = true
        if await !syncTime() {
            // Server unreachable → offline mode from the local cache (never block the UI on timeouts).
            connected = false
            bootOfflineFromCache()
            startLoops()
            return
        }
        connected = true
        if !local.snap.pendingOps.isEmpty { await resyncFromServer(); return }
        await initializeLastPlayedPrayer()
        async let s: () = loadSettings()
        async let p: () = loadDay()
        async let n: () = loadNextPrayer()
        async let u: () = loadUpdateInfo()
        async let a: () = loadAudioSupport()
        async let sch: () = loadSchedule()
        async let m: () = loadMutedWeekdays()
        async let r: () = loadRamadan()
        _ = await (s, p, n, u, a, sch, m, r)
        async let af: () = loadAudioFiles()
        async let qf: () = loadQuranFiles()
        async let dv: () = loadAudioDevices()
        _ = await (af, qf, dv)
        startLoops()
        Task { await cacheUpcomingFromServer() }
        await playOnPageLoad()
    }

    func startLoops() {
        stopLoops()
        // 5s — audio triggers (check-athan-time + check-friday-quran)
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.isStandalone {
                    self.checkAthanLocal()
                } else if !self.connected {
                    self.checkAthanLocal()
                    await self.probeConnectivity()
                } else {
                    await self.checkAudioTriggers()
                }
            }
        })
        // 60s — prayers + update info + skip status + connectivity probe
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.isStandalone {
                    await self.loadDay()
                    await self.refreshICSIfStale()
                } else if !self.connected {
                    self.loadDayLocal()
                } else {
                    await self.loadDay()
                    await self.loadUpdateInfo()
                    await self.refreshMuteState()
                }
            }
        })
        // 5min — clock resync
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.syncTime()
                await self.loadDay()
                await self.loadNextPrayer()
            }
        })
    }

    func stopLoops() {
        loops.forEach { $0.cancel() }
        loops = []
    }

    // MARK: - Server clock

    @discardableResult
    func syncTime() async -> Bool {
        guard configured, !isStandalone else { return false }
        let send = Date()
        do {
            let t = try await api.serverTime()
            let recv = Date()
            let rtt = recv.timeIntervalSince(send)
            serverOffset = (t.timestampMs / 1000.0) + rtt / 2 - recv.timeIntervalSince1970
            serverTimeInfo = t
            return true
        } catch {
            return false   // keep previous offset
        }
    }

    // MARK: - Derived date state

    var todayStr: String { DateUtil.dateString(serverNow) }
    var tomorrowStr: String {
        DateUtil.dateString(Calendar.current.date(byAdding: .day, value: 1, to: serverNow) ?? serverNow)
    }
    var selectedDateStr: String { DateUtil.dateString(selectedDate) }
    var currentTimeStr: String { DateUtil.timeString(serverNow) }
    var isViewingToday: Bool { selectedDateStr == todayStr }
    var isViewingTomorrow: Bool { selectedDateStr == tomorrowStr }
    var isFutureDate: Bool { selectedDateStr > todayStr }
    var dayDiff: Int { DateUtil.dayDifference(serverNow, selectedDate) }
    var isRamadanSelectedDate: Bool { ramadanDates.contains(selectedDateStr) }

    /// Isha of today has passed (drives next-prayer card on tomorrow view).
    private func ishaPassedToday() async -> Bool {
        let todayPrayers = await prayersOn(todayStr)
        guard let isha = todayPrayers.first(where: { $0.prayer_name == "Isha" }) else { return false }
        return currentTimeStr > isha.prayer_time
    }

    // MARK: - Loading

    /// Loads the selected day. Every call supersedes the previous one (generation token) so rapid
    /// navigation can never display a stale response nor be ignored by an in-flight load.
    func loadDay() async {
        loadGeneration += 1
        let gen = loadGeneration
        if isStandalone || !connected {
            loadDayLocal()
            return
        }
        guard configured else { return }
        loadingPrayers = true
        defer { if gen == loadGeneration { loadingPrayers = false } }
        let dateStr = selectedDateStr
        let pr: [Prayer], ch: [PrayerCheck], ac: [DailyActivity]
        do {
            async let p = api.prayers(date: dateStr)
            async let c = api.prayerChecks(date: dateStr)
            async let a = api.dailyActivities(date: dateStr)
            (pr, ch, ac) = try await (p, c, a)
        } catch {
            guard gen == loadGeneration else { return }
            markOffline()
            return
        }
        guard gen == loadGeneration, dateStr == selectedDateStr else { return }
        prayers = pr
        prayerChecks = Dictionary(ch.map { ($0.prayer_name, $0.checked) }, uniquingKeysWith: { _, new in new })
        // Keep iOS-only custom action states: the server only knows the built-in activities.
        var acts = Dictionary(ac.map { ($0.activity_name, $0.checked) }, uniquingKeysWith: { _, new in new })
        for (k, v) in local.snap.activities[dateStr] ?? [:] where !AC.activities.contains(where: { $0.name == k }) { acts[k] = v }
        activityChecks = acts
        cacheDayToLocal(date: dateStr, prayers: pr, checks: prayerChecks, acts: activityChecks)

        // Next prayer card visibility rules (loadPrayers in app.js)
        if isViewingToday {
            await loadNextPrayer()
            guard gen == loadGeneration else { return }
            if let np = nextPrayer, validateNextPrayer(np) {
                cardVisible = true; cardDateOnly = false
            } else if nextPrayer != nil {
                cardVisible = false
                Task { [weak self] in          // non-blocking retry in 5s (superseded by any newer load)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard let self, gen == self.loadGeneration else { return }
                    await self.loadDay()
                }
            } else {
                cardVisible = false
            }
            await refreshMuteState()
        } else if isViewingTomorrow {
            if await ishaPassedToday() {
                await loadNextPrayer()
                cardVisible = nextPrayer != nil
                cardDateOnly = false
            } else {
                cardVisible = true; cardDateOnly = true
            }
            await refreshMuteState()
        } else {
            cardVisible = true; cardDateOnly = true
            await refreshMuteState()
        }
    }

    /// Server stopped answering: switch to the local cache (probe loop will resync).
    func markOffline() {
        guard !isStandalone, connected else { return }
        connected = false
        loadDayLocal()
    }

    /// Offline boot: everything from the last known server snapshot.
    func bootOfflineFromCache() {
        settings = local.snap.settings
        schedule = local.snap.schedule
        selectedDate = Date()
        loadDayLocal()
    }

    /// validateNextPrayer: no main prayer may sit between now and nextPrayer.time.
    private func validateNextPrayer(_ np: Prayer) -> Bool {
        guard np.date == todayStr else { return true }
        let now = currentTimeStr
        for p in prayers where AC.mainPrayers.contains(p.prayer_name) {
            if p.prayer_time > now && p.prayer_time < np.prayer_time { return false }
        }
        return true
    }

    func loadNextPrayer() async {
        if isStandalone || !connected {
            nextPrayer = localNextPrayer()
        } else {
            if let np = try? await api.nextPrayer() { nextPrayer = np }
            else if !connected { nextPrayer = localNextPrayer() }
        }
    }

    func loadSettings() async {
        if isStandalone {
            settings = local.snap.settings
            return
        }
        if let s = try? await api.settings() {
            settings = s
            local.snap.settings = s
            local.save()
        }
    }

    func loadUpdateInfo() async {
        updateInfo = try? await api.updateInfo()
    }

    func loadAudioSupport() async {
        audioSupport = try? await api.audioSupport()
    }

    func loadSchedule() async {
        if isStandalone { schedule = local.snap.schedule; return }
        if let s = try? await api.prayerSchedule() {
            schedule = s
            local.snap.schedule = s
            local.save()
        }
    }

    func loadMutedWeekdays() async {
        let rows = (try? await api.mutedWeekdays()) ?? []
        mutedWeekdays = Dictionary(rows.map { ($0.weekday, $0.muted) }, uniquingKeysWith: { _, new in new })
    }

    func loadRamadan() async {
        let rows = (try? await api.ramadanDates()) ?? []
        ramadanDates = Set(rows.map { $0.gregorian_date })
    }

    func loadAudioFiles() async { audioFiles = (try? await api.audioFiles()) ?? [] }
    func loadQuranFiles() async { quranFiles = (try? await api.quranFiles()) ?? [] }
    func loadAudioDevices() async { audioDevices = (try? await api.audioDevices()) ?? [] }

    // MARK: - Mute banners (checkSkipNextStatus + updateWeekdayMuteBanner)

    var showMuteBannerContext: Bool {
        isViewingToday || (isViewingTomorrow && ishaPassedSync)
    }

    /// Cached result of isha check for banner logic.
    @Published var ishaPassedSync = false

    func refreshMuteState() async {
        if isStandalone || !connected {
            refreshMuteStateLocal()
            return
        }
        skipNext = (try? await api.skipNextStatus()) ?? skipNext
        if schedule.isEmpty { await loadSchedule() }
        if mutedWeekdays.isEmpty { await loadMutedWeekdays() }
        ishaPassedSync = await ishaPassedToday()

        muteAlertManual = false
        muteAlertGeneral = false
        guard showMuteBannerContext else { return }
        if skipNext {
            muteAlertManual = true
        } else if let np = nextPrayer {
            let day = DateUtil.scheduleDay(DateUtil.parseDate(np.date) ?? serverNow)
            if scheduleEnabled(np.prayer_name, day) == false {
                muteAlertGeneral = true
            }
        }
    }

    var muteAlertActive: Bool { muteAlertManual || muteAlertGeneral }

    var weekdayMuteActive: Bool {
        isViewingToday
        && (mutedWeekdays[DateUtil.jsDay(serverNow)] ?? 0) == 1
        && !muteAlertActive
    }

    var muteAlertText: String {
        if muteAlertManual {
            if let name = nextPrayer?.prayer_name {
                return "Next athan (\(AC.displayPrayerName(name))) is muted"
            }
            return "Next athan is muted"
        }
        if muteAlertGeneral, let name = nextPrayer?.prayer_name {
            return "\(AC.displayPrayerName(name)) athan is muted (general settings)"
        }
        return "Next athan is muted"
    }

    // MARK: - Toggles

    func togglePrayer(_ name: String) async {
        guard !isFutureDate else { return }
        if isStandalone || !connected {
            let next = localNextCycle(prayerChecks[name] ?? 0)
            prayerChecks[name] = next
            local.setPrayerState(selectedDateStr, name, next)
            if !isStandalone {
                local.enqueue(PendingOp(kind: .prayerCheck, date: selectedDateStr, name: name, value: next, text: nil))
            }
            return
        }
        if let newState = try? await api.togglePrayerCheck(date: selectedDateStr, prayer: name) {
            prayerChecks[name] = newState
            local.setPrayerState(selectedDateStr, name, newState)
        }
    }

    func toggleActivity(_ name: String) async {
        await toggleActionLocal(name)
    }

    func muteNext() async {
        if isStandalone || !connected {
            muteNextLocal()
            if !isStandalone {
                local.enqueue(PendingOp(kind: .muteNext, date: nil, name: "mute", value: 1, text: nil))
            }
            return
        }
        do {
            let r = try await api.muteNextAthan()
            if r.success == true {
                skipNext = true
                muteAlertManual = true
            } else {
                showToast(r.message ?? "Already muted")
            }
        } catch let e as APIError {
            showToast(e.errorDescription ?? "Error")
        } catch { showToast("Mute failed") }
    }

    func unmuteNext() async {
        if isStandalone || !connected {
            unmuteNextLocal()
            if !isStandalone { _ = try? await api.resetSkipNext() }
            return
        }
        _ = try? await api.resetSkipNext()
        skipNext = false
        muteAlertManual = false
    }

    func unmuteWeekday() async {
        _ = try? await api.setMutedWeekday(DateUtil.jsDay(serverNow), muted: false)
        await loadMutedWeekdays()
        await refreshMuteState()
    }

    func scheduleEnabled(_ prayer: String, _ day: Int) -> Bool? {
        schedule.first { $0.prayer_name == prayer && $0.day_of_week == day }?.enabled == 1
    }

    func setSchedule(_ prayer: String, _ day: Int, _ enabled: Bool) async {
        if isStandalone {
            local.setSchedule(prayer, day, enabled)
            schedule = local.snap.schedule
            refreshMuteStateLocal()
            rescheduleNotifications()
            return
        }
        try? await api.setScheduleCell(prayer: prayer, day: day, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    func bulkSchedulePrayer(_ prayer: String, _ enabled: Bool) async {
        if isStandalone {
            local.bulkSchedule(prayer: prayer, enabled: enabled)
            schedule = local.snap.schedule
            refreshMuteStateLocal()
            rescheduleNotifications()
            return
        }
        try? await api.bulkSchedule(type: "prayer", target: prayer, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    func bulkScheduleDay(_ day: Int, _ enabled: Bool) async {
        if isStandalone {
            local.bulkSchedule(day: day, enabled: enabled)
            schedule = local.snap.schedule
            refreshMuteStateLocal()
            rescheduleNotifications()
            return
        }
        try? await api.bulkSchedule(type: "day", target: day, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    // MARK: - Settings actions

    func updateSetting(_ key: String, _ value: String) async {
        settings[key] = value
        local.snap.settings[key] = value
        local.save()
        if isStandalone || !connected {
            if !isStandalone {
                local.enqueue(PendingOp(kind: .setting, date: nil, name: key, value: 0, text: value))
            }
            if key == "ics_url" { await refreshICSIfStale(force: true) }
            if key.hasPrefix("quran") || key.contains("schedule") { rescheduleNotifications() }
            return
        }
        try? await api.setSetting(key, value)
        if key == "ics_url" {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await loadDay()
        }
    }

    func forceUpdatePrayers() async -> String {
        if isStandalone {
            await refreshICSIfStale(force: true)
            return "Prayer times updated"
        }
        let r = try? await api.updatePrayers()
        await loadDay(); await loadNextPrayer(); await loadUpdateInfo()
        return r?.message ?? "Updated"
    }

    func resetChecks() async {
        if isStandalone || !connected {
            local.snap.checks[selectedDateStr] = [:]
            local.save()
            prayerChecks = [:]
            return
        }
        _ = try? await api.resetPrayerChecks()
        await loadDay()
    }

    func restoreDefaults() async {
        if isStandalone {
            local.snap.checks = [:]
            local.snap.activities = [:]
            local.snap.customActions = []
            local.snap.settings = [:]
            local.snap.schedule = []
            local.ensureDefaultsAfterReset()
            await bootStandalone()
            return
        }
        _ = try? await api.restoreDefaults()
        await boot()
    }

    func importConfig(_ csv: String) async -> String {
        let r = try? await api.importSettings(csv: csv)
        await boot()
        return r?.message ?? "Imported"
    }

    func permanentSilence() async {
        if isStandalone {
            local.bulkSchedule(enabled: false)
            schedule = local.snap.schedule
            refreshMuteStateLocal()
            rescheduleNotifications()
            return
        }
        _ = try? await api.permanentSilence()
        await loadSchedule(); await loadSettings(); await refreshMuteState()
    }

    // MARK: - Audio triggers (5s polling)

    private func initializeLastPlayedPrayer() async {
        // Prevent the athan from firing right after launch (web parity).
        let todayPs = await prayersOn(todayStr)
        let now = currentTimeStr
        let passed = todayPs.filter { AC.mainPrayers.contains($0.prayer_name) && $0.prayer_time <= now }
        if let last = passed.last {
            lastPlayedPrayer = "\(todayStr)-\(last.prayer_name)"
        }
    }

    func checkAudioTriggers() async {
        await checkAthan()
        await checkQuran()
    }

    private func checkAthan() async {
        guard let r = try? await api.checkAthanTime() else { return }
        if r.shouldPlay, let name = r.prayerName, let file = r.audioFile {
            let key = "\(todayStr)-\(name)"
            guard key != lastPlayedPrayer else { return }
            lastPlayedPrayer = key
            if iosAudioEnabled, let url = api.athanURL(file) {
                audio.play(url: url, banner: "Athan calling...", isPrayer: true)
            }
        }
    }

    private func checkQuran() async {
        guard let r = try? await api.checkFridayQuran() else { return }
        if r.serverPlayingQuran == true && !audio.isPlaying {
            audio.showServerBanner("Al Kahf Sourat recitation playing", duration: 15)   // refreshed by each poll
        } else if r.serverPlayingQuran == false, audio.serverPlaying,
                  audio.bannerText == "Al Kahf Sourat recitation playing" {
            audio.clearServerBanner()
        }
        if r.shouldPlay == true, r.type == "friday_quran", let file = r.quranFile {
            let key = "\(todayStr)-quran"
            guard key != lastPlayedQuran else { return }
            lastPlayedQuran = key
            if iosAudioEnabled, let url = api.quranURL(file) {
                audio.play(url: url, banner: "Al Kahf Sourat recitation playing")
            }
        }
    }

    /// playOnPageLoad() — startup sound on app open.
    private func playOnPageLoad() async {
        guard settings["play_on_page_load"] == "1",
              ["browser", "both"].contains(settings["audio_output"] ?? "both"),
              let url = api.startupURL() else { return }
        audio.play(url: url, banner: "Startup sound")
    }

    // MARK: - Audio actions

    /// Stop everything: local player immediately, then the Pi (if reachable).
    func stopAllAudio() async {
        audio.stopLocal()
        if !isStandalone && configured { try? await api.stopAudio() }
    }

    func testAthanWeb() {
        if isStandalone { playLocalAthan(); return }
        let file = settings["audio_file"] ?? "Masjid Al-Haram.mp3"
        if let url = api.athanURL(file) {
            audio.play(url: url, banner: "Athan calling (app)...")
        }
    }

    func testQuranWeb() {
        guard !isStandalone else { showToast("Quran recitation requires a server"); return }
        let file = settings["friday_quran_file"] ?? "Sourat Al Kahf - Hani Arrifai.mp3"
        if let url = api.quranURL(file) {
            audio.play(url: url, banner: "Quran reciting (30s preview)...", limit30s: true)
        }
    }

    func testAthanServer() async {
        guard connected else { showToast("Server unreachable"); return }
        _ = try? await api.testAthanServer()
        audio.showServerBanner("Athan calling (server)...", duration: 40)
    }

    func testQuranServer() async {
        guard connected else { showToast("Server unreachable"); return }
        _ = try? await api.testQuranServer()
        audio.showServerBanner("Quran reciting (30s server preview)...", duration: 32)
    }

    /// "Listen to Sourat Al Kahf now"
    func playFullQuran() async {
        guard !isStandalone else { showToast("Quran recitation requires a server"); return }
        let output = settings["audio_output"] ?? "both"
        let file = settings["friday_quran_file"] ?? ""
        if output == "server" || output == "both" {
            _ = try? await api.triggerFridayQuran()
            if output == "server" { audio.showServerBanner("Al Kahf Sourat recitation playing", duration: 3600) }
        }
        if output == "browser" || output == "both", let url = api.quranURL(file) {
            audio.play(url: url, banner: "Al Kahf Sourat recitation playing")
        }
    }

    // MARK: - Quick Pray data (14-day window)

    func quickFillRows() async -> (days: [(date: String, label: String)], checks: [String: [String: Int]]) {
        if isStandalone || !connected { return quickFillRowsLocal() }
        let year = Calendar.current.component(.year, from: serverNow)
        var all = (try? await api.prayerChecksRange(year: year)) ?? []
        // If window crosses Jan 1, also fetch previous year.
        let windowStart = Calendar.current.date(byAdding: .day, value: -13, to: serverNow) ?? serverNow
        if Calendar.current.component(.year, from: windowStart) < year {
            all += (try? await api.prayerChecksRange(year: year - 1)) ?? []
        }
        var map: [String: [String: Int]] = [:]
        for c in all where AC.mainPrayers.contains(c.prayer_name) {
            map[c.date, default: [:]][c.prayer_name] = c.checked
        }
        // Find oldest incomplete day in window (today .. today-13).
        var days: [(String, String)] = []
        var lastIncomplete = 0
        for i in 0...13 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: serverNow)!
            let ds = DateUtil.dateString(d)
            let checks = map[ds] ?? [:]
            let complete = AC.mainPrayers.allSatisfy { (checks[$0] ?? 0) >= 1 }
            if !complete { lastIncomplete = i }
        }
        for i in stride(from: lastIncomplete, through: 0, by: -1) {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: serverNow)!
            days.append((DateUtil.dateString(d), DateUtil.relativeDayLabel(d, today: serverNow)))
        }
        return (days, map)
    }

    // MARK: - UI state helpers

    /// Is the selected past day incomplete (drives Quick Pray button swap)?
    var pastDayIncomplete: Bool {
        guard selectedDateStr < todayStr else { return false }
        return AC.mainPrayers.contains { (prayerChecks[$0] ?? 0) == 0 }
    }

    var theme: AppTheme { AppTheme(dark: settings["dark_mode"] == "1") }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Navigation

    func goPrevDay() { shiftDay(-1) }
    func goNextDay() { shiftDay(1) }
    func goToday() { setDate(serverNow) }
    func goToDate(_ d: Date) { setDate(d) }

    private func shiftDay(_ delta: Int) {
        setDate(Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate)
    }

    /// Paint the cached day immediately (no flash of stale/empty data), then refresh from the source.
    private func setDate(_ d: Date) {
        selectedDate = d
        let ds = selectedDateStr
        prayers = local.snap.prayers[ds] ?? []
        prayerChecks = local.snap.checks[ds] ?? [:]
        activityChecks = local.snap.activities[ds] ?? [:]
        Task { await loadDay() }
    }

    // MARK: - Prayer row state (displayPrayers in app.js)

    func isPastPrayer(_ p: Prayer) -> Bool {
        selectedDateStr < todayStr || (isViewingToday && p.prayer_time < currentTimeStr)
    }
}
