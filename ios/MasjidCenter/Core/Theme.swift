import SwiftUI

// MARK: - Theme
// Faithful port of styles.css design tokens (light / body.dark-mode).

struct AppTheme {
    let dark: Bool

    // Base / overlay
    var bgBase: Color { dark ? Color(hex: 0x0D1733) : Color(hex: 0xF0F4FF) }
    var bgOverlay: Color { Color.black.opacity(dark ? 0.82 : 0.45) }

    // Glass components
    var componentBg: Color { dark ? Color(red: 30/255, green: 30/255, blue: 40/255).opacity(0.2) : Color.white.opacity(0.5) }
    var componentBgHover: Color { dark ? Color.white.opacity(0.12) : Color.white.opacity(0.7) }
    var componentBorder: Color { dark ? Color.white.opacity(0.15) : Color.white.opacity(0.7) }
    var componentBorderHover: Color { dark ? Color.white.opacity(0.3) : Color.white.opacity(0.85) }

    // Text
    var textPrimary: Color { dark ? .white : Color(hex: 0x1A1A1A) }
    var textSecondary: Color { dark ? Color(hex: 0xF0F0F0) : Color(hex: 0x1A1A1A) }
    var textAccent: Color { dark ? Color(hex: 0x60A5FA) : Color(hex: 0x2A6DD1) }
    var textCard: Color { dark ? Color(hex: 0x60A5FA) : Color(hex: 0x114BB2) }
    var textShadowColor: Color { dark ? Color.black.opacity(0.6) : Color.white.opacity(0.7) }
    var textShadowStrong: Color { dark ? Color.black.opacity(0.95) : Color.white.opacity(0.95) }
    var muted: Color { dark ? Color(hex: 0xA0AEC0) : Color(hex: 0x6C757D) }
    var helpText: Color { dark ? Color(hex: 0xA0AEC0) : Color(hex: 0x6C757D) }
    var labelText: Color { dark ? Color(hex: 0xCBD5E0) : Color(hex: 0x495057) }

    // Gold / glow
    var cardGlow: Color { Color(red: 212/255, green: 175/255, blue: 55/255).opacity(dark ? 0.75 : 0.7) }
    var cardGlowSoft: Color { Color(red: 212/255, green: 175/255, blue: 55/255).opacity(dark ? 0.5 : 0.45) }
    static let gold = Color(hex: 0xD4AF37)

    // Danger
    var danger: Color { dark ? Color(hex: 0xEF4444) : Color(hex: 0xB91C1C) }
    var dangerBg: Color { dark ? Color(red: 74/255, green: 28/255, blue: 28/255).opacity(0.2) : Color(red: 254/255, green: 226/255, blue: 226/255).opacity(0.5) }
    var dangerBorder: Color { dark ? Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.25) : Color(red: 254/255, green: 202/255, blue: 202/255).opacity(0.8) }
    var dangerPast: Color { Color(hex: 0xEF4444) }
    static let checkmarkOrange = Color(hex: 0xFF8C00)

    // Buttons
    static let btnBlue = Color(hex: 0x2A6DD1)
    static let btnBlueDark = Color(hex: 0x114BB2)
    var dangerBtnBg: Color { dark ? Color(red: 74/255, green: 28/255, blue: 28/255).opacity(0.6) : Color(red: 254/255, green: 226/255, blue: 226/255).opacity(0.7) }
    var dangerBtnText: Color { dark ? Color(hex: 0xFCA5A5) : Color(hex: 0xB91C1C) }

    // Sheets / surfaces
    var sheetBg: Color { dark ? Color(red: 28/255, green: 30/255, blue: 38/255).opacity(0.97) : Color.white.opacity(0.97) }
    var cardSurface: Color { dark ? Color(hex: 0x2D3748) : Color(hex: 0xF8F9FA) }
    var cardSurfaceBorder: Color { dark ? Color(hex: 0x4A5568) : Color(hex: 0xE9ECEF) }
    var inputBg: Color { dark ? Color(hex: 0x2D3748) : .white }
    var inputText: Color { dark ? Color(hex: 0xE4E6EB) : Color(hex: 0x1A1A1A) }
    var inputBorder: Color { dark ? Color(hex: 0x4A5568) : Color(hex: 0xDEE2E6) }
    var sectionHeaderBg: LinearGradient {
        dark
            ? LinearGradient(colors: [Color(hex: 0x2D3748), Color(hex: 0x252830)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0xF8F9FA), Color(hex: 0xE9ECEF)], startPoint: .top, endPoint: .bottom)
    }
    var sheetText: Color { dark ? Color(hex: 0xE4E6EB) : Color(hex: 0x1A1A1A) }

    // Prayer overview cell states
    var poCheckedBg: Color { dark ? Color(hex: 0x1E3A5F) : Color(hex: 0xDBEAFE) }
    var poCheckedText: Color { dark ? Color(hex: 0x60A5FA) : Color(hex: 0x3B82F6) }
    var poLateBg: Color { dark ? Color(hex: 0x3D2E00) : Color(hex: 0xFFF3CD) }
    var poLateText: Color { Color(hex: 0xF59E0B) }
    var poTodayBg: Color { dark ? Color(hex: 0x60A5FA).opacity(0.1) : Color(hex: 0x3B82F6).opacity(0.06) }
    var poTodayLabel: Color { dark ? Color(hex: 0x60A5FA) : Color(hex: 0x3B82F6) }

    // Charts
    static let chartNotDone = Color(hex: 0x6C757D)
    static let chartOnTime = Color(hex: 0x2A6DD1)
    static let chartLate = Color(hex: 0xFF8C00)

    // Brand gradient
    var brandGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x2A6DD1), Color(hex: 0x114BB2)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var audioBannerGradient: LinearGradient {
        dark
            ? LinearGradient(colors: [Color(hex: 0x114BB2), Color(hex: 0x1E3A8A)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [Color(hex: 0x2A6DD1), Color(hex: 0x114BB2)], startPoint: .leading, endPoint: .trailing)
    }
    var duaGradient: LinearGradient {
        dark
            ? LinearGradient(colors: [Color(hex: 0x2D3748), Color(hex: 0x1A202C)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(hex: 0x2A6DD1), Color(hex: 0x114BB2)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var duaText: Color { dark ? Color(hex: 0x60A5FA) : .white }
}

// MARK: - Door metrics (styles.css :root)

struct DoorMetrics {
    let screenWidth: CGFloat
    var doorWidth: CGFloat { min(screenWidth - 16, 374) }
    var bgImageWidth: CGFloat { max(doorWidth * 2.63, screenWidth) * 1.05 }
    var bgImageHeight: CGFloat { bgImageWidth * 1.5 }
    var archHeight: CGFloat { bgImageHeight * 0.15 }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Glass component style (bg + 1pt border + 8pt radius)

struct GlassBox: ViewModifier {
    let theme: AppTheme
    var radius: CGFloat = 8
    func body(content: Content) -> some View {
        content
            .background(theme.componentBg)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.componentBorder, lineWidth: 1)
            )
    }
}

struct GlassCircle: ViewModifier {
    let theme: AppTheme
    func body(content: Content) -> some View {
        content
            .background(theme.componentBg)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.componentBorder, lineWidth: 1))
    }
}

