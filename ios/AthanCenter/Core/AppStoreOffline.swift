import Foundation
import SwiftUI
import Combine

// MARK: - Standalone + offline mode, custom actions, tasbih, notifications.
// Rules: standalone = everything local (ICS times). Server mode = server
// primary; on failure serve LocalStore cache + queue writes; on reconnect
// replay queue then reload (server wins conflicts).

extension AppStore {

    var local: LocalStore { LocalStore.shared }

    var isStandalone: Bool { local.snap.mode == .standalone }
    var standaloneReady: Bool { !local.snap.icsUrl.isEmpty && !local.snap.prayers.isEmpty }
    /// Whether first-launch setup (location OR server) is complete.
    var setupComplete: Bool { isStandalone ? standaloneReady : configured }

    // MARK: Setup / mode switching

    /// Standalone setup: store location + ICS URL, fetch prayers, apply.
    func configureStandalone(city: String, lat: Double, lon: Double, tz: String) async -> Bool {
        let url = ICSClient.icsURL(city: city, lat: lat, lon: lon, tz: tz)
        guard let map = try? await ICSClient.fetch(urlString: url), !map.isEmpty else { return false }
        local.snap.mode = .standalone
        local.snap.cityName = city
        local.snap.icsUrl = url
        local.snap.lat = lat
        local.snap.lon = lon
        local.snap.prayers = map
        local.snap.lastIcsFetch = todayStr
        local.save()
        serverBase = ""                    // no server in standalone mode
        await bootStandalone()
        return true
    }

    /// Change the city (Settings → Location). Standalone: ICS is fetched directly from the new link.
    /// Server mode: the new link is pushed to the server (single source of truth).
    func changeLocation(city: String, lat: Double, lon: Double, tz: String) async -> Bool {
        let url = ICSClient.icsURL(city: city, lat: lat, lon: lon, tz: tz)
        if isStandalone {
            guard let map = try? await ICSClient.fetch(urlString: url), !map.isEmpty else { return false }
            local.snap.cityName = city
            local.snap.icsUrl = url
            local.snap.lat = lat
            local.snap.lon = lon
            local.snap.prayers = map
            local.snap.lastIcsFetch = todayStr
            local.save()
            settings["ics_url"] = url
            loadDayLocal()
            rescheduleNotifications()
            return true
        }
        guard connected else { return false }
        await updateSetting("ics_url", url)
        _ = await forceUpdatePrayers()
        return true
    }

    /// Leave the server and go back to the standalone (on-device) mode.
    func switchToStandalone() {
        local.snap.mode = .standalone
        local.save()
        serverBase = ""
        connected = false
        if !standaloneReady { objectWillChange.send() }   // SetupView takes over
    }

    /// Switch to server mode (from Settings → Connect to server).
    func connectToServer(_ base: String) {
        local.snap.mode = .server
        local.save()
        serverBase = base                  // didSet -> boot()
    }

    /// Standalone boot — no network calls except ICS refresh.
    func bootStandalone() async {
        booted = true
        settings = local.snap.settings
        settings["ics_url"] = local.snap.icsUrl     // shown in the Location settings field
        schedule = local.snap.schedule
        prayers = local.snap.prayers[selectedDateStr] ?? []
        prayerChecks = local.snap.checks[selectedDateStr] ?? [:]
        activityChecks = local.snap.activities[selectedDateStr] ?? [:]
        // Same-minute dedup after relaunch (web parity with lastPlayed).
        if let last = (local.snap.prayers[todayStr] ?? [])
            .last(where: { AC.mainPrayers.contains($0.prayer_name) && $0.prayer_time <= currentTimeStr }) {
            markPlayed("\(todayStr)-\(last.prayer_name)")
        }
        nextPrayer = localNextPrayer()
        updateCardForLocal()
        startLoops()
        rescheduleNotifications()
        Task { await refreshICSIfStale() }
    }

