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
                    .position(x: geo.size.width / 2, y: metrics.bgImageHeight * 0.06)
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
                        .padding(.top, 50)
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
                        }
                        .onEnded { v in
                            let w = v.translation.width
                            let open = w < -80 || (w < -40 && v.predictedEndTranslation.width < -120)
                            withAnimation(.easeOut(duration: 0.25)) {
                                showTasbih = open && abs(v.translation.height) < abs(w)
                                tasbihDrag = 0
                            }
                        })
            }
            // --- Top corner buttons ---
            .overlay(alignment: .top) { topBar(theme) }
            // --- Tasbih overlay: slides in from the right, in continuity
            // with the swipe; swipe right (or the X) dismisses it.
            .overlay {
                if showTasbih || tasbihDrag < 0 {
                    TasbihView(onClose: {
                        withAnimation(.easeOut(duration: 0.25)) { showTasbih = false }
                    })
                        .environmentObject(store)
                        .offset(x: showTasbih ? max(0, tasbihDrag) : max(0, geo.size.width + tasbihDrag))
                        .ignoresSafeArea()
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { v in
                                    if showTasbih && v.translation.width > 0 {
                                        tasbihDrag = v.translation.width
                                    }
                                }
                                .onEnded { v in
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        if v.translation.width > 80 {
                                            showTasbih = false
                                        }
                                        tasbihDrag = 0
                                    }
                                })
                        .zIndex(20)
                }
            }
            // --- Floating bottom bar + audio banner + toast ---
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let toast = store.toast {
                        Text(toast)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.black.opacity(0.78))
                            .clipShape(Capsule())
                            .transition(.opacity)
                            .accessibilityIdentifier("toast")
                    }
                    if store.audio.isActive, let banner = store.audio.bannerText {
                        AudioStopBar(theme: theme, text: banner)
                    }
                    FloatingNavBar(theme: theme) { showCalendar = true }
                }
                .padding(.bottom, 6)
            }
        }
        .animation(.spring(response: 0.3), value: store.audio.bannerText)
        .animation(.easeOut, value: store.toast)
        .task { await store.boot() }
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
            Group {
                if store.pastDayIncomplete {
                    BarIconButton(theme: theme, id: "quickPrayBtn", a11y: "Quick pray",
                                  action: { showQuickPray = true }) {
                        Image("emoji-zap").resizable().frame(width: 22, height: 22)
                    }
                } else {
                    let off = store.skipNext || !store.cardVisible
                    BarIconButton(theme: theme, id: "muteNextBtn", a11y: "Mute next athan", disabled: off,
                                  action: { Task { await store.muteNext() } }) {
                        Image(systemName: "speaker.slash").foregroundStyle(theme.danger)
                    }
                }
            }
            .floatingGlass(dark: theme.dark, in: Circle())
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
            .floatingGlass(dark: theme.dark, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
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
