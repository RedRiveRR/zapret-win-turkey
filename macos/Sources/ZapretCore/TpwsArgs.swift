import Foundation
import Darwin

/// tpws komut satırı (SOCKS kipi, yalnız 127.0.0.1) ve kapı denetimi.
public enum TpwsArgs {
    public static let defaultPort = 1080

    /// hostlist verilirse atlatma yalnız o listedeki sitelere uygulanır (tpws --hostlist).
    public static func build(tpwsPath: String, port: Int, strategy: TpwsStrategy, hostlist: String?) -> [String] {
        var argv = [tpwsPath, "--socks", "--bind-addr=127.0.0.1", "--port=\(port)"]
        if let h = hostlist { argv.append("--hostlist=\(h)") }
        return argv + strategy.args
    }

    /// 127.0.0.1:port bağlanmaya açık değilse (dinleyen yoksa) true. Yardımcı da tpws'in canlılığını bununla izler.
    public static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return rc != 0
    }
}
