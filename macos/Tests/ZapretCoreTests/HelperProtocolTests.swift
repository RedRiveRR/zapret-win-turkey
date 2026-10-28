import XCTest
@testable import ZapretCore

final class HelperProtocolTests: XCTestCase {
    func testDecodeProxyOn() {
        XCTAssertEqual(try HelperProtocol.decode(#"{"cmd":"proxyOn","port":1080,"pid":123}"#).get(),
                       .proxyOn(port: 1080, ownerPid: 123))
        XCTAssertEqual(try HelperProtocol.decode(#"{"cmd":"proxyOff"}"#).get(), .proxyOff)
        XCTAssertEqual(try HelperProtocol.decode(#"{"cmd":"status"}"#).get(), .status)
    }

    func testEncodeRoundTrip() {
        for c in [HelperCommand.proxyOn(port: 1080, ownerPid: 42), .proxyOff, .status] {
            XCTAssertEqual(try HelperProtocol.decode(HelperProtocol.encode(c)).get(), c)
        }
    }

    func testRejectsUnknownCommand() {
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"rm","path":"/"}"#), .failure(.unknownCommand("rm")))
        XCTAssertEqual(HelperProtocol.decode("bozuk"), .failure(.badJson))
    }

    func testRejectsBadPort() {
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"proxyOn","port":80,"pid":1}"#), .failure(.badPort))
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"proxyOn","port":70000,"pid":1}"#), .failure(.badPort))
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"proxyOn","port":"1080","pid":1}"#), .failure(.badPort))
    }

    func testRejectsMissingPid() {
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"proxyOn","port":1080}"#), .failure(.missingPid))
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"proxyOn","port":1080,"pid":0}"#), .failure(.missingPid))
    }

    func testReply() {
        let r = HelperProtocol.encodeReply(ok: true, message: "tamam")
        XCTAssertEqual(Json.get(r, "ok"), "true")
        XCTAssertEqual(Json.get(r, "mesaj"), "tamam")
    }

    func testStatusMessageCarriesHelperVersion() {
        XCTAssertEqual(HelperProtocol.statusMessage(on: true), "acik v\(HelperProtocol.version)")
        XCTAssertEqual(HelperProtocol.statusMessage(on: false), "kapali v\(HelperProtocol.version)")
        XCTAssertEqual(HelperProtocol.parseVersion(HelperProtocol.statusMessage(on: false)), HelperProtocol.version)
        XCTAssertEqual(HelperProtocol.parseVersion("acik v12"), 12)
    }

    func testOldHelperHasNoVersion() {
        XCTAssertNil(HelperProtocol.parseVersion("kapali"))
        XCTAssertNil(HelperProtocol.parseVersion("acik"))
        XCTAssertNil(HelperProtocol.parseVersion("kapali vX"))
    }

    func testVersionTwoOrLaterManagesSecureWebProxy() {
        XCTAssertGreaterThanOrEqual(HelperProtocol.version, 2)
    }
}
