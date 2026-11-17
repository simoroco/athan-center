import SwiftUI

// MARK: - NextPrayerCard — the signature glowing card over the door arch.

struct NextPrayerCard: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    let metrics: DoorMetrics
    let now: Date
    var onOpenSettings: () -> Void = {}

    @State private var pulsing = false

    private var door: CGFloat { metrics.doorWidth }

    /// Seconds between server-now and the next prayer datetime (negative when passed).
    private var diff: TimeInterval? {
        guard let np = store.nextPrayer, np.date == store.todayStr,
              let pt = datetime(np) else { return nil }
        return pt.timeIntervalSince(store.serverNow)
    }

    private func datetime(_ p: Prayer) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: "\(p.date) \(p.prayer_time)")
    }

    /// Inside the 15-minute "Time to pray" window.
    private var inPrayerWindow: Bool {
        guard let d = diff else { return false }
        return d <= 0 && d > -15 * 60
    }

    private var countdownText: String {
        guard let d = diff else { return "" }
        if d > 0 {
            let t = Int(d)
            return String(format: "In %dh %dm %ds", t / 3600, (t % 3600) / 60, t % 60)
        }
        let remaining = max(0, Int(15 * 60 + d))
        return String(format: "%dm %ds remaining", remaining / 60, remaining % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.cardVisible {
                if store.cardDateOnly {
                    dateOnlyCard
                } else if let np = store.nextPrayer {
                    prayerCard(np)
                }
            }
        }
        .frame(width: door)
        .frame(minHeight: metrics.archHeight * 0.82)
        .padding(.top, 60)
        .padding(.bottom, 0)
        .onAppear { pulsing = true }
    }

    // MARK: Date-only placeholder (displayDateOnlyCard)

    private var dateOnlyCard: some View {
        VStack(spacing: 4) {
            Spacer()
            HStack(spacing: 8) {
                Text(DateUtil.relativeDayLabel(store.selectedDate, today: store.serverNow))
                    .font(.system(size: door * 0.09, weight: .bold).monospaced())
                if store.isRamadanSelectedDate {
                    Image(systemName: "moon.fill")
                        .font(.system(size: door * 0.05))
                        .foregroundStyle(AppTheme.gold)
                }
            }
            .foregroundStyle(theme.textPrimary)
            .glowText(theme)

            Text(DateUtil.shortFmt.string(from: store.selectedDate))
                .font(.system(size: door * 0.07, weight: .semibold).monospaced())
                .foregroundStyle(theme.textPrimary)
                .glowText(theme)
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dateOnlyCard")
    }

    // MARK: Next prayer card

    private func prayerCard(_ np: Prayer) -> some View {
        let playing = inPrayerWindow
        return VStack(spacing: 0) {
            Text(playing ? "Time to pray" : "Next Prayer")
                .font(.system(size: door * 0.053, weight: .bold))
                .foregroundStyle(theme.textCard.opacity(0.95))
                .glowText(theme, gold: true)
                .padding(.bottom, door * 0.025)

            HStack(spacing: 8) {
                if store.ramadanDates.contains(np.date) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: door * 0.09))
                        .foregroundStyle(AppTheme.gold)
                        .glowText(theme, gold: true)
                }
                Text(AC.displayPrayerName(np.prayer_name))
                    .font(.system(size: door * 0.115, weight: .heavy).monospaced())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.textCard)
            .glowText(theme, gold: true)
            .padding(.bottom, door * 0.011)

            Text(np.prayer_time)
                .font(.system(size: door * 0.118, weight: .bold))
                .foregroundStyle(theme.textCard)
                .glowText(theme, gold: true)
                .padding(.bottom, door * 0.025)

            // Mute banner occupies the countdown slot (mute-alert-banner in index.html).
            if store.muteAlertActive && store.showMuteBannerContext {
                muteBanner
            } else {
                Text(countdownText)
                    .font(.system(size: door * 0.053, weight: .bold))
                    .foregroundStyle(theme.textCard.opacity(0.95))
                    .glowText(theme, gold: true)
            }
        }
        .scaleEffect(playing && pulsing ? 1.06 : 1)
        .shadow(color: playing ? AppTheme.gold.opacity(0.9) : .clear, radius: playing ? 18 : 0)
        .shadow(color: playing ? AppTheme.gold.opacity(0.5) : .clear, radius: playing ? 40 : 0)
        .animation(playing ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : .default, value: pulsing)
        .onAppear { pulsing = true }
        .contentShape(Rectangle())
        .onTapGesture {
            if store.audio.isPlaying { Task { await store.stopAllAudio() } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nextPrayerCard")
    }

    // MARK: Mute alert banner (replaces countdown slot)

    private var muteBanner: some View {
        Button {
            if store.muteAlertManual {
                Task { await store.unmuteNext() }
            } else {
                onOpenSettings()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "speaker.slash")
                Text(store.muteAlertText)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.danger)
            .frame(width: door * 0.833)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(theme.dangerBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.dangerBorder, lineWidth: 1))
            .shadow(color: Color(hex: 0xDC2626).opacity(0.08), radius: 4, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("muteAlertBanner")
    }
}
