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
/// Tüm iç durum tek seri kuyrukta tutulur (başlat arka planda, durdur ana iş parçacığında çağrılabilir).
/// Bilinçli durdurmada sonlanma bildirimi kaldırılır; bildirim yalnız hâlâ güncel süreç için çalışır
/// (gözden geçirme #2). Süreç kimliği pid dosyasına yazılır; uygulama zorla kapatılıp tpws arkada
/// kalırsa bir sonraki başlatmada kapatılır (#3).
public final class TpwsEngine {
    public var onUnexpectedExit: (() -> Void)?
    public let port: Int
    let pidFile: URL?
    private let queue = DispatchQueue(label: "com.redriverr.zapret.engine")
    private var process: Process?
    private var logHandle: FileHandle?

    public init(port: Int = TpwsArgs.defaultPort, pidFile: URL? = nil) {
        self.port = port
        self.pidFile = pidFile
    }

    public var isRunning: Bool { queue.sync { process?.isRunning ?? false } }

    public func start(tpwsPath: String, strategy: TpwsStrategy, hostlist: String?, logURL: URL) throws {
        stop()
        if let f = pidFile { Self.killLeftover(pidFile: f, expectedPath: tpwsPath) }
        guard FileManager.default.isExecutableFile(atPath: tpwsPath) else { throw EngineError.missingBinary(tpwsPath) }
        guard TpwsArgs.isPortFree(port) else { throw EngineError.portBusy(port) }
        try launch(argv: TpwsArgs.build(tpwsPath: tpwsPath, port: port, strategy: strategy, hostlist: hostlist), logURL: logURL)
        // Kapı dinlemeye başlayana kadar en fazla 3 sn
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if !isRunning { break }
            if !TpwsArgs.isPortFree(port) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        stop() // erken kapanma: bildirim tetiklenmez, ayrıntılı hata döner
        let tail = (try? String(contentsOf: logURL, encoding: .utf8))?
            .split(separator: "\n").suffix(3).joined(separator: " | ") ?? ""
        throw EngineError.exitedEarly(tail)
    }

    /// Süreci başlatır (testler doğrudan çağırır).
    func launch(argv: [String], logURL: URL) throws {
        try queue.sync {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: argv[0])
            p.arguments = Array(argv.dropFirst())
            p.standardOutput = log
            p.standardError = log
            p.terminationHandler = { [weak self] proc in
                guard let self = self else { return }
                self.queue.async {
                    guard self.process === proc else { return } // eski ya da bilinçli durdurulmuş süreç
                    self.clearLocked()
                    if let cb = self.onUnexpectedExit { DispatchQueue.main.async { cb() } }
                }
            }
            try p.run()
            process = p
            logHandle = log
            if let f = pidFile { try? "\(p.processIdentifier)".write(to: f, atomically: true, encoding: .utf8) }
        }
    }

    public func stop() {
        queue.sync {
            guard let p = process else { return }
            p.terminationHandler = nil
            process = nil // bildirim gelirse kimlik denetiminde düşer
            if p.isRunning {
                p.terminate()
                let deadline = Date().addingTimeInterval(3)
                while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            clearLocked()
        }
    }

    private func clearLocked() {
        process = nil
        try? logHandle?.close()
        logHandle = nil
        if let f = pidFile { try? FileManager.default.removeItem(at: f) }
    }

    /// pid dosyasındaki süreç hâlâ çalışıyor ve `expectedPath`'teki program ise kapatır; dosyayı siler.
    public static func killLeftover(pidFile: URL, expectedPath: String) {
        defer { try? FileManager.default.removeItem(at: pidFile) }
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1,
              kill(pid, 0) == 0 else { return }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return }
        let path = String(cString: buf)
        let want = (expectedPath as NSString).resolvingSymlinksInPath
        guard (path as NSString).resolvingSymlinksInPath == want else { return }
        kill(pid, SIGTERM)
        for _ in 0..<30 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }
}
