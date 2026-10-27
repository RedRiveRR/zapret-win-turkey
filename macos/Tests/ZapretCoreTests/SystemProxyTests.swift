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

    func testEnableCommandsAlwaysLocalhost() {
        XCTAssertEqual(SystemProxy.enableCommands(service: "Wi-Fi", port: 1080), [
            [ns, "-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "1080"],
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "on"],
        ])
    }

    func testRestoreKeepsUserProxy() {
        XCTAssertEqual(SystemProxy.restoreCommands(service: "Wi-Fi", previous: SocksState(enabled: true, server: "10.0.0.9", port: 9050)), [
            [ns, "-setsocksfirewallproxy", "Wi-Fi", "10.0.0.9", "9050"],
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "on"],
        ])
    }

    func testRestoreDisabled() {
        XCTAssertEqual(SystemProxy.restoreCommands(service: "Wi-Fi", previous: SocksState(enabled: false, server: "", port: 0)), [
            [ns, "-setsocksfirewallproxystate", "Wi-Fi", "off"],
        ])
    }
}
