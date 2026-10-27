import XCTest
@testable import ZapretCore

final class StrategiesTests: XCTestCase {
    func testParseStrategies() {
        let ini = "; açıklama\n[tpws]\nA=--split-pos=1,midsld --disorder=tls\n\nB=--split-pos=midsld\n"
        let s = Strategies.parse(ini)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].name, "A")
        XCTAssertEqual(s[0].args, ["--split-pos=1,midsld", "--disorder=tls"])
        XCTAssertEqual(s[1].args, ["--split-pos=midsld"])
    }

    func testParseHandlesCRLFAndSpaces() {
        let s = Strategies.parse("[tpws]\r\nOrta alan adında bölme = --split-pos=midsld \r\n")
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].name, "Orta alan adında bölme")
        XCTAssertEqual(s[0].args, ["--split-pos=midsld"])
    }
}
