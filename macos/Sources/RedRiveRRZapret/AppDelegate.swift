import AppKit
import WebKit
import ZapretCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    let controller = AppController()

    func applicationDidFinishLaunching(_ n: Notification) {
        if offerMoveToApplications() { return }
        buildMenu()
        buildWindow()
        buildStatusItem()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Windows ADR-020 karşılığı: pencere kapanınca uygulama arka planda çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow(); return true
    }

    func applicationWillTerminate(_ n: Notification) { controller.stop() }

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"), let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        ucc.add(controller, name: "zwt")
        cfg.userContentController = ucc
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 444, height: 621), configuration: cfg)
        controller.webView = web
        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "RedRiveRR Zapret"
        window.contentView = web
        window.minSize = NSSize(width: 400, height: 560)
        window.isReleasedWhenClosed = false
        window.center()
        if let dir = Bundle.main.url(forResource: "web", withExtension: nil) {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: "RedRiveRR Zapret")
        let m = NSMenu()
        m.addItem(withTitle: "Göster", action: #selector(showWindowAction), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Kapat", action: #selector(quitAction), keyEquivalent: "").target = self
        statusItem.menu = m
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "RedRiveRR Zapret'i Kapat", action: #selector(quitAction), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    @objc private func showWindowAction() { showWindow() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Spec 7.6a: /Applications dışındaysa (İndirilenler, App Translocation) taşımayı önerir. Taşındıysa true.
    private func offerMoveToApplications() -> Bool {
        let path = Bundle.main.bundlePath
        guard !path.hasPrefix("/Applications/") else { return false }
        let a = NSAlert()
        a.messageText = "Uygulamalar klasörüne taşınsın mı?"
        a.informativeText = "RedRiveRR Zapret'in arka plan hizmeti ve güncellemeleri için Uygulamalar klasöründe olması gerekiyor."
        a.addButton(withTitle: "Taşı")
        a.addButton(withTitle: "Şimdi değil")
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        let dest = "/Applications/" + (path as NSString).lastPathComponent
        do {
            if FileManager.default.fileExists(atPath: dest) { try FileManager.default.removeItem(atPath: dest) }
            try FileManager.default.copyItem(atPath: path, toPath: dest)
        } catch {
            let e = NSAlert(); e.messageText = "Taşınamadı"; e.informativeText = error.localizedDescription; e.runModal()
            return false
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: dest), configuration: .init()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