extension View {
    func glassBox(_ theme: AppTheme, radius: CGFloat = 8) -> some View {
        modifier(GlassBox(theme: theme, radius: radius))
    }
    func glassCircle(_ theme: AppTheme) -> some View {
        modifier(GlassCircle(theme: theme))
    }
}

// MARK: - Text glow (text-shadow recipe from styles.css)

struct GlowText: ViewModifier {
    let theme: AppTheme
    var gold: Bool = false

    func body(content: Content) -> some View {
        if gold {
            // next-prayer-card glow
            content
                .shadow(color: Color(hex: 0xD4AF37), radius: 1.5)
                .shadow(color: Color(hex: 0xD4AF37).opacity(0.95), radius: 3.5)
                .shadow(color: Color(hex: 0xD4AF37).opacity(0.75), radius: 7)
                .shadow(color: Color(hex: 0xD4AF37).opacity(0.55), radius: 11)
                .shadow(color: Color.black.opacity(0.45), radius: 1.5, y: 1)
        } else {
            content
                .shadow(color: theme.textShadowStrong, radius: 1)
                .shadow(color: theme.textShadowColor, radius: 3)
                .shadow(color: theme.textShadowColor, radius: 6)
                .shadow(color: theme.textShadowColor, radius: 1, y: 1)
        }
    }
}

extension View {
    func glowText(_ theme: AppTheme, gold: Bool = false) -> some View {
        modifier(GlowText(theme: theme, gold: gold))
    }
}

// MARK: - Web-style toggle switch (60x30 pill, 22pt thumb)

struct WebToggle: View {
    let theme: AppTheme
    @Binding var isOn: Bool
    var disabled: Bool = false
    var onChange: (Bool) -> Void = { _ in }

    var body: some View {
        Button {
            guard !disabled else { return }
            isOn.toggle()
            onChange(isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? (theme.dark ? Color(hex: 0x114BB2) : Color(hex: 0x2A6DD1)) : Color(hex: 0xCCCCCC))
                    .frame(width: 60, height: 30)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(.horizontal, 4)
            }
            .frame(width: 60, height: 30)
            .animation(.easeInOut(duration: 0.25), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityIdentifier("webToggle")
    }
}

// MARK: - Primary button (.btn)

struct PrimaryButton: View {
    let theme: AppTheme
    let title: String
    var systemImage: String? = nil
    var danger: Bool = false
    var disabled: Bool = false
    var accessibility: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(danger ? theme.dangerBtnText : .white)
            .background(danger ? theme.dangerBtnBg : Color(hex: 0x2A6DD1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
        .accessibilityIdentifier(accessibility ?? title)
    }
}

// MARK: - Settings-style row card (input bg in sheets)

struct SheetCard: ViewModifier {
    let theme: AppTheme
    func body(content: Content) -> some View {
        content
            .background(theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardSurfaceBorder.opacity(theme.dark ? 1 : 0), lineWidth: 1))
    }
}
extension View {
    func sheetCard(_ theme: AppTheme) -> some View { modifier(SheetCard(theme: theme)) }
}
