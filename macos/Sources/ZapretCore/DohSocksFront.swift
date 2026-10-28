import Foundation
import Darwin

/// 127.0.0.1:port'ta SOCKS5 CONNECT ve HTTP CONNECT kabul eder, tpws'e (upstreamPort) iletir. Alan adı geldiğinde `resolve`
/// IP verirse (DoH ile, zehirsiz) tpws'e adın yerine IPv4 gider; tpws hostlist'i yine SNI'dan uygular.
/// Çözüm yoksa ad olduğu gibi tpws'e geçer (sistem DNS'i). Yalnız CONNECT (HTTP'de düz GET/POST 405); UDP/BIND desteklenmez.
public final class DohSocksFront {
    public let port: Int
    /// Her CONNECT denemesi için tek satır ("ad:kapı -> hedef [(DoH)] tamam|hata N"). Ziyaret geçmişi içerir; yalnız hata ayıklamada bağlanır.
    public var onEvent: ((String) -> Void)?
    private let upstreamPort: Int
    private let resolve: (String) -> [String]
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var clients = Set<Int32>()
    private var loopDone: DispatchSemaphore?

    public init(port: Int, upstreamPort: Int, resolve: @escaping (String) -> [String]) {
        self.port = port
        self.upstreamPort = upstreamPort
        self.resolve = resolve
    }

