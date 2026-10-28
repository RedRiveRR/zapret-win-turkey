import Foundation
import Darwin

/// Sistem çözücüsü (getaddrinfo) — ön proxy'nin kendi iş parçacığında, normal yığınla.
/// tpws'e ad gönderilmez (`--no-resolve`): tpws'in çözücü iş parçacıkları 32-64 KB yığınla açılıyor ve macOS 27'de
/// ilk getaddrinfo çağrısı (libnetwork yüklemesi) bu yığını taşırıp tpws'i çökertiyordu (SIGBUS).
public enum SystemResolver {
    /// Adresler, önce IPv4 sonra IPv6, tekrarsız. Çözülemezse boş.
    public static func resolve(_ host: String) -> [Socks5.Target] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(first) }
        var v4: [Socks5.Target] = [], v6: [Socks5.Target] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let a = p {
            if a.pointee.ai_family == AF_INET, let sa = a.pointee.ai_addr {
                let t = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { s -> Socks5.Target in
                    var addr = s.pointee.sin_addr
                    return .ipv4(withUnsafeBytes(of: &addr) { Array($0) })
                }
                if !v4.contains(t) { v4.append(t) }
            } else if a.pointee.ai_family == AF_INET6, let sa = a.pointee.ai_addr {
                let t = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s -> Socks5.Target in
                    var addr = s.pointee.sin6_addr
                    return .ipv6(withUnsafeBytes(of: &addr) { Array($0) })
                }
                if !v6.contains(t) { v6.append(t) }
            }
            p = a.pointee.ai_next
        }
        return v4 + v6
    }
}