    /// Re-download ICS once a day or when near the end of cached data.
    func refreshICSIfStale(force: Bool = false) async {
        guard isStandalone else { return }
        if let override = settings["ics_url"], !override.isEmpty, override != local.snap.icsUrl {
            local.snap.icsUrl = override
            local.save()
        }
        guard !local.snap.icsUrl.isEmpty else { return }
        let stale = local.snap.lastIcsFetch < todayStr
        let maxDate = local.snap.prayers.keys.max() ?? ""
        let horizon = DateUtil.dateString(
            Calendar.current.date(byAdding: .day, value: 14, to: serverNow) ?? serverNow)
        guard force || stale || maxDate < horizon else { return }
        if let map = try? await ICSClient.fetch(urlString: local.snap.icsUrl), !map.isEmpty {
            local.snap.prayers = map
            local.snap.lastIcsFetch = todayStr
            local.save()
            await loadDay()
            rescheduleNotifications()
        }
    }

    // MARK: Local data paths

    /// Prayers for a date: local map in standalone/offline, API when online.
    func prayersOn(_ dateStr: String) async -> [Prayer] {
        if isStandalone || !connected { return local.snap.prayers[dateStr] ?? [] }
        return (try? await api.prayers(date: dateStr)) ?? local.snap.prayers[dateStr] ?? []
    }

    func localNextPrayer() -> Prayer? {
        let now = currentTimeStr
        let today = local.snap.prayers[todayStr] ?? []
        if let p = today.first(where: { AC.mainPrayers.contains($0.prayer_name) && $0.prayer_time > now }) {
            return p
        }
        return (local.snap.prayers[tomorrowStr] ?? [])
            .first(where: { AC.mainPrayers.contains($0.prayer_name) })
    }

    /// Card visibility without API (mirrors loadDay card rules).
    func updateCardForLocal() {
        if isViewingToday {
            cardVisible = nextPrayer != nil
            cardDateOnly = false
        } else if isViewingTomorrow {
            let isha = (local.snap.prayers[todayStr] ?? [])
                .first(where: { $0.prayer_name == "Isha" })
            if let isha, currentTimeStr > isha.prayer_time {
                cardVisible = nextPrayer != nil
                cardDateOnly = false
            } else {
                cardVisible = true
                cardDateOnly = true
            }
        } else {
            cardVisible = true
            cardDateOnly = true
        }
    }

    func loadDayLocal() {
        prayers = local.snap.prayers[selectedDateStr] ?? []
        prayerChecks = local.snap.checks[selectedDateStr] ?? [:]
        activityChecks = local.snap.activities[selectedDateStr] ?? [:]
        nextPrayer = localNextPrayer()
        updateCardForLocal()
        skipNext = local.snap.skipNextDate == todayStr
        refreshMuteStateLocal()
    }

    /// Cache today's server data so offline mode has something to show.
    func cacheDayToLocal(date: String, prayers: [Prayer], checks: [String: Int], acts: [String: Int]) {
        local.snap.prayers[date] = prayers
        local.snap.checks[date] = checks
        local.snap.activities[date] = acts
        local.save()
    }

    // MARK: Local toggles (cycle 0 -> 2 -> 1 -> 0 like the server)

    func localNextCycle(_ v: Int) -> Int { v == 0 ? 2 : (v == 2 ? 1 : 0) }

    // MARK: Offline queue + sync (server wins on conflict)

    /// Connectivity probe — runs every 5s while offline (8s request timeout, never re-entrant).
    func probeConnectivity() async {
        guard !isStandalone, configured, !probing else { return }
        probing = true
        defer { probing = false }
        if await syncTime() {
            if !connected {
                connected = true
                await resyncFromServer()
            }
        } else if connected {
            markOffline()
        }
    }

    /// App returned to foreground: refresh clock-dependent state, resync, reschedule notifications.
    func appDidBecomeActive() async {
        if isStandalone {
            await loadDay()
            await refreshICSIfStale()
        } else if configured {
            await probeConnectivity()
            if connected { await syncTime(); await loadDay() }
        }
        rescheduleNotifications()
    }

    /// Cache the next days of prayer times (offline mode + notifications in server mode).
    func cacheUpcomingFromServer(days: Int = 10) async {
        guard !isStandalone, connected else { return }
        for i in 0..<days {
            guard let d = Calendar.current.date(byAdding: .day, value: i, to: serverNow) else { continue }
            let ds = DateUtil.dateString(d)
            if let p = try? await api.prayers(date: ds), !p.isEmpty { local.snap.prayers[ds] = p }
        }
        local.save()
        rescheduleNotifications()
    }

