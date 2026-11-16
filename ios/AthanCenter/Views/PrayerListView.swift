import SwiftUI

// MARK: - Prayers list, daily activities, date navigation, action buttons.

struct PrayerListView: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme

    var body: some View {
        VStack(spacing: 2) {
            if store.prayers.isEmpty {
                Text("No prayers available for this date")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.muted)
                    .padding(20)
            } else {
                ForEach(store.prayers) { prayer in
                    row(prayer)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)   // ~85% of container width
        .padding(.bottom, 21)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prayersList")
    }

    private func row(_ prayer: Prayer) -> some View {
        let checked = store.prayerChecks[prayer.prayer_name] ?? 0
        let past = store.isPastPrayer(prayer)
        let canToggle = !store.isFutureDate

        return Button {
            guard canToggle else { return }
            Task { await store.togglePrayer(prayer.prayer_name) }
        } label: {
            HStack {
                Text(AC.displayPrayerName(prayer.prayer_name))
                    .font(.system(size: 20.8, weight: .heavy).monospaced())
                    .foregroundStyle(nameColor(checked: checked, past: past))
                Spacer()
                HStack(spacing: 6) {
                    if checked == 1 {
                        Text("✓").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.textAccent)
                    } else if checked == 2 {
                        Text("✓").font(.system(size: 24, weight: .bold)).foregroundStyle(AppTheme.checkmarkOrange)
                    }
                    Text(prayer.prayer_time)
                        .font(.system(size: 18.4, weight: .heavy))
                        .foregroundStyle(timeColor(checked: checked, past: past))
                }
            }
            .glowText(theme)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 59)
            .glassBox(theme)
            .opacity(past ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canToggle)
        .accessibilityIdentifier("prayer-\(prayer.prayer_name)")
    }

    private func nameColor(checked: Int, past: Bool) -> Color {
        if checked >= 1 { return theme.textAccent }
        if past { return theme.dangerPast }       // unchecked past → red
        return theme.textPrimary
    }
    private func timeColor(checked: Int, past: Bool) -> Color {
        if checked >= 1 { return theme.textAccent }
        if past { return theme.dangerPast }
        return theme.textAccent
    }
}

// MARK: - Daily activities (Coran / Tasbih / Nawafil)

struct DailyActivitiesView: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AC.activities, id: \.name) { activity in
                cell(activity.name, icon: activity.icon)
            }
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyActivities")
    }

    private func cell(_ name: String, icon: String) -> some View {
        let checked = store.activityChecks[name] ?? 0
        let past = store.selectedDateStr < store.todayStr
        let canToggle = !store.isFutureDate

        return Button {
            guard canToggle else { return }
            Task { await store.toggleActivity(name) }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(icon).resizable().frame(width: 26, height: 26)
                    if checked == 1 {
                        Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textAccent)
                    } else if checked == 2 {
                        Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.checkmarkOrange)
                    }
                }
                Text(name)
                    .font(.system(size: 11, weight: .bold).monospaced())
                    .foregroundStyle(checked >= 1 ? theme.textAccent : (past ? theme.muted : theme.textPrimary))
            }
            .glowText(theme)
            .frame(maxWidth: .infinity, minHeight: 59)
            .glassBox(theme)
            .opacity(past ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canToggle)
        .accessibilityIdentifier("activity-\(name)")
    }
}