import Foundation
import Darwin
import ZapretCore

/// Sistem SOCKS ve Güvenli Web proxy'sini açar/kapatır, önceki ayarları yedekler ve korur (yardımcı içinde, root).
final class ProxyKeeper {
    let queue = DispatchQueue(label: "com.redriverr.zapret.helper.keeper")
    private var on = false
    private var ownerPid: Int32 = 0
    private var port = 0
    private var failures = 0

    func handle(_ cmd: HelperCommand) -> String {
        switch cmd {
        case .proxyOn(let p, let pid):
            proxyOn(port: p, ownerPid: pid)
            return HelperProtocol.encodeReply(ok: on, message: on ? "proxy açık" : "proxy açılamadı")
        case .proxyOff:
            proxyOff()
            return HelperProtocol.encodeReply(ok: true, message: "proxy kapalı")
        case .status:
            return HelperProtocol.encodeReply(ok: true, message: HelperProtocol.statusMessage(on: on))
        }
    }

    func tick() {
        guard on else { return }
        let ownerAlive = kill(ownerPid, 0) == 0 || errno == EPERM
        failures = TpwsArgs.isPortFree(port) ? failures + 1 : 0
        if ProxyKeeperLogic.shouldRestore(proxyOn: on, ownerAlive: ownerAlive, engineFailures: failures) {
            log("proxy geri alınıyor (sahip yaşıyor: \(ownerAlive), tpws cevapsız: \(failures))")
            proxyOff()
        }
    }

    func restoreLeftover() {
        if FileManager.default.fileExists(atPath: HelperPaths.backup) {
            log("önceki oturumdan kalan proxy yedeği geri yükleniyor")
            proxyOff()
        }
    }

    private func proxyOn(port p: Int, ownerPid pid: Int32) {
        let services = SystemProxy.parseServices(run([SystemProxy.networksetup, "-listallnetworkservices"]))
        // Var olan yedek kayıtları korunur (zaten açıkken yeniden açmak kullanıcı ayarını ezmesin); oturum
        // sırasında eklenen hizmetler (USB Ethernet, telefon paylaşımı, VPN) önce yedeğe eklenir (gözden geçirme #1).
        var existing: [String: ProxyBackup] = [:]
        if let data = FileManager.default.contents(atPath: HelperPaths.backup),
           let old = try? JSONDecoder().decode([String: ProxyBackup].self, from: data) { existing = old }
        var current: [String: ProxyBackup] = [:]
        for s in services where existing[s] == nil {
            current[s] = ProxyBackup(
                socks: SystemProxy.parseProxy(run([SystemProxy.networksetup, "-getsocksfirewallproxy", s])),
                secureWeb: SystemProxy.parseProxy(run([SystemProxy.networksetup, "-getsecurewebproxy", s])))
        }
        let backup = SystemProxy.mergeBackup(existing: existing, current: current)
        try? FileManager.default.createDirectory(atPath: (HelperPaths.backup as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(backup),
              FileManager.default.createFile(atPath: HelperPaths.backup, contents: data) else {
            log("yedek yazılamadı; proxy açılmadı")
            return
        }
        for s in services { for c in SystemProxy.enableCommands(service: s, port: p) { _ = run(c) } }
        on = true
        ownerPid = pid
        port = p
        failures = 0
        log("proxy açıldı: 127.0.0.1:\(p) (\(services.count) hizmet), sahip pid \(pid)")
    }

    private func proxyOff() {
        if let data = FileManager.default.contents(atPath: HelperPaths.backup),
           let backup = try? JSONDecoder().decode([String: ProxyBackup].self, from: data) {
            for (s, st) in backup { for c in SystemProxy.restoreCommands(service: s, previous: st) { _ = run(c) } }
            try? FileManager.default.removeItem(atPath: HelperPaths.backup)
            log("proxy önceki hâline döndü (\(backup.count) hizmet)")
        }
        on = false
        failures = 0
    }

    private func run(_ argv: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { log("çalıştırılamadı: \(argv[0])"); return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func log(_ s: String) {
        FileHandle.standardError.write("\(Date()) \(s)\n".data(using: .utf8)!)
    }
}
