import Foundation
import UserNotifications

// MARK: - NotificationManager — daily athan reminders (iOS-local feature).

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    /// Requests authorization. Returns true when granted.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func currentAuthorization() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized
    }

    /// Removes all pending requests then schedules one daily notification per
    /// enabled prayer for the next `days` days (date triggers — robust to
    /// clock changes, unlike repeating calendar triggers).
    func reschedule(prayers: [String: [Prayer]],
                    scheduleEnabled: (String, Int) -> Bool,
                    enabled: Bool) {
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        let cal = Calendar.current
        let now = Date()
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
        // iOS keeps only the 64 soonest pending requests: schedule exactly the soonest 60.
        for slot in slots.sorted(by: { $0.date < $1.date }).prefix(60) {
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
