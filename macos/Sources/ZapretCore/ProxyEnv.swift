import Foundation

/// Oturum ortam değişkeni HTTPS_PROXY (launchctl setenv): sonradan açılan uygulamalar devralır. Discord'un Rust
/// güncelleyicisi sistem proxy ayarını her zaman okumuyor, bu değişkeni ise okuyor (saha 2026-10-28; spoofmac aynı yolu kullanır).
public enum ProxyEnv {
    public static let launchctl = "/bin/launchctl"
    public static let names = ["HTTPS_PROXY", "https_proxy"]

    public static func value(port: Int) -> String { "http://127.0.0.1:\(port)" }

    public static func setCommands(port: Int) -> [[String]] {
        names.map { [launchctl, "setenv", $0, value(port: port)] }
    }

    public static func unsetCommands() -> [[String]] {
        names.map { [launchctl, "unsetenv", $0] }
    }

    /// `launchctl getenv` çıktısı bizim değerimiz mi (kullanıcının kendi proxy'sine dokunulmaz).
    public static func isOurs(_ current: String, port: Int) -> Bool {
        current.trimmingCharacters(in: .whitespacesAndNewlines) == value(port: port)
    }
}
