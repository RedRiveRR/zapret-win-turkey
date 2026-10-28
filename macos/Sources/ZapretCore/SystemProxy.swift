import Foundation

/// Bir ağ hizmetinin bir proxy ayarı (`networksetup -getsocksfirewallproxy` / `-getsecurewebproxy` çıktısı).
public struct SocksState: Codable, Equatable {
    public let enabled: Bool
    public let server: String
    public let port: Int
    public init(enabled: Bool, server: String, port: Int) { self.enabled = enabled; self.server = server; self.port = port }
}

/// Yardımcının yedeği: SOCKS ve Güvenli Web Proxy. `secureWeb == nil`: eski yardımcının yedeği (yalnız SOCKS tutulurdu),
/// geri yüklemede Güvenli Web Proxy'ye dokunulmaz. Eski yedek dosyası (düz `SocksState`) okunabilir.
public struct ProxyBackup: Codable, Equatable {
    public let socks: SocksState
    public let secureWeb: SocksState?
    public init(socks: SocksState, secureWeb: SocksState?) { self.socks = socks; self.secureWeb = secureWeb }

    private enum Keys: String, CodingKey { case socks, secureWeb }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.socks) {
            socks = try c.decode(SocksState.self, forKey: .socks)
            secureWeb = try c.decodeIfPresent(SocksState.self, forKey: .secureWeb)
        } else {
            socks = try SocksState(from: decoder)
            secureWeb = nil
        }
    }
}

/// macOS sistem proxy'leri (SOCKS + Güvenli Web Proxy): ayrıştırma ve `networksetup` komutları (çalıştırma yardımcıda, kök yetkiyle).
public enum SystemProxy {
    public static let networksetup = "/usr/sbin/networksetup"

    /// `networksetup -listallnetworkservices`: ilk satır açıklama; '*' ile başlayanlar devre dışı.
    public static func parseServices(_ listAllOutput: String) -> [String] {
        listAllOutput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.hasPrefix("An asterisk") }
    }

    /// `networksetup -getsocksfirewallproxy` ve `-getsecurewebproxy` aynı biçimde çıktı verir.
    public static func parseSocks(_ getOutput: String) -> SocksState { parseProxy(getOutput) }

    public static func parseProxy(_ getOutput: String) -> SocksState {
        var enabled = false, server = "", port = 0
        for line in getOutput.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "Enabled": enabled = parts[1].lowercased() == "yes"
            case "Server": server = parts[1]
            case "Port": port = Int(parts[1]) ?? 0
            default: break
            }
        }
        return SocksState(enabled: enabled, server: server, port: port)
    }

    /// Hizmetin SOCKS ve Güvenli Web Proxy'sini yerel ön proxy'ye yönlendirir (adres her zaman 127.0.0.1).
    /// Güvenli Web Proxy: Discord güncelleyicisi (Rust/reqwest) SOCKS'u görmez, yalnız HTTP(S) proxy'yi kullanır.
    public static func enableCommands(service: String, port: Int) -> [[String]] {
        [[networksetup, "-setsocksfirewallproxy", service, "127.0.0.1", String(port)],
         [networksetup, "-setsocksfirewallproxystate", service, "on"],
         [networksetup, "-setsecurewebproxy", service, "127.0.0.1", String(port)],
         [networksetup, "-setsecurewebproxystate", service, "on"]]
    }

    /// Var olan yedeğe, yedekte olmayan hizmetlerin şimdiki durumunu ekler (var olan kayıtlar değişmez).
    public static func mergeBackup<T>(existing: [String: T], current: [String: T]) -> [String: T] {
        existing.merging(current) { old, _ in old }
    }

    /// Hizmeti önceki hâline döndürür (kullanıcının kendi proxy'si varsa aynen geri yüklenir).
    public static func restoreCommands(service: String, previous: ProxyBackup) -> [[String]] {
        var cmds = restore(service: service, previous: previous.socks, set: "-setsocksfirewallproxy", state: "-setsocksfirewallproxystate")
        if let web = previous.secureWeb {
            cmds += restore(service: service, previous: web, set: "-setsecurewebproxy", state: "-setsecurewebproxystate")
        }
        return cmds
    }

    private static func restore(service: String, previous: SocksState, set: String, state: String) -> [[String]] {
        if previous.enabled && !previous.server.isEmpty {
            return [[networksetup, set, service, previous.server, String(previous.port)],
                    [networksetup, state, service, "on"]]
        }
        return [[networksetup, state, service, "off"]]
    }
}
