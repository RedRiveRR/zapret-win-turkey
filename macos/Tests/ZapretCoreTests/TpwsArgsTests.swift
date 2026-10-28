import XCTest
import Darwin
@testable import ZapretCore

final class TpwsArgsTests: XCTestCase {
    func testBuildArgs() {
        let s = TpwsStrategy(name: "Orta alan adında bölme", args: ["--split-pos=midsld"])
        XCTAssertEqual(TpwsArgs.build(tpwsPath: "/x/tpws", port: 1080, strategy: s, hostlist: nil),
                       ["/x/tpws", "--socks", "--bind-addr=127.0.0.1", "--port=1080", "--no-resolve", "--split-pos=midsld"])
    }

    func testBuildArgsWithHostlist() {
        // Atlatma yalnız listedeki sitelere (Discord/Roblox); diğer siteler değişmeden geçer.
        let s = TpwsStrategy(name: "TLS kaydı bölme", args: ["--tlsrec=sniext", "--split-pos=1"])
        XCTAssertEqual(TpwsArgs.build(tpwsPath: "/x/tpws", port: 1080, strategy: s, hostlist: "/a b/hostlist.txt"),
                       ["/x/tpws", "--socks", "--bind-addr=127.0.0.1", "--port=1080", "--no-resolve", "--hostlist=/a b/hostlist.txt",
                        "--tlsrec=sniext", "--split-pos=1"])
    }

    // macOS 27: tpws'in ad çözme iş parçacığı (32-64 KB yığın) getaddrinfo'da taşıp çöküyordu; adları ön proxy çözer.
    func testBuildArgsDisablesTpwsResolver() {
        let s = TpwsStrategy(name: "x", args: ["--tlsrec=sld+1"])
        XCTAssertTrue(TpwsArgs.build(tpwsPath: "/x/tpws", port: 1081, strategy: s, hostlist: nil).contains("--no-resolve"))
    }

    func testSystemResolverReturnsAddresses() {
        XCTAssertEqual(SystemResolver.resolve("1.2.3.4"), [.ipv4([1, 2, 3, 4])])
        XCTAssertTrue(SystemResolver.resolve("localhost").contains(.ipv4([127, 0, 0, 1])))
        XCTAssertEqual(SystemResolver.resolve("yok.invalid"), [])
    }
}
