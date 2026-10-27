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
        .failure(.badJson)
    }

    public static func encode(_ cmd: HelperCommand) -> String { "" }

    public static func encodeReply(ok: Bool, message: String) -> String { "" }
}

/// Proxy'yi koruma kararı (yardımcı her 2 sn'de çağırır): sahip uygulama öldüyse ya da tpws kapısı
/// art arda `engineFailureLimit` kez cevap vermediyse proxy geri alınır — yoksa Mac'in interneti kesilir.
public enum ProxyKeeperLogic {
    public static let engineFailureLimit = 0

    public static func shouldRestore(proxyOn: Bool, ownerAlive: Bool, engineFailures: Int) -> Bool { false }
}
