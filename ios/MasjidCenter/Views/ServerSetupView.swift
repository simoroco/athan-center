import SwiftUI

// MARK: - First-launch server configuration.
// The web app knows its origin; the iOS app needs the server URL once.

struct ServerSetupView: View {
    @EnvironmentObject var store: AppStore
    @State private var url: String = ServerURL.display(AC.defaultServer)
    @State private var checking = false
    @State private var error: String? = nil

    var body: some View {
        let theme = AppTheme(dark: false)
        ZStack {
            Color(hex: 0xF0F4FF).ignoresSafeArea()
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 24) {
                Image("logo")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color(hex: 0xD4AF37).opacity(0.6), radius: 18)

                Text("Masjid Center")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6)

                Text("Connect to your server")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))

                VStack(spacing: 14) {
                    TextField("192.168.1.50 or pi.local", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("serverURLField")

                    if let error {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFCA5A5))
                    }

                    Button {
                        connect()
                    } label: {
                        HStack {
                            if checking { ProgressView().tint(.white) }
                            Text(checking ? "Connecting…" : "Connect")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(theme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("connectButton")
                }
                .padding(20)
                .glassBox(theme, radius: 15)
                .padding(.horizontal, 28)
            }
        }
    }

    private func connect() {
        let candidate = ServerURL.normalize(url)
        checking = true
        error = nil
        Task {
            let client = APIClient(base: candidate)
            do {
                _ = try await client.serverTime()
                await MainActor.run {
                    store.serverBase = candidate
                    checking = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Cannot reach the server. Check the URL and that the Pi is online."
                    checking = false
                }
            }
        }
    }
}
