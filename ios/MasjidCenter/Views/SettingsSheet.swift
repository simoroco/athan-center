import SwiftUI
import UniformTypeIdentifiers
import MapKit

// MARK: - SettingsSheet — replicates the settings modal (accordion sections).

struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var openSection: Int? = 0
    @State private var icsDraft = ""
    @State private var serverDraft = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportURL: URL?
    @State private var confirmReset = false
    @State private var confirmRestore = false
    @State private var confirmResetApp = false
    @State private var editingAction: TrackedAction? = nil
    @State private var showActionEditor = false
    @State private var actionDeleteTarget: ActionItem? = nil
    @State private var busy = false
    @State private var cityDraft = ""
    @StateObject private var location = LocationManager()
    @StateObject private var citySearch = CitySearchCompleter()

    private var theme: AppTheme { store.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Dua card
                    VStack(spacing: 8) {
                        if store.isRamadanSelectedDate || isTodayRamadan {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(AppTheme.gold)
                        }
                        Text("لا تنسى أخاك في دعائك")
                            .font(.system(size: 20, weight: .semibold))
                        HStack(spacing: 6) {
                            Text("Don't forget your brother in your du'a")
                                .font(.system(size: 16, weight: .semibold))
                            Image("emoji-pray").resizable().frame(width: 18, height: 18)
                            Image("emoji-pray").resizable().frame(width: 18, height: 18)
                        }
                    }
                    .foregroundStyle(theme.duaText)
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .background(theme.duaGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(theme.dark ? Color(hex: 0x4A5568) : .clear, lineWidth: 2)
                    )
                    .shadow(color: Color(hex: 0x2A6DD1).opacity(0.25), radius: 15, y: 10)

                    accordion(0, "General", "wrench") { generalSection }
                    accordion(1, "Location", "mappin") { locationSection }
                    accordion(2, "Athan call", "building") { athanSection }
                    accordion(3, "Tasbih & Objectives", "checklist") { tasbihObjectivesSection }
                    accordion(4, "Quran recitation", "book") { quranSection }
                    accordion(5, "Audio control", "speaker.wave.1") { audioSection }
                    accordion(6, "Backup & Restore", "externaldrive") { backupSection }

                    Text(AC.appVersion)
                        .font(.system(size: 13)).foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .background(theme.sheetBg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(theme.dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .accessibilityIdentifier("closeSettings")
                }
            }
        }
        .task {
            icsDraft = store.settings["ics_url"] ?? ""
            serverDraft = store.serverDisplayHost
            if !store.isStandalone {
                await store.loadUpdateInfo()
                await store.syncTime()
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                // The main-screen toast is hidden behind this sheet too.
                if let toast = store.toast {
                    ToastCapsule(text: toast)
                }
                // The main-screen banner is hidden behind this sheet: audio must be stoppable from here too.
                if store.audio.isActive, let text = store.audio.bannerText {
                    AudioStopBar(theme: theme, text: text,
                                 stopId: "stopAudioBannerSheet", barId: "audioBannerSheet")
                }
            }
            .padding(.bottom, 10)
        }
        .animation(.spring(response: 0.3), value: store.audio.bannerText)
        .animation(.easeOut, value: store.toast)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let csv = try? String(contentsOf: url, encoding: .utf8) {
                    Task {
                        busy = true
                        let msg = await store.importConfig(csv)
                        busy = false
                        store.showToast(msg)
                    }
                }
            }
        }
        .sheet(isPresented: $showExporter) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .alert("Reset prayers & objectives?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { Task { await store.resetChecks() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all check marks from prayers and objectives (Coran, Tasbih & Nawafil)")
        }
        .alert("Restore default configuration?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) { Task { busy = true; await store.restoreDefaults(); busy = false } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset ALL settings to their default values")
        }
        .alert("Reset the iOS app?", isPresented: $confirmResetApp) {
            Button("Reset & quit", role: .destructive) {
                store.resetApp()
                dismiss()
                Task {
                    // Brief beat so the async cleanup (pending-notification removal)
                    // lands before the process exits; relaunch shows SetupView.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    exit(0)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All settings, checks and objectives stored on this iPhone will be erased, then the app will close. Relaunch it to run the first-launch setup again. Nothing changes on the server.")
        }
        .sheet(isPresented: $showActionEditor) {
            ActionEditSheet(editing: editingAction).environmentObject(store)
        }
        .alert(
            actionDeleteTarget?.builtin == true
                ? "Hide \"\(actionDeleteTarget?.name ?? "")\"?"
                : "Delete \"\(actionDeleteTarget?.name ?? "")\"?",
            isPresented: Binding(
                get: { actionDeleteTarget != nil },
                set: { if !$0 { actionDeleteTarget = nil } }),
            presenting: actionDeleteTarget
        ) { a in
            Button(a.builtin ? "Hide" : "Delete", role: .destructive) {
                store.removeAction(id: a.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { a in
            Text(a.builtin
                ? "You can restore it later from this section."
                : "This custom objective and its history will be deleted.")
        }
    }

    private var currentCityName: String {
        if store.isStandalone { return store.local.snap.cityName.isEmpty ? "—" : store.local.snap.cityName }
        return store.serverCityName
    }

    private func applyPlace(_ p: Place) async {
        let ok = await store.changeLocation(city: p.city, lat: p.lat, lon: p.lon, tz: p.tz)
        store.showToast(ok ? "Location set to \(p.city)" : "Could not update prayer times")
        if ok { icsDraft = store.settings["ics_url"] ?? icsDraft; await store.loadUpdateInfo() }
    }

    private func searchCity() {
        guard !busy else { return }
        citySearch.clear()
        Task {
            busy = true
            defer { busy = false }
            guard let p = await LocationManager.search(city: cityDraft) else {
                store.showToast("City not found"); return
            }
            await applyPlace(p)
            cityDraft = ""
        }
    }

    private func pickSuggestion(_ c: MKLocalSearchCompletion) {
        guard !busy else { return }
        Task {
            busy = true
            defer { busy = false }
            guard let p = await CitySearchCompleter.resolve(c) else {
                store.showToast("City not found"); return
            }
            citySearch.clear()
            cityDraft = ""
            await applyPlace(p)
        }
    }

    private var isTodayRamadan: Bool { store.ramadanDates.contains(store.todayStr) }

    // MARK: - Accordion wrapper

    @ViewBuilder
    private func accordion<C: View>(_ index: Int, _ title: String, _ icon: String,
                                    @ViewBuilder _ content: () -> C) -> some View {
        let isOpen = openSection == index
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    openSection = isOpen ? nil : index
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(isOpen ? .white : theme.sheetText)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(isOpen ? theme.brandGradient : theme.sectionHeaderBg)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("section-\(title)")

            if isOpen {
                content()
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.dark ? Color(hex: 0x4A5568) : Color(hex: 0xE9ECEF), lineWidth: 1)
        )
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Operating mode, stated clearly at the top.
            HStack(spacing: 8) {
                Image(systemName: store.isStandalone ? "iphone" : "wifi")
                Text(store.isStandalone
                     ? "Standalone app"
                     : "Sync: \(store.serverDisplayHost)")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(store.isStandalone ? theme.textAccent : .white)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(store.isStandalone ? AnyShapeStyle(theme.inputBg) : AnyShapeStyle(theme.brandGradient)))
            .accessibilityIdentifier("modeLabel")

            infoCard

            ToggleRow(theme: theme, title: "Dark mode",
                      isOn: Binding(get: { store.settings["dark_mode"] == "1" },
                                    set: { v in Task { await store.updateSetting("dark_mode", v ? "1" : "0") } }))
            .accessibilityIdentifier("darkModeToggle")

            Text("Enable dark mode for a comfortable viewing experience in low-light environments")
                .font(.system(size: 13)).foregroundStyle(theme.helpText)

            // iOS-specific: server address (the web app is served same-origin).
            VStack(alignment: .leading, spacing: 6) {
                Text("Sync with Masjid Center Server").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
                HStack(spacing: 8) {
                    TextField("192.168.1.50 or pi.local", text: $serverDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                        .font(.system(size: 14))
                        .padding(10)
                        .background(theme.inputBg)
                        .foregroundStyle(theme.inputText)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: 1))
                        .accessibilityIdentifier("serverField")
                    Button("Apply") { store.connectToServer(serverDraft) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(hex: 0x2A6DD1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("applyServerBtn")
                }
                Text(store.isStandalone
                     ? "Optional: connect to Masjid Center Server to sync data and have Athan on its speakers."
                     : "IP address or domain of Masjid Center Server (optional)")
                    .font(.system(size: 12)).foregroundStyle(theme.helpText)
                if !store.isStandalone {
                    Button("Disconnect — use standalone mode") { store.switchToStandalone() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.danger)
                        .accessibilityIdentifier("standaloneModeBtn")
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            if store.isStandalone {
                infoRow("mappin", "City:", store.local.snap.cityName.isEmpty ? "My location" : store.local.snap.cityName)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    infoRow("clock", "Device time:", liveServerTime)
                }
                .frame(height: 20)
                infoRow("calendar", "Last prayer times update:", store.local.snap.lastIcsFetch)
                infoRow("wifi.slash", "Mode:", "Standalone (no server)")
            } else {
            infoRow("mappin", "City:", store.serverCityName)
            infoRow("calendar", "Server date:", store.serverTimeInfo?.date ?? "--/--/----")
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                infoRow("clock", "Server time:", liveServerTime)
            }
            .frame(height: 20)
            infoRow("desktopcomputer", "Server IP:", store.serverTimeInfo?.ip ?? "Loading...")
            infoRow("textformat", "Server hostname:", store.serverTimeInfo?.hostname ?? "Loading...")
            infoRow("hourglass", "Last prayer times update:", lastUpdateText)
            infoRow("timer", "Next prayer times update:", nextUpdateText)
            infoRow("speaker.wave.2", "Server audio support:", store.audioSupport?.message ?? "Loading...")
            }
            if !store.isStandalone && !store.connected {
                infoRow("wifi.slash", "Connection:", "Offline — local cache, will resync")
            }
        }
        .padding(15)
        .sheetCard(theme)
    }

    // MARK: - Tasbih & Objectives (iOS-only: goal + tracked objectives list)

    private var tasbihObjectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            tasbihGoalPicker

            Text("Objectives").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            VStack(spacing: 0) {
                let hidden = store.local.snap.hiddenBuiltins
                ForEach(Array(store.allActions.enumerated()), id: \.element.id) { i, a in
                    objectiveRow(a)
                    if i < store.allActions.count - 1 || !hidden.isEmpty {
                        Divider().overlay(theme.inputBorder)
                    }
                }
                ForEach(Array(hidden.enumerated()), id: \.element) { i, n in
                    hiddenObjectiveRow(n)
                    if i < hidden.count - 1 { Divider().overlay(theme.inputBorder) }
                }
            }
            .sheetCard(theme)

            PrimaryButton(theme: theme, title: "Add objective",
                          systemImage: "plus", accessibility: "addObjectiveBtn") {
                editingAction = nil
                showActionEditor = true
            }
            Text("The pencil edits a custom objective. The trash hides a built-in (restorable below) or deletes a custom one.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
        }
    }

    private func objectiveRow(_ a: ActionItem) -> some View {
        HStack(spacing: 10) {
            if a.isAsset {
                Image(a.icon).resizable().frame(width: 24, height: 24)
            } else {
                Text(a.icon).font(.system(size: 20))
            }
            Text(a.name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.sheetText)
            if a.counter {
                Text("counter").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
            }
            Spacer()
            if !a.builtin {
                Button {
                    editingAction = store.local.snap.customActions.first { $0.id == a.id }
                    showActionEditor = true
                } label: {
                    Image(systemName: "pencil").font(.system(size: 15))
                        .foregroundStyle(theme.textAccent)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editObjective-\(a.name)")
            }
            Button { actionDeleteTarget = a } label: {
                Image(systemName: "trash").font(.system(size: 15))
                    .foregroundStyle(theme.danger)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deleteObjective-\(a.name)")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func hiddenObjectiveRow(_ name: String) -> some View {
        HStack(spacing: 10) {
            if let bi = AC.activities.first(where: { $0.name == name }) {
                Image(bi.icon).resizable().frame(width: 24, height: 24).opacity(0.5)
            }
            Text(name).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.muted)
            Text("hidden").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.muted)
            Spacer()
            Button("Restore") { store.restoreBuiltin(id: name) }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textAccent)
                .accessibilityIdentifier("restoreObjective-\(name)")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - iOS-only: Tasbih goal

    private var tasbihGoalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasbih goal").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            HStack(spacing: 8) {
                ForEach([10, 11, 33, 99, 100, 101], id: \.self) { n in
                    let on = store.tasbihTarget == n
                    Button { store.tasbihTarget = n } label: {
                        Text("\(n)")
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(on ? .white : theme.sheetText)
                            .background(on ? AnyShapeStyle(theme.brandGradient) : AnyShapeStyle(theme.inputBg))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tasbihTarget-\(n)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Swipe left on the main screen to open the Tasbih counter")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
        }
    }

    private var liveServerTime: String {
        DateUtil.hmsFmt.string(from: store.serverNow)
    }
    private var lastUpdateText: String {
        guard let l = store.updateInfo?.last_update else { return "Never" }
        return formatISO(l) + "  (\(store.updateInfo?.prayers_count ?? 0) prayers)"
    }
    private var nextUpdateText: String {
        guard let n = store.updateInfo?.next_update else { return "Loading..." }
        return formatISO(n)
    }
    private func formatISO(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: s) else { return s }
        let out = DateFormatter()
        out.dateFormat = "dd/MM/yyyy HH:mm"
        return out.string(from: d)
    }

    private func infoRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).frame(width: 16)
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.sheetText)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("City:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            Text(currentCityName)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.sheetText)
                .accessibilityIdentifier("currentCity")
            PrimaryButton(theme: theme, title: "Use my location",
                          systemImage: "location.fill", disabled: busy || location.resolving,
                          accessibility: "locateBtn") {
                Task {
                    busy = true
                    defer { busy = false }
                    guard let p = await location.resolve() else {
                        store.showToast(location.error ?? "Location unavailable"); return
                    }
                    await applyPlace(p)
                }
            }
            HStack(spacing: 8) {
                TextField("Enter a city (e.g. Paris)", text: $cityDraft)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(theme.inputBg).foregroundStyle(theme.inputText)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: 1))
                    .accessibilityIdentifier("cityField")
                    .onSubmit { searchCity(); hideKeyboard() }
                Button { searchCity() } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 40)
                        .background(Color(hex: 0x2A6DD1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(busy || cityDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("citySearchBtn")
            }
            .onChange(of: cityDraft) { _, q in citySearch.update(q) }
            if !citySearch.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(citySearch.results.prefix(5).enumerated()), id: \.offset) { i, r in
                        Button { pickSuggestion(r) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Color(hex: 0x2A6DD1))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(theme.sheetText)
                                    if !r.subtitle.isEmpty {
                                        Text(r.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.helpText)
                                    }
                                }
                                .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("citySuggestion-\(i)")
                    }
                }
                .background(theme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: 1))
            }
            Text(store.isStandalone
                 ? "Prayer times are downloaded directly from the ICS link on this iPhone."
                 : "The new location is applied to the server ICS link.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            Text("ICS link:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            TextField("ICS calendar URL", text: $icsDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .onSubmit { hideKeyboard() }
                .font(.system(size: 14))
                .padding(10)
                .background(theme.inputBg).foregroundStyle(theme.inputText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: 1))
                .accessibilityIdentifier("icsUrlField")
            Text("Use the ICS link to configure your location and athan times, then retrieve it. Please visit: Prayer WebCal (prayerwebcal.dsultan.com)")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            PrimaryButton(theme: theme, title: "Apply ICS link configuration",
                          systemImage: "arrow.clockwise", disabled: busy,
                          accessibility: "applyIcsBtn") {
                Task {
                    busy = true
                    await store.updateSetting("ics_url", icsDraft)
                    busy = false
                    store.showToast("Configuration applied")
                }
            }
            PrimaryButton(theme: theme, title: "Update athan times now",
                          systemImage: "arrow.clockwise", disabled: busy,
                          accessibility: "forceUpdateBtn") {
                Task {
                    busy = true
                    let msg = await store.forceUpdatePrayers()
                    busy = false
                    store.showToast(msg)
                }
            }
            Text("Prayer times are automatically updated every day at 12:00 AM\nFetches the next 3 months - Past data is preserved\nThe reference time is the server time (not the app time)")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
        }
    }

    // MARK: - Athan call

    /// File names displayed without the .mp3 extension.
    private func fileLabels(_ files: [String]) -> [String: String] {
        Dictionary(files.map { f in
            (f, f == "default_athan.mp3" ? "Athan (Nice An-Nour Institute)"
                : f.replacingOccurrences(of: ".mp3", with: ""))
        }, uniquingKeysWith: { _, new in new })
    }

    private var athanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Athan call audio file:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            PickerField(theme: theme,
                        options: store.isStandalone ? AC.bundledAthans : store.audioFiles,
                        labels: fileLabels(store.isStandalone ? AC.bundledAthans : store.audioFiles),
                        selection: Binding(
                            get: { store.settings["audio_file"] ?? "" },
                            set: { v in Task { await store.updateSetting("audio_file", v) } }))
                .accessibilityIdentifier("audioFilePicker")
            Text(store.isStandalone
                 ? "Athan files bundled with the app — they play entirely on this iPhone."
                 : "Upload your audio files into /audio/athan so they appear in this list.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            Text("Athan Schedule:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            Text("Select a day to configure athans. Use \"Whole week\" to enable/disable a prayer for the entire week.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
            ScheduleMatrixView(theme: theme)
        }
    }

    // MARK: - Quran recitation

    private var quranSection: some View {
        let files = store.isStandalone ? AC.bundledQurans : store.quranFiles
        return VStack(alignment: .leading, spacing: 12) {
            Text("Al Kahf Sourat audio file:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            PickerField(theme: theme,
                        options: files,
                        labels: fileLabels(files),
                        selection: Binding(
                            get: { store.settings["friday_quran_file"] ?? files.first ?? "" },
                            set: { v in Task { await store.updateSetting("friday_quran_file", v) } }))
                .accessibilityIdentifier("fridayQuranFilePicker")
            Text(store.isStandalone
                 ? "Bundled with the app — the recitation plays entirely on this iPhone."
                 : "Upload your audio files into /audio/coran so they appear in this list.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            PrimaryButton(theme: theme, title: "Listen to Sourat Al Kahf now",
                          systemImage: "speaker.wave.1", accessibility: "playFullQuranBtn") {
                Task { await store.playFullQuran() }
            }
            Text(store.isStandalone
                 ? "Plays the bundled file on this iPhone. Recitation continues until the end."
                 : "Plays on server and/or app (depending on audio output setting). Recitation continues until the end.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            Text("Schedule every Friday:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            ToggleRow(theme: theme, title: "Al Kahf Sourat on Friday",
                      isOn: Binding(get: { store.settings["friday_quran_enabled"] == "1" },
                                    set: { v in Task { await store.updateSetting("friday_quran_enabled", v ? "1" : "0") } }))
            .accessibilityIdentifier("fridayQuranToggle")
            Text("Al Kahf sourat listening every Friday at a specific time")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            QuranTimePicker(theme: theme)
        }
    }

    // MARK: - Audio control

    @ViewBuilder
    private var audioSection: some View {
        // Merged "iOS notifications" toggle (was Athan notifications + Play
        // audio on this iPhone): alerts AND plays enabled audio on this iPhone.
        ToggleRow(theme: theme, title: "iOS notifications",
                  isOn: Binding(get: { store.notificationsEnabled },
                                set: { store.notificationsEnabled = $0 }))
            .accessibilityIdentifier("notificationsToggle")
        Text("Notifies at each enabled prayer and plays the athan / Quran recitation on this iPhone")
            .font(.system(size: 12)).foregroundStyle(theme.helpText)

        if store.isStandalone { standaloneAudioSection } else { serverAudioSection }
    }

    private var standaloneAudioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrimaryButton(theme: theme, title: "Stop playing Athan",
                          systemImage: "stop.circle", danger: true,
                          accessibility: "stopAudioBtn") {
                Task { await store.stopAllAudio() }
            }
            PrimaryButton(theme: theme, title: "Athan call now (app)",
                          systemImage: "speaker.wave.2", accessibility: "testAthanBtn") {
                store.testAthanWeb()
            }
            Text("The athan plays on this iPhone at each enabled prayer time while the app is open. Use notifications (iPhone settings) to be alerted when it is closed.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
        }
    }

    private var serverAudioSection: some View {
        let supported = store.audioSupport?.supported ?? true
        return VStack(alignment: .leading, spacing: 12) {
            // Audio output
            Text("Audio output:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            PickerField(theme: theme,
                        options: ["both", "server", "browser"],
                        labels: ["both": "Both (Server and App)", "server": "Server only", "browser": "App only"],
                        selection: Binding(
                            get: { store.settings["audio_output"] ?? "both" },
                            set: { v in Task { await store.updateSetting("audio_output", v) } }),
                        disabled: !supported)
                .accessibilityIdentifier("audioOutputPicker")
            if !supported {
                Text("Server audio not available. Forced to \"App only\" mode.")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.danger)
            }
            Text("• Server: Audio is played on the Raspberry Pi speakers\n• App: Audio is played in this app (if it is open)\n• Both: Audio is played on the server and in the app")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            // Server audio device
            Text("Server audio device:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            PickerField(theme: theme,
                        options: ["auto"] + store.audioDevices.map { $0.card },
                        labels: deviceLabels,
                        selection: Binding(
                            get: { store.settings["audio_card"] ?? "auto" },
                            set: { v in Task { await store.updateSetting("audio_card", v) } }),
                        disabled: !supported)
                .accessibilityIdentifier("audioCardPicker")
            Text("Select which audio output to use on the server (Raspberry Pi / Linux only). Auto-detect prioritizes USB devices, then HDMI.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            // Volume
            VolumeSlider(theme: theme,
                         label: "Server volume",
                         value: Binding(
                            get: { Double(store.settings["volume"] ?? "50") ?? 50 },
                            set: { v in Task { await store.updateSetting("volume", String(Int(v))) } }),
                         disabled: !supported)
            Text("Server volume control: the app always plays at 100%.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            // Fajr volume
            ToggleRow(theme: theme, title: "Use different volume for Fajr Athan",
                      isOn: Binding(get: { store.settings["sync_fajr_volume"] == "1" },
                                    set: { v in
                                        Task {
                                            await store.updateSetting("sync_fajr_volume", v ? "1" : "0")
                                            if !v { await store.updateSetting("fajr_volume", store.settings["volume"] ?? "50") }
                                        }
                                    }))
            Text("When enabled, you can set a specific volume for Fajr below. When disabled, Fajr uses the same volume as other prayers.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)
            VolumeSlider(theme: theme,
                         label: "Fajr Athan volume",
                         value: Binding(
                            get: { Double(store.settings["fajr_volume"] ?? "50") ?? 50 },
                            set: { v in Task { await store.updateSetting("fajr_volume", String(Int(v))) } }),
                         disabled: !supported || store.settings["sync_fajr_volume"] != "1")

            ToggleRow(theme: theme, title: "Server startup sound",
                      isOn: Binding(get: { store.settings["play_on_startup"] == "1" },
                                    set: { v in Task { await store.updateSetting("play_on_startup", v ? "1" : "0") } }),
                      disabled: !supported)
            ToggleRow(theme: theme, title: "App startup sound",
                      isOn: Binding(get: { store.settings["play_on_page_load"] == "1" },
                                    set: { v in Task { await store.updateSetting("play_on_page_load", v ? "1" : "0") } }))

            PrimaryButton(theme: theme, title: "Stop playing Athan and Quran recitation",
                          systemImage: "stop.circle", danger: true,
                          accessibility: "stopAudioBtn") {
                Task { await store.stopAllAudio() }
            }
            Text("Stop all audio playback (athan, Quran recitation, startup, tests) on both the app and server.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            // Tests
            Text("Athan & Quran audio tests:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            HStack(spacing: 10) {
                PrimaryButton(theme: theme, title: "Athan call now (app)",
                              systemImage: "speaker.wave.2", accessibility: "testAthanBtn") {
                    store.testAthanWeb()
                }
                PrimaryButton(theme: theme, title: "Athan call now (server)",
                              systemImage: "speaker.wave.2", disabled: !supported,
                              accessibility: "testAthanServerBtn") {
                    Task { await store.testAthanServer() }
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(theme: theme, title: "Recite Quran (30s app preview)",
                              systemImage: "speaker.wave.2", accessibility: "testQuranBtn") {
                    store.testQuranWeb()
                }
                PrimaryButton(theme: theme, title: "Recite Quran (30s server)",
                              systemImage: "speaker.wave.2", disabled: !supported,
                              accessibility: "testQuranServerBtn") {
                    Task { await store.testQuranServer() }
                }
            }
            Text("Quickly test Athan and Quran recitation on the app or directly on the server speakers. Tests are limited to 30 seconds.")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            // API commands
            apiCommandsCard
        }
    }

    private var deviceLabels: [String: String] {
        var l = ["auto": "Auto-detect (USB/HDMI)"]
        for d in store.audioDevices { l[d.card] = d.displayName ?? d.name }
        return l
    }

    private var apiCommandsCard: some View {
        let base = store.serverBase
        let cmds: [(String, String)] = [
            ("Get next prayer (text):", "curl \(base)/api/next-prayer-text?lang=FR"),
            ("Test Athan on server (30 seconds):", "curl \(base)/api/test-athan-server"),
            ("Test Quran on server (30 seconds):", "curl \(base)/api/test-quran-server"),
            ("Mute next Athan:", "curl \(base)/api/mute-next-athan"),
            ("Unmute next Athan:", "curl \(base)/api/skip-next/reset"),
            ("Stop all playing audio in the server:", "curl \(base)/api/stop-audio"),
            ("Permanent silence (athan calls & quran recitation):", "curl \(base)/api/silence/permanent"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Use the API:").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.labelText)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(cmds, id: \.0) { label, cmd in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(size: 13, weight: .semibold))
                        Text(cmd)
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(theme.textAccent)
                            .textSelection(.enabled)
                    }
                    .onTapGesture {
                        UIPasteboard.general.string = cmd
                        store.showToast("Copied")
                    }
                }
            }
            .padding(15)
            .sheetCard(theme)
        }
        .foregroundStyle(theme.sheetText)
    }

    // MARK: - Backup & Restore

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PrimaryButton(theme: theme, title: "Export configuration",
                              systemImage: "square.and.arrow.up", disabled: busy,
                              accessibility: "exportConfigBtn") {
                    Task { await exportCSV() }
                }
                PrimaryButton(theme: theme, title: "Import configuration",
                              systemImage: "square.and.arrow.down", disabled: busy,
                              accessibility: "importConfigBtn") {
                    showImporter = true
                }
            }
            Text("Export all settings to a CSV file for backup or import to restore configuration")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            PrimaryButton(theme: theme, title: "Reset iOS app",
                          systemImage: "iphone", danger: true, disabled: busy,
                          accessibility: "resetAppBtn") {
                confirmResetApp = true
            }
            Text("Erases all app data on this iPhone, then quits — relaunch to redo the first-launch setup. The server is not affected.")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.danger)

            PrimaryButton(theme: theme, title: "Reset prayers & objectives",
                          systemImage: "arrow.clockwise", danger: true, disabled: busy,
                          accessibility: "resetChecksBtn") {
                confirmReset = true
            }
            Text("Remove all check marks from prayers and objectives (Coran, Tasbih & Nawafil)")
                .font(.system(size: 12)).foregroundStyle(theme.helpText)

            PrimaryButton(theme: theme, title: "Restore default configuration",
                          systemImage: "arrow.clockwise", danger: true, disabled: busy,
                          accessibility: "restoreDefaultsBtn") {
                confirmRestore = true
            }
            Text("This will reset ALL settings to their default values")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.danger)

            PrimaryButton(theme: theme, title: "Permanent silence (mute all athans + Friday Quran)",
                          systemImage: "speaker.slash", danger: true, disabled: busy,
                          accessibility: "permanentSilenceBtn") {
                Task { await store.permanentSilence(); store.showToast("Permanent silence enabled") }
            }
        }
        .overlay {
            if busy { ProgressView().scaleEffect(1.3).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.15)) }
        }
    }

    private func exportCSV() async {
        busy = true
        if let csv = await store.exportConfigCSV() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("masjid-center-config-\(store.todayStr).csv")
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showExporter = true
        } else {
            store.showToast("Export failed")
        }
        busy = false
    }
}

