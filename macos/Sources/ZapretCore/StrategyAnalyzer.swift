import Foundation
import Darwin

/// Analizde sınanan tek hedef: ad (SNI), DoH ile bulunan gerçek IP ve istemci profili.
public struct ProbeTarget: Equatable {
    public let host: String
    public let ip: String
    public let profile: TlsClientHello.Profile
    public init(host: String, ip: String, profile: TlsClientHello.Profile) { self.host = host; self.ip = ip; self.profile = profile }
}

public struct Measurement: Equatable {
    public let passed: Int
    public let total: Int
    public let latencyMs: Int
    public init(passed: Int, total: Int, latencyMs: Int) { self.passed = passed; self.total = total; self.latencyMs = latencyMs }
}

public struct StrategyScore: Codable, Equatable {
    public let name: String
    public let args: [String]
    public let passed: Int
    public let total: Int
    public let latencyMs: Int
    public init(name: String, args: [String], passed: Int, total: Int, latencyMs: Int) {
        self.name = name; self.args = args; self.passed = passed; self.total = total; self.latencyMs = latencyMs
    }
    public var score: Int { total == 0 ? 0 : passed * 100 / total }
    public var strategy: TpwsStrategy { TpwsStrategy(name: name, args: args) }
}

/// Puan (yüksek) → gecikme (düşük) → sadelik (az argüman) → ad.
public enum StrategyRanking {
    public static func sort(_ s: [StrategyScore]) -> [StrategyScore] {
        s.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.latencyMs != $1.latencyMs { return $0.latencyMs < $1.latencyMs }
            if $0.args.count != $1.args.count { return $0.args.count < $1.args.count }
            return $0.name < $1.name
        }
    }
}

/// tpws aday stratejileri. Saha: Türk ISS'lerinde SNI'lı ClientHello RST yiyor; TLS kaydı bölme (--tlsrec) işaret
/// ve ofsetleri ISS'ye ve istemciye göre değişiyor, bu yüzden geniş tarama yapılır.
public enum StrategyCandidates {
    public static func generate(including bundled: [TpwsStrategy] = []) -> [TpwsStrategy] {
        var args: [[String]] = []
        for m in ["sniext", "host", "sld", "midsld", "endsld", "endhost"] {
            for off in [-1, 0, 1, 2, 4] where !(m == "sniext" && off < 0) && !(m == "host" && off < 0) {
                args.append(["--tlsrec=\(m)\(off == 0 ? "" : (off > 0 ? "+\(off)" : "\(off)"))"])
            }
        }
        args += [["--tlsrec=1"], ["--tlsrec=2"], ["--tlsrec=5"]]
        for t in ["midsld", "host+1", "sniext+1"] {
            for sp in ["1", "midsld", "sniext+2"] { args.append(["--tlsrec=\(t)", "--split-pos=\(sp)"]) }
            args.append(["--tlsrec=\(t)", "--oob=tls"])
        }
        args += [["--split-pos=1"], ["--split-pos=2"], ["--split-pos=midsld"], ["--split-pos=1,midsld", "--disorder=tls"],
                 ["--oob=tls", "--split-pos=1"], ["--oob=tls", "--split-pos=midsld"], ["--disorder=tls", "--split-pos=2"],
                 ["--hostcase", "--tlsrec=midsld"]]
        var out = bundled
        var seen = Set(bundled.map(\.args))
        for a in args where !seen.contains(a) {
            seen.insert(a)
            out.append(TpwsStrategy(name: a.joined(separator: " "), args: a))
        }
        return out
    }
}

/// İki aşamalı analiz: eleme (her aday `screen` hedeflerinde 1 tur, tamamı geçmeli) → ayrıntı (kalanlar `detail`
/// hedeflerinde `rounds` tur). Ölçüm işlevi dışarıdan verilir (gerçek: `TpwsMeasure`, testte sahte).
public final class StrategyAnalyzer {
    public typealias Measure = (_ strategy: TpwsStrategy, _ targets: [ProbeTarget], _ rounds: Int) -> Measurement

