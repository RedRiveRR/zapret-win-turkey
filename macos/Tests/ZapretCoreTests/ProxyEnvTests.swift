import XCTest
@testable import ZapretCore

final class ProxyEnvTests: XCTestCase {
    func testSetCommandsPointHttpsProxyVariablesAtLocalFront() {
        XCTAssertEqual(ProxyEnv.setCommands(port: 1080), [
            ["/bin/launchctl", "setenv", "HTTPS_PROXY", "http://127.0.0.1:1080"],
            ["/bin/launchctl", "setenv", "https_proxy", "http://127.0.0.1:1080"],
        ])
    }

    func testUnsetCommandsRemoveBoth() {
        XCTAssertEqual(ProxyEnv.unsetCommands(), [
            ["/bin/launchctl", "unsetenv", "HTTPS_PROXY"],
            ["/bin/launchctl", "unsetenv", "https_proxy"],
        ])
    }

    func testOnlyOurOwnValueIsTreatedAsStale() {
        // Kullanıcının kendi proxy değişkeni varsa dokunulmaz; yalnız bizim bıraktığımız değer temizlenir.
        XCTAssertTrue(ProxyEnv.isOurs("http://127.0.0.1:1080", port: 1080))
        XCTAssertFalse(ProxyEnv.isOurs("http://10.0.0.7:3128", port: 1080))
        XCTAssertFalse(ProxyEnv.isOurs("", port: 1080))
    }
}
