import Foundation

/// DoH (JSON) yanıtı ayrıştırma ve sorgu adresi. ISS DNS'i Discord/Roblox adlarını bozuyor; public DNS'e
/// 53 kapısı kapalı, 443 (DoH) açık. Sistem DNS'ine dokunulmaz, yalnız atlatılan adlar buradan çözülür.
public enum Doh {
    public static let defaultEndpoints = [
        "https://1.1.1.1/dns-query",
        "https://8.8.8.8/resolve",
        "https://1.0.0.1/dns-query",
    ]

    public struct Answer: Equatable {
        public let addresses: [String]
        public let ttl: Int
    }

    /// Yalnız A kayıtları; 0.x ve 127.x (engel/boş yanıt) atılır. ttl: kayıtların en küçüğü (yoksa 0).
    public static func parse(_ data: Data) -> Answer {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = obj["Answer"] as? [[String: Any]] else { return Answer(addresses: [], ttl: 0) }
        var addrs: [String] = []
        var ttl = Int.max
        for a in answers {
            guard (a["type"] as? NSNumber)?.intValue == 1, let ip = a["data"] as? String,
                  let b = Socks5.ipv4Bytes(ip), b[0] != 0, b[0] != 127 else { continue }
            addrs.append(ip)
            ttl = min(ttl, (a["TTL"] as? NSNumber)?.intValue ?? 0)
        }
        return Answer(addresses: addrs, ttl: addrs.isEmpty ? 0 : ttl)
    }

    /// Ad yalnız harf, rakam, '-' ve '.' içerebilir (sorgu dizgisine kaçak olmasın).
    public static func queryURL(endpoint: String, host: String) -> URL? {
        guard !host.isEmpty, host.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x41 && $0 <= 0x5A) || $0 == 0x2D || $0 == 0x2E }) else { return nil }
        return URL(string: "\(endpoint)?name=\(host)&type=A")
    }
}

/// tpws hostlist ile aynı mantık: ad listedeki alan adının kendisi ya da alt alanı ise eşleşir.
public enum HostMatcher {
    public static func matches(_ host: String, _ list: [String]) -> Bool {
        let h = host.lowercased()
        return list.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    public static func parseList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

/// DoH uçlarını sırayla dener; sonuçları TTL kadar (30–300 sn) önbellekte tutar, başarısızlığı 5 sn anımsar.
public final class DohResolver {
    public typealias Fetch = (URL) -> Data?

    private let endpoints: [String]
    private let fetch: Fetch
    private let now: () -> Date
    private let lock = NSLock()
    private var cache: [String: (addrs: [String], expires: Date)] = [:]

    public init(endpoints: [String] = Doh.defaultEndpoints, fetch: Fetch? = nil, now: @escaping () -> Date = Date.init) {
        self.endpoints = endpoints
        self.fetch = fetch ?? DohResolver.urlSessionFetch
        self.now = now
    }

    public func resolve(_ host: String) -> [String] {
        let key = host.lowercased()
        lock.lock()
        if let hit = cache[key], hit.expires > now() { lock.unlock(); return hit.addrs }
        lock.unlock()
        for ep in endpoints {
            guard let url = Doh.queryURL(endpoint: ep, host: key), let data = fetch(url) else { continue }
            let a = Doh.parse(data)
            if a.addresses.isEmpty { continue }
            store(key, a.addresses, ttl: min(max(a.ttl, 30), 300))
            return a.addresses
        }
        store(key, [], ttl: 5)
        return []
    }

    private func store(_ key: String, _ addrs: [String], ttl: Int) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = (addrs, now().addingTimeInterval(TimeInterval(ttl)))
    }

    /// Sistem proxy'sini (bizim ön proxy dahil) kullanmaz: aksi hâlde sorgu kendi kendine döner.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [:]
        c.timeoutIntervalForRequest = 4
        c.timeoutIntervalForResource = 6
        return URLSession(configuration: c)
    }()

    private static func urlSessionFetch(_ url: URL) -> Data? {
        var req = URLRequest(url: url)
        req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { data, resp, _ in
            if let h = resp as? HTTPURLResponse, h.statusCode == 200 { result = data }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
        return result
    }
}
