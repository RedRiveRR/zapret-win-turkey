import XCTest
@testable import ZapretCore

final class GatewayTests: XCTestCase {
    func testHelperGatewayCommandsRoundTrip() {
        XCTAssertEqual(try HelperProtocol.decode(#"{"cmd":"gatewayOn","pid":42}"#).get(), .gatewayOn(ownerPid: 42))
        XCTAssertEqual(try HelperProtocol.decode(#"{"cmd":"gatewayOff"}"#).get(), .gatewayOff)
        XCTAssertEqual(HelperProtocol.decode(#"{"cmd":"gatewayOn"}"#), .failure(.missingPid))
        for c in [HelperCommand.gatewayOn(ownerPid: 7), .gatewayOff] {
            XCTAssertEqual(try HelperProtocol.decode(HelperProtocol.encode(c)).get(), c)
        }
        XCTAssertGreaterThanOrEqual(HelperProtocol.version, 3) // v3: ağ geçidi
    }

    func testSubnetAvoidsHomeNetworkClash() {
        XCTAssertEqual(GatewayPlan.make(lanAddress: "192.168.1.50").network, "172.24.0.0/16")
        XCTAssertEqual(GatewayPlan.make(lanAddress: "172.24.9.3").network, "10.77.0.0/16")
        XCTAssertEqual(GatewayPlan.make(lanAddress: nil).network, "172.24.0.0/16")
    }

    func testDeviceSettings() {
        let p = GatewayPlan.make(lanAddress: "192.168.1.50")
        XCTAssertEqual(p.gateway, "172.24.2.1")
        XCTAssertEqual(p.deviceIP, "172.24.2.50")
        XCTAssertEqual(p.mask, "255.255.0.0")
        XCTAssertEqual(p.dns, "172.24.2.1") // DNS sorguları geçitten yanıtlanır
        let q = GatewayPlan.make(lanAddress: "172.24.9.3")
        XCTAssertEqual(q.gateway, "10.77.2.1")
        XCTAssertEqual(q.deviceIP, "10.77.2.50")
    }

    func testConfigRoutesWebTrafficToZapretAndDnsToHost() throws {
        let json = GatewayPlan.make(lanAddress: "192.168.1.50").config(socksPort: 1082, interfaceAddress: "192.168.1.50")
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let pcap = try XCTUnwrap(o["pcap"] as? [String: Any])
        XCTAssertEqual(pcap["network"] as? String, "172.24.0.0/16")
        XCTAssertEqual(pcap["localIP"] as? String, "172.24.2.1")
        XCTAssertEqual(pcap["interfaceGateway"] as? String, "192.168.1.50")
        let rules = try XCTUnwrap((o["routing"] as? [String: Any])?["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.map { $0["dstPort"] as? String }, ["53", "80,443"])
        XCTAssertEqual(rules.map { $0["outboundTag"] as? String }, ["dns-out", "zapret"])
        let outs = try XCTUnwrap(o["outbounds"] as? [[String: Any]])
        let socks = try XCTUnwrap(outs.first { $0["tag"] as? String == "zapret" }?["socks"] as? [String: Any])
        XCTAssertEqual(socks["address"] as? String, "127.0.0.1:1082")
        XCTAssertNotNil(outs.first { $0["tag"] as? String == "" }?["direct"]) // geri kalanı (ses UDP) doğrudan
        XCTAssertEqual((o["capture"] as? [String: Any])?["enabled"] as? Bool, false)
    }

    func testConfigWithoutInterfaceLetsToolAutoDetect() throws {
        let json = GatewayPlan.make(lanAddress: nil).config(socksPort: 1082, interfaceAddress: nil)
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertNil((o["pcap"] as? [String: Any])?["interfaceGateway"])
    }

    func testDevicesFromToolLog() {
        let log = """
        time=2026-10-28T19:10:00 level=INFO msg="Device 172.24.2.50 (aa:bb:cc:dd:ee:ff) joined the network"
        time=2026-10-28T19:10:02 level=INFO msg="[TCP] Connection" source=172.24.2.50:51000 destination=162.159.128.233:443
        time=2026-10-28T19:11:00 level=INFO msg="Device 172.24.2.51 (aa:bb:cc:dd:ee:00) joined the network"
        time=2026-10-28T19:11:01 level=INFO msg="Device 172.24.2.50 (aa:bb:cc:dd:ee:ff) joined the network"
        """
        XCTAssertEqual(GatewayPlan.devices(inLog: log), ["172.24.2.50", "172.24.2.51"])
        XCTAssertEqual(GatewayPlan.devices(inLog: ""), [])
    }

    func testMtuFromIfconfig() {
        XCTAssertEqual(GatewayPlan.mtu(ifconfig: "en0: flags=8863<UP,BROADCAST> mtu 1500\n\tether 00:00"), 1500)
        XCTAssertNil(GatewayPlan.mtu(ifconfig: "bozuk"))
    }
}
