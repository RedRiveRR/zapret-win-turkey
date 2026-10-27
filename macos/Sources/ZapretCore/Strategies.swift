import Foundation

/// Bir tpws stratejisi: ad (arayüzde görünen) ve tpws'e eklenecek argümanlar.
public struct TpwsStrategy: Equatable {
    public let name: String
    public let args: [String]
    public init(name: String, args: [String]) { self.name = name; self.args = args }
}

public enum Strategies {
    /// strategies-macos.ini: "[tpws]" bölümünde "Ad=--arg1 --arg2"; ';' yorum, boş satır atlanır.
    public static func parse(_ ini: String) -> [TpwsStrategy] {
        return []
    }
}
