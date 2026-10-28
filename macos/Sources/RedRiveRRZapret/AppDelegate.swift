import AppKit
import WebKit
import ZapretCore

/// Menü çubuğu paneli: kenarlıksız, saydam, arkasında sistem camı (NSVisualEffectView). Klavye alabilsin diye key olabilir.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: GlassPanel!
    private var web: WKWebView!
    private var statusItem: NSStatusItem!
    private var outsideClick: Any?
    private var contentHeight: CGFloat = 420
    private static let width: CGFloat = 340
    let controller = AppController()

    func applicationDidFinishLaunching(_ n: Notification) {
        if offerMoveToApplications() { return }
        buildPanel()
        buildStatusItem()
        controller.onResize = { [weak self] h in self?.resize(to: h) }
        controller.onHide = { [weak self] in self?.hidePanel() }
        controller.onRunningChange = { [weak self] on in self?.updateIcon(running: on) }
        // İlk açılışta paneli göster: uygulama artık yalnız menü çubuğunda, kullanıcı yerini görsün.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showPanel() }
    }

    func applicationWillTerminate(_ n: Notification) { controller.stopForQuit() }

    // MARK: Panel
    private func buildPanel() {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"), let js = try? String(contentsOf: url, encoding: .utf8) {
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        ucc.add(controller, name: "zwt")
        cfg.userContentController = ucc
        let frame = NSRect(x: 0, y: 0, width: Self.width, height: contentHeight)
        web = WKWebView(frame: frame, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground") // saydam: camı arkadaki görünüm verir
        web.autoresizingMask = [.width, .height]
        controller.webView = web

        let glass = NSVisualEffectView(frame: frame)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        glass.addSubview(web)

        panel = GlassPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = glass
        if let dir = Bundle.main.url(forResource: "web", withExtension: nil) {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(running: false)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateIcon(running: Bool) {
        let img = NSImage(systemSymbolName: running ? "lock.open.fill" : "lock.fill",
                          accessibilityDescription: running ? "RedRiveRR Zapret: açık" : "RedRiveRR Zapret: kapalı")
        img?.isTemplate = true
        statusItem?.button?.image = img
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { return showContextMenu() }
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showContextMenu() {
        hidePanel()
        let m = NSMenu()
        m.addItem(withTitle: "Paneli aç", action: #selector(showPanelAction), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Zapret'ten çık", action: #selector(quitAction), keyEquivalent: "q").target = self
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // sol tık yine paneli açsın
    }

    @objc private func showPanelAction() { showPanel() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func showPanel() {
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hidePanel() }
    }

    private func hidePanel() {
        guard panel?.isVisible == true else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    }

    func windowDidResignKey(_ n: Notification) { hidePanel() }

    /// Simgenin altına, ekranın görünür alanı içinde; üst kenar sabit kalır.
    private func positionPanel() {
        guard let button = statusItem.button, let bw = button.window else { return }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let h = min(contentHeight, screen.height - 16)
        var x = b.midX - Self.width / 2
        x = max(screen.minX + 8, min(x, screen.maxX - Self.width - 8))
        panel.setFrame(NSRect(x: x, y: b.minY - 6 - h, width: Self.width, height: h), display: true)
    }

    private func resize(to h: CGFloat) {
        contentHeight = h
        guard panel.isVisible else { return }
        let top = panel.frame.maxY
        let screen = panel.screen?.visibleFrame ?? .zero
        let nh = min(h, screen.height - 16)
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - nh, width: Self.width, height: nh), display: true, animate: false)
    }

    /// Spec 7.6a: /Applications dışındaysa (İndirilenler, App Translocation) taşımayı önerir. Taşındıysa true.
    private func offerMoveToApplications() -> Bool {
        let path = Bundle.main.bundlePath
        guard !path.hasPrefix("/Applications/") else { return false }
        NSApp.activate(ignoringOtherApps: true) // menü çubuğu uygulamasında uyarı öne gelsin
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
        // copyItem karantina işaretini de taşır; hedefte temizle (kullanıcı zaten taşı dedi).
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", dest]
        try? x.run()
        x.waitUntilExit()
        // Aynı bundle id çalışırken varsayılan açış yeni kopyayı başlatmaz, bu örneği öne getirir;
        // sonra biz kapanınca uygulama ortadan kaybolurdu.
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: dest), configuration: cfg) { app, error in
            DispatchQueue.main.async {
                // Yeni örnek başlamadıysa kendimizi kapatma; kullanıcı uygulamasız kalmasın.
                if app != nil { NSApp.terminate(nil) } else if let error = error { NSLog("taşıma sonrası açılamadı: \(error.localizedDescription)") }
            }
        }
        return true
    }
}
