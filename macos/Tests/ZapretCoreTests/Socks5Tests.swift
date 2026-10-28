import XCTest
@testable import ZapretCore

final class Socks5Tests: XCTestCase {
    func testParseDomainRequest() {
        let host = Array("discord.com".utf8)
        let bytes: [UInt8] = [5, 1, 0, 3, UInt8(host.count)] + host + [0x01, 0xBB]
        let r = Socks5.parseRequest(bytes)
        XCTAssertEqual(r?.command, 1)
        XCTAssertEqual(r?.target, .domain("discord.com"))
        XCTAssertEqual(r?.port, 443)
    }

    func testParseIPv4Request() {
        let r = Socks5.parseRequest([5, 1, 0, 1, 162, 159, 138, 232, 0x01, 0xBB])
        XCTAssertEqual(r?.target, .ipv4([162, 159, 138, 232]))
        XCTAssertEqual(r?.port, 443)
    }

    func testParseIPv6Request() {
        let addr = [UInt8](repeating: 0x20, count: 16)
        let r = Socks5.parseRequest([5, 1, 0, 4] + addr + [0, 80])
        XCTAssertEqual(r?.target, .ipv6(addr))
        XCTAssertEqual(r?.port, 80)
    }

    func testParseRejectsWrongVersionAndTruncated() {
        XCTAssertNil(Socks5.parseRequest([4, 1, 0, 1, 1, 2, 3, 4, 0, 80]))
        XCTAssertNil(Socks5.parseRequest([5, 1, 0, 1, 1, 2, 3]))
        XCTAssertNil(Socks5.parseRequest([5, 1, 0, 3, 20, 65, 66, 0, 80])) // uzunluk gerçek veriden büyük
        XCTAssertNil(Socks5.parseRequest([5, 1, 0, 9, 1, 2, 3, 4, 0, 80])) // bilinmeyen adres türü
    }

    func testEncodeConnectRoundTrips() {
        let bytes = Socks5.encodeConnect(target: .ipv4([93, 184, 216, 34]), port: 8080)
        XCTAssertEqual(bytes, [5, 1, 0, 1, 93, 184, 216, 34, 0x1F, 0x90])
        XCTAssertEqual(Socks5.parseRequest(bytes)?.target, .ipv4([93, 184, 216, 34]))
        let d = Socks5.encodeConnect(target: .domain("a.b"), port: 443)
        XCTAssertEqual(Socks5.parseRequest(d)?.target, .domain("a.b"))
    }

    func testAddressLengthAfterHeader() {
        XCTAssertEqual(Socks5.addressBytes(atyp: 1, firstByte: 0), 4 + 2)
        XCTAssertEqual(Socks5.addressBytes(atyp: 4, firstByte: 0), 16 + 2)
        XCTAssertEqual(Socks5.addressBytes(atyp: 3, firstByte: 11), 1 + 11 + 2 - 1) // uzunluk baytı zaten okundu sayılmaz
        XCTAssertNil(Socks5.addressBytes(atyp: 7, firstByte: 0))
    }

    func testIPv4Text() {
        XCTAssertEqual(Socks5.ipv4Bytes("162.159.138.232"), [162, 159, 138, 232])
        XCTAssertNil(Socks5.ipv4Bytes("300.1.1.1"))
        XCTAssertNil(Socks5.ipv4Bytes("discord.com"))
    }
}
