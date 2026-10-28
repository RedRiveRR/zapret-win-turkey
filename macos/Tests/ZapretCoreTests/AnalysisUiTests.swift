import XCTest
@testable import ZapretCore

final class AnalysisUiTests: XCTestCase {
    let bundled = [TpwsStrategy(name: "TLS kaydı orta alan adı", args: ["--tlsrec=midsld"]),
                   TpwsStrategy(name: "TLS kaydı SNI sonrası", args: ["--tlsrec=sniext+1"])]
    let scores = [StrategyScore(name: "--tlsrec=midsld", args: ["--tlsrec=midsld"], passed: 30, total: 30, latencyMs: 38),
                  StrategyScore(name: "--tlsrec=host", args: ["--tlsrec=host"], passed: 30, total: 30, latencyMs: 40),
                  StrategyScore(name: "--tlsrec=sniext+1", args: ["--tlsrec=sniext+1"], passed: 3, total: 4, latencyMs: 41),
                  StrategyScore(name: "--split-pos=1", args: ["--split-pos=1"], passed: 0, total: 4, latencyMs: 0)]

    func testBundledArgsKeepTheirNameAndNewWinnersAreAdded() {
        let list = AnalysisReport.strategies(bundled: bundled, scores: scores)
        XCTAssertEqual(list.map(\.name), ["TLS kaydı orta alan adı", "TLS kaydı SNI sonrası", "TLS kaydı · ad başı"])
    }

    func testEverySelectableRowIsInTheStrategyList() {
        let many = (0..<12).map { StrategyScore(name: "--tlsrec=\($0)", args: ["--tlsrec=\($0)"], passed: 4, total: 4, latencyMs: 40 + $0) }
        let names = Set(AnalysisReport.strategies(bundled: bundled, scores: many).map(\.name))
        for r in AnalysisReport.rows(bundled: bundled, scores: many) where !r.secim.isEmpty {
            XCTAssertTrue(names.contains(r.secim), r.secim)
        }
    }

    func testBestUsesBundledNameWhenSameArgs() {
        XCTAssertEqual(AnalysisReport.best(bundled: bundled, scores: scores)?.name, "TLS kaydı orta alan adı")
        XCTAssertNil(AnalysisReport.best(bundled: bundled, scores: [scores[3]]))
    }

    func testRows() {
        let rows = AnalysisReport.rows(bundled: bundled, scores: scores, limit: 3, selected: "TLS kaydı · ad başı")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].puan, "100")
        XCTAssertEqual(rows[0].ad, "★ TLS kaydı orta alan adı")
        XCTAssertEqual(rows[0].durum, "30/30 geçti · 38 ms")
        XCTAssertEqual(rows[0].tam, "--tlsrec=midsld")
        XCTAssertTrue(rows[0].calisti)
        XCTAssertEqual(rows[2].ad, "TLS kaydı SNI sonrası")
        XCTAssertFalse(rows[2].calisti)
        // tam puanlılar seçilebilir (strateji listesindeki adla), eksikler seçilemez; seçili olan işaretli
        XCTAssertEqual(rows.map(\.secim), ["TLS kaydı orta alan adı", "TLS kaydı · ad başı", ""])
        XCTAssertEqual(rows.map(\.secili), [false, true, false])
    }

    func testStrategyJsonCarriesAnalysisState() {
        let rows = AnalysisReport.rows(bundled: bundled, scores: scores, limit: 2)
        let j = WebState.strategyJson(options: ["A"], selected: "A", analysisEnabled: true, time: "28.10 17:30", results: rows)
        XCTAssertEqual(Json.get(j, "analizAcik"), "true")
        XCTAssertEqual(Json.get(j, "zaman"), "28.10 17:30")
        XCTAssertTrue(j.contains(#""puan":"100""#))
        XCTAssertTrue(j.contains(#""calisti":true"#))
        XCTAssertTrue(j.contains(#""secim":"TLS kaydı orta alan adı""#))
        XCTAssertTrue(j.contains(#""secili":false"#))
        // eski çağrı biçimi bozulmaz
        XCTAssertEqual(Json.get(WebState.strategyJson(options: ["A"], selected: "A"), "analizAcik"), "false")
    }

    func testSavedReportRoundTripsAndTextSummary() throws {
        let r = AnalysisReport(time: "28.10 17:30", baselinePassed: 0, baselineTotal: 15, scores: scores)
        XCTAssertEqual(try JSONDecoder().decode(AnalysisReport.self, from: JSONEncoder().encode(r)), r)
        let text = r.text(bundled: bundled)
        XCTAssertTrue(text.contains("Engel var"))
        XCTAssertTrue(text.contains("100  30/30  38 ms  TLS kaydı orta alan adı  (--tlsrec=midsld)"))
    }

    func testPlanTargetsCoverEveryProfileAndScreenIsSmall() {
        let ips = ["discord.com": "1.1.1.1", "updates.discord.com": "1.1.1.2", "www.roblox.com": "2.2.2.2"]
        let plan = AnalysisPlan.make(resolve: { ips[$0].map { [$0] } ?? [] })
        XCTAssertEqual(Set(plan.detail.map(\.host)), Set(ips.keys))
        XCTAssertEqual(plan.detail.count, ips.count * TlsClientHello.Profile.allCases.count)
        XCTAssertTrue(plan.screen.contains(ProbeTarget(host: "updates.discord.com", ip: "1.1.1.2", profile: .appleLegacy)))
        XCTAssertTrue(plan.screen.contains(ProbeTarget(host: "discord.com", ip: "1.1.1.1", profile: .chromium)))
        XCTAssertLessThanOrEqual(plan.screen.count, 4)
        XCTAssertTrue(AnalysisPlan.make(resolve: { _ in [] }).detail.isEmpty)
    }
}
