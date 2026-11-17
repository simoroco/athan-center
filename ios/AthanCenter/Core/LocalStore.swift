import Foundation

// MARK: - LocalStore — on-device persistence for standalone + offline mode.
// Mirrors the server DB subsets the app needs when the Pi is unreachable.

enum AppMode: String, Codable {
    case standalone   // no server — location + ICS only
    case server       // server-primary, local cache + offline queue
}

/// Custom user-defined tracked action (iOS only — never synced to server).
struct TrackedAction: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String            // emoji glyph
    var counter: Bool = false   // false = tri-state (unchecked → orange → blue), true = numeric count
    var order: Int = 0
}

/// Flattened view of a tracked action (builtin or custom) for the UI.
struct ActionItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let isAsset: Bool
    let counter: Bool
    let builtin: Bool
}

/// A write made while offline in server mode, replayed on reconnect.
struct PendingOp: Codable, Hashable {
    enum Kind: String, Codable { case prayerCheck, activity, muteNext, setting }
    let kind: Kind
    let date: String?       // for checks/activities
    let name: String        // prayer/activity name or setting key
    let value: Int          // desired state / activity checked (setting uses value=0)
    let text: String?       // setting value
}

struct LocalSnapshot: Codable {
    var mode: AppMode = .standalone
    var cityName: String = ""
    var icsUrl: String = ""
    var lat: Double = 0
    var lon: Double = 0
    var lastIcsFetch: String = ""                     // YYYY-MM-DD
    var prayers: [String: [Prayer]] = [:]             // date -> prayers
    var checks: [String: [String: Int]] = [:]         // date -> prayer -> 0/2/1
    var activities: [String: [String: Int]] = [:]     // date -> activity -> 0/2/1 (builtins + customs)
    var customActions: [TrackedAction] = []
    var hiddenBuiltins: [String] = []                 // built-in action names hidden via the jiggle X
    var actionOrder: [String] = []                    // tile order (drag & drop); empty = builtins then customs
    var settings: [String: String] = [:]              // local overrides / standalone settings
    var pendingOps: [PendingOp] = []
    var schedule: [ScheduleEntry] = []                // standalone schedule matrix
    var mutedWeekdays: [Int: Int] = [:]               // cached from server (continuity)
    var ramadanDates: [String] = []                   // cached from server (continuity)
    var skipNextDate: String = ""
    var notificationsEnabled: Bool = false
    var tasbihTarget: Int = 11
    var tasbihDoneDate: String = ""                   // last date tasbih target reached
}

