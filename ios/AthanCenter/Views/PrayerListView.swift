import SwiftUI
import UIKit

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
                ForEach(store.prayers, id: \.rowKey) { prayer in
                    row(prayer)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)   // ~85% of container width
        .padding(.bottom, 21)
        .accessibilityElement(children: .contain)
        .accessibilityValue(store.selectedDateStr)
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
            .glassBox(theme, radius: 30)
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

// MARK: - Daily activities (Coran / Tasbih / Nawafil + custom actions).
// Long-press on an icon → iOS "jiggle" edit mode: delete badges on custom
// actions, tap to edit, "+" tile to add a new one. iOS-only feature.

struct DailyActivitiesView: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    @State private var jiggle = false
    @State private var editing: TrackedAction? = nil
    @State private var showEditor = false
    @State private var wiggleOn = false
    // Set when a long-press completes so the release doesn't ALSO fire the tap
    // (would toggle the action / open the editor right after entering jiggle).
    @State private var suppressTap = false

    var body: some View {
        let tiles = store.allActions.count + (jiggle ? 2 : 0)
        Group {
            if tiles <= 5 {
                HStack(spacing: 8) { rowContent(flexible: true) }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { rowContent(flexible: false) }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 22)     // same inset as the prayer rows → left/right edges align
        .padding(.vertical, 6)        // room for delete badges
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyActivities")
        .sheet(isPresented: $showEditor) {
            ActionEditSheet(editing: editing).environmentObject(store)
        }
    }

    @ViewBuilder
    private func rowContent(flexible: Bool) -> some View {
        ForEach(store.allActions, id: \.id) { a in
            cell(a, flexible: flexible)
        }
        if jiggle {
            addTile(flexible: flexible)
            doneTile(flexible: flexible)
        }
    }

    // MARK: Cells

    private func cell(_ a: ActionItem, flexible: Bool) -> some View {
        let checked = store.activityChecks[a.id] ?? 0
        let past = store.selectedDateStr < store.todayStr
        let canToggle = !store.isFutureDate

        return ZStack(alignment: .topTrailing) {
            Button {
                if suppressTap { suppressTap = false; return }
                if jiggle {
                    if !a.builtin {
                        editing = store.local.snap.customActions.first { $0.id == a.id }
                        showEditor = true
                    }
                    return
                }
                guard canToggle else { return }
                if a.counter {
                    store.incrementAction(a.id)
                } else {
                    Task { await store.toggleActivity(a.id) }
                }
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if a.isAsset {
                            Image(a.icon).resizable().frame(width: 26, height: 26)
                        } else {
                            Text(a.icon).font(.system(size: 24))
                        }
                        if a.counter {
                            Text("\(checked)")
                                .font(.system(size: 18, weight: .bold).monospacedDigit())
                                .foregroundStyle(checked > 0 ? theme.textAccent : (past ? theme.muted : theme.textPrimary))
                        } else if checked == 1 {
                            Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textAccent)
                        } else if checked == 2 {
                            Text("✓").font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.checkmarkOrange)
                        }
                    }
                }
                .glowText(theme)
                .frame(maxWidth: flexible ? .infinity : nil, minHeight: 59)
                .frame(width: flexible ? nil : 72)
                .glassBox(theme, radius: 30)
                .opacity(past ? 0.7 : 1)
                .rotationEffect(.degrees(jiggle && wiggleOn ? 1.6 : (jiggle ? -1.6 : 0)))
                .animation(jiggle ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default,
                           value: wiggleOn)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(a.name)
            .accessibilityValue(a.counter ? "\(checked)" : (checked == 1 ? "done" : checked == 2 ? "late" : "not done"))
            .accessibilityIdentifier("activity-\(a.name)")
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        suppressTap = true
                        withAnimation { jiggle = true }
                        wiggleOn = true
                        // If the finger never releases over the button, the tap
                        // won't fire — don't eat the NEXT real tap.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            suppressTap = false
                        }
                    }
            )

            if jiggle && !a.builtin {
                Button {
                    store.removeAction(id: a.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Color.red)
                        .background(Circle().fill(.black))
                }
                .offset(x: -3, y: 3)
                .zIndex(10)
                .accessibilityIdentifier("delete-\(a.name)")
            }
        }
    }

    private func addTile(flexible: Bool) -> some View {
        Button {
            editing = nil
            showEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0xD4AF37))
                .frame(maxWidth: flexible ? .infinity : nil, minHeight: 59)
                .frame(width: flexible ? nil : 72)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(
                    Color(hex: 0xD4AF37).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add action")
        .accessibilityIdentifier("addAction")
    }

    private func doneTile(flexible: Bool) -> some View {
        Button {
            withAnimation { jiggle = false }
            wiggleOn = false
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textAccent)
                .frame(maxWidth: flexible ? .infinity : nil, minHeight: 59)
                .frame(width: flexible ? nil : 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done editing")
        .accessibilityIdentifier("doneJiggle")
    }
}