    /// (biten, toplam, aşama) — aşama: "eleme" | "ayrıntı"
    public var onProgress: ((Int, Int, String) -> Void)?
    private let measure: Measure
    private let concurrency: Int
    private let lock = NSLock()
    private var cancelled = false

    public init(concurrency: Int = 4, measure: @escaping Measure) {
        self.concurrency = max(1, concurrency)
        self.measure = measure
    }

    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    public func run(candidates: [TpwsStrategy], screen: [ProbeTarget], detail: [ProbeTarget], rounds: Int = 2) -> [StrategyScore] {
        let first = runStage(candidates, targets: screen, rounds: 1, phase: "eleme")
        let survivors = candidates.filter { c in first[c.args].map { $0.total > 0 && $0.passed == $0.total } ?? false }
        let second = isCancelled ? [:] : runStage(survivors, targets: detail, rounds: rounds, phase: "ayrıntı")
        var scores: [StrategyScore] = []
        for c in candidates {
            guard let m = second[c.args] ?? first[c.args] else { continue }
            scores.append(StrategyScore(name: c.name, args: c.args, passed: m.passed, total: m.total, latencyMs: m.latencyMs))
        }
        return StrategyRanking.sort(scores)
    }

    private func runStage(_ list: [TpwsStrategy], targets: [ProbeTarget], rounds: Int, phase: String) -> [[String]: Measurement] {
        var results: [[String]: Measurement] = [:]
        var done = 0
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = concurrency
        for c in list {
            queue.addOperation { [self] in
                if isCancelled { return }
                let m = measure(c, targets, rounds)
                lock.lock()
                results[c.args] = m
                done += 1
                let d = done
                lock.unlock()
                onProgress?(d, list.count, phase)
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        lock.lock(); defer { lock.unlock() }
        return results
    }
}

/// Gerçek ölçüm: aday için geçici bir tpws (rastgele boş kapı) açar, hedeflere ClientHello sondası gönderir, kapatır.
public enum TpwsMeasure {
    public static func make(tpwsPath: String, hostlist: String?, logDir: URL, timeout: TimeInterval = 4) -> StrategyAnalyzer.Measure {
        return { strategy, targets, rounds in
            guard let port = freePort() else { return Measurement(passed: 0, total: targets.count * rounds, latencyMs: 0) }
            let engine = TpwsEngine(port: port)
            do {
                try engine.start(tpwsPath: tpwsPath, strategy: strategy, hostlist: hostlist,
                                 logURL: logDir.appendingPathComponent("analiz-tpws-\(port).log"))
            } catch {
                return Measurement(passed: 0, total: targets.count * rounds, latencyMs: 0)
            }
            defer {
                engine.stop()
                try? FileManager.default.removeItem(at: logDir.appendingPathComponent("analiz-tpws-\(port).log"))
            }
            return probeAll(targets, rounds: rounds) { t in
                TlsProbe.probe(ip: t.ip, socksPort: port, hello: TlsClientHello.build(sni: t.host, profile: t.profile), timeout: timeout)
            }
        }
    }

    /// tpws'siz: bu ağda engel var mı (taban ölçümü).
    public static func direct(_ targets: [ProbeTarget], timeout: TimeInterval = 4) -> Measurement {
        probeAll(targets, rounds: 1) { t in
            TlsProbe.probe(ip: t.ip, socksPort: nil, hello: TlsClientHello.build(sni: t.host, profile: t.profile), timeout: timeout)
        }
    }

    static func probeAll(_ targets: [ProbeTarget], rounds: Int, _ one: (ProbeTarget) -> TlsProbe.Outcome) -> Measurement {
        var passed = 0, latency = 0
        for _ in 0..<rounds {
            for t in targets {
                if case .passed(let ms) = one(t) { passed += 1; latency += ms }
            }
        }
        return Measurement(passed: passed, total: targets.count * rounds, latencyMs: passed == 0 ? 0 : latency / passed)
    }

    /// Çekirdeğin verdiği boş bir 127.0.0.1 kapısı.
    public static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = 0
        let ok = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return Int(UInt16(bigEndian: a.sin_port))
    }
}
