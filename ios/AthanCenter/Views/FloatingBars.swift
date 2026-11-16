import SwiftUI

// MARK: - Floating glass surfaces (iOS 26 Liquid Glass, material fallback on iOS 18+).
// Light mode uses a brighter, more opaque fill so icons stay readable over the dark door photo.

struct FloatingGlass<S: InsettableShape>: ViewModifier {
    let dark: Bool
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let tint: Color = dark ? Color.black.opacity(0.30) : Color.white.opacity(0.78)
            let glass: Glass = Glass.regular.tint(tint).interactive()
            content.glassEffect(glass, in: shape)
        } else {
            let fill: AnyShapeStyle = dark ? AnyShapeStyle(Material.ultraThinMaterial) : AnyShapeStyle(Color.white.opacity(0.9))
            content
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.18 : 0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }
}

extension View {
    func floatingGlass<S: InsettableShape>(dark: Bool, in shape: S) -> some View {
        modifier(FloatingGlass(dark: dark, shape: shape))
    }
}

// MARK: - Round icon button used in the top corners (mute, history, settings, quick pray)

struct BarIconButton<Label: View>: View {
    let theme: AppTheme
    let id: String
    var a11y: String
    var disabled = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityIdentifier(id)
        .accessibilityLabel(a11y)
    }
}

/// Icon tint that stays readable on the light-mode bright glass and on the dark-mode material.
func barIconColor(_ theme: AppTheme) -> Color {
    theme.dark ? .white : Color(hex: 0x1F2937)
}

// MARK: - Floating bottom navigation bar (previous / today / calendar / next)

struct FloatingNavBar: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    var onCalendar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            navButton("chevron.left", id: "prevDay", label: "Previous day") { store.goPrevDay() }
            navButton("house", id: "todayBtn", label: "Today", disabled: store.isViewingToday) { store.goToday() }
            navButton("calendar", id: "calendarBtn", label: "Calendar") { onCalendar() }
            navButton("chevron.right", id: "nextDay", label: "Next day") { store.goNextDay() }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .floatingGlass(dark: theme.dark, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navBar")
    }

    private func navButton(_ icon: String, id: String, label: String, disabled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(barIconColor(theme))
                .frame(width: 76, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}

// MARK: - Audio banner with an explicit Stop control (used on the main screen AND inside sheets)

struct AudioStopBar: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme
    let text: String
    var stopId = "stopAudioBanner"
    var barId = "audioBanner"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .symbolEffect(.pulse)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button { Task { await store.stopAllAudio() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: 0x8B0000))
                .padding(.horizontal, 14).frame(height: 34)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(stopId)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.audioBannerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color(hex: 0x2A6DD1).opacity(0.4), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(barId)
    }
}
