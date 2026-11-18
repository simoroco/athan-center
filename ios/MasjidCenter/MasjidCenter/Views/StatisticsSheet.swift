import SwiftUI
import Charts

// MARK: - StatisticsSheet — "History" modal (pie + stacked bars, 2-year data).

struct StatisticsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var prayerStats: [WeekStat] = []
    @State private var activityStats: [WeekStat] = []
    @State private var ramadanWeeks: Set<String> = []
    @State private var loading = true
    @State private var fullscreen: FullscreenChart?
    @State private var exportURL: URL?
    @State private var showShare = false

    private var theme: AppTheme { store.theme }

    private struct FullscreenChart: Identifiable {
        let id = UUID()
        let title: String
        let data: [WeekStat]
        let isPrayer: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            PrimaryButton(theme: theme, title: "Export to Excel",
                                          systemImage: "square.and.arrow.down",
                                          accessibility: "exportExcelBtn") {
                                Task { await exportExcel() }
                            }

                            StatsSection(
                                theme: theme,
                                title: "Prayer Statistics",
                                stats: prayerStats,
                                ramadanWeeks: ramadanWeeks,
                                onExpand: {
                                    fullscreen = FullscreenChart(
                                        title: "Prayer Statistics - 2 Years' Histogram",
                                        data: prayerStats, isPrayer: true)
                                }
                            )

                            StatsSection(
                                theme: theme,
                                title: "Objectives Statistics",
                                stats: activityStats,
                                ramadanWeeks: ramadanWeeks,
                                onExpand: {
                                    fullscreen = FullscreenChart(
                                        title: "Objectives Statistics - 2 Years' Histogram",
                                        data: activityStats, isPrayer: false)
                                }
                            )
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("History & Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .accessibilityIdentifier("closeStatistics")
                }
            }
        }
        .task { await load() }
        // The main-screen toast is hidden behind this sheet.
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastCapsule(text: toast)
                    .padding(.bottom, 10)
            }
        }
        .animation(.easeOut, value: store.toast)
        .sheet(item: $fullscreen) { fs in
            FullscreenChartView(theme: theme, title: fs.title, stats: fs.data, ramadanWeeks: ramadanWeeks)
        }
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
    }

    private func load() async {
        if store.isStandalone || !store.connected {
            let stats = store.localWeeklyStats()
            prayerStats = stats.prayers
            activityStats = stats.activities
            ramadanWeeks = []
        } else {
            async let pTask = store.api.statisticsPrayers()
            async let aTask = store.api.statisticsActivities()
            async let rTask = store.api.ramadanDates()
            prayerStats = (try? await pTask) ?? []
            let serverActs = (try? await aTask) ?? []
            ramadanWeeks = Set(((try? await rTask) ?? []).map { isoWeek($0.gregorian_date) })
            // Merge iOS-only custom actions into the activity stats.
            let localActs = store.localWeeklyStats().activities
            var merged: [String: WeekStat] = Dictionary(serverActs.map { ($0.week, $0) }, uniquingKeysWith: { _, new in new })
            for l in localActs {
                if var s = merged[l.week] {
                    merged[l.week] = WeekStat(
                        week: s.week, year: s.year, weekNumber: s.weekNumber,
                        not_done: s.not_done, on_time: s.on_time + l.on_time,
                        late: s.late + l.late,
                        total_prayers: s.total_prayers,
                        total_activities: (s.total_activities ?? 0) + (l.total_activities ?? 0),
                        on_time_percent: s.on_time_percent,
                        total_completed_percent: s.total_completed_percent)
                }
            }
            activityStats = merged.values.sorted { $0.week < $1.week }
        }
        loading = false
    }

    private func isoWeek(_ dateStr: String) -> String {
        DateUtil.isoWeekLabel(DateUtil.parseDate(dateStr) ?? Date())
    }

    private func exportExcel() async {
        guard let data = try? await store.api.exportExcel() else {
            store.showToast("Export failed")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("masjid-center-statistics-\(Int(Date().timeIntervalSince1970 * 1000)).xlsx")
        try? data.write(to: url)
        exportURL = url
        showShare = true
    }
}

// MARK: - Section (pie + bar)

private struct StatsSection: View {
    let theme: AppTheme
    let title: String
    let stats: [WeekStat]
    let ramadanWeeks: Set<String>
    let onExpand: () -> Void

    /// Last (current ISO) week — pie chart source.
    private var lastWeek: WeekStat? {
        let current = DateUtil.isoWeekLabel(Date())
        return stats.first { $0.week == current } ?? stats.last
    }

    /// Zero-filled rolling weeks, last 13 shown (mobile rule in app.js).
    private var barWeeks: [WeekStat] { zeroFilled().suffix(13).map { $0 } }

    private func zeroFilled() -> [WeekStat] {
        guard !stats.isEmpty else { return [] }
        let byWeek = Dictionary(stats.map { ($0.week, $0) }, uniquingKeysWith: { _, new in new })
        var out: [WeekStat] = []
        // Walk 104 weeks back from the latest stat week.
        guard let lastDate = weekStartDate(stats.last!.week) else { return stats }
        for i in stride(from: 103, through: 0, by: -1) {
            guard let d = Calendar.current.date(byAdding: .weekOfYear, value: -i, to: lastDate) else { continue }
            let label = DateUtil.isoWeekLabel(d)
            if let s = byWeek[label] {
                out.append(s)
            } else {
                out.append(WeekStat(week: label, year: 0, weekNumber: 0,
                                    not_done: 0, on_time: 0, late: 0,
                                    total_prayers: nil, total_activities: nil,
                                    on_time_percent: "0.0", total_completed_percent: "0.0"))
            }
        }
        return out
    }

