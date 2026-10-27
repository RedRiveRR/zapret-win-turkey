import Foundation
import Darwin

public enum EngineError: LocalizedError {
    case missingBinary(String)
    case portBusy(Int)
    case exitedEarly(String)

    public var errorDescription: String? {
        switch self {
        case .missingBinary(let p): return "Zapret motoru (tpws) bulunamadı: \(p)"
        case .portBusy(let p): return "Yerel kapı \(p) başka bir program tarafından kullanılıyor; o programı kapatıp yeniden deneyin."
        case .exitedEarly(let t): return "Zapret motoru (tpws) başlar başlamaz kapandı." + (t.isEmpty ? "" : " Ayrıntı: \(t)")
        }
    }
}

/// tpws'i SOCKS kipinde (yalnız 127.0.0.1) çalıştırır. Yönetici gerekmez.
public final class TpwsEngine {
    public var onUnexpectedExit: (() -> Void)?
    public let port: Int
    let pidFile: URL?

    public init(port: Int = TpwsArgs.defaultPort, pidFile: URL? = nil) {
        self.port = port
        self.pidFile = pidFile
    }

    public var isRunning: Bool { false }

    public func start(tpwsPath: String, strategy: TpwsStrategy, hostlist: String?, logURL: URL) throws {}

    func launch(argv: [String], logURL: URL) throws {}

    public func stop() {}

    public static func killLeftover(pidFile: URL, expectedPath: String) {}
}
