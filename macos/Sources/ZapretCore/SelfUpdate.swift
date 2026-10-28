import Foundation
import CryptoKit

/// Kendini güncelleme (Windows ADR-019 ile aynı sözleşme): bu deponun GitHub `releases/latest`'i, Mac paketi
/// `RedRiveRR-Zapret-macOS-v<sürüm>.zip`, aynı release'teki `SHA256SUMS.txt` ile doğrulama, adres denetimi.
public enum SelfUpdate {
    public static let repo = "RedRiveRR/zapret-win-turkey"
    public static let assetPrefix = "RedRiveRR-Zapret-macOS-"

    public struct Release: Equatable {
        public let version: String
        public let assetName: String
        public let assetURL: URL
        public let sumsURL: URL
    }

    /// "5.3.0" > "5.2.3"; başta "v" olabilir; sayı dışı ya da eksik parça → false.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let p = (v.hasPrefix("v") ? String(v.dropFirst()) : v).split(separator: ".").map { Int($0) }
            guard p.count == 3, !p.contains(where: { $0 == nil }) else { return nil }
            return p.compactMap { $0 }
        }
        guard let a = parts(candidate), let b = parts(current) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    /// Release JSON'dan Mac paketi ve özet dosyası; ikisi de yoksa ya da adres bu deponun değilse nil.
    public static func parseRelease(_ data: Data, repo: String = repo) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        func url(_ match: (String) -> Bool) -> (String, URL)? {
            for a in assets {
                guard let name = a["name"] as? String, match(name), let u = a["browser_download_url"] as? String,
                      urlAllowed(u, repo: repo), let url = URL(string: u) else { continue }
                return (name, url)
            }
            return nil
        }
        guard let zip = url({ $0.hasPrefix(assetPrefix) && $0.hasSuffix(".zip") }),
              let sums = url({ $0 == "SHA256SUMS.txt" }) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, assetName: zip.0, assetURL: zip.1, sumsURL: sums.1)
    }

    public static func urlAllowed(_ u: String, repo: String = repo) -> Bool {
        let prefix = "https://github.com/\(repo)/releases/download/"
        guard u.lowercased().hasPrefix(prefix.lowercased()) else { return false }
        let rest = u.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        return rest.count == 2 && rest.allSatisfy { !$0.isEmpty && !$0.contains("?") && !$0.contains("#") && !$0.contains(" ") }
    }

    /// `SHA256SUMS.txt` satırı: "<64 onaltılık>  [*]<dosya>". Küçük harf döner.
    public static func sum(in text: String, for name: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let p = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
            guard p.count == 2, p[0].count == 64, p[0].allSatisfy(\.isHexDigit) else { continue }
            var file = p[1].trimmingCharacters(in: .whitespaces)
            if file.hasPrefix("*") { file.removeFirst() }
            if file == name { return p[0].lowercased() }
        }
        return nil
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
