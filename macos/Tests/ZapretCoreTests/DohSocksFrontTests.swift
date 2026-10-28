import XCTest
import Darwin
@testable import ZapretCore

/// Sahte "tpws" (SOCKS5 yukarı akış) ile ön proxy'nin uçtan uca davranışı.
final class DohSocksFrontTests: XCTestCase {
    private func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0); defer { close(fd) }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = 0
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var l = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &l) } }
        return Int(UInt16(bigEndian: a.sin_port))
    }

    private func connectLocal(_ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = in_port_t(UInt16(port).bigEndian)
        let rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(rc, 0)
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private func readN(_ fd: Int32, _ n: Int) -> [UInt8] {
        var out = [UInt8]()
        while out.count < n {
            var b = [UInt8](repeating: 0, count: n - out.count)
            let k = recv(fd, &b, b.count, 0)
            if k <= 0 { break }
            out += b[0..<k]
        }
        return out
    }

    private func writeAll(_ fd: Int32, _ b: [UInt8]) { _ = b.withUnsafeBytes { send(fd, $0.baseAddress, b.count, 0) } }

    /// Tek bağlantı kabul eden, gelen CONNECT isteğini kaydeden, sonra yankılayan sahte yukarı akış.
    private func startFakeUpstream(port: Int, replyCode: UInt8 = 0, seen: @escaping ([UInt8]) -> Void) -> Int32 {
        let ls = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1; setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, 4)
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = in_port_t(UInt16(port).bigEndian)
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(ls, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(ls, 4)
        Thread.detachNewThread {
            while true {
                let c = accept(ls, nil, nil)
                if c < 0 { return }
                _ = self.readN(c, 3)                 // karşılama 05 01 00
                self.writeAll(c, [5, 0])
                let head = self.readN(c, 4)          // 05 01 00 atyp
                var req = head
                if head.count == 4 {
                    switch head[3] {
                    case 1: req += self.readN(c, 6)
                    case 3: let l = self.readN(c, 1); req += l; req += self.readN(c, Int(l.first ?? 0) + 2)
                    case 4: req += self.readN(c, 18)
                    default: break
                    }
                }
                seen(req)
                self.writeAll(c, [5, replyCode, 0, 1, 0, 0, 0, 0, 0, 0])
                if replyCode != 0 { close(c); continue }
                while true { let d = self.readN(c, 1); if d.isEmpty { break }; self.writeAll(c, d) }
                close(c)
            }
        }
        return ls
    }

    func testDomainFromHostlistIsResolvedAndForwardedAsIPv4() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { host in host == "discord.com" ? ["162.159.128.233"] : [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }

        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); XCTAssertEqual(readN(c, 2), [5, 0])
        writeAll(c, Socks5.encodeConnect(target: .domain("discord.com"), port: 443))
        XCTAssertEqual(readN(c, 10)[1], 0) // başarılı
        writeAll(c, [0x41]); XCTAssertEqual(readN(c, 1), [0x41]) // veri yukarı akıştan yankılanır
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .ipv4([162, 159, 128, 233]))
    }

    func testUnresolvedDomainPassesThroughByName() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); _ = readN(c, 2)
        writeAll(c, Socks5.encodeConnect(target: .domain("example.org"), port: 443))
        XCTAssertEqual(readN(c, 10)[1], 0)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .domain("example.org"))
    }

    func testUnsupportedCommandIsRefused() {
        let fp = freePort()
        let front = DohSocksFront(port: fp, upstreamPort: freePort(), resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); _ = readN(c, 2)
        writeAll(c, [5, 2, 0, 1, 1, 2, 3, 4, 0, 80]) // BIND
        XCTAssertEqual(readN(c, 10)[1], 7) // komut desteklenmiyor
    }

    func testStartFailsWhenPortBusyAndStopFreesPort() {
        let fp = freePort()
        let a = DohSocksFront(port: fp, upstreamPort: freePort(), resolve: { _ in [] })
        XCTAssertNoThrow(try a.start())
        let b = DohSocksFront(port: fp, upstreamPort: freePort(), resolve: { _ in [] })
        XCTAssertThrowsError(try b.start())
        a.stop()
        XCTAssertTrue(TpwsArgs.isPortFree(fp))
    }

    func testEventLogReportsRequestedNameChosenTargetAndResult() {
        let up = freePort(), fp = freePort()
        let ls = startFakeUpstream(port: up) { _ in }
        defer { close(ls) }
        let lock = NSLock(); var events: [String] = []
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in ["162.159.128.233"] })
        front.onEvent = { lock.lock(); events.append($0); lock.unlock() }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); _ = readN(c, 2)
        writeAll(c, Socks5.encodeConnect(target: .domain("discord.com"), port: 443))
        XCTAssertEqual(readN(c, 10)[1], 0)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(events, ["discord.com:443 -> 162.159.128.233 (DoH) tamam"])
    }

    func testEventLogMarksIPv4RequestsAndFailures() {
        let up = freePort(), fp = freePort()
        let ls = startFakeUpstream(port: up, replyCode: 5) { _ in }
        defer { close(ls) }
        let lock = NSLock(); var events: [String] = []
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] })
        front.onEvent = { lock.lock(); events.append($0); lock.unlock() }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); _ = readN(c, 2)
        writeAll(c, Socks5.encodeConnect(target: .ipv4([195, 175, 254, 2]), port: 443))
        XCTAssertEqual(readN(c, 10)[1], 5)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(events, ["195.175.254.2:443 -> 195.175.254.2 hata 5"])
    }

    // MARK: HTTP CONNECT (Discord güncelleyicisi gibi SOCKS bilmeyen istemciler; sistem "Güvenli Web Proxy")

    private func readHead(_ fd: Int32) -> String {
        var out = [UInt8]()
        while !(out.count >= 4 && Array(out.suffix(4)) == [13, 10, 13, 10]) {
            let b = readN(fd, 1)
            if b.isEmpty { break }
            out += b
        }
        return String(decoding: out, as: UTF8.self)
    }

    func testHttpConnectDomainIsResolvedAndTunnelled() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []; var events: [String] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { $0 == "updates.discord.com" ? ["162.159.138.232"] : [] })
        front.onEvent = { lock.lock(); events.append($0); lock.unlock() }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("CONNECT updates.discord.com:443 HTTP/1.1\r\nHost: updates.discord.com:443\r\n\r\n".utf8))
        XCTAssertEqual(readHead(c), "HTTP/1.1 200 Connection Established\r\n\r\n")
        writeAll(c, [0x42]); XCTAssertEqual(readN(c, 1), [0x42]) // tünel çalışıyor
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .ipv4([162, 159, 138, 232]))
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.port, 443)
        XCTAssertEqual(events, ["updates.discord.com:443 -> 162.159.138.232 (DoH) tamam"])
    }

    func testHttpConnectUnresolvedPassesNameThrough() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("CONNECT example.org:443 HTTP/1.1\r\n\r\n".utf8))
        XCTAssertTrue(readHead(c).hasPrefix("HTTP/1.1 200"))
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .domain("example.org"))
    }

    func testHttpPlainRequestIsRefused() {
        let fp = freePort()
        let front = DohSocksFront(port: fp, upstreamPort: freePort(), resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("GET /yerel HTTP/1.1\r\nHost: example.org\r\n\r\n".utf8))
        XCTAssertTrue(readHead(c).hasPrefix("HTTP/1.1 405"))
    }

    func testPlainHttpIsForwardedThroughUpstream() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        let req = "GET http://example.org/a HTTP/1.1\r\nHost: example.org\r\n\r\n"
        writeAll(c, Array(req.utf8))
        // sahte yukarı akış yankılar: istemci yeniden yazılmış isteği geri almalı (yanıt yerine)
        let expect = "GET /a HTTP/1.1\r\nHost: example.org\r\nConnection: close\r\n\r\n"
        XCTAssertEqual(String(decoding: readN(c, expect.utf8.count), as: UTF8.self), expect)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .domain("example.org"))
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.port, 80)
    }

    func testHttpConnectUpstreamFailureIs502() {
        let up = freePort(), fp = freePort()
        let ls = startFakeUpstream(port: up, replyCode: 5) { _ in }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] })
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("CONNECT example.org:443 HTTP/1.1\r\n\r\n".utf8))
        XCTAssertTrue(readHead(c).hasPrefix("HTTP/1.1 502"))
    }

    func testEventLogReportsRefusedHttpRequestLine() {
        let fp = freePort()
        let lock = NSLock(); var events: [String] = []
        let front = DohSocksFront(port: fp, upstreamPort: freePort(), resolve: { _ in [] })
        front.onEvent = { lock.lock(); events.append($0); lock.unlock() }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("GET /yerel HTTP/1.1\r\nHost: example.org\r\n\r\n".utf8))
        XCTAssertTrue(readHead(c).hasPrefix("HTTP/1.1 405"))
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(events, ["http reddedildi (405): GET /yerel HTTP/1.1"])
    }

    // MARK: SNI ile kurtarma (paylaşım: cihaz adı zehirli ISS DNS'iyle çözüp proxy'ye IP gönderirse)

    func testIpTargetIsRedirectedToDohAddressOfSniHost() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []; var events: [String] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { $0 == "discord.com" ? ["162.159.128.233"] : [] }, sniRecovery: true)
        front.onEvent = { lock.lock(); events.append($0); lock.unlock() }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, Array("CONNECT 195.175.254.2:443 HTTP/1.1\r\n\r\n".utf8))
        XCTAssertTrue(readHead(c).hasPrefix("HTTP/1.1 200"))
        let hello = TlsClientHello.build(sni: "discord.com", profile: .modern)
        writeAll(c, hello)
        XCTAssertEqual(readN(c, hello.count), hello) // ClientHello yukarı akışa (gerçek IP'ye) iletildi, yankı döndü
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .ipv4([162, 159, 128, 233]))
        XCTAssertEqual(events, ["195.175.254.2:443 (SNI discord.com) -> 162.159.128.233 (DoH) tamam"])
    }

    func testIpTargetWithUnlistedSniKeepsOriginalAddress() {
        let up = freePort(), fp = freePort()
        let lock = NSLock(); var seenReq: [UInt8] = []
        let ls = startFakeUpstream(port: up) { lock.lock(); seenReq = $0; lock.unlock() }
        defer { close(ls) }
        let front = DohSocksFront(port: fp, upstreamPort: up, resolve: { _ in [] }, sniRecovery: true)
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = connectLocal(fp); defer { close(c) }
        writeAll(c, [5, 1, 0]); _ = readN(c, 2)
        writeAll(c, Socks5.encodeConnect(target: .ipv4([93, 184, 216, 34]), port: 443))
        XCTAssertEqual(readN(c, 10)[1], 0)
        let hello = TlsClientHello.build(sni: "example.org", profile: .modern)
        writeAll(c, hello)
        XCTAssertEqual(readN(c, hello.count), hello)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(Socks5.parseRequest(seenReq)?.target, .ipv4([93, 184, 216, 34]))
    }
}
