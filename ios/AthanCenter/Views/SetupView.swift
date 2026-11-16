import SwiftUI

// MARK: - First-launch setup. Standalone is the default: the app asks for the
// position once (to build the ICS prayer-time feed), server connection is
// optional afterwards from Settings.

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var location = LocationManager()
    @State private var working = false
    @State private var error: String? = nil
    @State private var showServer = false
    @State private var showManualCity = false
    @State private var serverURL: String = AC.defaultServer
    @State private var manualCity: String = ""

    var body: some View {
        let theme = AppTheme(dark: false)
        ZStack {
            Color(hex: 0xF0F4FF).ignoresSafeArea()
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Image("logo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color(hex: 0xD4AF37).opacity(0.6), radius: 18)

                    Text("Athan Center")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)

                    VStack(spacing: 14) {
                        Text("Set your location to get prayer times")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)

                        Button { useLocation() } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                Text(working ? "Locating…" : "Use my location")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(.white)
                            .background(theme.brandGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(working)
                        .accessibilityIdentifier("useLocationButton")

                        Button {
                            showManualCity.toggle()
                        } label: {
                            HStack {
                                Image(systemName: "keyboard")
                                Text("Enter my city manually")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if showManualCity {
                            HStack {
                                TextField("City (e.g. Paris)", text: $manualCity)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityIdentifier("cityField")
                                Button { useCity() } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(Color(hex: 0xD4AF37))
                                }
                                .accessibilityIdentifier("cityGoButton")
                            }
                        }

                        if let e = error ?? location.error {
                            Text(e)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: 0xFCA5A5))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(18)
                    .glassBox(theme, radius: 15)

                    // --- Optional: connect to a server ---
                    VStack(spacing: 10) {
                        Button { withAnimation { showServer.toggle() } } label: {
                            HStack {
                                Image(systemName: "server.rack")
                                Text("I have an Athan Center server")
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Image(systemName: showServer ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(.white.opacity(0.75))
                        }
                        if showServer {
                            HStack {
                                TextField("http://192.168.1.50:7777", text: $serverURL)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(10)
                                    .background(Color.white.opacity(0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityIdentifier("serverURLField")
                                Button { connectServer() } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(Color(hex: 0xD4AF37))
                                }
                                .accessibilityIdentifier("connectButton")
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: Location flow

    private func useLocation() {
        working = true
        error = nil
        Task {
            defer { working = false }
            guard let r = await location.resolve() else { return }
            await apply(r)
        }
    }

    private func useCity() {
        guard !manualCity.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            guard let r = await LocationManager.search(city: manualCity) else {
                error = "City not found."
                return
            }
            await apply(r)
        }
    }

    private func apply(_ p: Place) async {
        if await !store.configureStandalone(city: p.city, lat: p.lat, lon: p.lon, tz: p.tz) {
            error = "Could not download prayer times. Check your connection."
        }
    }

    private func connectServer() {
        var candidate = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.lowercased().hasPrefix("http") { candidate = "http://" + candidate }
        working = true
        error = nil
        Task {
            let client = APIClient(base: candidate)
            do {
                _ = try await client.serverTime()
                await MainActor.run { store.connectToServer(candidate) }
            } catch {
                await MainActor.run {
                    self.error = "Cannot reach the server. Check the URL."
                    working = false
                }
            }
        }
    }
}
