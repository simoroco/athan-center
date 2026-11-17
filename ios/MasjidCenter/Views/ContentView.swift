import SwiftUI

// MARK: - ContentView — replicates index.html layout over the door background.

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCalendar = false
    @State private var showQuickPray = false
    @State private var showStats = false
    @State private var showSettings = false
    @State private var showTasbih = false
    /// Live horizontal drag: <0 while revealing Tasbih (swipe left),
    /// >0 while dismissing it (swipe right). Drives the slide animation.
    @State private var tasbihDrag: CGFloat = 0

    var body: some View {
        let theme = store.theme
        GeometryReader { geo in
            let metrics = DoorMetrics(screenWidth: geo.size.width)
            ZStack(alignment: .bottom) {
                // --- Background: photo + fixed dim overlay (body CSS) ---
                theme.bgBase.ignoresSafeArea()
                Image("background")
                    .resizable()
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(width: metrics.bgImageWidth, height: metrics.bgImageHeight)
                    .position(x: geo.size.width / 2, y: metrics.bgImageHeight * 0.16)
                    .clipped()
                    .ignoresSafeArea()
                theme.bgOverlay.ignoresSafeArea()

                // --- Content column (container, width = doorWidth) ---
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 0) {
                            NextPrayerCard(
                                theme: theme,
                                metrics: metrics,
                                now: context.date,
                                onOpenSettings: { showSettings = true }
                            )

                            if store.weekdayMuteActive {
                                weekdayMuteBanner(theme)
                            }

                            PrayerListView(theme: theme)

                            DailyActivitiesView(theme: theme)
                        }
                        .frame(width: metrics.doorWidth)
                        .frame(maxWidth: .infinity)
                        // Center the column between the top pad and the floating
                        // bar when it's shorter than the screen; it still scrolls
                        // when taller.
                        .frame(minHeight: max(0, geo.size.height - 64 - 130))
                        .padding(.top, 64)
                        .padding(.bottom, 130)   // content scrolls under the floating bar
                        // Tick: refresh the card when the 15-min window ends.
                        .onChange(of: context.date) { _, _ in
                            storeTick()
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                // Slide left → Tasbih counter. The overlay follows the finger
                // live, then snaps open/closed on release.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { v in
                            guard !showTasbih, v.translation.width < 0,
                                  abs(v.translation.width) > abs(v.translation.height)
                            else { return }
                            tasbihDrag = v.translation.width
                            // A horizontal swipe must not fire the buttons it started on.
                            if tasbihDrag < -8 { store.blockTaps = true }
                        }
                        .onEnded { v in
                            let w = v.translation.width
                            let open = w < -80 || (w < -40 && v.predictedEndTranslation.width < -120)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                showTasbih = open && abs(v.translation.height) < abs(w)
                                tasbihDrag = 0
                            }
                            // Release the block slightly after the touch-up so a
                            // tap fired at release-time still sees it active.
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                store.blockTaps = false
                            }
                        })
            }
            // --- Top corner buttons ---
            .overlay(alignment: .top) { topBar(theme) }
            // --- Floating bottom bar + audio banner + toast ---
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let toast = store.toast {
                        ToastCapsule(text: toast)
                    }
                    if store.audio.isActive, let banner = store.audio.bannerText {
                        AudioStopBar(theme: theme, text: banner)
                    }
                    FloatingNavBar(theme: theme) { showCalendar = true }
                        // The Tasbih page is translucent: fade the nav bar out as
                        // it slides in, back in as it slides out.
                        .opacity(navOpacity)
                }
                // Bar bottom sits ~14pt above the screen edge (into the safe area).
                .padding(.bottom, 14 - geo.safeAreaInsets.bottom)
            }
            // --- Tasbih overlay: slides in from the right, in continuity
            // with the swipe; swipe right (or the back arrow) dismisses it.
            // MUST stay the LAST overlay: overlays stack in declaration order, so
            // anything declared after it (nav bar, banner, toast) would draw on top.
            .overlay {
                if showTasbih || tasbihDrag < 0 {
                    TasbihView(onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showTasbih = false }
                    })
                        .environmentObject(store)
                        // Offset driven by the live drag only — independent of
                        // showTasbih so a removal never jumps before sliding out.
                        .offset(x: tasbihDrag < 0 ? max(0, geo.size.width + tasbihDrag) : tasbihDrag)
                        .ignoresSafeArea()
                        // Slide (not the default fade) on programmatic open/close,
                        // and let a released dismiss-drag keep sliding off-screen.
                        .transition(.move(edge: .trailing))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { v in
                                    if showTasbih && v.translation.width > 0 {
                                        tasbihDrag = v.translation.width
                                    }
                                }
                                .onEnded { v in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        if v.translation.width > 80 {
                                            showTasbih = false
                                        }
                                        tasbihDrag = 0
                                    }
                                })
                }
            }
        }
        .animation(.spring(response: 0.3), value: store.audio.bannerText)
        .animation(.easeOut, value: store.toast)
        .coordinateSpace(name: "mainContent")
        // Tap anywhere OUTSIDE the actions row → exit the jiggle edit mode.
        // Taps inside the row hit its own controls (tiles, X badges, +, done)
        // and must keep edit mode alive (exitJiggle ignores the release that
        // ended the entering long-press via jiggleTapGuard).
        .simultaneousGesture(
            SpatialTapGesture().onEnded { e in
                if !store.activityRowFrame.contains(e.location) {
                    store.exitJiggle()
                }
            })
        .task { await store.boot() }
        // Test hooks: -showTasbih YES opens the counter, -showSettings YES opens Settings.
        .onAppear {
            if UserDefaults.standard.bool(forKey: "showTasbih") { showTasbih = true }
            if UserDefaults.standard.bool(forKey: "showSettings") { showSettings = true }
        }
        // Unchecked Tasbih action tile → slide the counter in from the right.
        .onChange(of: store.tasbihOpenTick) { _, _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showTasbih = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.appDidBecomeActive() } }
        }
        .sheet(isPresented: $showCalendar) { CalendarSheet().environmentObject(store) }
        .sheet(isPresented: $showQuickPray) { QuickPraySheet().environmentObject(store) }
        .sheet(isPresented: $showStats) { StatisticsSheet().environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(store) }
    }

    // MARK: Top bar — mute / quick-pray (left), history + settings (right)

    private func topBar(_ theme: AppTheme) -> some View {
        HStack {
            HStack(spacing: 0) {
                BarIconButton(theme: theme, id: "muteNextBtn",
                              a11y: store.muteAlertActive ? "Unmute next athan" : "Mute next athan",
                              disabled: !store.cardVisible) {
                    // Same contract as the central "next athan is muted" banner:
                    // a manual mute unmutes, a schedule mute opens Settings.
                    if store.muteAlertActive {
                        if store.muteAlertManual { Task { await store.unmuteNext() } }
                        else { showSettings = true }
                    } else {
                        Task { await store.muteNext() }
                    }
                } label: {
                    Image(systemName: store.muteAlertActive ? "speaker.slash.fill" : "speaker.slash")
                        .foregroundStyle(theme.danger)
                }
                BarIconButton(theme: theme, id: "quickPrayBtn", a11y: "Quick pray",
                              action: { showQuickPray = true }) {
                    Image("emoji-zap").resizable().frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 4)
            .background(theme.componentBg, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.componentBorder, lineWidth: 1))
            Spacer()
            HStack(spacing: 0) {
                BarIconButton(theme: theme, id: "historyBtn", a11y: "Statistics",
                              action: { showStats = true }) {
                    Image(systemName: "chart.bar").foregroundStyle(barIconColor(theme))
                }
                BarIconButton(theme: theme, id: "settingsBtn", a11y: "Settings",
                              action: { showSettings = true }) {
                    Image(systemName: "gearshape").foregroundStyle(barIconColor(theme))
                }
            }
            .padding(.horizontal, 4)
            .background(theme.componentBg, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.componentBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// Nav bar alpha: slides to 0 while the Tasbih page drags in, back to 1
    /// while it drags out. Stays 0 while Tasbih is fully open.
    private var navOpacity: Double {
        if showTasbih { return max(0, min(1, tasbihDrag / 120)) }
        return max(0, min(1, 1 + tasbihDrag / 120))
    }

    /// Every second: when next-prayer window has expired, reload next prayer.
    private func storeTick() {
        guard store.cardVisible, !store.cardDateOnly, let np = store.nextPrayer,
              np.date == store.todayStr else { return }
        if let pt = prayerDateTime(np), store.serverNow.timeIntervalSince(pt) > 15 * 60 {
            Task { await store.loadNextPrayer() }
        }
    }

    private func prayerDateTime(_ p: Prayer) -> Date? {
        DateUtil.dayFmt.date(from: "\(p.date) \(p.prayer_time)") ??
        DateUtil.dayFmt.date(from: p.date)?.addingTimeInterval(minutesOf(p.prayer_time))
    }
    private func minutesOf(_ t: String) -> TimeInterval {
        let parts = t.split(separator: ":").compactMap { Double($0) }
        return (parts.first ?? 0) * 3600 + (parts.count > 1 ? parts[1] * 60 : 0)
    }

    // MARK: Weekday mute banner ("🔇 All athans muted for today")

    private func weekdayMuteBanner(_ theme: AppTheme) -> some View {
        Button { Task { await store.unmuteWeekday() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash")
                Text("All athans muted for today")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(theme.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(theme.dangerBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.dangerBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityIdentifier("weekdayMuteBanner")
    }
}
