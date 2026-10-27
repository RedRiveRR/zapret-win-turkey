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

    public static func parseServices(_ listAllOutput: String) -> [String] { [] }

    public static func parseSocks(_ getOutput: String) -> SocksState { SocksState(enabled: false, server: "x", port: -1) }

    public static func enableCommands(service: String, port: Int) -> [[String]] { [] }

    public static func restoreCommands(service: String, previous: SocksState) -> [[String]] { [] }
}
