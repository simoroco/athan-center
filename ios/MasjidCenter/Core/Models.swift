import Foundation

// MARK: - Constants (mirror app.js / server.js)

enum AC {
    /// The five main prayers as stored in DB.
    static let mainPrayers = ["Fajr | Sobh", "Dohr", "Asr", "Maghrib", "Isha"]
    /// Daily activities (name, asset image name) — hardcoded like the web app.
    /// Emoji are rasterized to assets because iOS simulator runtimes lack the color emoji font.
    static let activities: [(name: String, icon: String)] = [
        ("Coran", "emoji-coran"), ("Tasbih", "emoji-tasbih"), ("Nawafil", "emoji-nawafil")
    ]
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] // prayer_schedule: 0=Mon
    static let weekdayNamesSun = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] // JS getDay(): 0=Sun
    static let appVersion = "© 2026 Masjid Center | v7.0.0"
    static let defaultServer = "http://192.168.1.50:7777"

    /// Audio bundled into the app — athan & Quran keep working with no server
    /// at all (standalone) or while the Pi is unreachable (offline).
    static let bundledAthans = [
        "default_athan.mp3",
        "Athan - Ali Ahmed Mullah - Masjid Al-Haram.mp3",
        "Athan - Omar Hisham Al Arabi.mp3"
    ]
    static let bundledQurans = ["Sourat Al Kahf - Hani Arrifai.mp3"]

    /// getPrayerName() from app.js — normalizes ICS event names for display.
    static func displayPrayerName(_ name: String) -> String {
        let names: [String: String] = [
            "Fajr | Sobh": "Fajr | Sobh", "Dohr": "Dohr", "Asr": "Asr",
            "Maghrib": "Maghrib", "Isha": "Isha", "Sunrise": "Sunrise",
            "Sunset": "Sunset", "🌅 Sunrise": "Sunrise", "🌄 Sunset": "Sunset",
            "Tahajjud": "Tahajjud", "Qiyam": "Qiyam"
        ]
        return names[name] ?? name
    }
}

// MARK: - API models

struct Prayer: Codable, Identifiable, Hashable {
    var id: Int?
    let date: String
    let prayer_name: String
    let prayer_time: String
    /// Stable identity: locally-parsed (ICS) prayers have no DB id, so `id` can't be used in ForEach.
    var rowKey: String { "\(date)|\(prayer_name)|\(prayer_time)" }
}

struct PrayerCheck: Codable, Hashable {
    var id: Int?
    let date: String
    let prayer_name: String
    let checked: Int
    let checked_at: String?
}

struct DailyActivity: Codable, Hashable {
    var id: Int?
    let date: String
    let activity_name: String
    let checked: Int
    let checked_at: String?
}

struct ScheduleEntry: Codable, Identifiable, Hashable {
    var id: Int?
    let prayer_name: String
    let day_of_week: Int   // 0 = Monday … 6 = Sunday
    var enabled: Int
}

struct ServerTime: Codable {
    let timestamp: String
    let timestampMs: Double
    let time: String       // HH:MM:SS server local
    let date: String       // YYYY-MM-DD server local
    let timezone: String?
    let ip: String?
    let hostname: String?
}

struct UpdateInfo: Codable {
    var id: Int?
    let last_update: String?
    let prayers_count: Int
    let city_name: String?
    let next_update: String?
}

struct AudioSupport: Codable {
    let supported: Bool
    let status: String
    let message: String
    let color: String?
    let platform: String?
}

struct CheckAthanResponse: Codable {
    let shouldPlay: Bool
    let prayerName: String?
    let audioFile: String?
}

struct CheckQuranResponse: Codable {
    let shouldPlay: Bool?
    let quranFile: String?
    let type: String?
    let serverPlayingQuran: Bool?
}

struct SkipStatus: Codable { let skip: Bool }
struct MutedWeekday: Codable, Hashable { let weekday: Int; let muted: Int } // weekday: 0 = Sunday (JS getDay)
struct SuccessMessage: Codable { let success: Bool?; let message: String?; let checked: Int?; let error: String? }
struct ToggleResult: Codable { let success: Bool; let checked: Int }

struct AudioDevice: Codable, Hashable {
    let card: String
    let id: String?
    let name: String
    let displayName: String?
}
struct AudioDevicesResponse: Codable { let devices: [AudioDevice] }

struct WeekStat: Codable, Hashable {
    let week: String              // "YYYY-Www" ISO
    let year: Int
    let weekNumber: Int
    let not_done: Int
    let on_time: Int
    let late: Int
    let total_prayers: Int?
    let total_activities: Int?
    let on_time_percent: String
    let total_completed_percent: String
}
struct StatsResponse: Codable { let success: Bool; let statistics: [WeekStat] }

struct RamadanDate: Codable, Hashable { let gregorian_date: String; let hijri_year: Int }
struct RamadanResponse: Codable { let success: Bool; let ramadan_dates: [RamadanDate] }

struct ChecksRangeResponse: Codable {
    let success: Bool
    let checks: [PrayerCheck]
}

struct FridayQuranStatus: Codable {
    let enabled: Bool
    let time: String
    let file: String?
    let jobScheduled: Bool
    let isFriday: Bool
}

// MARK: - Date helpers (web parity: formatDateLocal, ISO weeks, day diff)

enum DateUtil {
    static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static let hmsFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static let shortFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd/MM"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static var isoCalendar: Calendar = {
        var c = Calendar(identifier: .iso8601); c.locale = Locale(identifier: "en_US_POSIX"); return c
    }()

    static func dateString(_ d: Date) -> String { dayFmt.string(from: d) }
    static func timeString(_ d: Date) -> String { timeFmt.string(from: d) }
    static func parseDate(_ s: String) -> Date? { dayFmt.date(from: s) }

    /// Whole days between two dates (midnight-aligned), like getDayDifference().
    static func dayDifference(_ from: Date, _ to: Date) -> Int {
        guard let a = parseDate(dateString(from)), let b = parseDate(dateString(to)) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86400).rounded())   // rounded: DST days are 23h/25h
    }

    /// ISO week label "YYYY-Www" like the web app's statistics.
    static func isoWeekLabel(_ d: Date) -> String {
        let y = isoCalendar.component(.yearForWeekOfYear, from: d)
        let w = isoCalendar.component(.weekOfYear, from: d)
        return String(format: "%04d-W%02d", y, w)
    }

    /// JS getDay(): 0 = Sunday … 6 = Saturday.
    static func jsDay(_ d: Date) -> Int {
        (Calendar.current.component(.weekday, from: d) + 6) % 7 == 0 ? 0 : Calendar.current.component(.weekday, from: d) - 1
    }

    /// prayer_schedule day_of_week: 0 = Monday … 6 = Sunday.
    static func scheduleDay(_ d: Date) -> Int {
        (jsDay(d) + 6) % 7
    }

    /// Monday-start of week like getWeekStart().
    static func weekStart(_ d: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return cal.date(from: comps) ?? d
    }

    /// getRelativeDayLabel() from app.js.
    static func relativeDayLabel(_ date: Date, today: Date) -> String {
        let diff = dayDifference(today, date)
        let weekday = AC.weekdayNamesSun[DateUtil.jsDay(date)]
        if diff == 0 { return "Today" }
        if diff == 1 { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        let weekDiff = dayDifference(weekStart(today), weekStart(date))
        if weekDiff == 0 { return "This \(weekday)" }
        if weekDiff == -7 { return "Last \(weekday)" }
        if weekDiff == 7 { return "Next \(weekday)" }
        return weekday
    }
}
