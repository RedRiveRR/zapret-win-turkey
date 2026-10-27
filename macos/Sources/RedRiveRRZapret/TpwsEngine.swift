import Foundation
import ZapretCore

enum EngineError: LocalizedError {
    case missingBinary(String)
    case portBusy(Int)
    case exitedEarly(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary(let p): return "Zapret motoru (tpws) bulunamadı: \(p)"
        case .portBusy(let p): return "Yerel kapı \(p) başka bir program tarafından kullanılıyor; o programı kapatıp yeniden deneyin."
        case .exitedEarly(let t): return "Zapret motoru (tpws) başlar başlamaz kapandı." + (t.isEmpty ? "" : " Ayrıntı: \(t)")
        }
    }
}

/// tpws'i SOCKS kipinde (yalnız 127.0.0.1) çalıştırır. Yönetici gerekmez.
final class TpwsEngine {
    private var process: Process?
    private var stopping = false
    /// tpws kendiliğinden kapanırsa (çökme vb.) ana kuyrukta çağrılır.
    var onUnexpectedExit: (() -> Void)?
    let port = TpwsArgs.defaultPort

    var isRunning: Bool { process?.isRunning ?? false }

    func start(tpwsPath: String, strategy: TpwsStrategy, hostlist: String?, logURL: URL) throws {
        stop()
        guard FileManager.default.isExecutableFile(atPath: tpwsPath) else { throw EngineError.missingBinary(tpwsPath) }
        guard TpwsArgs.isPortFree(port) else { throw EngineError.portBusy(port) }
        let argv = TpwsArgs.build(tpwsPath: tpwsPath, port: port, strategy: strategy, hostlist: hostlist)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { [weak self] _ in
            guard let self = self, !self.stopping else { return }
            DispatchQueue.main.async { self.onUnexpectedExit?() }
        }
        try p.run()
        process = p
        // Kapı dinlemeye başlayana kadar en fazla 3 sn bekle
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !p.isRunning { break }
            if !TpwsArgs.isPortFree(port) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let tail = (try? String(contentsOf: logURL, encoding: .utf8))?.split(separator: "\n").suffix(3).joined(separator: " | ") ?? ""
        stop()
        throw EngineError.exitedEarly(tail)
    }

    func stop() {
        guard let p = process else { return }
        stopping = true
        if p.isRunning { p.terminate(); p.waitUntilExit() }
        process = nil
        stopping = false
    }
}
