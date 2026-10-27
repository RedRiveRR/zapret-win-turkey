import Foundation

/// Uygulama → yönetici yardımcısı komutları. Yardımcı yalnız bunları kabul eder (spec 7.4).
public enum HelperCommand: Equatable {
    case proxyOn(port: Int, ownerPid: Int32)
    case proxyOff
    case status
}

public enum HelperError: Error, Equatable {
    case badJson
    case unknownCommand(String)
    case badPort
    case missingPid
}

public enum HelperPaths {
    public static let label = "com.redriverr.zapret.helper"
    public static let socket = "/var/run/com.redriverr.zapret.helper.sock"
    public static let binary = "/Library/PrivilegedHelperTools/com.redriverr.zapret.helper"
    public static let plist = "/Library/LaunchDaemons/com.redriverr.zapret.helper.plist"
    public static let backup = "/Library/Application Support/RedRiveRR Zapret/proxy-yedek.json"
}

/// Satır başına bir JSON: {"cmd":"proxyOn","port":1080,"pid":123} · {"cmd":"proxyOff"} · {"cmd":"status"}
public enum HelperProtocol {
    public static func decode(_ line: String) -> Result<HelperCommand, HelperError> {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cmd = obj["cmd"] as? String else { return .failure(.badJson) }
        switch cmd {
        case "proxyOn":
            // Sayı olmalı (metin "1080" kabul edilmez); Bool'un NSNumber olarak gelmesi de reddedilir.
            guard let n = obj["port"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                  n.doubleValue == n.doubleValue.rounded(), (1024...65535).contains(n.intValue) else { return .failure(.badPort) }
            guard let p = obj["pid"] as? NSNumber, p.int32Value > 0 else { return .failure(.missingPid) }
            return .success(.proxyOn(port: n.intValue, ownerPid: p.int32Value))
        case "proxyOff": return .success(.proxyOff)
        case "status": return .success(.status)
        default: return .failure(.unknownCommand(cmd))
        }
    }

    public static func encode(_ cmd: HelperCommand) -> String {
        switch cmd {
        case .proxyOn(let port, let pid): return Json.object(["cmd": "proxyOn", "port": port, "pid": Int(pid)])
        case .proxyOff: return Json.object(["cmd": "proxyOff"])
        case .status: return Json.object(["cmd": "status"])
        }
    }

    public static func encodeReply(ok: Bool, message: String) -> String {
        Json.object(["ok": ok, "mesaj": message])
    }
}

/// Proxy'yi koruma kararı (yardımcı her 2 sn'de çağırır): sahip uygulama öldüyse ya da tpws kapısı
/// art arda `engineFailureLimit` kez cevap vermediyse proxy geri alınır — yoksa Mac'in interneti kesilir.
public enum ProxyKeeperLogic {
    public static let engineFailureLimit = 3

    public static func shouldRestore(proxyOn: Bool, ownerAlive: Bool, engineFailures: Int) -> Bool {
        proxyOn && (!ownerAlive || engineFailures >= engineFailureLimit)
    }
}