    /// Reconnect: push queued writes, then reload — server is authoritative.
    func resyncFromServer() async {
        for op in local.snap.pendingOps {
            switch op.kind {
            case .prayerCheck:
                await setPrayerViaToggles(date: op.date ?? todayStr, name: op.name, target: op.value)
            case .activity:
                await setActivityViaToggles(date: op.date ?? todayStr, name: op.name, target: op.value)
            case .muteNext:
                _ = try? await api.muteNextAthan()
            case .setting:
                _ = try? await api.setSetting(op.name, op.text ?? "")
            }
        }
        local.clearPending()
        await boot()                        // server state wins
    }

    /// The API only exposes tri-state toggles — toggle until the target state.
    private func setPrayerViaToggles(date: String, name: String, target: Int) async {
        let cur = ((try? await api.prayerChecks(date: date)) ?? [])
            .first(where: { $0.prayer_name == name })?.checked ?? 0
        var s = cur
        for _ in 0..<3 where s != target {
            s = (try? await api.togglePrayerCheck(date: date, prayer: name)) ?? s
        }
    }
    private func setActivityViaToggles(date: String, name: String, target: Int) async {
        let cur = ((try? await api.dailyActivities(date: date)) ?? [])
            .first(where: { $0.activity_name == name })?.checked ?? 0
        var s = cur
        for _ in 0..<3 where s != target {
            s = (try? await api.toggleDailyActivity(date: date, activity: name)) ?? s
        }
    }

    // MARK: Standalone athan trigger (runs in the 5s loop)

    func checkAthanLocal() {
        guard isStandalone || !connected else { return }
        guard settings["athan_enabled"] == "1" else { return }
        guard settings["ios_audio_enabled"] != "0" else { return }
        guard !skipNext else { return }
        let now = currentTimeStr
        let dow = DateUtil.scheduleDay(serverNow)
        for p in (local.snap.prayers[todayStr] ?? []) where AC.mainPrayers.contains(p.prayer_name) {
            guard p.prayer_time == now else { continue }
            let key = "\(todayStr)-\(p.prayer_name)"
            guard key != lastPlayedPrayerKey else { continue }
            guard local.scheduleEnabled(p.prayer_name, dow) else { continue }
            markPlayed(key)
            playLocalAthan()
        }
    }

    /// Plays the bundled athan (standalone) — same UX as server playback.
    func playLocalAthan() {
        if let file = settings["audio_file"],
           let url = Bundle.main.url(forResource: file.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3") {
            audio.play(url: url, banner: "Athan calling...", isPrayer: true)
        } else if let url = Bundle.main.url(forResource: "default_athan", withExtension: "mp3") {
            audio.play(url: url, banner: "Athan calling...", isPrayer: true)
        }
    }

