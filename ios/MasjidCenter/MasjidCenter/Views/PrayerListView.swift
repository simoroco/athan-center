import SwiftUI
import UIKit

// MARK: - ObjectiveIcon — the same flat monochrome look as the nav-bar icons
// (white in dark mode, near-black in light). Asset PNGs are tinted directly;
// emoji glyphs are rasterized to a mask first. The symbols are unchanged —
// only the colors are stripped.

struct ObjectiveIcon: View {
    let icon: String
    let isAsset: Bool
    var size: CGFloat = 40
    let theme: AppTheme

    var body: some View {
        Group {
            if isAsset {
                Image(icon).renderingMode(.template).resizable()
            } else {
                Image(uiImage: Self.mask(icon, pointSize: size))
                    .renderingMode(.template).resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .foregroundStyle(barIconColor(theme))
    }

    /// Emoji → UIImage masks, cached (view bodies re-evaluate on every publish).
    private static var maskCache: [String: UIImage] = [:]
    static func mask(_ text: String, pointSize: CGFloat) -> UIImage {
        let key = "\(text)@\(Int(pointSize))"
        if let img = maskCache[key] { return img }
        let s = NSAttributedString(string: text,
                                   attributes: [.font: UIFont.systemFont(ofSize: pointSize)])
        let bounds = s.boundingRect(with: CGSize(width: 200, height: 200),
                                    options: .usesLineFragmentOrigin, context: nil)
        let size = CGSize(width: ceil(bounds.width) + 4, height: ceil(bounds.height) + 4)
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            s.draw(at: CGPoint(x: 2 - bounds.origin.x, y: 2 - bounds.origin.y))
        }
        maskCache[key] = img
        return img
    }
}

// MARK: - FlowLayout — rows of tiles that wrap instead of scrolling/clipping.
// Each row is centered (same look as the old centered HStack).

private struct FlowLayout: Layout {
    var hSpacing: CGFloat = 14
    var vSpacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxW { x = 0; y += rowH + vSpacing; rowH = 0 }
            rowH = max(rowH, size.height)
            x += size.width + hSpacing
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width { rows.append([]); x = 0 }
            rows[rows.count - 1].append((s, size))
            x += size.width + hSpacing
        }
        var y = bounds.minY
        for row in rows {
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.1.width } + hSpacing * CGFloat(row.count - 1)
            var rx = bounds.minX + max(0, (bounds.width - rowW) / 2)
            let rowH = row.map { $0.1.height }.max() ?? 0
            for (s, size) in row {
                s.place(at: CGPoint(x: rx, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                rx += size.width + hSpacing
            }
            y += rowH + vSpacing
        }
    }
}

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
        PrayerRowView(theme: theme, prayer: prayer)
    }
}

// MARK: - PrayerRowView — one prayer line. Checking it (blue or orange)
// triggers a fast double heartbeat: scale pulse + gold glow that fades.

