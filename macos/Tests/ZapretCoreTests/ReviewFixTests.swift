import XCTest
import Darwin
@testable import ZapretCore

/// Son gözden geçirme bulguları (Important #1–#3) için testler.
final class ReviewFixTests: XCTestCase {
    // #1: oturum sırasında eklenen ağ hizmeti yedeğe girmeli; var olan yedek kaydı değişmemeli.
    func testBackupMergeAddsNewServicesOnly() {
        let old = ["Wi-Fi": SocksState(enabled: true, server: "10.0.0.9", port: 9050)]
        let current = ["Wi-Fi": SocksState(enabled: true, server: "127.0.0.1", port: 1080),
                       "USB 10/100/1000 LAN": SocksState(enabled: false, server: "", port: 0)]
        let merged = SystemProxy.mergeBackup(existing: old, current: current)
        XCTAssertEqual(merged["Wi-Fi"], SocksState(enabled: true, server: "10.0.0.9", port: 9050))
        XCTAssertEqual(merged["USB 10/100/1000 LAN"], SocksState(enabled: false, server: "", port: 0))
        XCTAssertEqual(merged.count, 2)
    }

    private func tmpURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("zwt-test-\(UUID().uuidString)-\(name)")
    }

    // #2: bilinçli durdurma "beklenmedik kapanma" bildirmemeli.
    func testIntentionalStopDoesNotReportUnexpectedExit() throws {
        let e = TpwsEngine(port: 1, pidFile: tmpURL("pid"))
        var fired = false
        e.onUnexpectedExit = { _ in fired = true }
        try e.launch(argv: ["/bin/sleep", "30"], logURL: tmpURL("log"))
        XCTAssertTrue(e.isRunning)
        e.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertFalse(fired)
        XCTAssertFalse(e.isRunning)
    }

    // #2: kendiliğinden kapanma bildirilmeli (tam bir kez).
    func testUnexpectedExitReported() throws {
        let e = TpwsEngine(port: 1, pidFile: tmpURL("pid"))
        let exp = expectation(description: "beklenmedik kapanma")
        e.onUnexpectedExit = { _ in exp.fulfill() }
        try e.launch(argv: ["/bin/sleep", "0.3"], logURL: tmpURL("log"))
        wait(for: [exp], timeout: 5)
        XCTAssertFalse(e.isRunning)
    }

    // macOS 27 tpws çökmesi kayıtta görünmüyordu: kapanma nedeni (sinyal / çıkış kodu) bildirilmeli.
    func testUnexpectedExitReportsSignal() throws {
        let e = TpwsEngine(port: 1, pidFile: tmpURL("pid"))
        let exp = expectation(description: "neden")
        var why = ""
        e.onUnexpectedExit = { why = $0; exp.fulfill() }
        try e.launch(argv: ["/bin/sh", "-c", "kill -BUS $$"], logURL: tmpURL("log"))
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(why, "sinyal 10 (SIGBUS)")
    }

    func testUnexpectedExitReportsExitCode() throws {
        let e = TpwsEngine(port: 1, pidFile: tmpURL("pid"))
        let exp = expectation(description: "neden")
        var why = ""
        e.onUnexpectedExit = { why = $0; exp.fulfill() }
        try e.launch(argv: ["/bin/sh", "-c", "exit 3"], logURL: tmpURL("log"))
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(why, "çıkış kodu 3")
    }

    // #3: zorla kapatmadan arta kalan tpws, pid dosyasından bulunup kapatılmalı.
    func testKillsLeftoverFromPidFile() throws {
        let leftover = Process()
        leftover.executableURL = URL(fileURLWithPath: "/bin/sleep")
        leftover.arguments = ["30"]
        try leftover.run()
        let pidFile = tmpURL("pid")
        try "\(leftover.processIdentifier)".write(to: pidFile, atomically: true, encoding: .utf8)
        TpwsEngine.killLeftover(pidFile: pidFile, expectedPath: "/bin/sleep")
        leftover.waitUntilExit()
        XCTAssertFalse(leftover.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pidFile.path))
    }

    // #3: pid dosyasındaki süreç başka bir programsa dokunulmamalı.
    func testLeftoverOtherProgramNotKilled() throws {
        let other = Process()
        other.executableURL = URL(fileURLWithPath: "/bin/sleep")
        other.arguments = ["30"]
        try other.run()
        defer { other.terminate() }
        let pidFile = tmpURL("pid")
        try "\(other.processIdentifier)".write(to: pidFile, atomically: true, encoding: .utf8)
        TpwsEngine.killLeftover(pidFile: pidFile, expectedPath: "/Applications/RedRiveRR Zapret.app/Contents/Resources/bin/tpws")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(other.isRunning)
    }
}
