import Foundation

/// Arayüzle aynı JSON mesaj sözleşmesi (Windows: lib/WebMsg.au3).
public enum Json {
    /// Sırayı koruyarak tek düzey nesne üretir: String (kaçışlı), Bool (true/false), sayılar.
    /// Hazır JSON (dizi/nesne) eklemek için değeri `Json.Raw` ile sarın.
    public static func object(_ pairs: KeyValuePairs<String, Any>) -> String {
        let body = pairs.map { "\(quote($0.key)):\(value($0.value))" }.joined(separator: ",")
        return "{\(body)}"
    }

    /// Nesnedeki bir alanın metin değeri; yoksa ya da JSON bozuksa nil.
    public static func get(_ json: String, _ key: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let v = obj[key] else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        }
        return nil
    }

    /// Olduğu gibi eklenecek JSON parçası (ör. dizi).
    public struct Raw {
        public let text: String
        public init(_ text: String) { self.text = text }
    }

    static func value(_ v: Any) -> String {
        switch v {
        case let r as Raw: return r.text
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let i as Int32: return String(i)
        case let d as Double: return String(d)
        case let s as String: return quote(s)
        default: return quote(String(describing: v))
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }
}
