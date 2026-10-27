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
            "cp \(q(source)) \(q(HelperPaths.binary))",
            "chown root:wheel \(q(HelperPaths.binary))",
            "chmod 755 \(q(HelperPaths.binary))",
            "cp \(q(tmp.path)) \(q(HelperPaths.plist))",
            "chown root:wheel \(q(HelperPaths.plist))",
            "chmod 644 \(q(HelperPaths.plist))",
            "(launchctl bootout system/\(HelperPaths.label) 2>/dev/null; true)",
            "launchctl bootstrap system \(q(HelperPaths.plist))",
        ].joined(separator: " && ")
        let apple = "do shell script \"\(appleEscape(script))\" with administrator privileges with prompt \"RedRiveRR Zapret, Mac'in proxy ayarını değiştirebilmek için bir kez yönetici yardımcısını kuracak.\""
        var err: NSDictionary?
        NSAppleScript(source: apple)?.executeAndReturnError(&err)
        try? FileManager.default.removeItem(at: tmp)
        if let err = err { log("yardımcı kurulamadı: \(err[NSAppleScript.errorMessage] ?? err)"); return false }
        // Soket açılana kadar en fazla 5 sn
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: HelperPaths.socket) { Thread.sleep(forTimeInterval: 0.1) }
        let ok = FileManager.default.fileExists(atPath: HelperPaths.socket)
        log(ok ? "yönetici yardımcısı kuruldu" : "yardımcı kuruldu ama soket açılmadı")
        return ok
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleEscape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}
