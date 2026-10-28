import XCTest
@testable import ZapretCore

final class SystemProxyTests: XCTestCase {
    let ns = "/usr/sbin/networksetup"

    func testParseServicesSkipsHeaderAndDisabled() {
        let out = "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*Bluetooth PAN\nUSB 10/100/1000 LAN\n"
        XCTAssertEqual(SystemProxy.parseServices(out), ["Wi-Fi", "USB 10/100/1000 LAN"])
    }

    func testParseSocks() {
        XCTAssertEqual(SystemProxy.parseSocks("Enabled: Yes\nServer: 10.0.0.9\nPort: 9050\nAuthenticated Proxy Enabled: 0\n"),
                       SocksState(enabled: true, server: "10.0.0.9", port: 9050))
        XCTAssertEqual(SystemProxy.parseSocks("Enabled: No\nServer: \nPort: 0\n"),
                       SocksState(enabled: false, server: "", port: 0))
    }

    func testEnableCommandsSetsSocksAndSecureWebProxyOnLocalhost() {
        // Güvenli Web Proxy: Discord güncelleyicisi (Rust/reqwest) SOCKS'u görmez, yalnız HTTP(S) proxy'yi kullanır.
        XCTAssertEqual(SystemProxy.enableCommands(service: "Wi-Fi", port: 1080), [
            [ns, "-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "1080"],
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "on"],
            [ns, "-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "1080"],
            [ns, "-setsecurewebproxystate", "Wi-Fi", "on"],
        ])
    }

    func testRestoreKeepsUserProxies() {
        let prev = ProxyBackup(socks: SocksState(enabled: true, server: "10.0.0.9", port: 9050),
                               secureWeb: SocksState(enabled: true, server: "10.0.0.7", port: 3128))
        XCTAssertEqual(SystemProxy.restoreCommands(service: "Wi-Fi", previous: prev), [
            [ns, "-setsocksfirewallproxy", "Wi-Fi", "10.0.0.9", "9050"],
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "on"],
            [ns, "-setsecurewebproxy", "Wi-Fi", "10.0.0.7", "3128"],
            [ns, "-setsecurewebproxystate", "Wi-Fi", "on"],
        ])
    }

    func testRestoreDisabled() {
        let off = SocksState(enabled: false, server: "", port: 0)
        XCTAssertEqual(SystemProxy.restoreCommands(service: "Wi-Fi", previous: ProxyBackup(socks: off, secureWeb: off)), [
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "off"],
            [ns, "-setsecurewebproxystate", "Wi-Fi", "off"],
        ])
    }

    func testRestoreFromLegacyBackupLeavesSecureWebAlone() {
        // Eski yardımcı yalnız SOCKS'u yedeklerdi; Güvenli Web Proxy'ye dokunmamıştı, dokunulmaz.
        let prev = ProxyBackup(socks: SocksState(enabled: false, server: "", port: 0), secureWeb: nil)
        XCTAssertEqual(SystemProxy.restoreCommands(service: "Wi-Fi", previous: prev), [
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "off"],
        ])
    }

    func testBackupDecodesLegacyShapeAndRoundTripsNewShape() throws {
        let legacy = Data(#"{"Wi-Fi":{"enabled":true,"server":"10.0.0.9","port":9050}}"#.utf8)
        let old = try JSONDecoder().decode([String: ProxyBackup].self, from: legacy)
        XCTAssertEqual(old["Wi-Fi"], ProxyBackup(socks: SocksState(enabled: true, server: "10.0.0.9", port: 9050), secureWeb: nil))
        let b = ["Wi-Fi": ProxyBackup(socks: SocksState(enabled: false, server: "", port: 0),
                                      secureWeb: SocksState(enabled: true, server: "10.0.0.7", port: 3128))]
        let back = try JSONDecoder().decode([String: ProxyBackup].self, from: try JSONEncoder().encode(b))
        XCTAssertEqual(back, b)
    }

    func testParseProxyIsSharedByAllKinds() {
        XCTAssertEqual(SystemProxy.parseProxy("Enabled: Yes\nServer: 10.0.0.7\nPort: 3128\n"),
                       SocksState(enabled: true, server: "10.0.0.7", port: 3128))
    }
}