    public func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard listenFD < 0 else { return }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw EngineError.portBusy(port) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = Self.loopback(port)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0, listen(fd, 128) == 0 else { close(fd); throw EngineError.portBusy(port) }
        listenFD = fd
        let done = DispatchSemaphore(value: 0)
        loopDone = done
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(fd)
            close(fd) // kapı burada boşalır
            done.signal()
        }
    }

    public func stop() {
        lock.lock()
        let wasListening = listenFD >= 0
        listenFD = -1
        for c in clients { shutdown(c, SHUT_RDWR) } // bloklu okumalar uyanır, tutamaç kendi iş parçacığında kapanır
        let done = loopDone
        loopDone = nil
        lock.unlock()
        if wasListening { _ = done?.wait(timeout: .now() + 2) }
    }

    private var isListening: Bool { lock.lock(); defer { lock.unlock() }; return listenFD >= 0 }

    private func acceptLoop(_ fd: Int32) {
        while isListening {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 200) >= 0 || errno == EINTR else { return }
            guard p.revents & Int16(POLLIN) != 0 else { continue }
            let c = accept(fd, nil, nil)
            if c < 0 { continue }
            lock.lock(); clients.insert(c); lock.unlock()
            Thread.detachNewThread { [weak self] in self?.handle(c) }
        }
    }

    // MARK: Bağlantı

    /// İlk bayt 0x05 ise SOCKS5, değilse HTTP (CONNECT) istemcisi sayılır.
    private func handle(_ c: Int32) {
        defer {
            lock.lock(); clients.remove(c); lock.unlock()
            close(c)
        }
        Self.prepare(c)
        var first: UInt8 = 0
        guard recv(c, &first, 1, MSG_PEEK) == 1 else { return }
        if first == 5 { handleSocks(c) } else { handleHttp(c) }
    }

    private func handleSocks(_ c: Int32) {
        guard let g = Self.readExact(c, 2), g[0] == 5, Self.readExact(c, Int(g[1])) != nil else { return }
        Self.writeAll(c, [5, 0])
        guard let req = Self.readRequest(c) else { Self.writeAll(c, Self.failure(8)); return }
        guard let r = Socks5.parseRequest(req) else { Self.writeAll(c, Self.failure(1)); return }
        guard r.command == 1 else { Self.writeAll(c, Self.failure(7)); return }
        tunnel(c, target: r.target, port: r.port, http: false)
    }

    private func handleHttp(_ c: Int32) {
        guard let head = Self.readHead(c) else { Self.writeAll(c, HttpConnect.failure(400)); return }
        switch HttpConnect.parse(head: head) {
        case .connect(let target, let port): tunnel(c, target: target, port: port, http: true)
        case .notConnect: Self.writeAll(c, HttpConnect.failure(405))
        case .bad: Self.writeAll(c, HttpConnect.failure(400))
        }
    }

    /// Hedefi (gerekirse DoH ile IP'ye çevirip) tpws üzerinden açar ve iki yönlü aktarır.
    private func tunnel(_ c: Int32, target: Socks5.Target, port: UInt16, http: Bool) {
        var targets: [(target: Socks5.Target, doh: Bool)] = [(target, false)]
        if case .domain(let name) = target {
            let ips = resolve(name).compactMap(Socks5.ipv4Bytes).prefix(3).map { (target: Socks5.Target.ipv4($0), doh: true) }
            if !ips.isEmpty { targets = ips + [(target, false)] }
        }
        let asked = "\(Self.describe(target)):\(port)"
        var last = Self.failure(4)
        for t in targets {
            let how = "\(asked) -> \(Self.describe(t.target))\(t.doh ? " (DoH)" : "")"
            switch openUpstream(Socks5.encodeConnect(target: t.target, port: port)) {
            case .connected(let up, let reply):
                onEvent?("\(how) tamam")
                Self.writeAll(c, http ? HttpConnect.established : reply)
                relay(c, up)
                close(up)
                return
            case .refused(let reply):
                onEvent?("\(how) hata \(reply.count > 1 ? Int(reply[1]) : 1)")
                last = reply
            }
        }
        Self.writeAll(c, http ? HttpConnect.failure(502) : last)
    }

    private enum Upstream { case connected(Int32, [UInt8]); case refused([UInt8]) }

    private func openUpstream(_ request: [UInt8]) -> Upstream {
        let up = socket(AF_INET, SOCK_STREAM, 0)
        guard up >= 0 else { return .refused(Self.failure(1)) }
        Self.prepare(up)
        var addr = Self.loopback(upstreamPort)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(up, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else { close(up); return .refused(Self.failure(1)) }
        Self.writeAll(up, [5, 1, 0])
        guard let m = Self.readExact(up, 2), m == [5, 0] else { close(up); return .refused(Self.failure(1)) }
        Self.writeAll(up, request)
        guard let reply = Self.readRequest(up) else { close(up); return .refused(Self.failure(1)) }
        guard reply.count > 1, reply[1] == 0 else { close(up); return .refused(reply.count > 1 ? reply : Self.failure(1)) }
        return .connected(up, reply)
    }

    private func relay(_ a: Int32, _ b: Int32) {
        Self.clearTimeout(a); Self.clearTimeout(b)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            Self.pump(from: a, to: b)
            done.signal()
        }
        Self.pump(from: b, to: a)
        _ = done.wait(timeout: .distantFuture)
    }

    private static func pump(from src: Int32, to dst: Int32) {
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = recv(src, &buf, buf.count, 0)
            if n <= 0 { break }
            var off = 0
            while off < n {
                let k = buf.withUnsafeBytes { send(dst, $0.baseAddress! + off, n - off, 0) }
                if k <= 0 { shutdown(src, SHUT_RD); shutdown(dst, SHUT_WR); return }
                off += k
            }
        }
        shutdown(dst, SHUT_WR)
    }

    // MARK: Yardımcılar

    /// HTTP istek satırı + başlıklar (CRLFCRLF'e kadar, en çok 8 KiB); tünelin ilk baytlarını yutmamak için bayt bayt okunur.
    private static func readHead(_ fd: Int32) -> String? {
        var out = [UInt8]()
        while out.count < 8192 {
            guard let b = readExact(fd, 1) else { return nil }
            out += b
            if out.count >= 4, Array(out.suffix(4)) == [13, 10, 13, 10] { return String(decoding: out, as: UTF8.self) }
        }
        return nil
    }

    /// SOCKS5 isteği ya da yanıtı: 4 baytlık başlık + adres + kapı.
    private static func readRequest(_ fd: Int32) -> [UInt8]? {
        guard var out = readExact(fd, 4), out[0] == 5 else { return nil }
        var first: UInt8 = 0
        if out[3] == 3 {
            guard let l = readExact(fd, 1) else { return nil }
            out += l; first = l[0]
        }
        guard let n = Socks5.addressBytes(atyp: out[3], firstByte: first), let rest = readExact(fd, n) else { return nil }
        return out + rest
    }

    private static func describe(_ t: Socks5.Target) -> String {
        switch t {
        case .domain(let d): return d
        case .ipv4(let a): return a.map(String.init).joined(separator: ".")
        case .ipv6: return "ipv6"
        }
    }

    private static func failure(_ code: UInt8) -> [UInt8] { [5, code, 0, 1, 0, 0, 0, 0, 0, 0] }

    private static func loopback(_ port: Int) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        return a
    }

    /// SIGPIPE yok, el sıkışma sırasında 10 sn okuma zaman aşımı.
    private static func prepare(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func clearTimeout(_ fd: Int32) {
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func readExact(_ fd: Int32, _ n: Int) -> [UInt8]? {
        var out = [UInt8](); out.reserveCapacity(n)
        while out.count < n {
            var b = [UInt8](repeating: 0, count: n - out.count)
            let k = recv(fd, &b, b.count, 0)
            if k <= 0 { return nil }
            out += b[0..<k]
        }
        return out
    }

    private static func writeAll(_ fd: Int32, _ b: [UInt8]) {
        var off = 0
        while off < b.count {
            let k = b.withUnsafeBytes { send(fd, $0.baseAddress! + off, b.count - off, 0) }
            if k <= 0 { return }
            off += k
        }
    }
}
