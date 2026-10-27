import Foundation

/// Bir tpws stratejisi: ad (arayüzde görünen) ve tpws'e eklenecek argümanlar.
public struct TpwsStrategy: Equatable {
    public let name: String
    public let args: [String]
    public init(name: String, args: [String]) { self.name = name; self.args = args }
}

public enum Strategies {
    /// strategies-macos.ini: "[tpws]" bölümünde "Ad=--arg1 --arg2"; ';' yorum, boş satır, başka bölümler atlanır.
    public static func parse(_ ini: String) -> [TpwsStrategy] {
        var out: [TpwsStrategy] = []
        var inSection = false
        for raw in ini.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") { inSection = (line.lowercased() == "[tpws]"); continue }
            guard inSection, let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            let args = line[line.index(after: eq)...].split(separator: " ").map(String.init)
            if !name.isEmpty && !args.isEmpty { out.append(TpwsStrategy(name: name, args: args)) }
        }
        return out
    }
}
