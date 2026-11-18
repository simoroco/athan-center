import SwiftUI
import MapKit

// MARK: - First-launch setup — ONE field does everything.
//   • Type a city → live suggestions (pick one, or press search) → standalone mode.
//   • Type a server address → live reachability check → server mode.
//   • The trailing button fills the field from the device position.
// The mode is inferred from what the user typed; "Continue" only unlocks once a
// city is validated (position / suggestion / search) or a server answered.

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var location = LocationManager()
    @StateObject private var citySearch = CitySearchCompleter()
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var place: Place? = nil
    @State private var serverState: ServerState = .idle
    @State private var busy = false
    @State private var message: String? = nil
    @State private var serverTask: Task<Void, Never>? = nil
    /// Set for a programmatic `query` change so onChange doesn't invalidate the place it just validated.
    @State private var silent = false
    /// Search-field frame in the "setup" space — background taps inside it must NOT dismiss the keyboard.
    @State private var fieldFrame: CGRect = .zero
    /// True while the background LAN scan is looking for a server.
    @State private var scanning = false
    /// Server found by the LAN scan — offered as a tappable chip, NEVER written
    /// into the field (injected text corrupted the user's own typing: a city
    /// typed over a pre-filled IP became "192.168.1.51Paris" → misclassified).
    @State private var discovered: String? = nil

    private enum ServerState { case idle, checking, reachable, unreachable }
    private enum Kind: Equatable { case empty, city, server(String) }

    // MARK: Input classification

    private static func classify(_ raw: String) -> Kind {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .empty }
        func matches(_ p: String) -> Bool { s.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        let isServer = matches(#"^https?:"#)                                        // http:// …
            || matches(#"^(localhost|[a-z0-9-]+):\d{1,5}(/\S*)?$"#)                 // host:port
            || matches(#"^\d+\.[\d.]*(:\d{1,5})?(/\S*)?$"#)                         // 192.168.1.5(:7777)
            || matches(#"^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d{1,5})?(/\S*)?$"#)           // pi.local, my.domain.org
            || matches(#"^localhost(/\S*)?$"#)
        guard isServer else { return .city }
        return .server(ServerURL.normalize(s))
    }

    private var kind: Kind { Self.classify(query) }
    private var serverURL: String? { if case .server(let u) = kind { return u }; return nil }
    private var isCity: Bool { if case .city = kind { return true }; return false }
    /// The button stays tappable whenever something is typed: confirm()
    /// performs the validation itself and shows the loader while doing so.
    private var canConfirm: Bool { kind != .empty && !busy }
    private var showResults: Bool { isCity && place == nil && !citySearch.results.isEmpty }

    // MARK: Body

    var body: some View {
        let theme = store.theme
        GeometryReader { geo in
            let metrics = DoorMetrics(screenWidth: geo.size.width)
            ZStack {
                // Same background recipe as the main screen.
                theme.bgBase.ignoresSafeArea()
                Image("background")
                    .resizable()
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(width: metrics.bgImageWidth, height: metrics.bgImageHeight)
                    .position(x: geo.size.width / 2, y: metrics.bgImageHeight * 0.16)
                    .clipped()
                    .ignoresSafeArea()
                theme.bgOverlay.ignoresSafeArea()
                    // Tap outside the field → dismiss the keyboard. Without the
                    // frame check this gesture could fight the field's own tap
                    // and intermittently steal its focus.
                    .gesture(
                        SpatialTapGesture(coordinateSpace: .named("setup"))
                            .onEnded { v in
                                if !fieldFrame.insetBy(dx: -12, dy: -12).contains(v.location) {
                                    focused = false
                                }
                            })

                VStack(spacing: 14) {
                    if !focused { header.transition(.opacity.combined(with: .scale(scale: 0.9))) }
                    field(theme)
                    statusLine
                    resultsRegion(theme)
                    confirmButton(theme)
                }
                .padding(.horizontal, 24)
                .padding(.top, focused ? 8 : 0)
                .padding(.bottom, 16)
                .frame(maxWidth: 520, maxHeight: .infinity, alignment: focused ? .top : .center)
                .animation(.spring(response: 0.35, dampingFraction: 0.88), value: focused)
            }
            .coordinateSpace(name: "setup")
        }
        .onChange(of: query) { _, q in
            if silent { silent = false; return }
            queryChanged(q)
        }
        .task {
            // Background LAN scan: probe the subnet for a Masjid Center server
            // and offer it as a chip — the field itself is never touched. The
            // task is cancelled automatically when the setup view disappears.
            scanning = true
            defer { scanning = false }
            guard let url = await ServerDiscovery.findServer(), !Task.isCancelled else { return }
            guard query.isEmpty, place == nil else { return }
            discovered = url
        }
    }

    // MARK: Pieces

    private var header: some View {
        let theme = store.theme
        return VStack(spacing: 16) {
            Image("logo")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(theme.textCard)
                .glowText(theme, gold: true)
                .frame(width: 96, height: 96)
            Text("Masjid Center")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(theme.textCard)
                .glowText(theme, gold: true)
        }
        .padding(.bottom, 10)
    }

    private func field(_ theme: AppTheme) -> some View {
        HStack(spacing: 10) {
            Image(systemName: serverURL != nil ? "server.rack" : "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: 22)
            TextField("City or server address", text: $query)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 17))
                .foregroundStyle(theme.inputText)
                .tint(theme.textAccent)
                .disabled(busy)
                .onSubmit { submit() }
                .accessibilityIdentifier("setupField")
            Button { useLocation() } label: {
                Group {
                    if location.resolving { ProgressView().tint(theme.textAccent) }
                    else { Image(systemName: "location.fill") }
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.textAccent)
                .frame(width: 44, height: 44)
                .background(theme.textAccent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(location.resolving || busy)
            .accessibilityLabel("Use my location")
            .accessibilityIdentifier("useLocationButton")
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(height: 56)
        .background(theme.inputBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(focused ? AppTheme.gold : theme.inputBorder, lineWidth: focused ? 2 : 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        // Explicit focus on tap anywhere in the row + frame tracking so the
        // background tap-to-dismiss can ignore taps that land on the field.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("setup")) } action: {
            fieldFrame = $0
        }
    }

    /// One reserved slot for hints / validation / errors, so nothing below it jumps.
    private var statusLine: some View {
        Group {
            if busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(serverURL != nil ? "Connecting…" : "Downloading prayer times…")
                }
                .foregroundStyle(.white.opacity(0.85))
            } else if let e = message ?? location.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: 0xFCA5A5))
            } else if serverURL != nil {
                switch serverState {
                case .checking:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Checking server…")
                    }
                    .foregroundStyle(.white.opacity(0.85))
                case .reachable:
                    Label("Server reachable", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0x4ADE80))
                case .unreachable:
                    Label("Cannot reach the server", systemImage: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: 0xFCA5A5))
                case .idle:
                    Text("Enter the server IP address or domain").foregroundStyle(.white.opacity(0.7))
                }
            } else if let p = place {
                Label(p.city, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.gold)
            } else if scanning && kind == .empty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Searching the local network for a server…")
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("Type a city or a server address, or use your location")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.5), radius: 3)
        .frame(maxWidth: .infinity, minHeight: 34)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("setupStatus")
    }

    /// Takes all the room left while typing, so the suggestions get the maximum height.
    private func resultsRegion(_ theme: AppTheme) -> some View {
        ZStack(alignment: .top) {
            if showResults {
                ViewThatFits(in: .vertical) {
                    suggestionList(theme)
                    ScrollView { suggestionList(theme) }
                        .scrollDismissesKeyboard(.interactively)
                }
                .background(theme.inputBg, in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            } else if let discovered, kind == .empty {
                discoveredChip(theme, discovered)
            }
        }
        .frame(maxHeight: focused ? .infinity : nil, alignment: .top)
    }

    private func suggestionList(_ theme: AppTheme) -> some View {
        let items = Array(citySearch.results.enumerated())
        return VStack(spacing: 0) {
            ForEach(items, id: \.offset) { i, r in
                Button { pick(r) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.textAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 16, weight: .semibold))
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle).font(.system(size: 13)).foregroundStyle(theme.muted)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.inputText)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("citySuggestion-\(i)")
                if i < items.count - 1 { Divider().overlay(theme.inputBorder) }
            }
        }
    }

    /// Server found on the local network — same card look as a city suggestion.
    private func discoveredChip(_ theme: AppTheme, _ ip: String) -> some View {
        Button { pickDiscovered(ip) } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Masjid Center Server nearby")
                        .font(.system(size: 16, weight: .semibold))
                    Text(ip)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.inputText)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(theme.inputBg, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .accessibilityIdentifier("setupDiscoveredServer")
    }

    private func confirmButton(_ theme: AppTheme) -> some View {
        Button { confirm() } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(serverURL != nil ? "Connect" : "Continue")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(.white)
            .background(theme.brandGradient, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm)
        .opacity(canConfirm ? 1 : 0.4)
        .accessibilityIdentifier("setupConfirmButton")
    }

    // MARK: Behaviour

    private func setQuery(_ s: String) {
        guard s != query else { return }
        silent = true
        query = s
    }

    /// Any user edit invalidates the previous validation and restarts the right pipeline for the new text.
    private func queryChanged(_ q: String) {
        place = nil
        message = nil
        location.error = nil
        serverTask?.cancel()
        serverTask = nil
        switch Self.classify(q) {
        case .empty:
            serverState = .idle
            citySearch.clear()
        case .city:
            serverState = .idle
            citySearch.update(q)
        case .server(let url):
            citySearch.clear()
            checkServer(url)
        }
    }

    /// Debounced real-time check: the address is only accepted once /api/server-time answers.
    private func checkServer(_ url: String) {
        guard URL(string: url)?.host?.isEmpty == false else { serverState = .idle; return }
        serverState = .checking
        serverTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let ok = (try? await APIClient(base: url).serverTime()) != nil
            guard !Task.isCancelled else { return }
            serverState = ok ? .reachable : .unreachable
        }
    }

    private func validate(_ p: Place) {
        citySearch.clear()
        setQuery(p.city)
        place = p
        focused = false
    }

    private func useLocation() {
        focused = false
        message = nil
        serverTask?.cancel()
        busy = true   // blocks the confirm button while resolving
        Task {
            defer { busy = false }
            guard let p = await location.resolve() else { return }   // reason in location.error
            serverState = .idle
            validate(p)
        }
    }

    /// Fills the field with the discovered server — a deliberate user choice,
    /// so the live check runs and Connect unlocks like a typed address.
    private func pickDiscovered(_ ip: String) {
        focused = false
        message = nil
        discovered = nil
        query = ip   // non-silent edit → checkServer → "Checking server…" → reachable
    }

    private func pick(_ c: MKLocalSearchCompletion) {
        focused = false
        message = nil
        busy = true
        Task {
            defer { busy = false }
            guard let p = await CitySearchCompleter.resolve(c) else { message = "City not found."; return }
            validate(p)
        }
    }

    /// Keyboard "search": same as tapping the confirm button — validate then go.
    private func submit() {
        focused = false
        confirm()
    }

    /// A reachable check that can run at confirm time: reuses the debounced
    /// result when it already succeeded, pings the server directly otherwise.
    private func ensureServerReachable(_ url: String) async -> Bool {
        if serverState == .reachable { return true }
        serverTask?.cancel()
        let ok = (try? await APIClient(base: url).serverTime()) != nil
        serverState = ok ? .reachable : .unreachable
        return ok
    }

    /// Always runs the full pipeline for whatever was typed — never gated by
    /// a not-yet-finished validation (that made taps silently do nothing).
    /// `busy` drives the loader for the whole validate + configure duration.
    private func confirm() {
        guard canConfirm else { return }
        focused = false
        message = nil
        busy = true
        Task {
            defer { busy = false }
            switch kind {
            case .empty:
                return
            case .server(let url):
                if await ensureServerReachable(url) {
                    await store.connectToServerAndLoad(url)   // setupComplete flips → main screen
                } else {
                    message = "Cannot reach the server"
                }
            case .city:
                var p = place
                if p == nil { p = await LocationManager.search(city: query) }
                guard let p else { message = "City not found."; return }
                if await !store.configureStandalone(city: p.city, lat: p.lat, lon: p.lon, tz: p.tz) {
                    message = "Could not download prayer times. Check your connection."
                }
            }
        }
    }
}
