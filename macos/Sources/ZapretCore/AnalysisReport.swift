import Foundation

/// Analizde sınanan adlar ve hangi istemci profilleriyle sınandıkları.
public struct AnalysisPlan {
    public static let hosts = ["discord.com", "updates.discord.com", "cdn.discordapp.com", "gateway.discord.gg", "www.roblox.com"]
    public let screen: [ProbeTarget]
    public let detail: [ProbeTarget]

    /// `resolve`: DoH (ISS DNS'i bu adları bozuyor). Eleme: her profilden bir zor hedef (güncelleyici, Chromium, modern).
    public static func make(resolve: (String) -> [String]) -> AnalysisPlan {
        var detail: [ProbeTarget] = []
        for h in hosts {
            guard let ip = resolve(h).first else { continue }
            for p in TlsClientHello.Profile.allCases { detail.append(ProbeTarget(host: h, ip: ip, profile: p)) }
        }
        let want: [(String, TlsClientHello.Profile)] = [("updates.discord.com", .appleLegacy), ("discord.com", .chromium), ("www.roblox.com", .modern)]
        let screen = want.compactMap { w in detail.first { $0.host == w.0 && $0.profile == w.1 } }
        return AnalysisPlan(screen: screen.isEmpty ? Array(detail.prefix(3)) : screen, detail: detail)
    }
}

/// Son analizin kaydı (Application Support/analiz.json) ve arayüz/metin dönüşümleri.
public struct AnalysisReport: Codable, Equatable {
    public let time: String
    public let baselinePassed: Int
    public let baselineTotal: Int
    public let scores: [StrategyScore]

    public init(time: String, baselinePassed: Int, baselineTotal: Int, scores: [StrategyScore]) {
        self.time = time; self.baselinePassed = baselinePassed; self.baselineTotal = baselineTotal; self.scores = scores
    }

    public struct Row: Equatable {
        public let puan: String
        public let ad: String
        public let durum: String
        public let tam: String
        public let calisti: Bool
    }

    static func displayName(_ s: StrategyScore, bundled: [TpwsStrategy]) -> String {
        bundled.first { $0.args == s.args }?.name ?? "Analiz: " + s.args.joined(separator: " ")
    }

    /// Paketteki stratejiler + paketle aynı olmayan, tam puanlı en iyi 5 analiz sonucu.
    public static func strategies(bundled: [TpwsStrategy], scores: [StrategyScore]) -> [TpwsStrategy] {
        let extra = scores.filter { $0.score == 100 && !bundled.map(\.args).contains($0.args) }.prefix(5)
        return bundled + extra.map { TpwsStrategy(name: displayName($0, bundled: bundled), args: $0.args) }
    }

    public static func best(bundled: [TpwsStrategy], scores: [StrategyScore]) -> TpwsStrategy? {
        guard let s = scores.first(where: { $0.score == 100 }) else { return nil }
        return TpwsStrategy(name: displayName(s, bundled: bundled), args: s.args)
    }

    public static func rows(bundled: [TpwsStrategy], scores: [StrategyScore], limit: Int = 8) -> [Row] {
        scores.prefix(limit).enumerated().map { i, s in
            Row(puan: "\(s.score)", ad: (i == 0 && s.score == 100 ? "★ " : "") + displayName(s, bundled: bundled),
                durum: "\(s.passed)/\(s.total) geçti" + (s.passed > 0 ? " · \(s.latencyMs) ms" : ""),
                tam: s.args.joined(separator: " "), calisti: s.score == 100)
        }
    }

    public func text(bundled: [TpwsStrategy]) -> String {
        var t = "RedRiveRR Zapret — strateji analizi (\(time))\n"
        t += "Taban (tpws olmadan): \(baselinePassed)/\(baselineTotal) geçti → "
        t += baselinePassed == baselineTotal && baselineTotal > 0 ? "Engel yok görünüyor\n" : "Engel var\n"
        t += "Profiller: Apple TLS (Discord güncelleyicisi), Chromium (Discord), modern (tarayıcı/curl)\n\n"
        t += "Puan  Geçen  Gecikme  Strateji  (tpws argümanları)\n"
        for s in scores {
            t += "\(s.score)  \(s.passed)/\(s.total)  \(s.latencyMs) ms  \(Self.displayName(s, bundled: bundled))  (\(s.args.joined(separator: " ")))\n"
        }
        return t
    }
}

extension WebState {
    public static func strategyJson(options: [String], selected: String, analysisEnabled: Bool, time: String,
                                    results: [AnalysisReport.Row]) -> String {
        let rows = "[" + results.map {
            Json.object(["puan": $0.puan, "ad": $0.ad, "durum": $0.durum, "tam": $0.tam, "calisti": $0.calisti])
        }.joined(separator: ",") + "]"
        return Json.object(["tip": "strateji", "secenekler": Json.Raw(list(options)), "secili": selected,
                            "motorlar": Json.Raw(list(["tpws (macOS)"])), "motor": "tpws (macOS)",
                            "filtreler": Json.Raw("[]"), "filtre": "", "secimAcik": true, "filtreAcik": false,
                            "analizAcik": analysisEnabled, "zaman": time, "sonuclar": Json.Raw(rows)])
    }
}
