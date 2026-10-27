import Foundation

/// Arayüzle aynı JSON mesaj sözleşmesi (Windows: lib/WebMsg.au3).
public enum Json {
    /// Sırayı koruyarak tek düzey nesne üretir: String (kaçışlı), Bool (true/false), sayılar.
    public static func object(_ pairs: KeyValuePairs<String, Any>) -> String {
        return ""
    }

    /// Nesnedeki bir alanın metin değeri; yoksa ya da JSON bozuksa nil.
    public static func get(_ json: String, _ key: String) -> String? {
        return nil
    }
}
