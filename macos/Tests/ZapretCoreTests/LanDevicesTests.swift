import XCTest
@testable import ZapretCore

final class LanDevicesTests: XCTestCase {
    let table = "9C37CB\tPlayStation\n7C2A31\tSamsung\n"

    func testVendorFromMac() {
        XCTAssertEqual(LanDevices.vendor(mac: "9c:37:cb:6c:d8:79", table: table), "PlayStation")
        XCTAssertEqual(LanDevices.vendor(mac: "7C-2A-31-00-11-22", table: table), "Samsung")
        XCTAssertEqual(LanDevices.vendor(mac: "da:11:22:33:44:55", table: table), "Gizli adres (telefon / tablet olabilir)") // yerel yönetilen bit
        XCTAssertEqual(LanDevices.vendor(mac: "00:11:22:33:44:55", table: table), "")
        XCTAssertEqual(LanDevices.vendor(mac: "bozuk", table: table), "")
    }

    func testParsesJoinAndConnectionLinesIncrementally() {
        var d = LanDevices(vendors: table)
        d.feed("""
        time=2026-10-28T20:05:40.594+03:00 level=INFO msg="Device 172.24.2.50 (9c:37:cb:6c:d8:79) joined the network"
        time=2026-10-28T20:05:40.616+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.50:58220 dest=195.175.254.2:443
        time=2026-10-28T20:06:10.000+03:00 level=INFO msg="[UDP] Conn
        """)
        // yarım satır sonraki okumaya kalır
        d.feed("""
        ection" source=172.24.2.50:5000 dest=66.22.1.1:50001
        time=2026-10-28T20:07:00.000+03:00 level=INFO msg="Device 172.24.2.51 (da:11:22:33:44:55) joined the network"

        """)
        XCTAssertEqual(d.devices.map(\.ip), ["172.24.2.50", "172.24.2.51"])
        XCTAssertEqual(d.devices[0].kind, "PlayStation")
        XCTAssertEqual(d.devices[0].connections, 2)
        XCTAssertEqual(d.devices[1].kind, "Gizli adres (telefon / tablet olabilir)")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(d.devices[0].lastSeen, f.date(from: "2026-10-28T20:06:10+03:00"))
    }

    func testProxyClientsJoinTheList() {
        var d = LanDevices(vendors: table)
        let t = Date(timeIntervalSince1970: 1000)
        d.seenViaProxy("192.168.1.40", at: t)
        d.seenViaProxy("192.168.1.40", at: t.addingTimeInterval(5))
        XCTAssertEqual(d.devices.count, 1)
        XCTAssertEqual(d.devices[0].kind, "Proxy ayarlı cihaz")
        XCTAssertEqual(d.devices[0].connections, 2)
    }

    func testAgoTexts() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(LanDevices.ago(now.addingTimeInterval(-30), now: now), "Etkin")
        XCTAssertEqual(LanDevices.ago(now.addingTimeInterval(-90), now: now), "1 dk önce")
        XCTAssertEqual(LanDevices.ago(now.addingTimeInterval(-600), now: now), "10 dk önce")
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        XCTAssertEqual(LanDevices.ago(now.addingTimeInterval(-7200), now: now), f.string(from: now.addingTimeInterval(-7200)) + "'de")
    }

    func testJsonRowsHideMacAndCountActive() {
        var d = LanDevices(vendors: table)
        d.feed("time=2026-10-28T20:05:40.594+03:00 level=INFO msg=\"Device 172.24.2.50 (9c:37:cb:6c:d8:79) joined the network\"\n")
        let now = ISO8601DateFormatter().date(from: "2026-10-28T20:06:00+03:00")!
        let j = d.json(now: now)
        XCTAssertFalse(j.lowercased().contains("9c:37:cb"))
        XCTAssertTrue(j.contains(#""tur":"PlayStation""#))
        XCTAssertTrue(j.contains(#""durum":"Etkin""#))
        XCTAssertEqual(d.activeCount(now: now), 1)
    }
}
