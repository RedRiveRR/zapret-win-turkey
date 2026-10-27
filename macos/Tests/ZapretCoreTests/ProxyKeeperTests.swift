import XCTest
@testable import ZapretCore

final class ProxyKeeperTests: XCTestCase {
    func testProxyRestoredWhenOwnerDies() {
        XCTAssertTrue(ProxyKeeperLogic.shouldRestore(proxyOn: true, ownerAlive: false, engineFailures: 0))
        XCTAssertFalse(ProxyKeeperLogic.shouldRestore(proxyOn: true, ownerAlive: true, engineFailures: 0))
        XCTAssertFalse(ProxyKeeperLogic.shouldRestore(proxyOn: false, ownerAlive: false, engineFailures: 0))
    }

    func testProxyRestoredWhenEngineStops() {
        XCTAssertEqual(ProxyKeeperLogic.engineFailureLimit, 3)
        XCTAssertTrue(ProxyKeeperLogic.shouldRestore(proxyOn: true, ownerAlive: true, engineFailures: 3))
        XCTAssertFalse(ProxyKeeperLogic.shouldRestore(proxyOn: true, ownerAlive: true, engineFailures: 2))
    }

    func testPathsAreRootOwnedLocations() {
        XCTAssertTrue(HelperPaths.binary.hasPrefix("/Library/PrivilegedHelperTools/"))
        XCTAssertTrue(HelperPaths.plist.hasPrefix("/Library/LaunchDaemons/"))
        XCTAssertEqual(HelperPaths.socket, "/var/run/com.redriverr.zapret.helper.sock")
    }
}
