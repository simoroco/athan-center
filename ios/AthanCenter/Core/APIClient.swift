import Foundation

// MARK: - APIClient — covers every endpoint used by the web app.

enum APIError: Error, LocalizedError {
    case badURL, http(Int, String?), decode(Error)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL"
        case .http(let code, let msg): return msg ?? "HTTP \(code)"
        case .decode(let e): return "Invalid response: \(e.localizedDescription)"
        }
    }
}

actor APIClient {
    let base: String
    private let session: URLSession

    init(base: String) {
        self.base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: cfg)
    }

    private func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var comps = URLComponents(string: base + path)
        if !query.isEmpty { comps?.queryItems = query }
        guard let u = comps?.url else { throw APIError.badURL }
        return u
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let u = try url(path, query: query)
        let (data, resp) = try await session.data(from: u)
        try validate(resp, data)
        return data
    }

    private func post(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await session.data(for: req)
        try validate(resp, data)
        return data
    }

    private func validate(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var msg: String? = nil
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                msg = (obj["error"] ?? obj["message"]) as? String
            }
            throw APIError.http(http.statusCode, msg)
        }
    }

    private func decode<T: Decodable>(_ t: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode(error) }
    }

    /// Percent-encode a single path segment (audio filenames contain spaces & '&').
    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    // MARK: Server time / info

    func serverTime() async throws -> ServerTime { try decode(ServerTime.self, await get("/api/server-time")) }
    func updateInfo() async throws -> UpdateInfo { try decode(UpdateInfo.self, await get("/api/update-info")) }
    func audioSupport() async throws -> AudioSupport { try decode(AudioSupport.self, await get("/api/audio-support")) }

    // MARK: Prayers

    func prayers(date: String) async throws -> [Prayer] {
        (try? decode([Prayer].self, await get("/api/prayers/\(date)"))) ?? []
    }
    func nextPrayer() async throws -> Prayer? {
        let data = try await get("/api/prayers/next/upcoming")
        if String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return nil }
        return try? decode(Prayer.self, data)
    }
    func updatePrayers() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/update-prayers"))
    }
    func nextPrayerText(lang: String = "FR") async throws -> String {
        let data = try await get("/api/next-prayer-text", query: [URLQueryItem(name: "lang", value: lang)])
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Prayer checks

    func prayerChecks(date: String) async throws -> [PrayerCheck] {
        (try? decode([PrayerCheck].self, await get("/api/prayer-checks/\(date)"))) ?? []
    }
    func prayerChecksRange(year: Int) async throws -> [PrayerCheck] {
        let resp = try decode(ChecksRangeResponse.self, await get("/api/prayer-checks-range", query: [URLQueryItem(name: "year", value: String(year))]))
        return resp.checks
    }
    @discardableResult
    func togglePrayerCheck(date: String, prayer: String) async throws -> Int {
        let r = try decode(ToggleResult.self, await post("/api/prayer-checks/toggle", body: ["date": date, "prayer_name": prayer]))
        return r.checked
    }
    func resetPrayerChecks() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/prayer-checks/reset"))
    }

    // MARK: Daily activities

    func dailyActivities(date: String) async throws -> [DailyActivity] {
        (try? decode([DailyActivity].self, await get("/api/daily-activities/\(date)"))) ?? []
    }
    @discardableResult
    func toggleDailyActivity(date: String, activity: String) async throws -> Int {
        let r = try decode(ToggleResult.self, await post("/api/daily-activities/toggle", body: ["date": date, "activity_name": activity]))
        return r.checked
    }

    // MARK: Settings

    func settings() async throws -> [String: String] {
        (try? decode([String: String].self, await get("/api/settings"))) ?? [:]
    }
    func setSetting(_ key: String, _ value: String) async throws {
        _ = try await post("/api/settings", body: ["key": key, "value": value])
    }
    func exportSettingsCSV() async throws -> String {
        let data = try await get("/api/settings/export")
        return String(data: data, encoding: .utf8) ?? ""
    }
    func importSettings(csv: String) async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/settings/import", body: ["csvData": csv]))
    }
    func restoreDefaults() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/settings/restore-defaults"))
    }

    // MARK: Schedule matrix

    func prayerSchedule() async throws -> [ScheduleEntry] {
        (try? decode([ScheduleEntry].self, await get("/api/prayer-schedule"))) ?? []
    }
    func setScheduleCell(prayer: String, day: Int, enabled: Bool) async throws {
        _ = try await post("/api/prayer-schedule", body: ["prayer_name": prayer, "day_of_week": day, "enabled": enabled ? 1 : 0])
    }
    func bulkSchedule(type: String, target: Any, enabled: Bool) async throws {
        _ = try await post("/api/prayer-schedule/bulk", body: ["type": type, "target": target, "enabled": enabled ? 1 : 0])
    }

    // MARK: Mute / silence

    func skipNextStatus() async throws -> Bool {
        (try? decode(SkipStatus.self, await get("/api/skip-next")))?.skip ?? false
    }
    func muteNextAthan() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/skip-next"))
    }
    func resetSkipNext() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await post("/api/skip-next/reset"))
    }
    func permanentSilence() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await get("/api/silence/permanent"))
    }
    func mutedWeekdays() async throws -> [MutedWeekday] {
        (try? decode([MutedWeekday].self, await get("/api/muted-weekdays"))) ?? []
    }
    func setMutedWeekday(_ weekday: Int, muted: Bool) async throws {
        _ = try await post("/api/muted-weekdays/\(weekday)", body: ["muted": muted ? 1 : 0])
    }

    // MARK: Audio / Quran

    func checkAthanTime() async throws -> CheckAthanResponse {
        try decode(CheckAthanResponse.self, await get("/api/check-athan-time"))
    }
    func checkFridayQuran() async throws -> CheckQuranResponse {
        try decode(CheckQuranResponse.self, await get("/api/check-friday-quran"))
    }
    func stopAudio() async throws {
        _ = try await get("/api/stop-audio")
    }
    func testAthanServer() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await get("/api/test-athan-server"))
    }
    func testQuranServer() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await get("/api/test-quran-server"))
    }
    func triggerFridayQuran() async throws -> SuccessMessage {
        try decode(SuccessMessage.self, await get("/api/trigger-friday-quran"))
    }
    func fridayQuranStatus() async throws -> FridayQuranStatus {
        try decode(FridayQuranStatus.self, await get("/api/friday-quran-status"))
    }
    func audioFiles() async throws -> [String] {
        (try? decode([String].self, await get("/api/audio-files"))) ?? []
    }
    func quranFiles() async throws -> [String] {
        (try? decode([String].self, await get("/api/quran-files"))) ?? []
    }
    func audioDevices() async throws -> [AudioDevice] {
        (try? decode(AudioDevicesResponse.self, await get("/api/audio/devices")))?.devices ?? []
    }

    /// Streaming URLs (AVPlayer) — nonisolated, base is a let.
    nonisolated func athanURL(_ file: String) -> URL? {
        let e = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        return URL(string: base + "/api/audio/" + e)
    }
    nonisolated func quranURL(_ file: String) -> URL? {
        let e = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        return URL(string: base + "/api/quran/" + e)
    }
    nonisolated func startupURL() -> URL? { URL(string: base + "/audio/system/startup.mp3") }

    // MARK: Statistics

    func statisticsPrayers() async throws -> [WeekStat] {
        (try? decode(StatsResponse.self, await get("/api/statistics/prayers")))?.statistics ?? []
    }
    func statisticsActivities() async throws -> [WeekStat] {
        (try? decode(StatsResponse.self, await get("/api/statistics/activities")))?.statistics ?? []
    }
    func exportExcel() async throws -> Data {
        try await get("/api/statistics/export-excel")
    }
    func ramadanDates() async throws -> [RamadanDate] {
        (try? decode(RamadanResponse.self, await get("/api/hijri/ramadan-weeks")))?.ramadan_dates ?? []
    }
}
