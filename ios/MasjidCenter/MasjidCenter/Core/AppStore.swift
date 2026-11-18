import Foundation
import SwiftUI
import Combine
import CoreLocation

// MARK: - AppStore — replicates app.js behavior against the same REST API.

@MainActor
final class AppStore: ObservableObject {

    // MARK: Configuration
    @Published var serverBase: String {
        didSet {
            UserDefaults.standard.set(serverBase, forKey: "serverBaseURL")
            api = APIClient(base: serverBase)
            bootTask = Task { await boot() }
        }
    }
    /// Last boot started by a server address change — first-launch setup awaits it.
    var bootTask: Task<Void, Never>?
    /// True while first-launch setup is fetching data: the main screen stays hidden (loader in SetupView).
    @Published var settingUp = false
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

    /// Transient: true while a horizontal swipe is in progress → buttons on the
    /// main page must ignore the release (the touch was a gesture, not a tap).
    var blockTaps = false

    /// Transient: after the user stops audio, the Pi can keep reporting
    /// serverPlayingQuran=true for a few seconds → don't let the poll re-show
    /// the banner until the server actually confirms playback stopped.
    var suppressServerBanner = false

    // MARK: Actions edit (iOS jiggle) mode — shared so taps anywhere can exit it
    @Published var actionsEditMode = false
    /// Eats the FIRST tap after entering jiggle: it's the release of the
    /// long-press that opened it, not a deliberate "tap outside".
    private var jiggleTapGuard = false
    private var jiggleTimer: Task<Void, Never>? = nil
    private var jiggleGuardTask: Task<Void, Never>? = nil

