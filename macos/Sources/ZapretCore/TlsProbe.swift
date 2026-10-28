import Foundation
import Darwin

/// Tek bağlantılık DPI sondası: (isteğe bağlı SOCKS5 üzerinden) IP:443'e ClientHello gönderir. Sunucudan TLS kaydı
/// (ServerHello 0x16 ya da uyarı 0x15) gelirse ClientHello sunucuya ulaşmıştır; RST/kapanma DPI kesmesidir.
/// El sıkışma tamamlanmaz, veri gitmez.
public enum TlsProbe {
    public enum Outcome: Equatable {
        case passed(ms: Int)
        case reset
        case timeout
        case failed(String)

        public var isPass: Bool { if case .passed = self { return true }; return false }
    }

    public static func probe(ip: String, port: UInt16 = 443, socksPort: Int?, hello: [UInt8], timeout: TimeInterval) -> Outcome {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failed("socket") }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let start = Date()
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr(socksPort == nil ? ip : "127.0.0.1")
        addr.sin_port = in_port_t((socksPort.map { UInt16(truncatingIfNeeded: $0) } ?? port).bigEndian)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else { return errno == ETIMEDOUT || errno == EAGAIN ? .timeout : .failed("bağlanamadı (\(errno))") }
        if socksPort != nil {
            guard let ipBytes = Socks5.ipv4Bytes(ip) else { return .failed("IPv4 değil") }
            guard write(fd, [5, 1, 0]), let m = read(fd, 2), m == [5, 0] else { return .failed("SOCKS el sıkışması") }
            guard write(fd, Socks5.encodeConnect(target: .ipv4(ipBytes), port: port)), let r = read(fd, 10) else { return .failed("SOCKS yanıtı") }
            guard r[1] == 0 else { return .failed("SOCKS hata \(r[1])") }
        }
        guard write(fd, hello) else { return .reset }
        var b: UInt8 = 0
        let n = recv(fd, &b, 1, 0)
        if n == 1 { return b == 0x16 || b == 0x15 ? .passed(ms: Int(Date().timeIntervalSince(start) * 1000)) : .failed("TLS dışı yanıt") }
        if n == 0 { return .reset }
        return errno == EAGAIN || errno == EWOULDBLOCK ? .timeout : .reset
    }

    private static func write(_ fd: Int32, _ b: [UInt8]) -> Bool {
        var off = 0
        while off < b.count {
            let k = b.withUnsafeBytes { send(fd, $0.baseAddress! + off, b.count - off, 0) }
            if k <= 0 { return false }
            off += k
        }
        return true
    }

    private static func read(_ fd: Int32, _ n: Int) -> [UInt8]? {
        var out = [UInt8]()
        while out.count < n {
            var b = [UInt8](repeating: 0, count: n - out.count)
            let k = recv(fd, &b, b.count, 0)
            if k <= 0 { return nil }
            out += b[0..<k]
        }
        return out
    }
}
