import Foundation
import Darwin

/// tpws komut satırı (SOCKS kipi, yalnız 127.0.0.1) ve kapı denetimi.
public enum TpwsArgs {
    public static let defaultPort = 1080

    /// hostlist verilirse atlatma yalnız o listedeki sitelere uygulanır (tpws --hostlist).
    public static func build(tpwsPath: String, port: Int, strategy: TpwsStrategy, hostlist: String?) -> [String] { [] }

    /// 127.0.0.1:port bağlanmaya açık değilse (dinleyen yoksa) true.
    public static func isPortFree(_ port: Int) -> Bool { true }
}
