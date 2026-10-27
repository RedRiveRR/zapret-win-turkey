import Foundation

/// Bir ağ hizmetinin SOCKS proxy ayarı (`networksetup -getsocksfirewallproxy` çıktısı).
public struct SocksState: Codable, Equatable {
    public let enabled: Bool
    public let server: String
    public let port: Int
    public init(enabled: Bool, server: String, port: Int) { self.enabled = enabled; self.server = server; self.port = port }
}

/// macOS sistem SOCKS proxy'si: ayrıştırma ve `networksetup` komutları (çalıştırma yardımcıda, kök yetkiyle).
public enum SystemProxy {
    public static let networksetup = "/usr/sbin/networksetup"

    /// `networksetup -listallnetworkservices`: ilk satır açıklama; '*' ile başlayanlar devre dışı.
    public static func parseServices(_ listAllOutput: String) -> [String] {
        listAllOutput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") && !$0.hasPrefix("An asterisk") }
    }

    /// `networksetup -getsocksfirewallproxy <hizmet>` çıktısı.
    public static func parseSocks(_ getOutput: String) -> SocksState {
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

    /// Hizmetin SOCKS proxy'sini yerel tpws'e yönlendirir (adres her zaman 127.0.0.1).
    public static func enableCommands(service: String, port: Int) -> [[String]] {
        [[networksetup, "-setsocksfirewallproxy", service, "127.0.0.1", String(port)],
         [networksetup, "-setsocksfirewallproxystate", service, "on"]]
    }

    /// Hizmeti önceki hâline döndürür (kullanıcının kendi proxy'si varsa aynen geri yüklenir).
    public static func restoreCommands(service: String, previous: SocksState) -> [[String]] {
        if previous.enabled && !previous.server.isEmpty {
            return [[networksetup, "-setsocksfirewallproxy", service, previous.server, String(previous.port)],
                    [networksetup, "-setsocksfirewallproxystate", service, "on"]]
        }
        return [[networksetup, "-setsocksfirewallproxystate", service, "off"]]
    }
}