    func enterJiggle() {
        actionsEditMode = true
        jiggleTapGuard = true
        jiggleTimer?.cancel()
        // Auto-exit after 20s.
        jiggleTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            self?.actionsEditMode = false
            self?.jiggleTapGuard = false
        }
        jiggleGuardTask?.cancel()
        // The guard must not eat a real later tap if the release never fired one.
        jiggleGuardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.jiggleTapGuard = false
        }
    }

    /// Exits jiggle mode ("tap anywhere else"). The tap that released the
    /// entering long-press is ignored via `jiggleTapGuard`.
    func exitJiggle(force: Bool = false) {
        if !force && jiggleTapGuard { jiggleTapGuard = false; return }
        actionsEditMode = false
        jiggleTapGuard = false
        jiggleTimer?.cancel()
        jiggleGuardTask?.cancel()
    }

    /// Global frame of the actions row — taps inside it are edit controls, not
    /// "tap outside" gestures (kept up to date by DailyActivitiesView).
    var activityRowFrame: CGRect = .zero

    // MARK: Location permission at first launch
    // The app must ask once even when the setup screen is skipped (server-mode
    // installs never see SetupView) — otherwise it never shows up under iOS
    // Settings → Location and the locate buttons have nothing to request.

    private var askedLocationPermission = false
    /// Kept alive for the prompt's lifetime — releasing the manager drops it.
    private var permissionManager: CLLocationManager?

    /// Requests "when in use" access once per app lifetime. Called when the
    /// scene becomes active — iOS silently drops prompts asked while the app
    /// is still activating. Never prompts when the app is already configured:
    /// location access is only asked by the "use my location" buttons.
    func requestLocationPermissionOnce() {
        guard !setupComplete else { return }
        guard !askedLocationPermission else { return }
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("-resetLocal"), !args.contains("-serverBase") else { return }
        askedLocationPermission = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let m = CLLocationManager()
            guard m.authorizationStatus == .notDetermined else { return }
            permissionManager = m
            m.requestWhenInUseAuthorization()
        }
    }

    /// Set by the unchecked Tasbih action tile → ContentView slides the counter in.
    /// A monotonic counter (not a flag): onChange fires on every increment.
    @Published var tasbihOpenTick = 0
    func requestTasbih() { tasbihOpenTick += 1 }

    /// City shown in Settings when the server only knows "Unknown": the coords
    /// are embedded in the ICS URL (x=…:y=…) → reverse-geocode them once.
    @Published var geoCityName: String? = nil
    private var geoCityResolvedFor = ""

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

    /// Server address as shown to the user: "192.168.1.50" (scheme and default port hidden).
    var serverDisplayHost: String {
        ServerURL.display(serverBase)
    }

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
        Task { await cacheAllChecksFromServer() }
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
                    self.checkQuranLocal()
                } else if !self.connected {
                    self.checkAthanLocal()
                    self.checkQuranLocal()
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
        await resolveGeoCityIfNeeded()
    }

    /// Server-mode city name: from update-info, else reverse-geocoded from the
    /// coordinates embedded in the configured ICS URL (fixes "Unknown").
    var serverCityName: String {
        let n = updateInfo?.city_name ?? ""
        if !n.isEmpty && n != "Unknown" && n != "Not configured" { return n }
        return geoCityName ?? (updateInfo == nil ? "Loading..." : "—")
    }

    private func resolveGeoCityIfNeeded() async {
        guard !isStandalone, geoCityName == nil, geoCityResolvedFor != settings["ics_url"] ?? "",
              let ics = settings["ics_url"],
              let m = try? NSRegularExpression(pattern: "x=(-?[0-9]+\\.?[0-9]*):y=(-?[0-9]+\\.?[0-9]*)")
                  .firstMatch(in: ics, range: NSRange(ics.startIndex..., in: ics)),
              let xr = Range(m.range(at: 1), in: ics), let yr = Range(m.range(at: 2), in: ics),
              let lat = Double(ics[xr]), let lon = Double(ics[yr]) else { return }
        geoCityResolvedFor = ics
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: lon)).first {
            geoCityName = mark.locality ?? mark.administrativeArea
        }
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
        if let rows = try? await api.mutedWeekdays() {
            mutedWeekdays = Dictionary(rows.map { ($0.weekday, $0.muted) }, uniquingKeysWith: { _, new in new })
            local.snap.mutedWeekdays = mutedWeekdays
            local.save()
        } else {
            mutedWeekdays = local.snap.mutedWeekdays   // offline → last known values
        }
    }

    func loadRamadan() async {
        if let rows = try? await api.ramadanDates() {
            ramadanDates = Set(rows.map { $0.gregorian_date })
            local.snap.ramadanDates = rows.map { $0.gregorian_date }
            local.save()
        } else {
            ramadanDates = Set(local.snap.ramadanDates)
        }
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

    /// Configuration backup in the web CSV format: from the server API when it
    /// is reachable, generated locally otherwise — either file loads on the Pi.
    func exportConfigCSV() async -> String? {
        if isStandalone || !connected { return local.exportConfigCSV() }
        return try? await api.exportSettingsCSV()
    }

    /// Restores a web-format backup: pushed to the server when reachable,
    /// applied to the local snapshot otherwise (same merge rules as the Pi).
    func importConfig(_ csv: String) async -> String {
        if isStandalone || !connected {
            let n = local.importConfigCSV(csv)
            guard n > 0 else { return "Invalid or empty backup file" }
            await loadDay()
            rescheduleNotifications()
            return "Imported \(n) entries"
        }
        guard let r = try? await api.importSettings(csv: csv) else { return "Import failed" }
        await boot()
        return r.message ?? "Imported"
    }

    /// Full iOS-side reset: wipes every local datum (LocalStore snapshot,
    /// UserDefaults incl. the server address, pending notifications) and every
    /// in-memory field, without touching the server. setupComplete flips to
    /// false → SetupView replaces the main screen right away, no relaunch needed.
    func resetApp() {
        stopLoops()
        audio.stopLocal()
        local.reset()
        if let bid = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bid)
        }
        rescheduleNotifications()           // clears pending requests; notifications are off in the fresh snap
        selectedDate = Date()
        prayers = []
        prayerChecks = [:]
        activityChecks = [:]
        nextPrayer = nil
        cardVisible = false
        cardDateOnly = false
        settings = [:]
        updateInfo = nil
        audioSupport = nil
        skipNext = false
        mutedWeekdays = [:]
        schedule = []
        ramadanDates = []
        audioFiles = []
        quranFiles = []
        audioDevices = []
        connected = false
        loadingPrayers = false
        probing = false
        toast = nil
        muteAlertManual = false
        muteAlertGeneral = false
        actionsEditMode = false
        geoCityName = nil
        ishaPassedSync = false
        serverTimeInfo = nil
        serverOffset = 0
        settingUp = false
        booted = false
        serverBase = ""                     // setupComplete flips → SetupView; didSet → fresh API client
        objectWillChange.send()
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
        if r.serverPlayingQuran == true {
            // Suppressed right after a user stop: the Pi's flag stays true for a
            // few seconds after the kill — don't resurrect the banner.
            if !suppressServerBanner && !audio.isPlaying {
                audio.showServerBanner("Al Kahf Sourat recitation playing", duration: 15)
            }
        } else {
            suppressServerBanner = false     // server confirmed playback ended
            if audio.serverPlaying, audio.bannerText == "Al Kahf Sourat recitation playing" {
                audio.clearServerBanner()
            }
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
        suppressServerBanner = true   // don't let the 5s poll re-show the banner
        if !isStandalone && configured { try? await api.stopAudio() }
    }

    func testAthanWeb() {
        if isStandalone || !connected { playLocalAthan(); return }
        let file = settings["audio_file"] ?? "Masjid Al-Haram.mp3"
        if let url = api.athanURL(file) {
            audio.play(url: url, banner: "Athan calling (app)...")
        }
    }

    func testQuranWeb() {
        // No server reachability → bundled file; online → 30s server preview.
        if isStandalone || !connected { playLocalQuran(); return }
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
        if isStandalone || !connected { playLocalQuran(); return }
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

    // MARK: - Prayer Overview data (14-day window)

    func prayerOverviewRows() async -> (days: [(date: String, label: String)], checks: [String: [String: Int]]) {
        if isStandalone || !connected { return prayerOverviewRowsLocal() }
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

    /// Is the selected past day incomplete (drives Prayer Overview button swap)?
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
