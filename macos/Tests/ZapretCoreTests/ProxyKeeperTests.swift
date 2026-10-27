import XCTest
import Darwin
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

    func testStartFailsWhenPortBusy() throws {
        // Geçici bir yerel kapı tutulur; TpwsArgs.isPortFree onu dolu görmeli.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && listen(fd, 1) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        XCTAssertTrue(bound)
        let port = Int(UInt16(bigEndian: addr.sin_port))
        XCTAssertFalse(TpwsArgs.isPortFree(port))
        close(fd)
        XCTAssertTrue(TpwsArgs.isPortFree(port))
    }
}
