import Foundation

/// Analiz için sentetik TLS ClientHello. Üç profil sahada yakalanan gerçek istemcileri taklit eder; DPI'nin
/// SNI'yı nerede aradığı istemciye göre değiştiği için strateji hepsinde sınanır (saha 2026-10-28: --tlsrec=sniext+1
/// Chromium'da geçip Discord güncelleyicisinde RST yiyordu).
public enum TlsClientHello {
    public enum Profile: String, CaseIterable, Codable {
        /// Apple Secure Transport (Discord güncelleyicisi): yalnız TLS 1.2, SNI ilk uzantı, ~180 B.
        case appleLegacy
        /// Chromium/Electron (Discord uygulaması): TLS 1.3, SNI ortada, dolguyla ~1780 B.
        case chromium
        /// curl/LibreSSL, tarayıcı benzeri: TLS 1.3, ~320 B.
        case modern
    }

    public static func build(sni: String, profile: Profile, random: () -> UInt8 = { UInt8.random(in: 0...255) }) -> [UInt8] {
        func rnd(_ n: Int) -> [UInt8] { (0..<n).map { _ in random() } }
        let name = Array(sni.utf8)
        let sniExt = ext(0x0000, u16(name.count + 3) + [0] + u16(name.count) + name)
        let groups12 = ext(0x000a, list16([0x001d, 0x0017, 0x0018, 0x0019]))
        let points = ext(0x000b, [1, 0])
        let sigalgs = ext(0x000d, list16([0x0403, 0x0804, 0x0401, 0x0503, 0x0805, 0x0501, 0x0806, 0x0601, 0x0201]))
        let status = ext(0x0005, [1, 0, 0, 0, 0])
        let ems = ext(0x0017, [])
        let versions = ext(0x002b, [4, 0x03, 0x04, 0x03, 0x03])
        let keyShare = ext(0x0033, u16(36) + u16(0x001d) + u16(32) + rnd(32))
        let pskModes = ext(0x002d, [1, 1])
        let alpn = ext(0x0010, u16(14) + [2] + Array("h2".utf8) + [8] + Array("http/1.1".utf8))
        let reneg = ext(0xff01, [0])
        let tls12Ciphers: [Int] = [0xc02c, 0xc02b, 0xc024, 0xc023, 0xc00a, 0xc009, 0xc030, 0xc02f, 0xc028, 0xc027, 0xc014, 0xc013,
                                   0x009d, 0x009c, 0x003d, 0x003c, 0x0035, 0x002f, 0xcca9, 0xcca8, 0xc008, 0xc012]
        let tls13Ciphers: [Int] = [0x1301, 0x1302, 0x1303, 0xc02b, 0xc02f, 0xc02c, 0xc030, 0xcca9, 0xcca8, 0xc013, 0xc014, 0x009c, 0x009d, 0x002f, 0x0035]

        var sessionId: [UInt8] = []
        var ciphers: [Int]
        var exts: [UInt8]
        switch profile {
        case .appleLegacy:
            ciphers = tls12Ciphers
            exts = sniExt + groups12 + points + sigalgs + status + ext(0x0012, []) + ems
        case .chromium:
            sessionId = rnd(32)
            ciphers = [0x0a0a] + tls13Ciphers
            let grease = ext(0x1a1a, [])
            let groups = ext(0x000a, list16([0x0a0a, 0x001d, 0x0017, 0x0018]))
            let compressCert = ext(0x001b, [2, 0, 2])
            let body = grease + sigalgs + ext(0x0012, []) + keyShare + ext(0x0023, []) + compressCert + groups + versions
                + alpn + status + pskModes + sniExt + points + ems + reneg
            // Chromium'un post-kuantum anahtar paylaşımı ClientHello'yu ~1780 B yapar; dolgu (padding) ile aynı boyut.
            let tail = ext(0x2a2a, [0])
            let bare = assemble(rnd(32), sessionId, ciphers, body + tail).count
            exts = body + (bare + 4 < 1780 ? ext(0x0015, [UInt8](repeating: 0, count: 1780 - bare - 4)) : []) + tail
        case .modern:
            sessionId = rnd(32)
            ciphers = tls13Ciphers + [0xc024, 0xc023, 0xc028, 0xc027, 0x003d, 0x003c, 0xc00a, 0xc009, 0x00ff]
            exts = versions + keyShare + sniExt + points + groups12 + sigalgs + alpn
        }
        return assemble(rnd(32), sessionId, ciphers, exts)
    }

    private static func assemble(_ random: [UInt8], _ sessionId: [UInt8], _ ciphers: [Int], _ exts: [UInt8]) -> [UInt8] {
        var hello: [UInt8] = [0x03, 0x03] + random + [UInt8(sessionId.count)] + sessionId
        hello += u16(ciphers.count * 2) + ciphers.flatMap { u16($0) }
        hello += [1, 0]
        hello += u16(exts.count) + exts
        let hs: [UInt8] = [1, UInt8((hello.count >> 16) & 0xff), UInt8((hello.count >> 8) & 0xff), UInt8(hello.count & 0xff)] + hello
        return [0x16, 0x03, 0x01] + u16(hs.count) + hs
    }

    /// SNI'yı okur (testler ve günlük için); bozuksa nil.
    public static func serverName(in h: [UInt8]) -> String? {
        guard let exts = extensions(in: h) else { return nil }
        for (t, d) in exts where t == 0 {
            guard d.count >= 5 else { return nil }
            let n = Int(d[3]) << 8 | Int(d[4])
            guard d.count >= 5 + n else { return nil }
            return String(bytes: d[5..<(5 + n)], encoding: .utf8)
        }
        return nil
    }

    public static func extensionTypes(in h: [UInt8]) -> [Int] { extensions(in: h)?.map(\.0) ?? [] }

    private static func extensions(in h: [UInt8]) -> [(Int, [UInt8])]? {
        guard h.count > 43, h[0] == 0x16, h[5] == 1 else { return nil }
        var p = 9 + 2 + 32
        guard p < h.count else { return nil }
        p += 1 + Int(h[p])
        guard p + 2 <= h.count else { return nil }
        p += 2 + (Int(h[p]) << 8 | Int(h[p + 1]))
        guard p < h.count else { return nil }
        p += 1 + Int(h[p])
        guard p + 2 <= h.count else { return nil }
        let end = p + 2 + (Int(h[p]) << 8 | Int(h[p + 1]))
        p += 2
        guard end <= h.count else { return nil }
        var out: [(Int, [UInt8])] = []
        while p + 4 <= end {
            let t = Int(h[p]) << 8 | Int(h[p + 1]), l = Int(h[p + 2]) << 8 | Int(h[p + 3])
            guard p + 4 + l <= end else { return nil }
            out.append((t, Array(h[(p + 4)..<(p + 4 + l)])))
            p += 4 + l
        }
        return out
    }

    private static func u16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    private static func ext(_ type: Int, _ data: [UInt8]) -> [UInt8] { u16(type) + u16(data.count) + data }
    private static func list16(_ items: [Int]) -> [UInt8] { u16(items.count * 2) + items.flatMap { u16($0) } }
}
