import Foundation
import ZapretCore

/// Yönetici yardımcısını bir kez kurar (macOS'un parola penceresi). Yardımcı ikilisi root'a ait konuma
/// kopyalanır: uygulama paketi kullanıcıya yazılabilir olduğu için root hizmeti oradan çalıştırılmaz.
enum HelperInstaller {
    static func install(log: (String) -> Void) -> Bool {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/zwt-helper").path
        guard FileManager.default.isExecutableFile(atPath: source) else { log("yardımcı pakette yok: \(source)"); return false }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(HelperPaths.label)</string>
          <key>ProgramArguments</key><array><string>\(HelperPaths.binary)</string><string>--uid</string><string>\(getuid())</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardErrorPath</key><string>/var/log/\(HelperPaths.label).log</string>
        </dict></plist>
        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(HelperPaths.label).plist")
        do { try plist.write(to: tmp, atomically: true, encoding: .utf8) } catch { log("plist yazılamadı"); return false }
        let q = shellQuote
        let script = [
            "mkdir -p /Library/PrivilegedHelperTools \(q("/Library/Application Support/RedRiveRR Zapret"))",
            "cp -X \(q(source)) \(q(HelperPaths.binary))",
            "(xattr -c \(q(HelperPaths.binary)) 2>/dev/null; true)",
            "chown root:wheel \(q(HelperPaths.binary))",
            "chmod 755 \(q(HelperPaths.binary))",
            "cp -X \(q(tmp.path)) \(q(HelperPaths.plist))",
            "chown root:wheel \(q(HelperPaths.plist))",
            "chmod 644 \(q(HelperPaths.plist))",
            "(launchctl bootout system/\(HelperPaths.label) 2>/dev/null; true)",
            "launchctl bootstrap system \(q(HelperPaths.plist))",
        ].joined(separator: " && ")
        let apple = "do shell script \"\(appleEscape(script))\" with administrator privileges with prompt \"RedRiveRR Zapret, Mac'in proxy ayarını değiştirebilmek için bir kez yönetici yardımcısını kuracak.\""
        // NSAppleScript ana iş parçacığı dışında güvenli değil; ayrı osascript süreci kullanılır (gözden geçirme #5).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", apple]
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch { try? FileManager.default.removeItem(at: tmp); log("osascript çalıştırılamadı"); return false }
        let errText = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        try? FileManager.default.removeItem(at: tmp)
        if p.terminationStatus != 0 {
            log("yardımcı kurulamadı: \(errText.trimmingCharacters(in: .whitespacesAndNewlines))")
            return false
        }
        // Soket açılana kadar en fazla 5 sn
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: HelperPaths.socket) { Thread.sleep(forTimeInterval: 0.1) }
        let ok = FileManager.default.fileExists(atPath: HelperPaths.socket)
        log(ok ? "yönetici yardımcısı kuruldu" : "yardımcı kuruldu ama soket açılmadı")
        return ok
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleEscape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}
