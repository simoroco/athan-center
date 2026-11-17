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

    private enum ServerState { case idle, checking, reachable, unreachable }
    private enum Kind { case empty, city, server(String) }

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
        var url = s.lowercased().hasPrefix("http") ? s : "http://" + s
        while url.hasSuffix("/") { url.removeLast() }
        return .server(url)
    }

    private var kind: Kind { Self.classify(query) }
    private var serverURL: String? { if case .server(let u) = kind { return u }; return nil }
    private var isCity: Bool { if case .city = kind { return true }; return false }
    private var canConfirm: Bool { serverURL != nil ? serverState == .reachable : place != nil }
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
                    .onTapGesture { focused = false }

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
        }
        .onChange(of: query) { _, q in
            if silent { silent = false; return }
            queryChanged(q)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 16) {
            Image("logo")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color(hex: 0xD4AF37).opacity(0.6), radius: 18)
            Text("Masjid Center")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
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
    }

    /// One reserved slot for hints / validation / errors, so nothing below it jumps.
    private var statusLine: some View {
        Group {
            if let e = message ?? location.error {
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
                    Text("Enter the full server address").foregroundStyle(.white.opacity(0.7))
                }
            } else if let p = place {
                Label(p.city, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.gold)
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
        .disabled(!canConfirm || busy)
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
        Task {
            guard let p = await location.resolve() else { return }   // reason in location.error
            serverState = .idle
            validate(p)
        }
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

    /// Keyboard "search": validates the typed city when no suggestion was picked, or confirms.
    private func submit() {
        focused = false
        switch kind {
        case .empty: return
        case .server: if canConfirm { confirm() }
        case .city:
            if place != nil { confirm(); return }
            message = nil
            busy = true
            Task {
                defer { busy = false }
                guard let p = await LocationManager.search(city: query) else { message = "City not found."; return }
                validate(p)
            }
        }
    }

    private func confirm() {
        guard canConfirm, !busy else { return }
        focused = false
        message = nil
        if let url = serverURL {
            store.connectToServer(url)   // setupComplete flips → main screen
            return
        }
        guard let p = place else { return }
        busy = true
        Task {
            defer { busy = false }
            if await !store.configureStandalone(city: p.city, lat: p.lat, lon: p.lon, tz: p.tz) {
                message = "Could not download prayer times. Check your connection."
            }
        }
    }
}
