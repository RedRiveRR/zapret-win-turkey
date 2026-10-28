import Foundation

/// tpws argümanlarından okunur Türkçe ad ("--tlsrec=midsld" → "TLS kaydı · alan adı ortası").
/// Ham argüman arayüzde okunmuyordu (yazı tipi "--"yi "–" yapıyor), tam hâli ipucunda/raporda kalır.
public enum StrategyNames {
    static let markers = ["sniext": "SNI", "host": "ad başı", "endhost": "ad sonu", "sld": "ana alan adı",
                          "midsld": "alan adı ortası", "endsld": "alan adı sonu", "method": "yöntem"]

    public static func label(_ args: [String]) -> String {
        var tlsrec: String?, split: String?
        var extras: [String] = [], unknown: [String] = []
        var oobData: String?
        for a in args {
            let kv = a.split(separator: "=", maxSplits: 1).map(String.init)
            switch kv[0] {
            case "--tlsrec": tlsrec = kv.count > 1 ? positions(kv[1]) : ""
            case "--split-pos": split = kv.count > 1 ? positions(kv[1]) : ""
            case "--oob": extras.append("OOB")
            case "--disorder": extras.append("sıra bozma")
            case "--hostcase": extras.append("harf karıştırma")
            case "--oob-data": oobData = kv.count > 1 ? kv[1] : nil
            case "--tamper-cutoff": extras.append("yalnız ilk paket")
            default: unknown.append(a.hasPrefix("--") ? String(a.dropFirst(2)) : a)
            }
        }
        if let d = oobData, let i = extras.firstIndex(of: "OOB") { extras[i] = "OOB (\(d))" }
        var parts: [String] = []
        if let t = tlsrec {
            parts.append("TLS kaydı · \(t)")
            if let s = split { parts.append("bölme · \(s)") }
        } else if let s = split {
            parts.append("Bölme · \(s)")
        }
        parts += extras + unknown
        return parts.joined(separator: " + ")
    }

    /// "1,midsld" → "1. bayt, alan adı ortası"; "sniext+2" → "SNI +2"; "endsld-1" → "alan adı sonu −1".
    static func positions(_ v: String) -> String {
        v.split(separator: ",").map { p -> String in
            let s = String(p)
            guard let i = s.firstIndex(where: { $0 == "+" || $0 == "-" }), i != s.startIndex else { return base(s) }
            let sign = s[i] == "+" ? "+" : "−"
            return "\(base(String(s[..<i]))) \(sign)\(s[s.index(after: i)...])"
        }.joined(separator: ", ")
    }

    static func base(_ m: String) -> String {
        if let n = Int(m) { return "\(n). bayt" }
        return markers[m] ?? m
    }
}

extension Strategies {
    /// Kayıtlı seçimi bulur: ada göre, olmazsa kayıtlı argümanlara göre, olmazsa eski sürümün "Analiz: <argümanlar>" adından.
    public static func resolve(savedName: String, savedArgs: String, in list: [TpwsStrategy]) -> TpwsStrategy? {
        if let s = list.first(where: { $0.name == savedName }) { return s }
        for text in [savedArgs, savedName.hasPrefix("Analiz: ") ? String(savedName.dropFirst(8)) : ""] where !text.isEmpty {
            let args = text.split(separator: " ").map(String.init)
            if let s = list.first(where: { $0.args == args }) { return s }
        }
        return nil
    }
}