    var lastPlayedPrayerKey: String {
        get { UserDefaults.standard.string(forKey: "lastAthanLocal") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastAthanLocal") }
    }
    func markPlayed(_ key: String) { lastPlayedPrayerKey = key }

    // MARK: Standalone mute banners

    func refreshMuteStateLocal() {
        skipNext = local.snap.skipNextDate == todayStr
        ishaPassedSync = (local.snap.prayers[todayStr] ?? [])
            .first(where: { $0.prayer_name == "Isha" })
            .map { currentTimeStr > $0.prayer_time } ?? false
        muteAlertManual = false
        muteAlertGeneral = false
        guard isViewingToday || (isViewingTomorrow && ishaPassedSync) else { return }
        if skipNext {
            muteAlertManual = true
        } else if let np = nextPrayer {
            let day = DateUtil.scheduleDay(DateUtil.parseDate(np.date) ?? serverNow)
            if !local.scheduleEnabled(np.prayer_name, day) { muteAlertGeneral = true }
        }
    }

    func muteNextLocal() {
        local.snap.skipNextDate = todayStr
        local.save()
        skipNext = true
        muteAlertManual = true
    }

    func unmuteNextLocal() {
        local.snap.skipNextDate = ""
        local.save()
        skipNext = false
        muteAlertManual = false
    }

    // MARK: Quick Pray (local data)

    func quickFillRowsLocal() -> (days: [(date: String, label: String)], checks: [String: [String: Int]]) {
        var map: [String: [String: Int]] = [:]
        for (date, checks) in local.snap.checks {
            map[date] = checks.filter { AC.mainPrayers.contains($0.key) }
        }
        var days: [(String, String)] = []
        var lastIncomplete = 0
        for i in 0...13 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: serverNow)!
            let ds = DateUtil.dateString(d)
            let c = map[ds] ?? [:]
            if !AC.mainPrayers.allSatisfy({ (c[$0] ?? 0) >= 1 }) { lastIncomplete = i }
        }
        for i in stride(from: lastIncomplete, through: 0, by: -1) {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: serverNow)!
            days.append((DateUtil.dateString(d), DateUtil.relativeDayLabel(d, today: serverNow)))
        }
        return (days, map)
    }

    // MARK: Custom actions (iOS only — local persistence)

    /// All actions shown in the row: built-in 3 + user customs.
    var allActions: [ActionItem] {
        var list = AC.activities.map {
            ActionItem(id: $0.name, name: $0.name, icon: $0.icon, isAsset: true, counter: false, builtin: true)
        }
        list += local.snap.customActions.map {
            ActionItem(id: $0.id, name: $0.name, icon: $0.icon, isAsset: false, counter: $0.counter, builtin: false)
        }
        return list
    }

    func addAction(_ a: TrackedAction) {
        var action = a
        action.order = (local.snap.customActions.map(\.order).max() ?? 2) + 1
        local.snap.customActions.append(action)
        local.save()
        objectWillChange.send()
    }

    func updateAction(_ a: TrackedAction) {
        if let i = local.snap.customActions.firstIndex(where: { $0.id == a.id }) {
            local.snap.customActions[i] = a
            local.save()
            objectWillChange.send()
        }
    }

    func removeAction(id: String) {
        local.snap.customActions.removeAll { $0.id == id }
        for (date, _) in local.snap.activities {
            local.snap.activities[date]?.removeValue(forKey: id)
        }
        local.save()
        activityChecks = local.snap.activities[selectedDateStr] ?? activityChecks
        objectWillChange.send()
    }

    func moveAction(from: IndexSet, to: Int) {
        var arr = local.snap.customActions
        arr.move(fromOffsets: from, toOffset: to)
        for (i, _) in arr.enumerated() { arr[i].order = 10 + i }
        local.snap.customActions = arr
        local.save()
        objectWillChange.send()
    }

    /// Tri-state toggle for an action (builtin or custom non-counter).
    func toggleActionLocal(_ id: String) async {
        guard !isFutureDate else { return }
        let cur = activityChecks[id] ?? 0
        let next = localNextCycle(cur)
        let isBuiltin = AC.activities.contains { $0.name == id }
        if isStandalone || !connected || !isBuiltin {
            local.setActivityState(selectedDateStr, id, next)
            activityChecks[id] = next
            if !isStandalone && isBuiltin {
                local.enqueue(PendingOp(kind: .activity, date: selectedDateStr, name: id, value: next, text: nil))
            }
        } else if let v = try? await api.toggleDailyActivity(date: selectedDateStr, activity: id) {
            activityChecks[id] = v
            local.setActivityState(selectedDateStr, id, v)   // keep cache fresh
        }
    }

    /// Counter actions: tap +1.
    func incrementAction(_ id: String, delta: Int = 1) {
        guard !isFutureDate else { return }
        let v = max(0, (activityChecks[id] ?? 0) + delta)
        local.setActivityState(selectedDateStr, id, v)
        activityChecks[id] = v
    }

    // MARK: Tasbih

    var tasbihTarget: Int {
        get { local.snap.tasbihTarget }
        set { local.snap.tasbihTarget = newValue; local.save(); objectWillChange.send() }
    }

    var tasbihDoneToday: Bool { local.snap.tasbihDoneDate == todayStr }

    /// Called when the fullscreen counter reaches its target.
    func completeTasbih() {
        local.snap.tasbihDoneDate = todayStr
        local.save()
        // Auto-check the Tasbih activity (blue) for today.
        Task {
            if isViewingToday || selectedDateStr == todayStr {
                activityChecks["Tasbih"] = 1
            }
            local.setActivityState(todayStr, "Tasbih", 1)
            if !isStandalone && connected {
                await setActivityViaToggles(date: todayStr, name: "Tasbih", target: 1)
            }
        }
    }

    // MARK: Notifications

    var notificationsEnabled: Bool {
        get { local.snap.notificationsEnabled }
        set {
            local.snap.notificationsEnabled = newValue
            local.save()
            objectWillChange.send()
            if newValue {
                Task {
                    let granted = await NotificationManager.shared.requestAuthorization()
                    if !granted {
                        local.snap.notificationsEnabled = false
                        local.save()
                        showToast("Notifications not allowed — enable them in iOS Settings")
                    }
                    rescheduleNotifications()
                }
            } else {
                rescheduleNotifications()
            }
        }
    }

    func rescheduleNotifications() {
        NotificationManager.shared.reschedule(
            prayers: local.snap.prayers,
            scheduleEnabled: { [weak self] p, d in
                self?.local.scheduleEnabled(p, d) ?? true
            },
            enabled: local.snap.notificationsEnabled)
    }

    // MARK: iOS audio output

    /// Whether the iPhone itself should play athan/quran (independent of server/web output).
    var iosAudioEnabled: Bool {
        get { settings["ios_audio_enabled"] ?? "1" == "1" }
        set {
            settings["ios_audio_enabled"] = newValue ? "1" : "0"
            local.snap.settings["ios_audio_enabled"] = settings["ios_audio_enabled"]
            local.save()
        }
    }

    // MARK: Local statistics (standalone + custom actions)

    /// Aggregates weekly prayer/activity stats from local data — same shape as the API.
    func localWeeklyStats() -> (prayers: [WeekStat], activities: [WeekStat]) {
        var byWeek: [String: (notDone: Int, onTime: Int, late: Int)] = [:]
        var actByWeek: [String: (notDone: Int, onTime: Int, late: Int)] = [:]
        var weekDayCount: [String: Int] = [:]

        for (date, checks) in local.snap.checks {
            guard let d = DateUtil.parseDate(date) else { continue }
            let week = DateUtil.isoWeekLabel(d)
            weekDayCount[week, default: 0] += 1
            for name in AC.mainPrayers {
                switch checks[name] ?? 0 {
                case 1: byWeek[week, default: (0,0,0)].onTime += 1
                case 2: byWeek[week, default: (0,0,0)].late += 1
                default: byWeek[week, default: (0,0,0)].notDone += 1
                }
            }
        }
        for (date, acts) in local.snap.activities {
            guard let d = DateUtil.parseDate(date) else { continue }
            let week = DateUtil.isoWeekLabel(d)
            for a in allActions {
                let v = acts[a.id] ?? 0
                if a.counter {
                    if v > 0 { actByWeek[week, default: (0,0,0)].onTime += 1 }
                    else { actByWeek[week, default: (0,0,0)].notDone += 1 }
                } else {
                    switch v {
                    case 1: actByWeek[week, default: (0,0,0)].onTime += 1
                    case 2: actByWeek[week, default: (0,0,0)].late += 1
                    default: actByWeek[week, default: (0,0,0)].notDone += 1
                    }
                }
            }
        }
        func toStats(_ m: [String: (notDone: Int, onTime: Int, late: Int)],
                     total perWeek: (String) -> Int) -> [WeekStat] {
            m.keys.sorted().map { w in
                let s = m[w]!
                let total = perWeek(w)
                let done = s.onTime + s.late
                let parts = w.split(separator: "-W")
                return WeekStat(
                    week: w,
                    year: Int(parts.first ?? "0") ?? 0,
                    weekNumber: Int(parts.last ?? "0") ?? 0,
                    not_done: total - done,
                    on_time: s.onTime,
                    late: s.late,
                    total_prayers: total,
                    total_activities: nil,
                    on_time_percent: total > 0 ? String(format: "%.1f", 100.0 * Double(s.onTime) / Double(total)) : "0",
                    total_completed_percent: total > 0 ? String(format: "%.1f", 100.0 * Double(done) / Double(total)) : "0")
            }
        }
        let pray = toStats(byWeek) { w in (weekDayCount[w] ?? 0) * AC.mainPrayers.count }
        let acts = toStats(actByWeek) { w in (weekDayCount[w] ?? 0) * allActions.count }
        return (pray, acts)
    }
}