final class LocalStore {
    static let shared = LocalStore()
    var snap = LocalSnapshot()

    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("athan-local.json")
    }

    private init() { load() }

    func load() {
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(LocalSnapshot.self, from: data) {
            snap = s
        }
        ensureDefaults()
    }

    /// Wipes every local datum (UI tests / "fresh install" simulation).
    func reset() {
        try? FileManager.default.removeItem(at: url)
        snap = LocalSnapshot()
        ensureDefaults()
    }


    func save() {
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func ensureDefaults() {
        if snap.schedule.isEmpty {
            var rows: [ScheduleEntry] = []
            for day in 0...6 {
                for p in AC.mainPrayers {
                    rows.append(ScheduleEntry(id: nil, prayer_name: p, day_of_week: day, enabled: 1))
                }
            }
            snap.schedule = rows
        }
        for k in ["athan_enabled": "1", "friday_quran_enabled": "0", "dark_mode": "0",
                  "play_on_page_load": "0", "audio_output": "app", "skip_next_athan": "0",
                  "audio_file": "default_athan.mp3", "ios_audio_enabled": "1",
                  "friday_quran_file": AC.bundledQurans[0], "friday_quran_time": "07:00"] {
            if snap.settings[k.key] == nil { snap.settings[k.key] = k.value }
        }
        if snap.customActions.isEmpty {
            snap.customActions = []   // builtins live in AC.activities, customs appended
        }
        save()
    }

    /// Re-run after a manual reset to restore the default schedule matrix.
    func ensureDefaultsAfterReset() { ensureDefaults() }

    // MARK: Checks

    func prayerState(_ date: String, _ name: String) -> Int { snap.checks[date]?[name] ?? 0 }
    func setPrayerState(_ date: String, _ name: String, _ v: Int) {
        snap.checks[date, default: [:]][name] = v; save()
    }
    func activityState(_ date: String, _ name: String) -> Int { snap.activities[date]?[name] ?? 0 }
    func setActivityState(_ date: String, _ name: String, _ v: Int) {
        snap.activities[date, default: [:]][name] = v; save()
    }

    // MARK: Pending ops (offline queue — server mode only)

    func enqueue(_ op: PendingOp) {
        snap.pendingOps.append(op); save()
    }
    func clearPending() { snap.pendingOps = []; save() }

    // MARK: Schedule helpers (standalone)

    func scheduleEnabled(_ prayer: String, _ day: Int) -> Bool {
        snap.schedule.first { $0.prayer_name == prayer && $0.day_of_week == day }?.enabled == 1
    }
    func setSchedule(_ prayer: String, _ day: Int, _ enabled: Bool) {
        if let i = snap.schedule.firstIndex(where: { $0.prayer_name == prayer && $0.day_of_week == day }) {
            snap.schedule[i].enabled = enabled ? 1 : 0
        }
        save()
    }
    func bulkSchedule(prayer: String? = nil, day: Int? = nil, enabled: Bool) {
        for i in snap.schedule.indices {
            if let p = prayer, snap.schedule[i].prayer_name != p { continue }
            if let d = day, snap.schedule[i].day_of_week != d { continue }
            snap.schedule[i].enabled = enabled ? 1 : 0
        }
        save()
    }

    // MARK: - Backup CSV (web-compatible: same rows as server /api/settings/export).
    // iOS-only rows (custom_action / hidden_builtin / action_order) are skipped
    // by the web importer, which ignores unknown types — the file stays fully
    // loadable on the Pi.

    func exportConfigCSV() -> String {
        var csv = "type,key,value\n"
        for (k, v) in snap.settings.sorted(by: { $0.key < $1.key }) {
            csv += "setting,\(k),\(v.replacingOccurrences(of: "\n", with: " "))\n"
        }
        csv += "setting,tasbih_target,\(snap.tasbihTarget)\n"
        for (w, m) in snap.mutedWeekdays.sorted(by: { $0.key < $1.key }) {
            csv += "weekday_mute,\(w),\(m)\n"
        }
        for s in snap.schedule {
            csv += "prayer_schedule,\(s.prayer_name)-\(s.day_of_week),\(s.enabled)\n"
        }
        csv += "skip_next,skip,\(snap.skipNextDate.isEmpty ? 0 : 1)\n"
        for (date, checks) in snap.checks.sorted(by: { $0.key < $1.key }) {
            for (name, v) in checks.sorted(by: { $0.key < $1.key }) where v > 0 {
                csv += "prayer_check,\(date)::\(name),\(v)|\n"
            }
        }
        for (date, acts) in snap.activities.sorted(by: { $0.key < $1.key }) {
            for (name, v) in acts.sorted(by: { $0.key < $1.key }) where v > 0 {
                csv += "daily_activity,\(date)::\(name),\(v)|\n"
            }
        }
        for a in snap.customActions {
            if let d = try? JSONEncoder().encode(a), let j = String(data: d, encoding: .utf8) {
                csv += "custom_action,\(a.id),\(j)\n"
            }
        }
        for n in snap.hiddenBuiltins {
            csv += "hidden_builtin,\(n),1\n"
        }
        if !snap.actionOrder.isEmpty {
            csv += "action_order,ids,\(snap.actionOrder.joined(separator: ";"))\n"
        }
        return csv
    }

    /// Parses a web backup CSV into the local snapshot (merge semantics, same as
    /// the server import: INSERT OR REPLACE). Returns the number of applied rows.
    @discardableResult
    func importConfigCSV(_ csv: String) -> Int {
        let lines = csv.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return 0 }
        let headers = lines[0].components(separatedBy: ",")
        guard headers.count >= 3, headers[0] == "type", headers[1] == "key", headers[2] == "value" else { return 0 }

        var imported = 0
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3 else { continue }
            let type = parts[0], key = parts[1]
            let value = parts.dropFirst(2).joined(separator: ",")   // values may contain commas
            switch type {
            case "setting":
                snap.settings[key] = value
                if key == "tasbih_target", let n = Int(value) { snap.tasbihTarget = n }
                imported += 1
            case "prayer_setting":   // legacy → enable/disable the prayer for all 7 days
                let en = Int(value) ?? 0
                bulkSchedule(prayer: key, enabled: en != 0)
                imported += 1
            case "weekday_mute":
                if let w = Int(key), let m = Int(value) { snap.mutedWeekdays[w] = m; imported += 1 }
            case "prayer_schedule":   // key = "name-dow" — split on the LAST '-' (names may contain '-')
                if let i = key.lastIndex(of: "-"), let dow = Int(key[key.index(after: i)...]) {
                    let name = String(key[..<i])
                    let en = Int(value) ?? 1
                    if let idx = snap.schedule.firstIndex(where: { $0.prayer_name == name && $0.day_of_week == dow }) {
                        snap.schedule[idx].enabled = en
                    } else {
                        snap.schedule.append(ScheduleEntry(id: nil, prayer_name: name, day_of_week: dow, enabled: en))
                    }
                    imported += 1
                }
            case "skip_next" where key == "skip":
                snap.skipNextDate = (Int(value) ?? 0) != 0 ? DateUtil.dateString(Date()) : ""
                imported += 1
            case "prayer_check", "daily_activity":
                let (date, rawName) = Self.parseCompositeKey(key)
                let name = type == "daily_activity" ? Self.mapActivityName(rawName) : rawName
                // value = "checked|checked_at" — a bare timestamp (legacy) means checked=1
                let state = value.contains("|") ? (Int(value.split(separator: "|").first ?? "1") ?? 1) : 1
                if type == "prayer_check" { snap.checks[date, default: [:]][name] = state }
                else { snap.activities[date, default: [:]][name] = state }
                imported += 1
            case "custom_action":
                if let d = value.data(using: .utf8), let a = try? JSONDecoder().decode(TrackedAction.self, from: d) {
                    if let i = snap.customActions.firstIndex(where: { $0.id == a.id }) { snap.customActions[i] = a }
                    else { snap.customActions.append(a) }
                    imported += 1
                }
            case "hidden_builtin":
                if !snap.hiddenBuiltins.contains(key) { snap.hiddenBuiltins.append(key); imported += 1 }
            case "action_order" where key == "ids":
                snap.actionOrder = value.split(separator: ";").map(String.init)
                imported += 1
            default: break   // unknown row types are skipped, like the web importer
            }
        }
        save()
        return imported
    }

    /// Splits "date::name" (new format) or "YYYY-MM-DD-name" (legacy) — same
    /// rules as the server's parseCompositeKey.
    private static func parseCompositeKey(_ key: String) -> (date: String, name: String) {
        if key.contains("::") {
            let parts = key.components(separatedBy: "::")
            return (parts[0], parts.dropFirst().joined(separator: "::"))
        }
        let parts = key.components(separatedBy: "-")
        return (parts.prefix(3).joined(separator: "-"), parts.dropFirst(3).joined(separator: "-"))
    }

    /// Legacy activity labels → current names (same map as the server import).
    private static func mapActivityName(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        let legacy = ["Read Coran": "Coran", "Tasbih & Dikr": "Tasbih", "Tasbih and Dikr": "Tasbih",
                      "Dikr": "Tasbih", "Nawafil prayers": "Nawafil", "Optional prayers": "Nawafil"]
        return legacy[t] ?? t
    }
}
