import XCTest
import Darwin
@testable import ZapretCore

final class UpdateTests: XCTestCase {
    let repo = "RedRiveRR/zapret-win-turkey"
    func release(_ tag: String, assets: [String]) -> Data {
        let a = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/RedRiveRR/zapret-win-turkey/releases/download/\#(tag)/\#($0)"}"# }
        return Data(#"{"tag_name":"\#(tag)","html_url":"https://github.com/RedRiveRR/zapret-win-turkey/releases/tag/\#(tag)","assets":[\#(a.joined(separator: ","))]}"#.utf8)
    }

    func testVersionCompare() {
        XCTAssertTrue(SelfUpdate.isNewer("5.3.0", than: "5.2.3"))
        XCTAssertTrue(SelfUpdate.isNewer("v5.2.10", than: "5.2.9"))
        XCTAssertFalse(SelfUpdate.isNewer("5.2.3", than: "5.2.3"))
        XCTAssertFalse(SelfUpdate.isNewer("5.2", than: "5.2.3"))
        XCTAssertFalse(SelfUpdate.isNewer("bozuk", than: "5.2.3"))
    }

    func testFindsMacAssetAndSums() {
        let r = SelfUpdate.parseRelease(release("v5.3.0", assets: ["RedRiveRR-Zapret-v5.3.0.zip", "RedRiveRR-Zapret-macOS-v5.3.0.zip", "SHA256SUMS.txt"]), repo: repo)
        XCTAssertEqual(r?.version, "5.3.0")
        XCTAssertEqual(r?.assetName, "RedRiveRR-Zapret-macOS-v5.3.0.zip")
        XCTAssertEqual(r?.assetURL.absoluteString, "https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.3.0/RedRiveRR-Zapret-macOS-v5.3.0.zip")
        XCTAssertEqual(r?.sumsURL.lastPathComponent, "SHA256SUMS.txt")
    }

    func testReleaseWithoutMacBuildIsIgnored() {
        XCTAssertNil(SelfUpdate.parseRelease(release("v5.2.3", assets: ["RedRiveRR-Zapret-v5.2.3.zip", "SHA256SUMS.txt"]), repo: repo))
        XCTAssertNil(SelfUpdate.parseRelease(release("v5.3.0", assets: ["RedRiveRR-Zapret-macOS-v5.3.0.zip"]), repo: repo)) // özet dosyası şart
    }

    func testForeignDownloadURLRejected() {
        let bad = Data(#"{"tag_name":"v9.0.0","assets":[{"name":"RedRiveRR-Zapret-macOS-v9.0.0.zip","browser_download_url":"https://evil.example/RedRiveRR-Zapret-macOS-v9.0.0.zip"},{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v9.0.0/SHA256SUMS.txt"}]}"#.utf8)
        XCTAssertNil(SelfUpdate.parseRelease(bad, repo: repo))
        XCTAssertFalse(SelfUpdate.urlAllowed("https://github.com/baska/depo/releases/download/v1/x.zip", repo: repo))
        XCTAssertFalse(SelfUpdate.urlAllowed("https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v1/a/b.zip", repo: repo))
    }

    func testSums() {
        let text = "\(String(repeating: "a", count: 64))  RedRiveRR-Zapret-v5.3.0.zip\r\n\(String(repeating: "B", count: 64)) *RedRiveRR-Zapret-macOS-v5.3.0.zip\n"
        XCTAssertEqual(SelfUpdate.sum(in: text, for: "RedRiveRR-Zapret-macOS-v5.3.0.zip"), String(repeating: "b", count: 64))
        XCTAssertNil(SelfUpdate.sum(in: text, for: "yok.zip"))
        XCTAssertEqual(SelfUpdate.sha256Hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class ShareTests: XCTestCase {
    func testPrivateAddresses() {
        for ip in ["10.0.0.5", "172.16.3.4", "172.31.255.1", "192.168.1.50", "169.254.10.1", "127.0.0.1"] { XCTAssertTrue(LanShare.isLocal(ip), ip) }
        for ip in ["8.8.8.8", "172.32.0.1", "192.169.1.1", "100.64.0.1", "bozuk", ""] { XCTAssertFalse(LanShare.isLocal(ip), ip) }
    }

    func testPicksWiredOrWifiPrivateAddress() {
        XCTAssertEqual(LanShare.pickAddress([("lo0", "127.0.0.1"), ("utun3", "10.8.0.2"), ("en0", "192.168.1.50")]), "192.168.1.50")
        XCTAssertEqual(LanShare.pickAddress([("en1", "192.168.0.9"), ("en0", "169.254.3.3")]), "192.168.0.9")
        XCTAssertNil(LanShare.pickAddress([("lo0", "127.0.0.1"), ("utun0", "10.8.0.2")]))
    }

    func testClientsAreActiveForAMinute() {
        var c = LanClients()
        let t = Date(timeIntervalSince1970: 1000)
        c.seen("192.168.1.20", at: t)
        c.seen("192.168.1.21", at: t.addingTimeInterval(30))
        c.seen("192.168.1.20", at: t.addingTimeInterval(40))
        XCTAssertEqual(c.activeCount(at: t.addingTimeInterval(80)), 2)
        XCTAssertEqual(c.activeCount(at: t.addingTimeInterval(95)), 1)
        XCTAssertEqual(c.activeCount(at: t.addingTimeInterval(200)), 0)
    }

    func testFrontRejectsClientsTheFilterRefuses() {
        let fp = Int(TpwsMeasure.freePort()!)
        let front = DohSocksFront(port: fp, upstreamPort: Int(TpwsMeasure.freePort()!), resolve: { _ in [] }, allow: { _ in false })
        var seen: [String] = []
        front.onClient = { seen.append($0) }
        XCTAssertNoThrow(try front.start()); defer { front.stop() }
        let c = socket(AF_INET, SOCK_STREAM, 0); defer { close(c) }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = in_port_t(UInt16(fp).bigEndian)
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(c, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var tv = timeval(tv_sec: 2, tv_usec: 0); setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var hello: [UInt8] = [5, 1, 0]; _ = send(c, &hello, 3, 0)
        var b = [UInt8](repeating: 0, count: 2)
        XCTAssertLessThanOrEqual(recv(c, &b, 2, 0), 0) // reddedilen istemci yanıt almadan kapatılır
        XCTAssertTrue(seen.isEmpty)
    }

    func testFrontCanListenOnAllInterfaces() throws {
        let fp = Int(TpwsMeasure.freePort()!)
        let front = DohSocksFront(port: fp, upstreamPort: 1, resolve: { _ in [] }, bindAddress: "0.0.0.0", allow: LanShare.isLocal)
        var seen: [String] = []
        let lock = NSLock()
        front.onClient = { ip in lock.lock(); seen.append(ip); lock.unlock() }
        try front.start(); defer { front.stop() }
        let c = socket(AF_INET, SOCK_STREAM, 0); defer { close(c) }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = in_port_t(UInt16(fp).bigEndian)
        let rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(c, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(rc, 0)
        var hello: [UInt8] = [5, 1, 0]; _ = send(c, &hello, 3, 0)
        var b = [UInt8](repeating: 0, count: 2); _ = recv(c, &b, 2, 0)
        XCTAssertEqual(b, [5, 0])
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(seen, ["127.0.0.1"])
    }
}
