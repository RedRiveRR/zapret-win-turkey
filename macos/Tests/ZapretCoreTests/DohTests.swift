import XCTest
@testable import ZapretCore

final class DohTests: XCTestCase {
    func testParseKeepsOnlyARecords() {
        let json = """
        {"Status":0,"Answer":[{"name":"discord.com","type":5,"TTL":60,"data":"x.cdn."},
        {"name":"discord.com","type":1,"TTL":120,"data":"162.159.128.233"},
        {"name":"discord.com","type":28,"TTL":120,"data":"2606:4700::1"},
        {"name":"discord.com","type":1,"TTL":300,"data":"162.159.138.232"}]}
        """
        let a = Doh.parse(Data(json.utf8))
        XCTAssertEqual(a.addresses, ["162.159.128.233", "162.159.138.232"])
        XCTAssertEqual(a.ttl, 120) // en küçük TTL
    }

    func testParseGarbageAndEmpty() {
        XCTAssertEqual(Doh.parse(Data("html".utf8)).addresses, [])
        XCTAssertEqual(Doh.parse(Data(#"{"Status":3}"#.utf8)).addresses, [])
    }

    func testParseRejectsNonPublicAnswers() {
        let json = #"{"Answer":[{"type":1,"TTL":60,"data":"127.0.0.1"},{"type":1,"TTL":60,"data":"0.0.0.0"},{"type":1,"TTL":60,"data":"1.2.3.4"}]}"#
        XCTAssertEqual(Doh.parse(Data(json.utf8)).addresses, ["1.2.3.4"])
    }

    func testHostMatcher() {
        let list = ["discord.com", "roblox.com"]
        XCTAssertTrue(HostMatcher.matches("discord.com", list))
        XCTAssertTrue(HostMatcher.matches("Gateway.Discord.COM", list))
        XCTAssertFalse(HostMatcher.matches("notdiscord.com", list))
        XCTAssertFalse(HostMatcher.matches("discord.com.evil.net", list))
    }

    func testHostlistParse() {
        XCTAssertEqual(HostMatcher.parseList("# yorum\ndiscord.com\n\n  Roblox.com \r\n"), ["discord.com", "roblox.com"])
    }

    func testResolverUsesCacheAndFallsBack() {
        var calls: [String] = []
        let body = Data(#"{"Answer":[{"type":1,"TTL":100,"data":"1.2.3.4"}]}"#.utf8)
        var t = Date(timeIntervalSince1970: 1000)
        let r = DohResolver(endpoints: ["https://bir/q", "https://iki/q"], fetch: { url in
            calls.append(url.host ?? "")
            return url.host == "bir" ? nil : body
        }, now: { t })
        XCTAssertEqual(r.resolve("discord.com"), ["1.2.3.4"])
        XCTAssertEqual(calls, ["bir", "iki"]) // ilk uç başarısız, ikincisi cevapladı
        XCTAssertEqual(r.resolve("discord.com"), ["1.2.3.4"])
        XCTAssertEqual(calls.count, 2) // önbellekten
        t = t.addingTimeInterval(101)
        XCTAssertEqual(r.resolve("discord.com"), ["1.2.3.4"])
        XCTAssertEqual(calls.count, 4) // TTL doldu, yeniden soruldu
    }

    func testResolverFailureIsBrieflyRemembered() {
        var n = 0
        var t = Date(timeIntervalSince1970: 1000)
        let r = DohResolver(endpoints: ["https://x/q"], fetch: { _ in n += 1; return nil }, now: { t })
        XCTAssertEqual(r.resolve("discord.com"), [])
        XCTAssertEqual(r.resolve("discord.com"), [])
        XCTAssertEqual(n, 1) // art arda başarısızlıkta uçlar yeniden yorulmaz
        t = t.addingTimeInterval(10)
        _ = r.resolve("discord.com")
        XCTAssertEqual(n, 2)
    }

    func testQueryURL() {
        let u = Doh.queryURL(endpoint: "https://1.1.1.1/dns-query", host: "discord.com")
        XCTAssertEqual(u?.absoluteString, "https://1.1.1.1/dns-query?name=discord.com&type=A")
        XCTAssertNil(Doh.queryURL(endpoint: "https://1.1.1.1/dns-query", host: "bad host&x=1"))
    }
}
