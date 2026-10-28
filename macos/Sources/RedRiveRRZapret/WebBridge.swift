import AppKit
import WebKit
import ZapretCore

/// Panel sayfası (Resources/web) <-> program. Mesaj sözleşmesi Resources/web/uygulama.js başında.
final class AppController: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    /// Menü çubuğu paneli için: içerik yüksekliği, gizleme isteği, Zapret açık/kapalı (simge).
    var onResize: ((CGFloat) -> Void)?
    var onHide: (() -> Void)?
    var onRunningChange: ((Bool) -> Void)?
    private static let discordId = "com.hnc.Discord"
    /// Sistem proxy'si `TpwsArgs.defaultPort`'taki ön proxy'ye (DoH ile ad çözer) gider; tpws iç kapıdadır.
    private static let tpwsPort = TpwsArgs.defaultPort + 1
    private let engine = TpwsEngine(port: AppController.tpwsPort, pidFile: AppController.supportDir.appendingPathComponent("tpws.pid"))
    private var front: DohSocksFront? // yalnız `work` kuyruğunda
    private var lanFront: DohSocksFront?           // ağ paylaşımı (0.0.0.0:8080), yalnız `work` kuyruğunda
    private var gatewayFront: DohSocksFront?       // ağ geçidi trafiği (127.0.0.1:1082, SNI kurtarmalı), yalnız `work` kuyruğunda
    private var gatewayOn = false                  // lanLock ile
    private var frontResolve: ((String) -> [String])?
    private lazy var devices = LanDevices(vendors: Bundle.main.url(forResource: "cihaz-ureticileri", withExtension: "txt", subdirectory: "veri")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    private var gatewayLogOffset: UInt64 = 0 // lanLock ile
    private var shareOn = false // lanLock ile; ana iş parçacığı work kuyruğunu beklemesin (başlatma parola bekleyebilir)
    private let lanLock = NSLock()
    private var shareTimer: Timer?
    private var update: SelfUpdate.Release?
    private var updating = false
    private static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    /// Motor ve yardımcı çağrıları ana iş parçacığını kilitlemesin; sırayla çalışsın (gözden geçirme #2).
    private let work = DispatchQueue(label: "com.redriverr.zapret.work")
    private var strategies: [TpwsStrategy] = []
    private var bundled: [TpwsStrategy] = [] // paketteki strategies-macos.ini
    private var report: AnalysisReport?      // son strateji analizi (analiz.json)
    private var analyzing = false
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
    private var analysisURL: URL { Self.supportDir.appendingPathComponent("analiz.json") }

    override init() {
        super.init()
        let ini = Bundle.main.url(forResource: "strategies-macos", withExtension: "ini")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        bundled = Strategies.parse(ini)
        if let d = try? Data(contentsOf: analysisURL), let r = try? JSONDecoder().decode(AnalysisReport.self, from: d) {
            // eski kayıtlar başka kuralla sıralanmış olabilir
            report = AnalysisReport(time: r.time, baselinePassed: r.baselinePassed, baselineTotal: r.baselineTotal,
                                    scores: StrategyRanking.sort(r.scores, order: bundled.map(\.args)))
        }
        strategies = AnalysisReport.strategies(bundled: bundled, scores: report?.scores ?? [])
        let cfg = readConfig()
        selected = Strategies.resolve(savedName: cfg["ActiveStrategy"] ?? "", savedArgs: cfg["ActiveArgs"] ?? "", in: strategies)?.name
            ?? strategies.first?.name ?? ""
        engine.onUnexpectedExit = { [weak self] why in self?.engineDied(why) }
        clearProxyEnv(onlyIfOurs: true) // çökmeden kalan HTTPS_PROXY
        log("=== RedRiveRR Zapret (macOS) başlatıldı, \(strategies.count) strateji")
    }

    // MARK: Sayfadan gelenler
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        switch Json.get(text, "tip") {
        case "hazir":
            post(Json.object(["tip": "surum", "surum": Self.appVersion]))
            sendStatus()
            sendShare()
            sendUpdate()
            checkUpdate()
        case "kopyala":
            if let t = Json.get(text, "metin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                notify("Kopyalandı")
            }
        case "boyut":
            if let h = Json.get(text, "yukseklik").flatMap(Double.init), h > 0 { onResize?(CGFloat(h)) }
        case "komut":
            switch Json.get(text, "ad") {
            case "baslat": start()
            case "durdur": stop()
            case "analiz": analyze()
            case "sonuclar": openReport()
            case "kayitlar": NSWorkspace.shared.open(Self.logDir)
            case "github": NSWorkspace.shared.open(URL(string: "https://github.com/RedRiveRR/zapret-win-turkey")!)
            case "cikis": NSApp.terminate(nil)
            case "gizle": onHide?()
            case "discordYenile": restartDiscord()
            case "paylasimAc": setShare(true)
            case "paylasimKapat": setShare(false)
            case "guncelle": installUpdate()
            default: break
            }
        case "secim":
            // Başlatma/durdurma sürerken seçim yok sayılır; sayfa eski seçime döndürülür (gözden geçirme #6).
            if busy {
                sendStatus()
                sendStrategy()
            } else if Json.get(text, "alan") == "strateji", let v = Json.get(text, "deger"), strategies.contains(where: { $0.name == v }) {
                select(v)
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
        let startedAt = Date()
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
                    // Discord Zapret'ten önce açıldıysa eski (proxy'siz) bağlantısını tutar; yeniden başlatılmalı.
                    let discordWasOpen = NSRunningApplication.runningApplications(withBundleIdentifier: Self.discordId).contains {
                        ($0.launchDate ?? .distantPast) < startedAt
                    }
                    self.post(Json.object(["tip": "discord", "yenidenBaslat": discordWasOpen]))
                }
                self.sendStatus()
            }
        }
    }

    /// Arka planda: yardımcı (gerekirse bir kez kurulur) + tpws + sistem proxy'si. Hata metni ya da nil.
    private func startWork(_ strategy: TpwsStrategy) -> String? {
        if !HelperClient.isCurrent {
            log(HelperClient.isInstalled ? "yönetici yardımcısı eski sürüm; güncelleniyor" : "yönetici yardımcısı kuruluyor")
            if !HelperInstaller.install(log: log) {
                return "Yönetici yardımcısı çalışmıyor. Parola istendiyse girin; macOS 13 ve sonrasında Sistem Ayarları › Genel › Giriş Öğeleri › \"Arka planda izin ver\" altında RedRiveRR Zapret'i açın."
            }
        }
        stopFront() // çalışırken strateji değişince eski ön proxy 1080'i bırakmalı
        do { try startEngine(strategy) } catch {
            return error.localizedDescription
        }
        let hostlist = Self.hostlistPath
        // ISS DNS'i Discord/Roblox adlarını bozuyor: yalnız hostlist'tekiler DoH ile çözülür, gerisi sistem DNS'inde kalır.
        let hosts = hostlist.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }.map(HostMatcher.parseList) ?? []
        let resolver = DohResolver()
        let resolve: (String) -> [String] = { HostMatcher.matches($0, hosts) ? resolver.resolve($0) : [] }
        frontResolve = resolve
        let f = DohSocksFront(port: TpwsArgs.defaultPort, upstreamPort: engine.port, resolve: resolve)
        // config.ini'ye Ayrinti=1 yazılırsa her SOCKS isteği günlüğe düşer (ziyaret geçmişi içerir, varsayılan kapalı).
        if readConfig()["Ayrinti"] == "1" { f.onEvent = { [weak self] in self?.log("socks \($0)") } }
        do { try f.start() } catch {
            engine.stop()
            return error.localizedDescription
        }
        front = f
        if case .failure(let e) = HelperClient.send(.proxyOn(port: f.port, ownerPid: getpid())) {
            stopFront()
            engine.stop()
            return e.localizedDescription
        }
        for c in ProxyEnv.setCommands(port: f.port) { _ = Self.run(c) }
        if readConfig()["Paylasim"] == "1" { _ = startShareLocked() }
        return nil
    }

    func stop() {
        guard !busy else { return }
        busy = true
        sendStatus()
        work.async {
            HelperClient.send(.proxyOff)
            self.stopFront()
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
            stopFront()
            engine.stop()
        }
    }

    private func stopFront() {
        stopShareLocked()
        clearProxyEnv(onlyIfOurs: false)
        front?.stop()
        front = nil
    }

    private func clearProxyEnv(onlyIfOurs: Bool) {
        if onlyIfOurs && !ProxyEnv.isOurs(Self.run([ProxyEnv.launchctl, "getenv", ProxyEnv.names[0]]), port: TpwsArgs.defaultPort) { return }
        for c in ProxyEnv.unsetCommands() { _ = Self.run(c) }
    }

    @discardableResult
    private static func run(_ argv: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // İlk Mac sürümü: atlatma yalnız Discord/Roblox listesine (filtre seçimi sonraki aşamada).
    private static var hostlistPath: String? { Bundle.main.url(forResource: "hostlist", withExtension: "txt")?.path }

    private func startEngine(_ strategy: TpwsStrategy) throws {
        try engine.start(tpwsPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/tpws").path,
                         strategy: strategy, hostlist: Self.hostlistPath,
                         logURL: Self.logDir.appendingPathComponent("tpws.log"))
    }

    /// tpws kendiliğinden kapanırsa ön proxy ve sistem proxy'si yerinde kalır, motor yeniden başlatılır (60 sn'de en çok 3 kez);
    /// sürerse proxy geri alınır ki internet kesilmesin.
    private var engineRestarts: [Date] = []

    private func engineDied(_ why: String) {
        log("tpws beklenmedik şekilde kapandı: \(why)")
        engineRestarts = engineRestarts.filter { $0 > Date().addingTimeInterval(-60) }
        guard engineRestarts.count < 3, let strategy = strategies.first(where: { $0.name == running }) else {
            return engineGaveUp()
        }
        engineRestarts.append(Date())
        work.async {
            guard self.front != nil else { return } // bu arada durduruldu
            do {
                try self.startEngine(strategy)
                self.log("tpws yeniden başlatıldı")
            } catch {
                DispatchQueue.main.async {
                    self.log("tpws yeniden başlatılamadı: \(error.localizedDescription)")
                    self.engineGaveUp()
                }
            }
        }
    }

    private func engineGaveUp() {
        status = .error
        running = ""
        errorText = "Zapret beklenmedik şekilde durdu; internet bağlantınız eski hâline getirildi."
        log("tpws durdu; proxy geri alındı")
        sendStatus()
        work.async {
            HelperClient.send(.proxyOff)
            self.stopFront()
        }
    }

    private func select(_ name: String) {
        selected = name
        writeConfig("ActiveStrategy", name)
        if let s = strategies.first(where: { $0.name == name }) { writeConfig("ActiveArgs", s.args.joined(separator: " ")) }
    }

    /// Discord'u kapatıp yeniden açar (HTTPS_PROXY ile; güncelleyici sistem proxy'sini her zaman okumuyor).
    private func restartDiscord() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.discordId)
            apps.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(8)
            while apps.contains(where: { !$0.isTerminated }) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.discordId) else {
                return self.notify("Discord bulunamadı.")
            }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.environment = Dictionary(uniqueKeysWithValues: ProxyEnv.names.map { ($0, ProxyEnv.value(port: TpwsArgs.defaultPort)) })
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
                self.post(Json.object(["tip": "discord", "yenidenBaslat": error != nil]))
                self.notify(error == nil ? "Discord yeniden açılıyor" : "Discord açılamadı: \(error!.localizedDescription)")
                self.log(error == nil ? "Discord yeniden başlatıldı" : "Discord açılamadı")
            }
        }
    }

    // MARK: Ağ paylaşımı
    /// `work` kuyruğunda: Zapret çalışıyorsa ön proxy'nin yerel ağa açık kopyası. Hata metni ya da nil.
    private func startShareLocked() -> String? {
        guard lanFront == nil else { return nil }
        guard let resolve = frontResolve, front != nil else { return "Önce Zapret'i başlatın." }
        let f = DohSocksFront(port: LanShare.port, upstreamPort: engine.port, resolve: resolve, bindAddress: "0.0.0.0",
                              allow: LanShare.isLocal, sniRecovery: true)
        // Paylaşım günlüğü: yalnız atlatılan adlar (DoH) ve başarısızlıklar; ziyaret geçmişi tutulmaz (Ayrinti=1 hepsini yazar).
        let all = readConfig()["Ayrinti"] == "1"
        f.onEvent = { [weak self] e in if all || e.contains("DoH") || e.contains("hata") { self?.log("paylaşım \(e)") } }
        f.onClient = { [weak self] ip in
            guard let self = self, ip != "127.0.0.1" else { return }
            self.lanLock.lock(); self.devices.seenViaProxy(ip); self.lanLock.unlock()
        }
        do { try f.start() } catch { return "Paylaşım kapısı \(LanShare.port) başka bir program tarafından kullanılıyor." }
        lanFront = f
        lanLock.lock(); shareOn = true; devices.reset(); gatewayLogOffset = 0; lanLock.unlock()
        log("ağ paylaşımı açık: \(LanShare.port)")
        return startGatewayLocked(resolve: resolve, notifyOnly: true)
    }

    /// Ağ geçidi (Windows yöntemi): yardımcı go-pcap2socks'u root ile başlatır; cihazın TCP 80/443'ü 1082'deki SNI kurtarmalı
    /// ön proxy'ye gelir. Proxy'yi yok sayan uygulamalar (PS5 Discord) da böylece geçer. Araç pakette yoksa yalnız proxy kalır.
    private func startGatewayLocked(resolve: @escaping (String) -> [String], notifyOnly: Bool) -> String? {
        guard gatewayFront == nil,
              FileManager.default.isExecutableFile(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/pcap2socks").path)
        else { return nil }
        let g = DohSocksFront(port: GatewayPorts.socks, upstreamPort: engine.port, resolve: resolve, sniRecovery: true)
        g.onEvent = { [weak self] e in if e.contains("DoH") || e.contains("hata") { self?.log("geçit \(e)") } }
        do { try g.start() } catch { return "Ağ geçidi kapısı \(GatewayPorts.socks) kullanımda." }
        if case .failure(let e) = HelperClient.send(.gatewayOn(ownerPid: getpid())) {
            g.stop()
            log("ağ geçidi açılamadı: \(e.localizedDescription)")
            let msg = "Ağ geçidi açılamadı (proxy yolu açık): \(e.localizedDescription)"
            if notifyOnly { notify(msg); return nil }
            return msg
        }
        gatewayFront = g
        lanLock.lock(); gatewayOn = true; lanLock.unlock()
        log("ağ geçidi açık")
        return nil
    }

    private func setShare(_ on: Bool) {
        writeConfig("Paylasim", on ? "1" : "0")
        work.async {
            var err: String?
            if on { err = self.startShareLocked() } else { self.stopShareLocked(); self.log("ağ paylaşımı kapalı") }
            DispatchQueue.main.async {
                if let e = err { self.writeConfig("Paylasim", "0"); self.notify(e) }
                self.sendShare()
            }
        }
    }

    private func stopShareLocked() {
        if gatewayFront != nil {
            HelperClient.send(.gatewayOff)
            gatewayFront?.stop()
            gatewayFront = nil
        }
        lanFront?.stop()
        lanFront = nil
        lanLock.lock(); shareOn = false; gatewayOn = false; lanLock.unlock()
    }

    /// Araç günlüğünün yeni kısmını cihaz listesine işler (dosya yeniden başladıysa sıfırdan). lanLock tutulurken çağrılır.
    private func pollGatewayLogLocked() {
        guard let h = FileHandle(forReadingAtPath: HelperPaths.gatewayLog) else { return }
        defer { try? h.close() }
        let size = h.seekToEndOfFile()
        if size < gatewayLogOffset { devices.reset(); gatewayLogOffset = 0 }
        guard size > gatewayLogOffset else { return }
        h.seek(toFileOffset: gatewayLogOffset)
        let data = h.readData(ofLength: Int(min(size - gatewayLogOffset, 4 * 1024 * 1024)))
        gatewayLogOffset += UInt64(data.count)
        devices.feed(String(decoding: data, as: UTF8.self))
    }

    /// Donanım portları oturum boyunca değişmez; her 5 sn'de bir networksetup çalıştırılmasın.
    private static let hardwarePorts = run(["/usr/sbin/networksetup", "-listallhardwareports"])

    private func sendShare() {
        lanLock.lock()
        let on = shareOn, gw = gatewayOn
        if gw { pollGatewayLogLocked() }
        let deviceRows = devices.json(), deviceCount = devices.devices.count, activeCount = devices.activeCount()
        lanLock.unlock()
        let firewall = on && Self.run(["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"]).contains("enabled")
        let ifs = LanShare.interfaces()
        let lan = LanShare.pickAddress(ifs)
        let plan = GatewayPlan.make(lanAddress: lan)
        let ifName = ifs.first { $0.1 == lan }?.0
        let mtu = GatewayPlan.deviceMTU(interfaceMTU: ifName.flatMap { GatewayPlan.mtu(ifconfig: Self.run(["/sbin/ifconfig", $0])) } ?? 1500)
        post(Json.object(["tip": "paylasim", "acik": on, "kullanilabilir": status == .manual, "gecit": gw,
                          "adres": lan ?? "", "port": LanShare.port,
                          "ip": plan.deviceIP, "maske": plan.mask, "agGecidi": plan.gateway, "dns": plan.dns, "dns2": plan.dns2, "mtu": mtu,
                          "kablosuz": ifName.map { LanShare.wifiDevices(hardwarePorts: Self.hardwarePorts).contains($0) } ?? false,
                          "cihaz": deviceCount, "etkin": activeCount, "cihazlar": Json.Raw(deviceRows), "guvenlikDuvari": firewall]))
        DispatchQueue.main.async {
            if on && self.shareTimer == nil {
                self.shareTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sendShare() }
            } else if !on {
                self.shareTimer?.invalidate(); self.shareTimer = nil
            }
        }
    }

    // MARK: Kendini güncelleme (Windows ADR-019 sözleşmesi)
    private func checkUpdate() {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(SelfUpdate.repo)/releases/latest")!, timeoutInterval: 10)
        req.setValue("RedRiveRR-Zapret-macOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let d = data, let r = SelfUpdate.parseRelease(d), SelfUpdate.isNewer(r.version, than: Self.appVersion) else { return }
            DispatchQueue.main.async {
                self.update = r
                self.log("yeni sürüm var: \(r.version)")
                self.sendUpdate()
            }
        }.resume()
    }

    private func sendUpdate(_ state: String? = nil, _ text: String = "") {
        post(Json.object(["tip": "guncelleme", "surum": update?.version ?? "", "durum": state ?? (updating ? "indiriliyor" : "hazir"), "metin": text]))
    }

    /// İndirir, özeti doğrular, imzayı ve paket kimliğini denetler, eski paketin yerine koyar, yeniden açar.
    private func installUpdate() {
        guard let r = update, !updating else { return }
        updating = true
        sendUpdate("indiriliyor", "İndiriliyor…")
        DispatchQueue.global(qos: .userInitiated).async {
            let err = self.performUpdate(r)
            DispatchQueue.main.async {
                self.updating = false
                if let e = err {
                    self.log("güncelleme başarısız: \(e)")
                    self.sendUpdate("hata", e)
                }
            }
        }
    }

    private func performUpdate(_ r: SelfUpdate.Release) -> String? {
        func get(_ u: URL) -> Data? {
            var data: Data?
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: URLRequest(url: u, timeoutInterval: 120)) { d, resp, _ in
                if (resp as? HTTPURLResponse)?.statusCode == 200 { data = d }
                sem.signal()
            }.resume()
            sem.wait()
            return data
        }
        guard let sums = get(r.sumsURL).map({ String(decoding: $0, as: UTF8.self) }),
              let want = SelfUpdate.sum(in: sums, for: r.assetName) else { return "Özet dosyasında Mac paketi yok." }
        guard let zip = get(r.assetURL) else { return "Paket indirilemedi." }
        guard SelfUpdate.sha256Hex(zip) == want else { return "Paketin özeti tutmuyor; kurulmadı." }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zwt-guncelleme-\(r.version)", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let zipURL = tmp.appendingPathComponent(r.assetName)
        guard (try? zip.write(to: zipURL)) != nil else { return "Geçici klasöre yazılamadı." }
        _ = Self.run(["/usr/bin/ditto", "-xk", zipURL.path, tmp.appendingPathComponent("acik").path])
        let newApp = tmp.appendingPathComponent("acik/RedRiveRR Zapret.app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == r.version else { return "Paket beklenen uygulama değil." }
        _ = Self.run(["/usr/bin/xattr", "-cr", newApp.path])
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", newApp.path]
        try? verify.run(); verify.waitUntilExit()
        guard verify.terminationStatus == 0 else { return "Paketin imzası bozuk." }
        let current = Bundle.main.bundleURL
        let backup = tmp.appendingPathComponent("eski.app")
        do {
            try FileManager.default.moveItem(at: current, to: backup)
            do { try FileManager.default.moveItem(at: newApp, to: current) } catch {
                try? FileManager.default.moveItem(at: backup, to: current)
                return "Uygulama değiştirilemedi: \(error.localizedDescription)"
            }
        } catch { return "Uygulama değiştirilemedi: \(error.localizedDescription)" }
        log("güncellendi: \(Self.appVersion) → \(r.version)")
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1.5; /usr/bin/open -n \"$0\"", current.path]
        try? relaunch.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return nil
    }

    // MARK: Strateji analizi
    /// Sağlayıcıya göre en iyi stratejiyi ölçer (sistem proxy'sine dokunmaz; adaylar geçici tpws kapılarında sınanır).
    func analyze() {
        guard !analyzing else { return }
        analyzing = true
        sendStrategy()
        progress(true, "Adlar şifreli DNS ile çözülüyor…", 0.02)
        log("strateji analizi başladı")
        let tpws = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/tpws").path
        let hostlist = Bundle.main.url(forResource: "hostlist", withExtension: "txt")?.path
        let candidates = StrategyCandidates.generate(including: bundled)
        DispatchQueue.global(qos: .userInitiated).async {
            let plan = AnalysisPlan.make(resolve: DohResolver().resolve)
            guard !plan.detail.isEmpty else {
                DispatchQueue.main.async { self.analysisDone(nil, error: "Discord adları çözülemedi; şifreli DNS'e (DoH) ulaşılamıyor.") }
                return
            }
            let base = TpwsMeasure.direct(plan.detail)
            let analyzer = StrategyAnalyzer(concurrency: 4, measure: TpwsMeasure.make(tpwsPath: tpws, hostlist: hostlist, logDir: Self.logDir))
            analyzer.onProgress = { done, total, phase in
                let screening = phase == "eleme"
                let ratio = screening ? 0.05 + 0.55 * Double(done) / Double(max(total, 1)) : 0.6 + 0.4 * Double(done) / Double(max(total, 1))
                self.progress(true, (screening ? "Adaylar eleniyor" : "Kalanlar ayrıntılı ölçülüyor") + " · \(done)/\(total)", ratio)
            }
            let scores = analyzer.run(candidates: candidates, screen: plan.screen, detail: plan.detail)
            let f = DateFormatter()
            f.dateFormat = "dd.MM HH:mm"
            let r = AnalysisReport(time: f.string(from: Date()), baselinePassed: base.passed, baselineTotal: base.total, scores: scores)
            DispatchQueue.main.async { self.analysisDone(r, error: nil) }
        }
    }

    private func analysisDone(_ r: AnalysisReport?, error: String?) {
        analyzing = false
        progress(false, "", 0)
        if let r = r {
            report = r
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: analysisURL, options: .atomic) }
            strategies = AnalysisReport.strategies(bundled: bundled, scores: r.scores)
            let summary = r.scores.prefix(3).map { "\($0.score) \($0.args.joined(separator: " "))" }.joined(separator: "; ")
            log("strateji analizi bitti: taban \(r.baselinePassed)/\(r.baselineTotal), \(r.scores.count) aday; ilk: \(summary)")
            if let best = AnalysisReport.best(bundled: bundled, scores: r.scores) {
                select(best.name)
                notify("En iyi strateji seçildi: \(best.name)" + (status == .manual ? " — uygulanıyor" : ""))
                if status == .manual { start() }
            } else {
                notify("Bu ağda çalışan strateji bulunamadı. Tüm sonuçlar'dan ayrıntıya bakabilirsiniz.")
            }
        } else if let e = error {
            log("strateji analizi başarısız: \(e)")
            notify(e)
        }
        sendStrategy()
        sendStatus()
    }

    private func openReport() {
        guard let r = report else { return notify("Henüz analiz yapılmadı.") }
        let url = Self.logDir.appendingPathComponent("strateji-analizi.txt")
        try? r.text(bundled: bundled).write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    private func sendStrategy() {
        post(WebState.strategyJson(options: strategies.map(\.name), selected: selected, analysisEnabled: !analyzing,
                                   time: report?.time ?? "", results: AnalysisReport.rows(bundled: bundled, scores: report?.scores ?? [], selected: running.isEmpty ? selected : running)))
    }

    private func progress(_ on: Bool, _ text: String, _ ratio: Double) {
        post(Json.object(["tip": "analiz", "calisiyor": on, "metin": text, "oran": Json.Raw(String(format: "%.3f", ratio))]))
    }
    private func notify(_ s: String) { post(Json.object(["tip": "bildirim", "metin": s])) }

    // MARK: Sayfaya gidenler
    private func sendStatus() {
        defer { sendStrategy() } // sonuç listesindeki "seçili" işareti çalışan stratejiyi izler
        let on = status == .manual
        DispatchQueue.main.async {
            self.onRunningChange?(on)
            self.sendShare() // paylaşım Zapret'e bağlı
        }
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
        try? (d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n")
            .write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static let logLock = NSLock() // ön proxy iş parçacıkları da yazar

    func log(_ s: String) {
        Self.logLock.lock(); defer { Self.logLock.unlock() }
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
