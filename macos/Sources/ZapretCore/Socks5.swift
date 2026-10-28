import Foundation

/// SOCKS5 (RFC 1928) CONNECT isteği ayrıştırma/oluşturma. Yalnız ön proxy'nin ihtiyacı kadar.
public enum Socks5 {
    public enum Target: Equatable {
        case ipv4([UInt8])
        case ipv6([UInt8])
        case domain(String)
    }

    public struct Request: Equatable {
        public let command: UInt8
        public let target: Target
        public let port: UInt16
    }

    /// Tam bir istek baytı dizisini (05 CMD 00 ATYP ADDR PORT) ayrıştırır; eksik/bozuksa nil.
    public static func parseRequest(_ b: [UInt8]) -> Request? {
        guard b.count >= 4, b[0] == 5 else { return nil }
        let target: Target
        let end: Int
        switch b[3] {
        case 1:
            guard b.count >= 10 else { return nil }
            target = .ipv4(Array(b[4..<8])); end = 8
        case 4:
            guard b.count >= 22 else { return nil }
            target = .ipv6(Array(b[4..<20])); end = 20
        case 3:
            guard b.count >= 5 else { return nil }
            let len = Int(b[4])
            guard len > 0, b.count >= 5 + len + 2,
                  let name = String(bytes: b[5..<(5 + len)], encoding: .utf8) else { return nil }
            target = .domain(name); end = 5 + len
        default:
            return nil
        }
        return Request(command: b[1], target: target, port: UInt16(b[end]) << 8 | UInt16(b[end + 1]))
    }

    public static func encodeConnect(target: Target, port: UInt16) -> [UInt8] {
        var out: [UInt8] = [5, 1, 0]
        switch target {
        case .ipv4(let a): out += [1] + a
        case .ipv6(let a): out += [4] + a
        case .domain(let d): let n = Array(d.utf8); out += [3, UInt8(n.count)] + n
        }
        return out + [UInt8(port >> 8), UInt8(port & 0xFF)]
    }

    /// Dört baytlık başlıktan sonra okunacak bayt sayısı. Alan adında önce uzunluk baytı okunur,
    /// dönen sayı o baytın ARDINDAN kalanı (ad + 2 bayt kapı) verir. Bilinmeyen tür: nil.
    public static func addressBytes(atyp: UInt8, firstByte: UInt8) -> Int? {
        switch atyp {
        case 1: return 4 + 2
        case 4: return 16 + 2
        case 3: return Int(firstByte) + 2
        default: return nil
        }
    }

    public static func ipv4Bytes(_ s: String) -> [UInt8]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = UInt8(p) else { return nil }
            out.append(n)
        }
        return out
    }
}