private struct PrayerRowView: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    let prayer: Prayer
    @State private var beat = false
    @State private var glow = false

    var body: some View {
        let checked = store.prayerChecks[prayer.prayer_name] ?? 0
        let past = store.isPastPrayer(prayer)
        let canToggle = !store.isFutureDate

        Button {
            guard canToggle, !store.blockTaps else { return }   // swipe, not a tap
            // The toggle cycles 0 → 2 → 1 → 0: pulse only when it lands on a check.
            if checked == 0 || checked == 2 { heartbeat() }
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
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(AppTheme.gold.opacity(glow ? 0.95 : 0), lineWidth: 2)
            )
            .shadow(color: AppTheme.gold.opacity(glow ? 0.9 : 0), radius: 16)
            .scaleEffect(beat ? 1.05 : 1)
            .opacity(past ? 0.7 : 1)
            // Single fast heartbeat (~0.2s), glow fades out right after.
            .animation(.easeInOut(duration: 0.09).repeatCount(1, autoreverses: true), value: beat)
            .animation(.easeOut(duration: 0.4), value: glow)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(canToggle)
        .accessibilityIdentifier("prayer-\(prayer.prayer_name)")
    }

    private func heartbeat() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        beat = true
        glow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            beat = false
            glow = false
        }
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
    @State private var editing: TrackedAction? = nil
    @State private var showEditor = false
    @State private var wiggleOn = false
    @State private var wiggleTimer: Timer? = nil
    // Set when a long-press completes so the release doesn't ALSO fire the tap
    // (would toggle the action / open the editor right after entering jiggle).
    @State private var suppressTap = false
    /// Action pending the delete/hide confirmation alert.
    @State private var deleteTarget: ActionItem? = nil
    /// Tile currently playing the check pulse (same heartbeat as prayer rows).
    @State private var beatId: String? = nil
    @State private var glowId: String? = nil
    /// Working tile order while editing — persisted on each drop.
    @State private var orderIds: [String] = []
    /// Drag & drop reorder state (jiggle mode only).
    @State private var dragId: String? = nil
    @State private var dragStartIndex = 0
    @State private var dragDX: CGFloat = 0

    private var jiggle: Bool { store.actionsEditMode }
    /// One tile slot = 84pt circle + 14pt gap.
    private var tileStep: CGFloat { 98 }

    /// Tile order actually displayed: the working order in edit mode (with any
    /// tiles missing from it appended), the store order otherwise.
    private var displayActions: [ActionItem] {
        let all = store.allActions
        guard jiggle else { return all }
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ordered = orderIds.compactMap { byId[$0] }
        let present = Set(ordered.map(\.id))
        ordered += all.filter { !present.contains($0.id) }
        return ordered
    }

    /// Single fast heartbeat on the tapped tile (~0.25s), glow fades right after.
    private func pulse(_ id: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        beatId = id
        glowId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if beatId == id { beatId = nil }
            if glowId == id { glowId = nil }
        }
    }

    var body: some View {
        // Fixed-size circles, centered per row. Overflow wraps to a second
        // line — never clips a tile off the right edge (iPhone 13 only fits 3).
        FlowLayout(hSpacing: 14, vSpacing: 16) { rowContent() }
        // Rebuild the whole row on mode toggle: kills the scroll offset that
        // otherwise keeps drifting the tiles for seconds after edit mode ends.
        .id(jiggle)
        .padding(.horizontal, 22)     // same inset as the prayer rows → left/right edges align
        .padding(.vertical, 6)        // room for delete badges
        .padding(.bottom, 6)
        // Keep the row's frame current — taps inside are edit controls, not "tap outside".
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mainContent")) } action: {
            store.activityRowFrame = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dailyActivities")
        .alert(
            deleteTarget?.builtin == true
                ? "Hide \"\(deleteTarget?.name ?? "")\"?"
                : "Delete \"\(deleteTarget?.name ?? "")\"?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { a in
            Button(a.builtin ? "Hide" : "Delete", role: .destructive) {
                store.removeAction(id: a.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { a in
            Text(a.builtin
                ? "You can restore it later from the + tile."
                : "This custom objective and its history will be deleted.")
        }
        .sheet(isPresented: $showEditor) {
            ActionEditSheet(editing: editing).environmentObject(store)
        }
        // iOS jiggle: alternate the rotation while edit mode is on.
        .onChange(of: jiggle) { _, on in
            wiggleTimer?.invalidate()
            wiggleTimer = nil
            if dragId != nil { store.setActionOrder(orderIds); dragId = nil }
            if on {
                orderIds = store.allActions.map(\.id)
                wiggleTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { _ in
                    Task { @MainActor in wiggleOn.toggle() }
                }
            } else {
                wiggleOn = false
            }
        }
    }

    @ViewBuilder
    private func rowContent() -> some View {
        ForEach(Array(displayActions.enumerated()), id: \.element.id) { i, a in
            cell(a, phase: i.isMultiple(of: 2) ? 1 : -1)
        }
        if jiggle {
            addTile()
            doneTile()
        }
    }

    // MARK: Cells

    private func cell(_ a: ActionItem, phase: Double) -> some View {
        let checked = store.activityChecks[a.id] ?? 0
        let past = store.selectedDateStr < store.todayStr
        let canToggle = !store.isFutureDate

        return ZStack(alignment: .topTrailing) {
            Button {
                if store.blockTaps { return }          // was a swipe, not a tap
                if suppressTap { suppressTap = false; return }
                if jiggle {
                    if !a.builtin {
                        editing = store.local.snap.customActions.first { $0.id == a.id }
                        showEditor = true
                    }
                    return
                }
                guard canToggle else { return }
                // Unchecked Tasbih → open the counter page (checking it is the
                // counter's job once the daily target is reached).
                let opensTasbih = a.builtin && a.id == "Tasbih" && checked == 0
                // Same pulse as the prayer rows: only when the tap lands on a
                // check (tri-state 0→2 / 2→1) or bumps a counter.
                if !opensTasbih && (a.counter || checked == 0 || checked == 2) { pulse(a.id) }
                if opensTasbih {
                    store.requestTasbih()
                } else if a.counter {
                    store.incrementAction(a.id)
                } else {
                    Task { await store.toggleActivity(a.id) }
                }
            } label: {
                // The symbol stays centered in the circle in every state —
                // flat monochrome, no glow/shadow (matches the nav icons).
                ObjectiveIcon(icon: a.icon, isAsset: a.isAsset, size: 40, theme: theme)
                .frame(width: 84, height: 84)
                // Jiggle animates the glyph + check only: the circle itself
                // never moves off its slot.
                .rotationEffect(.degrees(jiggle ? phase * (wiggleOn ? 3.4 : -3.4) : 0))
                .offset(x: jiggle ? (wiggleOn ? -1.5 : 1.5) : 0,
                        y: jiggle ? (wiggleOn ? 1.5 : -1.5) : 0)
                .animation(.easeInOut(duration: 0.16), value: wiggleOn)
                .frame(width: 84, height: 84)
                .glassCircle(theme)
                // Check heartbeat, identical to the prayer rows: scale pulse +
                // gold ring & halo that fade right after.
                .overlay(Circle().strokeBorder(AppTheme.gold.opacity(glowId == a.id ? 0.95 : 0), lineWidth: 2))
                .shadow(color: AppTheme.gold.opacity(glowId == a.id ? 0.9 : 0), radius: 16)
                .scaleEffect(beatId == a.id ? 1.05 : 1)
                .opacity(past ? 0.7 : 1)
                .animation(.easeInOut(duration: 0.09).repeatCount(1, autoreverses: true), value: beatId)
                .animation(.easeOut(duration: 0.4), value: glowId)
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
                        withAnimation { store.enterJiggle() }
                        // If the finger never releases over the button, the tap
                        // won't fire — don't eat the NEXT real tap. The row is
                        // recreated on jiggle (.id), so the release usually can't
                        // reach the button at all: keep the window short.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            suppressTap = false
                        }
                    }
            )

            // Check / counter badge lives OUTSIDE the button label so it stays
            // above the tile in every state — including while the heartbeat
            // scale + glow animation runs (it used to slip under the borders).
            stateBadge(a, checked: checked, past: past)
                .frame(width: 84, height: 84, alignment: .bottom)
                .offset(y: 12)
                .allowsHitTesting(false)
                .zIndex(5)

            // Red X on EVERY action tile — customs are deleted, built-ins hidden.
            if jiggle {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    deleteTarget = a
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85), Color(hex: 0xFF3B30))
                }
                .offset(x: -3, y: 3)
                .zIndex(10)
                .accessibilityIdentifier("delete-\(a.name)")
            }
        }
        // Drag & drop reorder (edit mode): lift the tile with a mostly-vertical
        // pull, then move it sideways. The slot formula keeps the tile glued
        // to the finger while its array index already changed.
        .offset(x: dragId == a.id
                ? dragDX + CGFloat(dragStartIndex - (orderIds.firstIndex(of: a.id) ?? 0)) * tileStep
                : 0)
        .scaleEffect(dragId == a.id ? 1.08 : 1)
        .zIndex(dragId == a.id ? 8 : 0)
        .animation(.spring(response: 0.25), value: dragId)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    guard jiggle else { return }
                    if dragId == nil {
                        // Pick up on a mostly-vertical pull so flat horizontal
                        // swipes still scroll the row / open the Tasbih page.
                        guard abs(v.translation.height) > 10,
                              abs(v.translation.height) > abs(v.translation.width) * 0.6 else { return }
                        dragId = a.id
                        dragStartIndex = orderIds.firstIndex(of: a.id) ?? 0
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    guard dragId == a.id else { return }
                    dragDX = v.translation.width
                    let target = max(0, min(orderIds.count - 1,
                        dragStartIndex + Int((v.translation.width / tileStep).rounded())))
                    if let cur = orderIds.firstIndex(of: a.id), target != cur {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            orderIds.move(fromOffsets: IndexSet(integer: cur),
                                          toOffset: target > cur ? target + 1 : target)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .onEnded { _ in
                    guard dragId == a.id else { return }
                    dragId = nil
                    dragDX = 0
                    store.setActionOrder(orderIds)
                }
        )
    }

    /// Check / counter badge shown straddling the tile's bottom rim — keeps the
    /// symbol free to sit dead-center in the circle, checked or not.
    @ViewBuilder
    private func stateBadge(_ a: ActionItem, checked: Int, past: Bool) -> some View {
        if a.counter {
            Text("\(checked)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(checked > 0 ? theme.textAccent : (past ? theme.muted : theme.textPrimary))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: Capsule())
        } else if checked == 1 || checked == 2 {
            // Same design as the prayer rows: a plain bold ✓, accent or orange.
            Text("✓")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(checked == 1 ? theme.textAccent : AppTheme.checkmarkOrange)
                .glowText(theme)
        }
    }

    private func addTile() -> some View {
        Button {
            editing = nil
            showEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(barIconColor(theme))
                .frame(width: 84, height: 84)
                .background(Color.white.opacity(0.06))
                .overlay(Circle().strokeBorder(
                    barIconColor(theme).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add objective")
        .accessibilityIdentifier("addAction")
    }

    private func doneTile() -> some View {
        Button {
            withAnimation { store.exitJiggle(force: true) }
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(barIconColor(theme))
                .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done editing")
        .accessibilityIdentifier("doneJiggle")
    }
}
