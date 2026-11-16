import SwiftUI

// MARK: - ScheduleMatrixView — "Whole week" + per-day tabs (loadScheduleMatrix in app.js).
// prayer_schedule.day_of_week: 0 = Monday … 6 = Sunday.

struct ScheduleMatrixView: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    @State private var tab: Int = -1   // -1 = Whole week, 0..6 = Mon..Sun

    private let tabNames = ["Whole week", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(-1..<7, id: \.self) { i in
                        Button { tab = i } label: {
                            Text(tabNames[i + 1])
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .foregroundStyle(tab == i ? .white : Color(hex: 0x2A6DD1))
                                .background(tab == i ? Color(hex: 0x2A6DD1) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color(hex: 0x2A6DD1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("schedTab-\(i)")
                    }
                }
            }

            if tab == -1 {
                wholeWeekContent
            } else {
                dayContent(tab)
            }
        }
        .task { await store.loadSchedule() }
        .accessibilityIdentifier("scheduleMatrix")
    }

    // MARK: Whole week tab

    private var wholeWeekContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By weekdays")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2A6DD1))
                .padding(.bottom, 8)

            matrixRow("All athans", isOn: allEnabled) { v in
                Task { for d in 0..<7 { await store.bulkScheduleDay(d, v) } }
            }
            .accessibilityIdentifier("sched-all")
            divider

            ForEach(AC.mainPrayers, id: \.self) { prayer in
                matrixRow(AC.displayPrayerName(prayer), isOn: prayerAllDays(prayer)) { v in
                    Task { await store.bulkSchedulePrayer(prayer, v) }
                }
                .accessibilityIdentifier("sched-week-\(prayer)")
            }
        }
    }

    // MARK: Single day tab

    private func dayContent(_ day: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AC.weekdayNames[day])
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2A6DD1))
                .padding(.bottom, 8)

            matrixRow("Whole day", isOn: dayAllEnabled(day)) { v in
                Task { await store.bulkScheduleDay(day, v) }
            }
            .accessibilityIdentifier("sched-day-all")
            divider

            ForEach(AC.mainPrayers, id: \.self) { prayer in
                matrixRow(AC.displayPrayerName(prayer), isOn: cellEnabled(prayer, day)) { v in
                    Task { await store.setSchedule(prayer, day, v) }
                }
                .accessibilityIdentifier("sched-\(day)-\(prayer)")
            }
        }
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle().fill(Color(hex: 0x2A6DD1).opacity(0.4)).frame(height: 1)
            .padding(.vertical, 4)
    }

    private var allEnabled: Binding<Bool> {
        Binding(
            get: { store.schedule.filter { AC.mainPrayers.contains($0.prayer_name) }.allSatisfy { $0.enabled == 1 } },
            set: { _ in })
    }
    private func prayerAllDays(_ p: String) -> Binding<Bool> {
        Binding(
            get: { store.schedule.filter { $0.prayer_name == p }.allSatisfy { $0.enabled == 1 } },
            set: { _ in })
    }
    private func dayAllEnabled(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { store.schedule.filter { $0.day_of_week == day && AC.mainPrayers.contains($0.prayer_name) }.allSatisfy { $0.enabled == 1 } },
            set: { _ in })
    }
    private func cellEnabled(_ p: String, _ day: Int) -> Binding<Bool> {
        Binding(get: { store.scheduleEnabled(p, day) ?? true }, set: { _ in })
    }

    private func matrixRow(_ title: String, isOn: Binding<Bool>,
                           action: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.sheetText)
            Spacer()
            WebToggle(theme: theme, isOn: Binding(
                get: { isOn.wrappedValue },
                set: { v in action(v) }))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0x2A6DD1).opacity(0.2)).frame(height: 1)
        }
    }
}
