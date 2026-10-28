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
        XCTAssertEqual(HttpConnect.parse(head: "GET /yerel HTTP/1.1\r\nHost: example.org\r\n\r\n"), .notConnect) // proxy isteği değil
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

    // PS5 ağ paylaşımı: bağlantı testi ve bazı servisler düz HTTP proxy isteği (mutlak adres) gönderir (saha 2026-10-28: 405 → "internet yok").
    func testPlainHttpProxyRequestIsForwardedInOriginForm() {
        let head = "GET http://ps5.example.net/netstart/ps5?x=1 HTTP/1.1\r\nHost: ps5.example.net\r\nProxy-Connection: keep-alive\r\nUser-Agent: PS5\r\n\r\n"
        guard case .forward(let target, let port, let out) = HttpConnect.parse(head: head) else { return XCTFail("\(HttpConnect.parse(head: head))") }
        XCTAssertEqual(target, .domain("ps5.example.net"))
        XCTAssertEqual(port, 80)
        XCTAssertEqual(String(decoding: out, as: UTF8.self),
                       "GET /netstart/ps5?x=1 HTTP/1.1\r\nHost: ps5.example.net\r\nUser-Agent: PS5\r\nConnection: close\r\n\r\n")
    }

    func testForwardWithPortIPv4AndNoPath() {
        guard case .forward(let t, let p, let out) = HttpConnect.parse(head: "POST http://10.0.0.9:8081 HTTP/1.0\r\nConnection: keep-alive\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(t, .ipv4([10, 0, 0, 9]))
        XCTAssertEqual(p, 8081)
        XCTAssertEqual(String(decoding: out, as: UTF8.self), "POST / HTTP/1.0\r\nConnection: close\r\n\r\n")
    }

    func testForwardRejectsHttpsAbsoluteAndBadHosts() {
        XCTAssertEqual(HttpConnect.parse(head: "GET https://a.b/ HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: "GET http://a b/ HTTP/1.1\r\n\r\n"), .bad)
        XCTAssertEqual(HttpConnect.parse(head: "GET http://:80/ HTTP/1.1\r\n\r\n"), .bad)
    }
}