    private func weekStartDate(_ weekLabel: String) -> Date? {
        // "YYYY-Www" → Monday of that ISO week.
        let parts = weekLabel.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]),
              let w = Int(parts[1].dropFirst()) else { return nil }
        var comps = DateComponents()
        comps.weekOfYear = w
        comps.yearForWeekOfYear = y
        comps.weekday = 2 // Monday
        return DateUtil.isoCalendar.date(from: comps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "moon.stars")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2C3E50).opacity(theme.dark ? 0 : 1))
                .foregroundStyle(theme.sheetText)

            VStack(spacing: 14) {
                // Last week pie
                VStack(spacing: 8) {
                    Text("Last Week Summary")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.sheetText)
                    PieChartView(stat: lastWeek, theme: theme)
                        .frame(height: 200)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(theme.dark ? Color(hex: 0x1A202C) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

                // 2-year histogram (13 weeks on phone)
                VStack(spacing: 8) {
                    HStack {
                        Text("2 Years' Histogram")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.sheetText)
                        Spacer()
                        Button(action: onExpand) {
                            Label("Expand", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(hex: 0x3498DB))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("expandChart-\(title)")
                    }
                    WeekBarChart(stats: barWeeks, ramadanWeeks: ramadanWeeks, theme: theme)
                        .frame(height: 240)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(theme.dark ? Color(hex: 0x1A202C) : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
        .padding(14)
        .background(theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Pie chart (Not Done / On Time / Late)

private struct PieChartView: View {
    let stat: WeekStat?
    let theme: AppTheme

    private var slices: [(String, Int, Color)] {
        guard let s = stat else { return [] }
        return [
            ("Not Done", s.not_done, AppTheme.chartNotDone),
            ("On Time", s.on_time, AppTheme.chartOnTime),
            ("Late", s.late, AppTheme.chartLate)
        ]
    }

    var body: some View {
        if let s = stat {
            HStack(spacing: 16) {
                Chart(slices, id: \.0) { item in
                    SectorMark(angle: .value("Count", item.1), innerRadius: .ratio(0.45))
                        .foregroundStyle(item.2)
                        .cornerRadius(3)
                }
                .frame(width: 150, height: 150)
                .chartLegend(.hidden)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(slices, id: \.0) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.2).frame(width: 10, height: 10)
                            Text("\(item.0): \(item.1)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.sheetText)
                            let total = max(1, s.not_done + s.on_time + s.late)
                            Text(String(format: "(%.0f%%)", Double(item.1) / Double(total) * 100))
                                .font(.system(size: 12))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("No data").foregroundStyle(theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Stacked bar chart

private struct WeekBarChart: View {
    let stats: [WeekStat]
    let ramadanWeeks: Set<String>
    let theme: AppTheme
    var dense: Bool = false

    private func label(_ s: WeekStat) -> String {
        let w = "W\(s.weekNumber > 0 ? String(s.weekNumber) : String(s.week.dropFirst(6)))"
        return ramadanWeeks.contains(s.week) ? "☾ \(w)" : w
    }

    var body: some View {
        Chart {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                BarMark(x: .value("Week", label(s)), y: .value("Count", s.not_done))
                    .foregroundStyle(AppTheme.chartNotDone)
                BarMark(x: .value("Week", label(s)), y: .value("Count", s.late))
                    .foregroundStyle(AppTheme.chartLate)
                BarMark(x: .value("Week", label(s)), y: .value("Count", s.on_time))
                    .foregroundStyle(AppTheme.chartOnTime)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: dense ? 6 : 9))
            }
        }
        .chartForegroundStyleScale([
            "Not Done": AppTheme.chartNotDone,
            "Late": AppTheme.chartLate,
            "On Time": AppTheme.chartOnTime
        ])
        .chartLegend(position: .bottom)
    }
}

// MARK: - Fullscreen chart sheet (all 104 weeks)

private struct FullscreenChartView: View {
    let theme: AppTheme
    let title: String
    let stats: [WeekStat]
    let ramadanWeeks: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var filled: [WeekStat] {
        guard let last = stats.last else { return stats }
        let byWeek = Dictionary(stats.map { ($0.week, $0) }, uniquingKeysWith: { _, new in new })
        let parts = last.week.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let w = Int(parts[1].dropFirst()) else { return stats }
        var comps = DateComponents(); comps.weekOfYear = w; comps.yearForWeekOfYear = y; comps.weekday = 2
        guard let lastDate = DateUtil.isoCalendar.date(from: comps) else { return stats }
        var out: [WeekStat] = []
        for i in stride(from: 103, through: 0, by: -1) {
            guard let d = Calendar.current.date(byAdding: .weekOfYear, value: -i, to: lastDate) else { continue }
            let label = DateUtil.isoWeekLabel(d)
            out.append(byWeek[label] ?? WeekStat(week: label, year: 0, weekNumber: 0,
                                               not_done: 0, on_time: 0, late: 0,
                                               total_prayers: nil, total_activities: nil,
                                               on_time_percent: "0.0", total_completed_percent: "0.0"))
        }
        return out
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(hex: 0xE74C3C))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                WeekBarChart(stats: filled, ramadanWeeks: ramadanWeeks,
                             theme: AppTheme(dark: true), dense: true)
                    .padding()
                    .background(Color(hex: 0x1A202C))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
