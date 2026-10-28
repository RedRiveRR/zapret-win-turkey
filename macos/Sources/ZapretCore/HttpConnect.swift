import Foundation

/// HTTP CONNECT isteği ayrıştırma. Sistem "Güvenli Web Proxy"si yalnız CONNECT gönderir; Discord'un Rust
/// güncelleyicisi (reqwest) SOCKS'u görmez, yalnız bunu kullanır.
public enum HttpConnect {
    public enum Parsed: Equatable {
        case connect(Socks5.Target, UInt16)
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
        guard method == "CONNECT" else { return .notConnect }
        guard parts.count >= 2, !parts[1].hasPrefix("["), let colon = parts[1].lastIndex(of: ":") else { return .bad }
        let host = String(parts[1][..<colon])
        guard let port = Int(parts[1][parts[1].index(after: colon)...]), (1...65535).contains(port),
              !host.isEmpty, host.utf8.count <= 253,
              host.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x41 && $0 <= 0x5A) || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F })
        else { return .bad }
        if let ip = Socks5.ipv4Bytes(host) { return .connect(.ipv4(ip), UInt16(port)) }
        return .connect(.domain(host), UInt16(port))
    }
}
