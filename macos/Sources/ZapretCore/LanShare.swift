import Foundation
import Darwin

/// Ağ paylaşımı (macOS): ön proxy yerel ağa da açılır; PS5/PS4/Switch ağ ayarlarında "proxy sunucusu" olarak
/// Mac'in adresi girilir. Yalnız yerel/özel adreslerden bağlantı kabul edilir. (Windows'taki ağ geçidi yöntemi
/// Mac'te root + paket yakalama ister; proxy yolu kullanıcı alanında çalışır.)
public enum LanShare {
    public static let port = 8080

    /// 10/8, 172.16/12, 192.168/16, 169.254/16 ve 127/8.
    public static func isLocal(_ ip: String) -> Bool {
        guard let b = Socks5.ipv4Bytes(ip) else { return false }
        switch (b[0], b[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Kablo/Wi-Fi (en*) üzerindeki özel adres; bağlantı-yerel (169.254) son seçenek; VPN (utun) ve lo0 atlanır.
    public static func pickAddress(_ interfaces: [(String, String)]) -> String? {
        let candidates = interfaces.filter { $0.0.hasPrefix("en") && isLocal($0.1) && !$0.1.hasPrefix("127.") }
        return (candidates.first { !$0.1.hasPrefix("169.254.") } ?? candidates.first)?.1
    }

    /// `networksetup -listallhardwareports` çıktısından Wi-Fi (eski adı AirPort) aygıtları. `-getairportnetwork` macOS 14.4+'ta
    /// konum izni olmadan Wi-Fi'yi göstermediği için bu yol kullanılır.
    public static func wifiDevices(hardwarePorts out: String) -> [String] {
        var result: [String] = [], isWifi = false
        for raw in out.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                let name = line.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
                isWifi = name == "Wi-Fi" || name == "AirPort"
            } else if line.hasPrefix("Device:"), isWifi {
                result.append(line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces))
                isWifi = false
            }
        }
        return result
    }

    /// Sistemdeki IPv4 arayüzleri (ad, adres).
    public static func interfaces() -> [(String, String)] {
        var out: [(String, String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var p = head
        while let i = p {
            if let a = i.pointee.ifa_addr, a.pointee.sa_family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    out.append((String(cString: i.pointee.ifa_name), String(cString: host)))
                }
            }
            p = i.pointee.ifa_next
        }
        return out
    }
}

/// Paylaşımdan bağlanan cihazlar: son 60 sn'de bağlantı açan "etkin" sayılır.
public struct LanClients {
    private var lastSeen: [String: Date] = [:]
    public init() {}
    public mutating func seen(_ ip: String, at t: Date = Date()) { lastSeen[ip] = t }
    public func activeCount(at t: Date = Date()) -> Int { lastSeen.values.filter { t.timeIntervalSince($0) <= 60 }.count }
}
