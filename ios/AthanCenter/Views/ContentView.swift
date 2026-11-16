import SwiftUI

// MARK: - ContentView — replicates index.html layout over the door background.

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var showCalendar = false
    @State private var showQuickPray = false
    @State private var showStats = false
    @State private var showSettings = false

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

                            DateNavView(theme: theme, showCalendar: $showCalendar)

                            ActionsRow(
                                theme: theme,
                                showQuickPray: $showQuickPray,
                                showStats: $showStats,
                                showSettings: $showSettings
                            )
                        }
                        .frame(width: metrics.doorWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                        .padding(.bottom, 20)
                        // Tick: refresh the card when the 15-min window ends.
                        .onChange(of: context.date) { _, _ in
                            storeTick()
                        }
                    }
                }
                .scrollIndicators(.hidden)

                // --- Floating audio notification banner ---
                if let banner = store.audio.bannerText {
                    audioBanner(theme, text: banner)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 18)
                }

                // --- Toast ---
                if let toast = store.toast {
                    Text(toast)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 80)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.3), value: store.audio.bannerText)
        .animation(.easeOut, value: store.toast)
        .task { await store.boot() }
        .onDisappear { store.stopLoops() }
        .onAppear { store.startLoops() }
        .sheet(isPresented: $showCalendar) { CalendarSheet().environmentObject(store) }
        .sheet(isPresented: $showQuickPray) { QuickPraySheet().environmentObject(store) }
        .sheet(isPresented: $showStats) { StatisticsSheet().environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(store) }
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

    // MARK: Audio notification banner

    private func audioBanner(_ theme: AppTheme, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 20))
                .symbolEffect(.pulse)
            Button { Task { await store.stopAllAudio() } } label: {
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { store.audio.hideBanner() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("closeAudioBanner")
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(theme.audioBannerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: 0x2A6DD1).opacity(0.4), radius: 10, y: 4)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("audioBanner")
        .onTapGesture { Task { await store.stopAllAudio() } }
    }
}
