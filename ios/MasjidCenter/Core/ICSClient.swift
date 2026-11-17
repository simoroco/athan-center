import Foundation

// MARK: - ICSClient — fetches + parses PrayerWebCal ICS exactly like server.js.
// Standalone mode gets prayer times directly instead of through the Pi API.

enum ICSClient {

    /// Builds the PrayerWebCal URL for a position (same format the server stores).
    static func icsURL(city: String, lat: Double, lon: Double, tz: String) -> String {
        let c = city.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "Location"
        let tzEnc = tz.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "Europe%2FParis"
        return "https://prayerwebcal.dsultan.com/ics/\(c)/cq=0:csr=0:ct=0:ee=0:qs=0:srs=0:ss=0:sus=0:ts=0:tz=\(tzEnc):x=\(lat):y=\(lon)"
    }

    /// mapPrayerNameFromWebCal — identical mapping to server.js.
    static func mapName(_ webCal: String) -> String {
        ["Fajr": "Fajr | Sobh", "Dhuhr": "Dohr", "Asr": "Asr",
         "Maghrib": "Maghrib", "Isha": "Isha"][webCal] ?? webCal
    }

    /// Downloads + parses the ICS feed → [date: [Prayer]] for the next 3 months.
    static func fetch(urlString: String) async throws -> [String: [Prayer]] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("MasjidCenter-iOS", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ ics: String) -> [String: [Prayer]] {
        // Unfold continuation lines (ICS spec: line starting with space/tab continues previous).
        let unfolded = ics.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        let today = DateUtil.dateString(Date())
        let limit = DateUtil.dateString(Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())

        var result: [String: [Prayer]] = [:]
        var inEvent = false, summary = "", dtstart = ""
        for raw in unfolded.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "BEGIN:VEVENT" { inEvent = true; summary = ""; dtstart = "" }
            else if line == "END:VEVENT" {
                inEvent = false
                if let (date, time) = parseDT(dtstart), date >= today, date <= limit {
                    let p = Prayer(id: nil, date: date, prayer_name: mapName(summary), prayer_time: time)
                    result[date, default: []].append(p)
                }
            } else if inEvent {
                if line.hasPrefix("SUMMARY") { summary = String(line.drop(while: { $0 != ":" }).dropFirst()) }
                else if line.hasPrefix("DTSTART") { dtstart = line }
            }
        }
        for date in result.keys {
            result[date]?.sort { $0.prayer_time < $1.prayer_time }
        }
        return result
    }

    /// Extracts (date, "HH:mm") from DTSTART params — value is UTC or TZID local.
    static func parseDT(_ line: String) -> (String, String)? {
        guard let value = line.components(separatedBy: ":").last, value.count >= 15 else { return nil }
        let isUTC = value.hasSuffix("Z")
        let ymdhms = String(value.prefix(15))
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = isUTC ? TimeZone(identifier: "UTC") : TimeZone.current
        guard let d = f.date(from: ymdhms) else { return nil }
        return (DateUtil.dateString(d), DateUtil.timeString(d))
    }
}
