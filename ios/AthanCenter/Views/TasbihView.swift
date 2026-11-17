import SwiftUI
import UIKit

// MARK: - Tasbih — fullscreen dhikr counter (iOS-only feature).
// Tap anywhere: +1, haptic + flash. At the target: long vibration, the Tasbih
// activity of the day is auto-checked (blue) and the page closes itself.

struct TasbihView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    /// Overlay presentation uses this; sheet presentation falls back to dismiss().
    var onClose: (() -> Void)? = nil
    @State private var count = 0
    @State private var flash = false
    @State private var done = false

    var target: Int { store.tasbihTarget }

    var body: some View {
        ZStack {
            // Mostly-opaque dim: the main page only hints through underneath.
            Color.black.opacity(0.82).ignoresSafeArea()
            // Subtle radial glow matching the app's gold accent.
            RadialGradient(
                colors: [Color(hex: 0xD4AF37).opacity(0.14), Color.clear],
                center: .center, startRadius: 40, endRadius: 420)
                .ignoresSafeArea()

            if flash {
                Color(hex: 0xD4AF37).opacity(0.18).ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                HStack {
                    Button { onClose?() ?? dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 46, height: 46)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 52)
                    .accessibilityIdentifier("tasbihClose")
                    Spacer()
                }
                Spacer()

                Text("Tasbih")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD4AF37).opacity(0.8))
                    .tracking(4)

                Text(done ? "Alhamdulillah" : "\(count)")
                    .font(.system(size: done ? 44 : 120, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: Color(hex: 0xD4AF37).opacity(done ? 0.9 : 0.35), radius: 24)
                    .scaleEffect(flash ? 1.06 : 1.0)
                    .accessibilityIdentifier("tasbihCount")

                Text(done ? "Goal reached — \(target)" : "of \(target)")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                if !done {
                    Text("Tap anywhere to count")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer().frame(height: 50)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasbihScreen")
    }

    private func tap() {
        guard !done else { return }
        count += 1
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
        }
        if count >= target {
            done = true
            store.completeTasbih()
            // Short celebration pause, then the page closes itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                onClose?() ?? dismiss()
            }
            // Long completion vibration.
            let g = UINotificationFeedbackGenerator()
            g.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
