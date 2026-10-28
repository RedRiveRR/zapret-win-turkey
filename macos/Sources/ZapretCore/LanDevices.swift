import Foundation

/// Paylaşıma bağlı cihazlar (Windows `_LanDevices*` ile aynı mantık): go-pcap2socks çıktısındaki
/// `msg="Device <IP> (<MAC>) joined the network"` ve `msg="[TCP|UDP] Connection" source=<IP>:<port>` satırları.
/// MAC tutulmaz/gösterilmez; yalnız ilk üç baytından (OUI) üretici bulunur (`veri/cihaz-ureticileri.txt`).
public struct LanDevices {
    public struct Device: Equatable {
        public let ip: String
        public var kind: String
        public var firstSeen: Date?
        public var lastSeen: Date?
        public var connections: Int
    }

    public static let activeSeconds: TimeInterval = 60
    public private(set) var devices: [Device] = []
    private let vendors: [String: String]
    private var rest = ""

    public init(vendors table: String) {
        var v: [String: String] = [:]
        for line in table.components(separatedBy: .newlines) {
            let p = line.split(separator: "\t", maxSplits: 1)
            if p.count == 2 { v[String(p[0]).uppercased()] = String(p[1]) }
        }
        vendors = v
    }

    /// Rastgele (yerel yönetilen) adresler telefon/tabletlerin gizlilik özelliğidir; üretici bilinemez.
    public static func vendor(mac: String, table: String) -> String { LanDevices(vendors: table).vendor(mac: mac) }

    func vendor(mac: String) -> String {
        let hex = mac.uppercased().filter(\.isHexDigit)
        guard hex.count == 12, let first = UInt8(hex.prefix(2), radix: 16) else { return "" }
        if first & 2 != 0 { return "Gizli adres (telefon / tablet olabilir)" }
        return vendors[String(hex.prefix(6))] ?? ""
    }

    /// Günlüğün yeni kısmı; yarım kalan son satır bir sonraki çağrıya bırakılır.
    public mutating func feed(_ chunk: String) {
        let text = rest + chunk
        guard let cut = text.lastIndex(of: "\n") else { rest = text; return }
        rest = String(text[text.index(after: cut)...])
        for line in text[..<cut].split(separator: "\n") { process(String(line)) }
    }

    public mutating func seenViaProxy(_ ip: String, at t: Date = Date()) {
        let i = index(ip, at: t)
        if devices[i].kind.isEmpty { devices[i].kind = "Proxy ayarlı cihaz" }
        devices[i].connections += 1
    }

    public mutating func reset() { devices = []; rest = "" }

    private mutating func process(_ line: String) {
        let t = Self.time(line)
        if let r = line.range(of: "msg=\"Device ") {
            let after = line[r.upperBound...]
            let ip = String(after.prefix { $0 != " " })
            guard Socks5.ipv4Bytes(ip) != nil else { return }
            let i = index(ip, at: t)
            if let open = after.firstIndex(of: "("), let close = after.firstIndex(of: ")"), open < close {
                let kind = vendor(mac: String(after[after.index(after: open)..<close]))
                if !kind.isEmpty { devices[i].kind = kind }
            }
        } else if line.contains("Connection\""), let r = line.range(of: "source=") {
            let ip = String(line[r.upperBound...].prefix { $0 != ":" && $0 != " " })
            guard Socks5.ipv4Bytes(ip) != nil else { return }
            devices[index(ip, at: t)].connections += 1
        }
    }

    private mutating func index(_ ip: String, at t: Date?) -> Int {
        if let i = devices.firstIndex(where: { $0.ip == ip }) {
            if let t = t { devices[i].lastSeen = t }
            return i
        }
        devices.append(Device(ip: ip, kind: "", firstSeen: t, lastSeen: t, connections: 0))
        return devices.count - 1
    }

    static func time(_ line: String) -> Date? {
        guard let r = line.range(of: "time=") else { return nil }
        let s = String(line[r.upperBound...].prefix { $0 != " " })
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// 60 sn içinde "Etkin", bir saat içinde "N dk önce", sonra "HH:mm'de".
    public static func ago(_ last: Date?, now: Date = Date()) -> String {
        guard let last = last else { return "" }
        let s = now.timeIntervalSince(last)
        if s < activeSeconds { return "Etkin" }
        if s < 120 { return "1 dk önce" }
        if s < 3600 { return "\(Int(s / 60)) dk önce" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: last) + "'de"
    }

    public func activeCount(now: Date = Date()) -> Int {
        devices.filter { ($0.lastSeen.map { now.timeIntervalSince($0) < Self.activeSeconds }) ?? false }.count
    }

    /// Arayüz satırları: [{ip, tur, durum, etkin, baglanti}] (MAC yok).
    public func json(now: Date = Date()) -> String {
        "[" + devices.map { d in
            Json.object(["ip": d.ip, "tur": d.kind, "durum": Self.ago(d.lastSeen, now: now),
                         "etkin": d.lastSeen.map { now.timeIntervalSince($0) < Self.activeSeconds } ?? false, "baglanti": d.connections])
        }.joined(separator: ",") + "]"
    }
}
