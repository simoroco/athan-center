import SwiftUI

// MARK: - QuickPraySheet — "⚡️ Quick Pray" modal (14-day grid with week separators).

struct QuickPraySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var days: [(date: String, label: String)] = []
    @State private var checks: [String: [String: Int]] = [:]
    @State private var loading = true

    private var theme: AppTheme { store.theme }
    private let colHeaders = ["Faj", "Doh", "Asr", "Mag", "Ish"]

    private enum RowItem: Hashable {
        case separator(String)
        case day(String, String)
    }

    /// Flattened rows with ISO-week separators (qf-week-sep rows in the web app).
    private var rowItems: [RowItem] {
        var items: [RowItem] = []
        var lastWeek = ""
        for day in days {
            let week = DateUtil.isoWeekLabel(DateUtil.parseDate(day.date) ?? Date())
            if week != lastWeek {
                items.append(.separator(week))
                lastWeek = week
            }
            items.append(.day(day.date, day.label))
        }
        return items
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 4) {
                                Text("").frame(width: 44, alignment: .leading)
                                ForEach(Array(colHeaders.enumerated()), id: \.offset) { _, h in
                                    Text(h)
                                        .font(.system(size: 11, weight: .bold))
                                        .textCase(.uppercase)
                                        .tracking(1)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .foregroundStyle(theme.sheetText)
                            .padding(.bottom, 8)

                            ForEach(rowItems, id: \.self) { item in
                                switch item {
                                case .separator(let week):
                                    weekSeparator(week)
                                case .day(let date, let label):
                                    dayRow((date: date, label: label))
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Quick Pray")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .accessibilityIdentifier("closeQuickPray")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let r = await store.quickFillRows()
        days = r.days
        checks = r.checks
        loading = false
    }

    private func weekSeparator(_ week: String) -> some View {
        HStack {
            Text(String(week.dropFirst(4))) // "Www"
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(theme.sheetText.opacity(0.55))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func dayRow(_ day: (date: String, label: String)) -> some View {
        let isToday = day.date == store.todayStr
        return HStack(spacing: 4) {
            Text(isToday ? "T." : shortDay(day.date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isToday ? theme.qfTodayLabel : theme.sheetText)
                .frame(width: 44, alignment: .leading)
            ForEach(AC.mainPrayers, id: \.self) { p in
                cell(date: day.date, prayer: p)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(isToday ? theme.qfTodayBg : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qf-row-\(day.date)")
    }

    private func shortDay(_ ds: String) -> String {
        guard let d = DateUtil.parseDate(ds) else { return ds }
        let f = DateFormatter(); f.dateFormat = "EEE d"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    private func cell(date: String, prayer: String) -> some View {
        let state = checks[date]?[prayer] ?? 0
        return QFPulseCell(theme: theme, date: date, prayer: prayer, state: state) {
            // Optimistic cycle 0 → 2 → 1 → 0, then POST toggle.
            let next = state == 0 ? 2 : (state == 2 ? 1 : 0)
            checks[date, default: [:]][prayer] = next
            Task {
                do {
                    let r = try await store.api.togglePrayerCheck(date: date, prayer: prayer)
                    checks[date, default: [:]][prayer] = r
                    if date == store.selectedDateStr { store.prayerChecks[prayer] = r }
                } catch {
                    checks[date, default: [:]][prayer] = state
                }
            }
        }
    }

}

// MARK: - QFPulseCell — one quick-pray cell; fast heartbeat + gold glow
// when the tap checks it (blue or orange), like the main page rows.

private struct QFPulseCell: View {
    let theme: AppTheme
    let date: String
    let prayer: String
    let state: Int
    let action: () -> Void
    @State private var beat = false
    @State private var glow = false

    var body: some View {
        Button {
            // Cycle 0 → 2 → 1 → 0: pulse only when it lands on a check.
            if state == 0 || state == 2 { heartbeat() }
            action()
        } label: {
            Text(state >= 1 ? "✓" : "")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(state == 1 ? theme.qfCheckedText : theme.qfLateText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(cellBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.componentBorder, lineWidth: state == 0 ? 1.5 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppTheme.gold.opacity(glow ? 0.95 : 0), lineWidth: 2)
                )
                .shadow(color: AppTheme.gold.opacity(glow ? 0.9 : 0), radius: 10)
                .scaleEffect(beat ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.09).repeatCount(1, autoreverses: true), value: beat)
                .animation(.easeOut(duration: 0.4), value: glow)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("qf-\(date)-\(prayer)")
    }

    private var cellBg: Color {
        switch state {
        case 1: return theme.qfCheckedBg
        case 2: return theme.qfLateBg
        default: return theme.componentBg
        }
    }

    private func heartbeat() {
        beat = true
        glow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            beat = false
            glow = false
        }
    }
}