// MARK: - Toggle row (.prayer-toggle)

struct ToggleRow: View {
    let theme: AppTheme
    let title: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.sheetText)
            Spacer()
            WebToggle(theme: theme, isOn: $isOn, disabled: disabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .sheetCard(theme)
    }
}

// MARK: - Picker field (styled like .input-field select)

struct PickerField: View {
    let theme: AppTheme
    let options: [String]
    var labels: [String: String] = [:]
    @Binding var selection: String
    var disabled: Bool = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(labels[opt] ?? opt) { selection = opt }
            }
        } label: {
            HStack {
                Text(labels[selection] ?? (selection.isEmpty ? "Select…" : selection))
                    .font(.system(size: 14))
                    .foregroundStyle(selection.isEmpty ? theme.muted : theme.inputText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
            }
            .padding(10)
            .background(theme.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inputBorder, lineWidth: 1))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Volume slider (0–200%, >100 → warning)

struct VolumeSlider: View {
    let theme: AppTheme
    let label: String
    @Binding var value: Double
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label): \(Int(value))%")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.labelText)
            Slider(value: $value, in: 0...200, step: 1)
                .tint(value > 100 ? Color(hex: 0x8B0000) : Color(hex: 0x2A6DD1))
                .disabled(disabled)
                .accessibilityIdentifier("\(label)Slider")
            if value > 100 {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: 0x8B0000))
                    Text("WARNING: Volume above 100% may cause audio distortion or damage to speakers!")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x8B0000))
                }
            }
        }
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Friday Quran time picker (hour 06-21 : minute step 5)

