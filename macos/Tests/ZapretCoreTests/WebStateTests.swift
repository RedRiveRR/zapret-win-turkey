import XCTest
@testable import ZapretCore

final class WebStateTests: XCTestCase {
    private func field(_ json: String, _ key: String) -> String? { Json.get(json, key) }

    func testManualStatusTexts() {
        let j = WebState.statusJson(status: .manual, running: true, buttonEnabled: true,
                                    strategy: "Orta alan adında bölme", detail: "tpws (macOS)", error: nil)
        XCTAssertEqual(field(j, "tip"), "durum")
        XCTAssertEqual(field(j, "durum"), "aktif")
        XCTAssertEqual(field(j, "rozet"), "Zapret çalışıyor")
        XCTAssertEqual(field(j, "baslik"), "Discord'a yol açık")
        XCTAssertEqual(field(j, "aciklama"), "Discord'u şimdi açın; zaten açıksa yeniden başlatın.")
        XCTAssertEqual(field(j, "calisiyor"), "true")
        XCTAssertEqual(field(j, "strateji"), "Orta alan adında bölme")
        XCTAssertEqual(field(j, "stratejiDetay"), "tpws (macOS)")
        XCTAssertFalse(j.contains("Servis")) // Mac'te servis yok
    }

    func testReady() {
        let j = WebState.statusJson(status: .ready, running: false, buttonEnabled: true, strategy: "", detail: "", error: nil)
        XCTAssertEqual(field(j, "durum"), "hazir")
        XCTAssertEqual(field(j, "rozet"), "Çalışmaya hazır")
        XCTAssertEqual(field(j, "baslik"), "Zapret kapalı")
        XCTAssertEqual(field(j, "aciklama"), "Başlatmak için düğmeye basın.")
        XCTAssertEqual(field(j, "calisiyor"), "false")
    }

    func testErrorShowsMessage() {
        let j = WebState.statusJson(status: .error, running: false, buttonEnabled: true, strategy: "", detail: "",
                                    error: "Port 1080 kullanımda")
        XCTAssertEqual(field(j, "durum"), "hata")
        XCTAssertEqual(field(j, "aciklama"), "Port 1080 kullanımda")
    }

    func testStrategyJson() {
        let j = WebState.strategyJson(options: ["A", "B"], selected: "B")
        XCTAssertEqual(field(j, "tip"), "strateji")
        XCTAssertEqual(field(j, "secili"), "B")
        XCTAssertTrue(j.contains(#""secenekler":["A","B"]"#))
        XCTAssertTrue(j.contains(#""motorlar":["tpws (macOS)"]"#))
        XCTAssertEqual(field(j, "analizAcik"), "false")
    }
}
