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
    var settings: [String: String] = [:]              // local overrides / standalone settings
    var pendingOps: [PendingOp] = []
    var schedule: [ScheduleEntry] = []                // standalone schedule matrix
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
                  "audio_file": "default_athan.mp3", "ios_audio_enabled": "1"] {
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
}