struct QuranTimePicker: View {
    @EnvironmentObject var store: AppStore
    let theme: AppTheme

    private var hour: Binding<String> {
        Binding(
            get: { String((store.settings["friday_quran_time"] ?? "07:00").prefix(2)) },
            set: { h in
                let m = String((store.settings["friday_quran_time"] ?? "07:00").suffix(2))
                Task { await store.updateSetting("friday_quran_time", "\(h):\(m)") }
            })
    }
    private var minute: Binding<String> {
        Binding(
            get: { String((store.settings["friday_quran_time"] ?? "07:00").suffix(2)) },
            set: { m in
                let h = String((store.settings["friday_quran_time"] ?? "07:00").prefix(2))
                Task { await store.updateSetting("friday_quran_time", "\(h):\(m)") }
            })
    }

    var body: some View {
        HStack(spacing: 10) {
            PickerField(theme: theme,
                        options: (6...21).map { String(format: "%02d", $0) },
                        selection: hour)
                .frame(width: 90)
                .accessibilityIdentifier("fridayHourPicker")
            Text(":").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.sheetText)
            PickerField(theme: theme,
                        options: stride(from: 0, through: 55, by: 5).map { String(format: "%02d", $0) },
                        selection: minute)
                .frame(width: 90)
                .accessibilityIdentifier("fridayMinutePicker")
        }
    }
}
