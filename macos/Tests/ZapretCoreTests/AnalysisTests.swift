import XCTest
import Darwin
@testable import ZapretCore

final class ClientHelloTests: XCTestCase {
    func testEveryProfileCarriesRequestedSNIAndConsistentLengths() {
        for p in TlsClientHello.Profile.allCases {
            let h = TlsClientHello.build(sni: "updates.discord.com", profile: p)
            XCTAssertEqual(h[0], 0x16, "\(p)")
            XCTAssertEqual(Int(h[3]) << 8 | Int(h[4]), h.count - 5, "kayıt uzunluğu \(p)")
            XCTAssertEqual(h[5], 1, "ClientHello \(p)")
            XCTAssertEqual(Int(h[6]) << 16 | Int(h[7]) << 8 | Int(h[8]), h.count - 9, "el sıkışma uzunluğu \(p)")
            XCTAssertEqual(TlsClientHello.serverName(in: h), "updates.discord.com", "\(p)")
        }
    }

    func testProfilesMimicRealClients() {
        // Saha yakalamaları: güncelleyici 179 B (SNI ilk uzantı), Chromium ~1785 B, curl/Roblox ~324 B.
        let legacy = TlsClientHello.build(sni: "updates.discord.com", profile: .appleLegacy)
        let chromium = TlsClientHello.build(sni: "discord.com", profile: .chromium)
        let modern = TlsClientHello.build(sni: "www.roblox.com", profile: .modern)
        XCTAssertTrue((150...260).contains(legacy.count), "\(legacy.count)")
        XCTAssertTrue((1650...1900).contains(chromium.count), "\(chromium.count)")
        XCTAssertTrue((250...450).contains(modern.count), "\(modern.count)")
        XCTAssertEqual(TlsClientHello.extensionTypes(in: legacy).first, 0)
        XCTAssertFalse(TlsClientHello.extensionTypes(in: legacy).contains(43)) // yalnız TLS 1.2
        XCTAssertTrue(TlsClientHello.extensionTypes(in: chromium).contains(43))
        XCTAssertNotEqual(TlsClientHello.extensionTypes(in: chromium).first, 0) // SNI ortada
    }

    func testServerNameRejectsGarbage() {
        XCTAssertNil(TlsClientHello.serverName(in: [0x16, 3, 1, 0, 2, 1, 0]))
        XCTAssertNil(TlsClientHello.serverName(in: []))
    }
}

final class CandidatesTests: XCTestCase {
    func testGeneratedCandidatesAreUniqueAndIncludeFieldWinners() {
        let c = StrategyCandidates.generate()
        XCTAssertEqual(Set(c.map(\.args)).count, c.count)
        XCTAssertTrue((25...80).contains(c.count), "\(c.count)")
        for known in [["--tlsrec=midsld"], ["--tlsrec=sniext+1"], ["--tlsrec=host+1"], ["--oob=tls", "--split-pos=1"]] {
            XCTAssertTrue(c.contains { $0.args == known }, "\(known)")
        }
        XCTAssertTrue(c.allSatisfy { !$0.name.isEmpty && !$0.args.isEmpty })
    }

    func testBundledStrategiesComeFirstWithoutDuplicates() {
        let bundled = [TpwsStrategy(name: "Benim", args: ["--tlsrec=midsld"])]
        let c = StrategyCandidates.generate(including: bundled)
        XCTAssertEqual(c.first?.name, "Benim")
        XCTAssertEqual(c.filter { $0.args == ["--tlsrec=midsld"] }.count, 1)
    }
}

final class AnalyzerTests: XCTestCase {
    let screen = [ProbeTarget(host: "discord.com", ip: "1.1.1.1", profile: .chromium)]
    let detail = [ProbeTarget(host: "discord.com", ip: "1.1.1.1", profile: .chromium),
                  ProbeTarget(host: "updates.discord.com", ip: "1.1.1.2", profile: .appleLegacy)]

    func testScreeningEliminatesAndDetailRanks() {
        let good = TpwsStrategy(name: "iyi", args: ["--a"]), slow = TpwsStrategy(name: "yavaş", args: ["--b", "--c"])
        let half = TpwsStrategy(name: "yarım", args: ["--d"]), bad = TpwsStrategy(name: "kötü", args: ["--e"])
        var detailCalls: [String] = []
        let lock = NSLock()
        let a = StrategyAnalyzer(concurrency: 2) { s, targets, rounds in
            let isDetail = targets.count > 1
            if isDetail { lock.lock(); detailCalls.append(s.name); lock.unlock() }
            let total = targets.count * rounds
            switch s.name {
            case "iyi": return Measurement(passed: total, total: total, latencyMs: 40)
            case "yavaş": return Measurement(passed: total, total: total, latencyMs: 90)
            case "yarım": return Measurement(passed: isDetail ? total / 2 : total, total: total, latencyMs: 30)
            default: return Measurement(passed: 0, total: total, latencyMs: 0)
            }
        }
        let r = a.run(candidates: [bad, slow, half, good], screen: screen, detail: detail, rounds: 2)
        XCTAssertEqual(r.map(\.name), ["iyi", "yavaş", "yarım", "kötü"])
        XCTAssertEqual(r[0].score, 100)
        XCTAssertEqual(r[2].score, 50)
        XCTAssertEqual(r[3].score, 0)
        XCTAssertEqual(Set(detailCalls), ["iyi", "yavaş", "yarım"]) // elenen ayrıntılı ölçülmez
    }

