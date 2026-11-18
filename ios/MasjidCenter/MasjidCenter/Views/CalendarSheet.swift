import SwiftUI

// MARK: - CalendarSheet — year calendar like #calendarModal.

struct CalendarSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var checks: [String: [String: Int]] = [:]   // date -> prayer -> state

    private var theme: AppTheme { store.theme }
    private let monthNames = ["January", "February", "March", "April", "May", "June",
                              "July", "August", "September", "October", "November", "December"]
    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // Year navigation
                    HStack {
                        Button { year -= 1; Task { await load() } } label: {
                            Image(systemName: "chevron.left").font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 34)
                                .background(Color(hex: 0x2A6DD1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(String(year))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(hex: 0x2A6DD1))
                        Button { year += 1; Task { await load() } } label: {
                            Image(systemName: "chevron.right").font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 34)
                                .background(Color(hex: 0x2A6DD1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(1...12, id: \.self) { month in
                            monthCard(month)
                                .id(month)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    let m = Calendar.current.component(.month, from: store.selectedDate)
                    proxy.scrollTo(m, anchor: .top)
                }
            }
            .navigationTitle("Select a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .accessibilityIdentifier("closeCalendar")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let all = (try? await store.api.prayerChecksRange(year: year)) ?? []
        var map: [String: [String: Int]] = [:]
        for c in all where AC.mainPrayers.contains(c.prayer_name) {
            map[c.date, default: [:]][c.prayer_name] = c.checked
        }
        checks = map
        if store.ramadanDates.isEmpty { await store.loadRamadan() }
    }

    // MARK: Month card

    @ViewBuilder
    private func monthCard(_ month: Int) -> some View {
        VStack(spacing: 6) {
            Text(monthNames[month - 1])
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(hex: 0x2A6DD1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0x2A6DD1)).frame(height: 2)
                }

            // Header row: week-number column + weekday letters
            HStack(spacing: 2) {
                Text("W").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.muted)
                    .frame(width: 20)
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeksIn(month).enumerated()), id: \.offset) { _, week in
                weekRow(week, month: month)
            }
        }
        .padding(10)
        .background(theme.dark ? Color(hex: 0x2D3748) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.dark ? Color(hex: 0x4A5568) : Color(hex: 0xE9ECEF), lineWidth: 2))
    }

    /// Weeks of the month: each = ISO week number + 7 optional dates (Mon..Sun).
    private func weeksIn(_ month: Int) -> [[Date?]] {
        var cal = DateUtil.isoCalendar
        cal.timeZone = .current
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let first = cal.date(from: comps) else { return [] }
        comps.month! += 1
        let nextMonth = cal.date(from: comps)!
        var weeks: [[Date?]] = []
        // Find Monday of the week containing the 1st.
        var cursor = first
        while DateUtil.scheduleDay(cursor) != 0 {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        while cursor < nextMonth {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(cursor)
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
            // Stop once the whole week is past the month.
            if week.allSatisfy({ cal.component(.month, from: $0!) != month }) { break }
            weeks.append(week)
        }
        return weeks
    }

    private func weekRow(_ week: [Date?], month: Int) -> some View {
        let firstReal = week.compactMap { $0 }.first
        let weekNum = firstReal.map { String(DateUtil.isoCalendar.component(.weekOfYear, from: $0)) } ?? ""
        return HStack(spacing: 2) {
            Text(weekNum)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2A6DD1))
                .frame(width: 20, height: 20)
                .background(Color(hex: 0x2A6DD1).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                dayCell(date, month: month)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date?, month: Int) -> some View {
        if let date {
            let ds = DateUtil.dateString(date)
            let inMonth = Calendar.current.component(.month, from: date) == month
            let isToday = ds == store.todayStr
            let isSelected = ds == store.selectedDateStr
            let marker = dayMarker(ds)

            Button {
                store.goToDate(date)
                dismiss()
            } label: {
                VStack(spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 12, weight: isToday || isSelected ? .bold : .regular))
                    HStack(spacing: 1) {
                        if let marker {
                            Text(marker)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(markerColor(ds))
                        }
                        if store.ramadanDates.contains(ds) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(AppTheme.gold)
                        }
                    }
                    .frame(height: 10)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .foregroundStyle(cellTextColor(inMonth: inMonth, isToday: isToday, isSelected: isSelected))
                .background(cellBg(inMonth: inMonth, isToday: isToday, isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: 0x114BB2), lineWidth: isToday ? 2 : 0)
                )
                .opacity(inMonth ? 1 : 0.3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("day-\(ds)")
        } else {
            Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }

    /// ✓ marker: green if all 5 on-time, orange if all checked but not all on-time.
    private func dayMarker(_ ds: String) -> String? {
        guard let map = checks[ds] else { return nil }
        let states = AC.mainPrayers.map { map[$0] ?? 0 }
        if states.allSatisfy({ $0 == 1 }) { return "✓" }
        if states.contains(where: { $0 >= 1 }) { return "✓" }
        return nil
    }

    private func markerColor(_ ds: String) -> Color {
        guard let map = checks[ds] else { return .clear }
        let states = AC.mainPrayers.map { map[$0] ?? 0 }
        return states.allSatisfy { $0 == 1 } ? Color(hex: 0x22C55E) : AppTheme.checkmarkOrange
    }

    private func cellTextColor(inMonth: Bool, isToday: Bool, isSelected: Bool) -> Color {
        if isToday || isSelected { return .white }
        return theme.sheetText
    }
    private func cellBg(inMonth: Bool, isToday: Bool, isSelected: Bool) -> Color {
        if isToday { return Color(hex: 0x2A6DD1) }
        if isSelected { return Color(hex: 0x114BB2) }
        return theme.dark ? Color(hex: 0x1C1E26) : Color(hex: 0xF8F9FA)
    }
}
