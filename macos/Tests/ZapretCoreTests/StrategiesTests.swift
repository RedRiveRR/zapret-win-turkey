import XCTest
@testable import ZapretCore

final class StrategiesTests: XCTestCase {
    func testParseStrategies() {
        let ini = "; açıklama\n[tpws]\nA=--split-pos=1,midsld --disorder=tls\n\nB=--split-pos=midsld\n"
        let s = Strategies.parse(ini)
        guard s.count == 2 else { return XCTFail("2 strateji bekleniyordu, \(s.count) geldi") }
        XCTAssertEqual(s[0].name, "A")
        XCTAssertEqual(s[0].args, ["--split-pos=1,midsld", "--disorder=tls"])
        XCTAssertEqual(s[1].args, ["--split-pos=midsld"])
    }

    func testParseHandlesCRLFAndSpaces() {
        let s = Strategies.parse("[tpws]\r\nOrta alan adında bölme = --split-pos=midsld \r\n")
        guard s.count == 1 else { return XCTFail("1 strateji bekleniyordu, \(s.count) geldi") }
        XCTAssertEqual(s[0].name, "Orta alan adında bölme")
        XCTAssertEqual(s[0].args, ["--split-pos=midsld"])
    }

    func testOtherSectionsIgnored() {
        XCTAssertEqual(Strategies.parse("[baska]\nX=--y\n[tpws]\nA=--split-pos=1\n").map(\.name), ["A"])
    }
}