    func testRankingPrefersSimplerOnTie() {
        let s = StrategyRanking.sort([
            StrategyScore(name: "b", args: ["--x", "--y"], passed: 4, total: 4, latencyMs: 50),
            StrategyScore(name: "a", args: ["--x"], passed: 4, total: 4, latencyMs: 50),
        ])
        XCTAssertEqual(s.map(\.name), ["a", "b"])
    }

    func testProgressAndCancel() {
        let cands = (0..<10).map { TpwsStrategy(name: "s\($0)", args: ["--s\($0)"]) }
        var seen: [Int] = []
        let lock = NSLock()
        let a = StrategyAnalyzer(concurrency: 1) { _, t, r in Measurement(passed: 0, total: t.count * r, latencyMs: 0) }
        a.onProgress = { done, _, _ in lock.lock(); seen.append(done); if done == 3 { a.cancel() }; lock.unlock() }
        let r = a.run(candidates: cands, screen: screen, detail: detail)
        XCTAssertTrue(a.isCancelled)
        XCTAssertLessThan(r.count, 10)
        XCTAssertEqual(seen.prefix(3), [1, 2, 3])
    }

    func testScoreJsonRoundTrip() throws {
        let s = [StrategyScore(name: "a", args: ["--tlsrec=midsld"], passed: 3, total: 4, latencyMs: 12)]
        XCTAssertEqual(try JSONDecoder().decode([StrategyScore].self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(s[0].score, 75)
    }
}

/// Yerel sahte sunucularla sonda: TLS yanıtı → geçti, kapanma → sıfırlama, sessizlik → zaman aşımı.
final class TlsProbeTests: XCTestCase {
    private func server(_ behaviour: @escaping (Int32) -> Void) -> (Int32, Int) {
        let ls = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1; setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, 4)
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = 0
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(ls, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(ls, 4)
        var l = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(ls, $0, &l) } }
        Thread.detachNewThread { let c = accept(ls, nil, nil); if c >= 0 { behaviour(c) } }
        return (ls, Int(UInt16(bigEndian: a.sin_port)))
    }

    private func readSome(_ c: Int32) { var b = [UInt8](repeating: 0, count: 4096); _ = recv(c, &b, b.count, 0) }

    func testServerHelloCountsAsPassed() {
        let (ls, port) = server { c in self.readSome(c); var r: [UInt8] = [0x16, 3, 3, 0, 1]; _ = send(c, &r, 5, 0); Thread.sleep(forTimeInterval: 0.2); close(c) }
        defer { close(ls) }
        let o = TlsProbe.probe(ip: "127.0.0.1", port: UInt16(port), socksPort: nil, hello: [0x16, 3, 1, 0, 0], timeout: 2)
        if case .passed = o {} else { XCTFail("\(o)") }
    }

    func testAlertAlsoMeansDpiPassed() {
        let (ls, port) = server { c in self.readSome(c); var r: [UInt8] = [0x15, 3, 3, 0, 2]; _ = send(c, &r, 5, 0); Thread.sleep(forTimeInterval: 0.2); close(c) }
        defer { close(ls) }
        if case .passed = TlsProbe.probe(ip: "127.0.0.1", port: UInt16(port), socksPort: nil, hello: [1], timeout: 2) {} else { XCTFail() }
    }

    func testCloseIsReset() {
        let (ls, port) = server { c in self.readSome(c); close(c) }
        defer { close(ls) }
        XCTAssertEqual(TlsProbe.probe(ip: "127.0.0.1", port: UInt16(port), socksPort: nil, hello: [1], timeout: 2), .reset)
    }

    func testSilenceIsTimeout() {
        let (ls, port) = server { c in self.readSome(c); Thread.sleep(forTimeInterval: 1.5); close(c) }
        defer { close(ls) }
        XCTAssertEqual(TlsProbe.probe(ip: "127.0.0.1", port: UInt16(port), socksPort: nil, hello: [1], timeout: 0.5), .timeout)
    }

    func testViaSocksSendsConnectForIPThenHello() {
        var seen: [UInt8] = []
        let lock = NSLock()
        let (ls, port) = server { c in
            var b = [UInt8](repeating: 0, count: 3); _ = recv(c, &b, 3, MSG_WAITALL)
            var ok: [UInt8] = [5, 0]; _ = send(c, &ok, 2, 0)
            var req = [UInt8](repeating: 0, count: 10); _ = recv(c, &req, 10, MSG_WAITALL)
            lock.lock(); seen = req; lock.unlock()
            var rep: [UInt8] = [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]; _ = send(c, &rep, 10, 0)
            self.readSome(c)
            var r: [UInt8] = [0x16, 3, 3, 0, 1]; _ = send(c, &r, 5, 0); Thread.sleep(forTimeInterval: 0.2); close(c)
        }
        defer { close(ls) }
        let o = TlsProbe.probe(ip: "162.159.128.233", port: 443, socksPort: port, hello: [0x16], timeout: 2)
        if case .passed = o {} else { XCTFail("\(o)") }
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seen)?.target, .ipv4([162, 159, 128, 233]))
        XCTAssertEqual(Socks5.parseRequest(seen)?.port, 443)
    }
}
