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
    @Published var toast: String? = nil

    // MARK: Audio
    let audio = AudioManager()
    private var lastPlayedPrayer = ""                     // "date-name" dedup key
    private var lastPlayedQuran = ""

    // MARK: Banner state
    @Published var muteAlertManual = false
    @Published var muteAlertGeneral = false

    private var loops: [Task<Void, Never>] = []
    private var booted = false
    private var toastTask: Task<Void, Never>?

    init() {
        var saved = UserDefaults.standard.string(forKey: "serverBaseURL") ?? ""
        // UI-test hook: -serverBase <url>
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-serverBase"), args.count > i + 1 {
            saved = args[i + 1]
            UserDefaults.standard.set(saved, forKey: "serverBaseURL")
        }
        serverBase = saved
        api = APIClient(base: saved.isEmpty ? AC.defaultServer : saved)
        selectedDate = Date()
    }

    var configured: Bool { !serverBase.isEmpty }

    // MARK: - Boot

    func boot() async {
        guard configured, !Task.isCancelled else { return }
        booted = true
        await syncTime()
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
        connected = true
        startLoops()
        await playOnPageLoad()
    }

    func startLoops() {
        stopLoops()
        // 5s — audio triggers (check-athan-time + check-friday-quran)
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.checkAudioTriggers()
            }
        })
        // 60s — prayers + update info + skip status
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.loadDay()
                await self.loadUpdateInfo()
                await self.refreshMuteState()
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

    func syncTime() async {
        let send = Date()
        do {
            let t = try await api.serverTime()
            let recv = Date()
            let rtt = recv.timeIntervalSince(send)
            serverOffset = (t.timestampMs / 1000.0) + rtt / 2 - recv.timeIntervalSince1970
            serverTimeInfo = t
        } catch {
            // keep previous offset
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
        let todayPrayers = (try? await api.prayers(date: todayStr)) ?? prayers
        guard let isha = todayPrayers.first(where: { $0.prayer_name == "Isha" }) else { return false }
        return currentTimeStr > isha.prayer_time
    }

    // MARK: - Loading

    func loadDay() async {
        guard configured, !loadingPrayers else { return }
        loadingPrayers = true
        defer { loadingPrayers = false }
        let dateStr = selectedDateStr
        async let p = api.prayers(date: dateStr)
        async let c = api.prayerChecks(date: dateStr)
        async let a = api.dailyActivities(date: dateStr)
        let (pr, ch, ac) = await ((try? p) ?? [], (try? c) ?? [], (try? a) ?? [])
        prayers = pr
        prayerChecks = Dictionary(uniqueKeysWithValues: ch.map { ($0.prayer_name, $0.checked) })
        activityChecks = Dictionary(uniqueKeysWithValues: ac.map { ($0.activity_name, $0.checked) })

        // Next prayer card visibility rules (loadPrayers in app.js)
        if isViewingToday {
            await loadNextPrayer()
            if let np = nextPrayer, validateNextPrayer(np) {
                cardVisible = true; cardDateOnly = false
            } else if nextPrayer != nil {
                cardVisible = false
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { await loadDay() }
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
        nextPrayer = try? await api.nextPrayer()
    }

    func loadSettings() async {
        settings = (try? await api.settings()) ?? [:]
    }

    func loadUpdateInfo() async {
        updateInfo = try? await api.updateInfo()
    }

    func loadAudioSupport() async {
        audioSupport = try? await api.audioSupport()
    }

    func loadSchedule() async {
        schedule = (try? await api.prayerSchedule()) ?? []
    }

    func loadMutedWeekdays() async {
        let rows = (try? await api.mutedWeekdays()) ?? []
        mutedWeekdays = Dictionary(uniqueKeysWithValues: rows.map { ($0.weekday, $0.muted) })
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
        if let newState = try? await api.togglePrayerCheck(date: selectedDateStr, prayer: name) {
            prayerChecks[name] = newState
        }
    }

    func toggleActivity(_ name: String) async {
        guard !isFutureDate else { return }
        if let newState = try? await api.toggleDailyActivity(date: selectedDateStr, activity: name) {
            activityChecks[name] = newState
        }
    }

    func muteNext() async {
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
        try? await api.setScheduleCell(prayer: prayer, day: day, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    func bulkSchedulePrayer(_ prayer: String, _ enabled: Bool) async {
        try? await api.bulkSchedule(type: "prayer", target: prayer, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    func bulkScheduleDay(_ day: Int, _ enabled: Bool) async {
        try? await api.bulkSchedule(type: "day", target: day, enabled: enabled)
        await loadSchedule()
        await refreshMuteState()
    }

    // MARK: - Settings actions

    func updateSetting(_ key: String, _ value: String) async {
        try? await api.setSetting(key, value)
        settings[key] = value
        if key == "ics_url" {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await loadDay()
        }
    }

    func forceUpdatePrayers() async -> String {
        let r = try? await api.updatePrayers()
        await loadDay(); await loadNextPrayer(); await loadUpdateInfo()
        return r?.message ?? "Updated"
    }

    func resetChecks() async {
        _ = try? await api.resetPrayerChecks()
        await loadDay()
    }

    func restoreDefaults() async {
        _ = try? await api.restoreDefaults()
        await boot()
    }

    func importConfig(_ csv: String) async -> String {
        let r = try? await api.importSettings(csv: csv)
        await boot()
        return r?.message ?? "Imported"
    }

    func permanentSilence() async {
        _ = try? await api.permanentSilence()
        await loadSchedule(); await loadSettings(); await refreshMuteState()
    }

    // MARK: - Audio triggers (5s polling)

    private func initializeLastPlayedPrayer() async {
        // Prevent the athan from firing right after launch (web parity).
        let todayPs = (try? await api.prayers(date: todayStr)) ?? []
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
            if let url = api.athanURL(file) {
                audio.play(url: url, banner: "Athan calling...", isPrayer: true)
            }
        }
    }

    private func checkQuran() async {
        guard let r = try? await api.checkFridayQuran() else { return }
        if r.serverPlayingQuran == true && audio.bannerText == nil {
            audio.bannerText = "Al Kahf Sourat recitation playing"
        }
        if r.shouldPlay == true, r.type == "friday_quran", let file = r.quranFile {
            let key = "\(todayStr)-quran"
            guard key != lastPlayedQuran else { return }
            lastPlayedQuran = key
            if let url = api.quranURL(file) {
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

    func stopAllAudio() async {
        audio.stopLocal()
        try? await api.stopAudio()
    }

    func testAthanWeb() {
        let file = settings["audio_file"] ?? "Masjid Al-Haram.mp3"
        if let url = api.athanURL(file) {
            audio.play(url: url, banner: "Athan calling (app)...")
        }
    }

    func testQuranWeb() {
        let file = settings["friday_quran_file"] ?? "Sourat Al Kahf - Hani Arrifai.mp3"
        if let url = api.quranURL(file) {
            audio.play(url: url, banner: "Quran reciting (30s preview)...", limit30s: true)
        }
    }

    func testAthanServer() async {
        _ = try? await api.testAthanServer()
        audio.bannerText = "Athan calling (server)..."
    }

    func testQuranServer() async {
        _ = try? await api.testQuranServer()
        audio.bannerText = "Quran reciting (30s server preview)..."
    }

    /// "Listen to Sourat Al Kahf now"
    func playFullQuran() async {
        let output = settings["audio_output"] ?? "both"
        let file = settings["friday_quran_file"] ?? ""
        if output == "server" || output == "both" {
            _ = try? await api.triggerFridayQuran()
            if output == "server" { audio.bannerText = "Al Kahf Sourat recitation playing" }
        }
        if output == "browser" || output == "both", let url = api.quranURL(file) {
            audio.play(url: url, banner: "Al Kahf Sourat recitation playing")
        }
    }

    // MARK: - Quick Pray data (14-day window)

    func quickFillRows() async -> (days: [(date: String, label: String)], checks: [String: [String: Int]]) {
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
    func goToday() { selectedDate = serverNow; Task { await loadDay() } }
    func goToDate(_ d: Date) { selectedDate = d; Task { await loadDay() } }

    private func shiftDay(_ delta: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
        Task { await loadDay() }
    }

    // MARK: - Prayer row state (displayPrayers in app.js)

    func isPastPrayer(_ p: Prayer) -> Bool {
        selectedDateStr < todayStr || (isViewingToday && p.prayer_time < currentTimeStr)
    }
}
