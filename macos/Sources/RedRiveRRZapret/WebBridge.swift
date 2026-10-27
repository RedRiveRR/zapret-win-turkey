import AppKit
import WebKit
import ZapretCore

/// Sayfa (ui/web) <-> program. Mesaj sözleşmesi ui/web/uygulama.js başındaki listeyle aynı.
final class AppController: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private let engine = TpwsEngine(pidFile: AppController.supportDir.appendingPathComponent("tpws.pid"))
    /// Motor ve yardımcı çağrıları ana iş parçacığını kilitlemesin; sırayla çalışsın (gözden geçirme #2).
    private let work = DispatchQueue(label: "com.redriverr.zapret.work")
    private var strategies: [TpwsStrategy] = []
    private var selected = ""
    private var running = "" // çalışan strateji (seçili olandan farklı olabilir)
    private var status: AppStatus = .ready
    private var errorText: String?
    private var busy = false

    static let supportDir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RedRiveRR Zapret", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let logDir: URL = {
        let u = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/RedRiveRR Zapret", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    private var configURL: URL { Self.supportDir.appendingPathComponent("config.ini") }

    override init() {
        super.init()
        let ini = Bundle.main.url(forResource: "strategies-macos", withExtension: "ini")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        strategies = Strategies.parse(ini)
        let saved = readConfig()["ActiveStrategy"] ?? ""
        selected = strategies.contains { $0.name == saved } ? saved : (strategies.first?.name ?? "")
        engine.onUnexpectedExit = { [weak self] in self?.engineDied() }
        log("=== RedRiveRR Zapret (macOS) başlatıldı, \(strategies.count) strateji")
    }

    // MARK: Sayfadan gelenler
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        switch Json.get(text, "tip") {
        case "hazir":
            post(Json.object(["tip": "platform", "ad": "macos"]))
            post(Json.object(["tip": "tema", "tema": readConfig()["Tema"] ?? systemTheme()]))
            sendStatus()
            post(WebState.strategyJson(options: strategies.map(\.name), selected: selected))
        case "tema":
            writeConfig("Tema", Json.get(text, "tema") == "koyu" ? "koyu" : "acik")
        case "komut":
            switch Json.get(text, "ad") {
            case "baslat": start()
            case "durdur": stop()
            case "kayitlar": NSWorkspace.shared.open(Self.logDir)
            case "github": NSWorkspace.shared.open(URL(string: "https://github.com/RedRiveRR/zapret-win-turkey")!)
            default: break
            }
        case "secim":
            // Başlatma/durdurma sürerken seçim yok sayılır; sayfa eski seçime döndürülür (gözden geçirme #6).
            if busy {
                sendStatus()
                post(WebState.strategyJson(options: strategies.map(\.name), selected: selected))
            } else if Json.get(text, "alan") == "strateji", let v = Json.get(text, "deger"), strategies.contains(where: { $0.name == v }) {
                selected = v
                writeConfig("ActiveStrategy", v)
                if status == .manual { start() } // çalışırken strateji değişince yeniden başlat
                else { sendStatus() }
            }
        default: break
        }
    }

    // MARK: Başlat / durdur
    func start() {
        guard !busy, let strategy = strategies.first(where: { $0.name == selected }) else { return }
        busy = true
        status = .starting
        errorText = nil
        sendStatus()
        work.async {
            let err = self.startWork(strategy)
            DispatchQueue.main.async {
                self.busy = false
                if let err = err {
                    self.status = .error
                    self.errorText = err
                    self.running = ""
                    self.log("başlatılamadı: \(err)")
                } else {
                    self.status = .manual
                    self.running = strategy.name
                    self.log("başladı: \(strategy.name) \(strategy.args.joined(separator: " "))")
                }
                self.sendStatus()
            }
        }
    }

    /// Arka planda: yardımcı (gerekirse bir kez kurulur) + tpws + sistem proxy'si. Hata metni ya da nil.
    private func startWork(_ strategy: TpwsStrategy) -> String? {
        if !HelperClient.isInstalled && !HelperInstaller.install(log: log) {
            return "Yönetici yardımcısı kurulamadı. Proxy ayarı için bir kez yönetici parolası gerekiyor."
        }
        let tpws = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/tpws").path
        do {
            // İlk Mac sürümü: atlatma yalnız Discord/Roblox listesine (filtre seçimi sonraki aşamada).
            let hostlist = Bundle.main.url(forResource: "hostlist", withExtension: "txt")?.path
            try engine.start(tpwsPath: tpws, strategy: strategy, hostlist: hostlist,
                             logURL: Self.logDir.appendingPathComponent("tpws.log"))
        } catch {
            return error.localizedDescription
        }
        if case .failure(let e) = HelperClient.send(.proxyOn(port: engine.port, ownerPid: getpid())) {
            engine.stop()
            return e.localizedDescription
        }
        return nil
    }

    func stop() {
        guard !busy else { return }
        busy = true
        sendStatus()
        work.async {
            HelperClient.send(.proxyOff)
            self.engine.stop()
            DispatchQueue.main.async {
                self.busy = false
                self.status = .ready
                self.errorText = nil
                self.running = ""
                self.log("durduruldu")
                self.sendStatus()
            }
        }
    }

    /// Uygulama kapanırken: proxy geri alınır, motor durdurulur (bekleyerek).
    func stopForQuit() {
        work.sync {
            HelperClient.send(.proxyOff)
            engine.stop()
        }
    }

    private func engineDied() {
        status = .error
        running = ""
        errorText = "Zapret beklenmedik şekilde durdu; internet bağlantınız eski hâline getirildi."
        log("tpws beklenmedik şekilde kapandı; proxy geri alındı")
        sendStatus()
        work.async { HelperClient.send(.proxyOff) }
    }

    // MARK: Sayfaya gidenler
    private func sendStatus() {
        post(WebState.statusJson(status: status, running: status == .manual, buttonEnabled: !busy,
                                 strategy: running.isEmpty ? selected : running, detail: "tpws (macOS), Discord ve Roblox siteleri", error: errorText))
    }

    func post(_ json: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__zwtGelen(\(Json.quote(json)))", completionHandler: nil)
        }
    }

    // MARK: Ayarlar ve kayıt
    private func readConfig() -> [String: String] {
        guard let t = try? String(contentsOf: configURL, encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for line in t.components(separatedBy: .newlines) {
            let p = line.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { d[p[0]] = p[1] }
        }
        return d
    }

    private func writeConfig(_ key: String, _ value: String) {
        var d = readConfig()
        d[key] = value
        try? d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
            .write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func systemTheme() -> String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "koyu" : "acik"
    }

    func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(s)\n"
        let url = Self.logDir.appendingPathComponent("app.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
