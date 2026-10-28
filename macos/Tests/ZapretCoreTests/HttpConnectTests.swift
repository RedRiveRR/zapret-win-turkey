import XCTest
@testable import ZapretCore

final class HttpConnectTests: XCTestCase {
    func testParseConnectDomain() {
        let head = "CONNECT updates.discord.com:443 HTTP/1.1\r\nHost: updates.discord.com:443\r\nProxy-Connection: Keep-Alive\r\n\r\n"
        XCTAssertEqual(HttpConnect.parse(head: head), .connect(Socks5.Target.domain("updates.discord.com"), 443))
    }

    func testParseConnectIPv4Literal() {
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT 162.159.138.232:8443 HTTP/1.0\r\n\r\n"),
                       .connect(Socks5.Target.ipv4([162, 159, 138, 232]), 8443))
    }

    func testOtherMethodsAreNotConnect() {
        XCTAssertEqual(HttpConnect.parse(head: "GET http://example.org/ HTTP/1.1\r\nHost: example.org\r\n\r\n"), .notConnect)
        XCTAssertEqual(HttpConnect.parse(head: "connect a.b:443 HTTP/1.1\r\n\r\n"), .notConnect) // yöntem büyük/küçük harfe duyarlı
    }

    func testBadRequests() {
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT nohost HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT a.b:0 HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT a.b:70000 HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT [::1]:443 HTTP/1.1\r\n\r\n"), .bad) // IPv6 sabit adres desteklenmez
        XCTAssertEqual(HttpConnect.parse(head: "CONNECT :443 HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: ""), .bad)
    }

    func testReplies() {
        XCTAssertEqual(String(decoding: HttpConnect.established, as: UTF8.self), "HTTP/1.1 200 Connection Established\r\n\r\n")
        XCTAssertTrue(String(decoding: HttpConnect.failure(502), as: UTF8.self).hasPrefix("HTTP/1.1 502 "))
        XCTAssertTrue(String(decoding: HttpConnect.failure(405), as: UTF8.self).hasPrefix("HTTP/1.1 405 "))
        XCTAssertTrue(String(decoding: HttpConnect.failure(400), as: UTF8.self).hasSuffix("\r\n\r\n"))
    }
}
