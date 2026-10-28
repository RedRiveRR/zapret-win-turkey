import Foundation

/// HTTP CONNECT isteği ayrıştırma. Sistem "Güvenli Web Proxy"si yalnız CONNECT gönderir; Discord'un Rust
/// güncelleyicisi (reqwest) SOCKS'u görmez, yalnız bunu kullanır.
public enum HttpConnect {
    public enum Parsed: Equatable {
        case connect(Socks5.Target, UInt16)
        /// Düz HTTP proxy isteği (mutlak adres): hedef ve kaynak biçimine yeniden yazılmış istek başı.
        case forward(Socks5.Target, UInt16, [UInt8])
        case notConnect
        case bad
    }

    public static let established = Array("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)

    public static func failure(_ code: Int) -> [UInt8] {
        let reason: String
        switch code {
        case 400: reason = "Bad Request"
        case 405: reason = "Method Not Allowed"
        default: reason = "Bad Gateway"
        }
        return Array("HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }

    /// `head`: istek satırı ve başlıklar (CRLFCRLF dahil ya da değil). Yöntem büyük/küçük harfe duyarlıdır.
    public static func parse(head: String) -> Parsed {
        let line = head.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let method = parts.first else { return .bad }
        guard method == "CONNECT" else {
            guard parts.count >= 3 else { return .notConnect }
            let lower = parts[1].lowercased()
            if lower.hasPrefix("https://") { return .bad }
            guard lower.hasPrefix("http://") else { return .notConnect }
            guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { return .bad }
            return forward(head: head, method: method, url: String(parts[1].dropFirst(7)), version: parts[2])
        }
        guard parts.count >= 2, let (target, port) = authority(parts[1], defaultPort: nil) else { return .bad }
        return .connect(target, port)
    }

    /// "host:port" (port yoksa `defaultPort`); IPv6 sabit adres ve geçersiz ad reddedilir.
    static func authority(_ a: String, defaultPort: Int?) -> (Socks5.Target, UInt16)? {
        guard !a.hasPrefix("[") else { return nil }
        var host = a, port = defaultPort
        if let colon = a.lastIndex(of: ":") {
            host = String(a[..<colon])
            port = Int(a[a.index(after: colon)...])
        }
        guard let p = port, (1...65535).contains(p), !host.isEmpty, host.utf8.count <= 253,
              host.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x41 && $0 <= 0x5A) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F })
        else { return nil }
        if let ip = Socks5.ipv4Bytes(host) { return (.ipv4(ip), UInt16(p)) }
        return (.domain(host), UInt16(p))
    }

    /// "GET http://h:p/yol?q HTTP/1.1" → hedef + "GET /yol?q HTTP/1.1"; proxy/bağlantı başlıkları atılır, "Connection: close"
    /// eklenir (bağlantı başına tek istek: farklı sunuculara giden ardışık istekler karışmasın).
    static func forward(head: String, method: String, url: String, version: String) -> Parsed {
        let cut = url.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? url.endIndex
        guard let (target, port) = authority(String(url[..<cut]), defaultPort: 80) else { return .bad }
        var path = String(url[cut...])
        if path.isEmpty { path = "/" } else if path.hasPrefix("?") { path = "/" + path }
        let drop: Set<String> = ["proxy-connection", "proxy-authorization", "connection", "keep-alive"]
        var lines = ["\(method) \(path) \(version)"]
        for raw in head.components(separatedBy: "\n").dropFirst() {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty { break }
            let name = line.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            if !drop.contains(name) { lines.append(line) }
        }
        lines.append("Connection: close")
        return .forward(target, port, Array((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8))
    }
}
