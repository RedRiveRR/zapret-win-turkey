import XCTest
@testable import ZapretCore

final class StrategyNamesTests: XCTestCase {
    func testHumanLabels() {
        XCTAssertEqual(StrategyNames.label(["--tlsrec=midsld"]), "TLS kaydı · alan adı ortası")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=midsld+4"]), "TLS kaydı · alan adı ortası +4")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=endsld-1"]), "TLS kaydı · alan adı sonu −1")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=sniext+1"]), "TLS kaydı · SNI +1")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=2"]), "TLS kaydı · 2. bayt")
        XCTAssertEqual(StrategyNames.label(["--hostcase", "--tlsrec=midsld"]), "TLS kaydı · alan adı ortası + harf karıştırma")
        XCTAssertEqual(StrategyNames.label(["--oob=tls", "--split-pos=1"]), "Bölme · 1. bayt + OOB")
        XCTAssertEqual(StrategyNames.label(["--split-pos=1,midsld", "--disorder=tls"]), "Bölme · 1. bayt, alan adı ortası + sıra bozma")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=host+1", "--split-pos=sniext+2"]), "TLS kaydı · ad başı +1 + bölme · SNI +2")
        XCTAssertEqual(StrategyNames.label(["--oob=tls", "--oob-data=0x16", "--split-pos=1"]), "Bölme · 1. bayt + OOB (0x16)")
        XCTAssertEqual(StrategyNames.label(["--tlsrec=sld+1", "--tamper-cutoff=n2"]), "TLS kaydı · ana alan adı +1 + yalnız ilk paket")
    }

    func testLabelsNeverContainDoubleHyphenAndUnknownFallsBack() {
        for c in StrategyCandidates.generate() { XCTAssertFalse(StrategyNames.label(c.args).contains("--"), c.name) }
        XCTAssertEqual(StrategyNames.label(["--bilinmeyen=3"]), "bilinmeyen=3")
    }

    func testGeneratedCandidatesUseHumanNamesAndAreUnique() {
        let c = StrategyCandidates.generate()
        XCTAssertEqual(Set(c.map(\.name)).count, c.count)
        XCTAssertTrue(c.contains { $0.name == "TLS kaydı · alan adı ortası" })
    }

    func testResolveKeepsSelectionAcrossRenames() {
        let list = [TpwsStrategy(name: "TLS kaydı · alan adı ortası", args: ["--tlsrec=midsld"]),
                    TpwsStrategy(name: "TLS kaydı · ad başı +1", args: ["--tlsrec=host+1"])]
        XCTAssertEqual(Strategies.resolve(savedName: "TLS kaydı · ad başı +1", savedArgs: "", in: list)?.args, ["--tlsrec=host+1"])
        XCTAssertEqual(Strategies.resolve(savedName: "eski ad", savedArgs: "--tlsrec=host+1", in: list)?.args, ["--tlsrec=host+1"])
        XCTAssertEqual(Strategies.resolve(savedName: "Analiz: --tlsrec=host+1", savedArgs: "", in: list)?.args, ["--tlsrec=host+1"]) // eski sürüm adı
        XCTAssertNil(Strategies.resolve(savedName: "yok", savedArgs: "--x", in: list))
    }

    func testBundledListOnlyKeepsFieldProvenStrategies() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/strategies-macos.ini")
        let s = Strategies.parse(try String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(s.contains { $0.args == ["--tlsrec=sniext+1"] }) // Discord güncelleyicisinde RST
        XCTAssertFalse(s.contains { $0.args.contains("--disorder=tls") })
        XCTAssertTrue((2...5).contains(s.count))
    }
}
