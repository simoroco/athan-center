import Foundation

// MARK: - ServerDiscovery — finds a Masjid Center server on the local network.
//
// The server doesn't advertise Bonjour/mDNS, so the setup view scans the
// device's own Wi-Fi subnet instead: every host is probed on
// http://<ip>:7777/api/server-time with a short timeout, and the first one
// answering with a valid ServerTime payload wins.

enum ServerDiscovery {

    private static let port = 7777
    private static let probeTimeout: TimeInterval = 1.5
    private static let concurrency = 64

    /// Returns the bare IP ("192.168.1.50") of the first Masjid Center server
    /// answering on the device's subnet, or nil. Safe to call from a cancellable task.
    static func findServer() async -> String? {
        guard let (ip, mask) = selfIPv4() else { return nil }
        let hosts = subnetHosts(ip: ip, mask: mask)
        guard !hosts.isEmpty else { return nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = probeTimeout
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        // Sliding-window task group: keeps at most `concurrency` probes in
        // flight and returns as soon as one host validates.
        return await withTaskGroup(of: String?.self) { group in
            var next = hosts.makeIterator()
            var running = 0
            func enqueue() {
                guard let h = next.next() else { return }
                running += 1
                group.addTask { await probe(host: h, session: session) }
            }
            for _ in 0..<concurrency { enqueue() }
            while running > 0, let found = await group.next() {
                running -= 1
                if let found { group.cancelAll(); return found }
                enqueue()
            }
            return nil
        }
    }

    /// A host counts as a Masjid Center server only when /api/server-time
    /// answers 200 AND decodes as ServerTime (random services on :7777 don't).
    private static func probe(host: UInt32, session: URLSession) async -> String? {
        let ip = ipv4String(host)
        guard let url = URL(string: "http://\(ip):\(port)/api/server-time"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              (try? JSONDecoder().decode(ServerTime.self, from: data)) != nil else { return nil }
        return ip
    }

    /// Device Wi-Fi IPv4 + netmask in host byte order (en0).
    private static func selfIPv4() -> (ip: UInt32, mask: UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cur = list
        while let ifa = cur?.pointee {
            defer { cur = ifa.ifa_next }
            guard String(cString: ifa.ifa_name) == "en0",
                  let sa = ifa.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET else { continue }
            let ip = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            var mask: UInt32 = 0xFFFFFF00
            if let nm = ifa.ifa_netmask {
                mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
            }
            return (ip, mask)
        }
        return nil
    }

    /// Usable host addresses of the subnet; subnets wider than /24 are clipped
    /// to the /24 containing the device so the scan stays fast.
    private static func subnetHosts(ip: UInt32, mask: UInt32) -> [UInt32] {
        var net = ip & mask
        var count = ~mask                  // broadcast - network offset
        if count > 255 {                   // wider than /24 → clip to device's /24
            net = ip & 0xFFFFFF00
            count = 255
        }
        guard count > 1 else { return [] }
        return (1..<count).map { net + $0 }
    }

    private static func ipv4String(_ h: UInt32) -> String {
        "\(h >> 24).\(h >> 16 & 0xFF).\(h >> 8 & 0xFF).\(h & 0xFF)"
    }
}
