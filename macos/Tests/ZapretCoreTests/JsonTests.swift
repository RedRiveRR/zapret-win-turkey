import XCTest
@testable import ZapretCore

final class JsonTests: XCTestCase {
    func testObjectKeepsOrderAndTypes() {
        XCTAssertEqual(Json.object(["tip": "durum", "calisiyor": true, "n": 3]),
                       #"{"tip":"durum","calisiyor":true,"n":3}"#)
    }

    func testEscapes() {
        XCTAssertEqual(Json.object(["s": "a\"b\\c\n"]), #"{"s":"a\"b\\c\n"}"#)
    }

    func testGet() {
        XCTAssertEqual(Json.get(#"{"tip":"komut","ad":"baslat"}"#, "ad"), "baslat")
        XCTAssertNil(Json.get(#"{"tip":"komut"}"#, "ad"))
        XCTAssertNil(Json.get("bozuk", "ad"))
    }
}
