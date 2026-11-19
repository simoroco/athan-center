import Foundation
import UserNotifications

// MARK: - NotificationManager — daily athan reminders + objective reminders
// (both iOS-local features, gated by the "iOS notifications" master switch).

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    /// Water-drop sound bundled in the app (Settings → Tasbih & Objectives reminders).
    static let reminderSound = UNNotificationSoundName("water_drop.wav")

    /// iOS keeps the 64 soonest pending requests — objective reminders share
    /// that budget with the dated athan notifications.
    private static let maxReminderRequests = 30

    /// Requests authorization. Returns true when granted.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func currentAuthorization() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized
    }

    /// Removes all pending requests then reschedules:
    /// - one daily repeating notification per configured objective reminder
    ///   time (iOS-app-only local notifications, water-drop sound);
    /// - one daily notification per enabled prayer for the next `days` days
    ///   (date triggers — robust to clock changes, unlike repeating calendar
    ///   triggers).
    func reschedule(prayers: [String: [Prayer]],
                    scheduleEnabled: (String, Int) -> Bool,
                    reminders: [(id: String, name: String, times: [(hour: Int, minute: Int)])],
                    enabled: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        let cal = Calendar.current
        let now = Date()

        // Objective reminders: one daily repeating trigger per configured
        // time (each request repeats forever, so it counts only once against
        // the 64-request budget). Duplicate times collapse to one trigger.
        var reminderCount = 0
        for r in reminders {
            var seen = Set<Int>()
            for (i, t) in r.times.enumerated() {
                guard reminderCount < Self.maxReminderRequests else { break }
                guard seen.insert(t.hour * 60 + t.minute).inserted else { continue }
                let content = UNMutableNotificationContent()
                content.title = r.name
                content.body = "Objective reminder — take a moment for it today"
                content.sound = UNNotificationSound(named: Self.reminderSound)
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: t.hour, minute: t.minute), repeats: true)
                center.add(UNNotificationRequest(
                    identifier: "objrem-\(r.id)-\(i)", content: content, trigger: trigger))
                reminderCount += 1
            }
        }

        var slots: [(date: Date, id: String, name: String, time: String)] = []
        for dateStr in prayers.keys.sorted() {
            guard let day = DateUtil.dayFmt.date(from: dateStr) else { continue }
            let dow = DateUtil.scheduleDay(day)
            for p in prayers[dateStr] ?? [] where AC.mainPrayers.contains(p.prayer_name) {
                guard scheduleEnabled(p.prayer_name, dow) else { continue }
                let t = p.prayer_time.split(separator: ":").compactMap { Int($0) }
                guard t.count == 2,
                      let fire = cal.date(bySettingHour: t[0], minute: t[1], second: 0, of: day),
                      fire > now else { continue }          // past slots would waste the 64-request budget
                slots.append((fire, "athan-\(dateStr)-\(p.prayer_name)", p.prayer_name, p.prayer_time))
            }
        }
        // iOS keeps only the 64 soonest pending requests: schedule the soonest
        // athan slots within the budget left by the objective reminders.
        for slot in slots.sorted(by: { $0.date < $1.date }).prefix(max(0, 60 - reminderCount)) {
            let content = UNMutableNotificationContent()
            content.title = AC.displayPrayerName(slot.name)
            content.body = "It's time to pray — \(slot.time)"
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: slot.id, content: content, trigger: trigger))
        }
    }
}
