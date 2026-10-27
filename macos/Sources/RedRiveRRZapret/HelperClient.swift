import Foundation
import Darwin
import ZapretCore

enum HelperClientError: LocalizedError {
    case notInstalled, connect, refused(String)
    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Yönetici yardımcısı kurulu değil."
        case .connect: return "Yönetici yardımcısına bağlanılamadı."
        case .refused(let m): return "Yönetici yardımcısı isteği reddetti: \(m)"
        }
    }
}

/// zwt-helper'a Unix soketiyle tek satırlık istek gönderir.
enum HelperClient {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperPaths.plist) && FileManager.default.fileExists(atPath: HelperPaths.socket)
    }

    @discardableResult
    static func send(_ cmd: HelperCommand) -> Result<String, Error> {
        guard FileManager.default.fileExists(atPath: HelperPaths.socket) else { return .failure(HelperClientError.notInstalled) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(HelperClientError.connect) }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in HelperPaths.socket.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) } }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return .failure(HelperClientError.connect) }
        var tv = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = (HelperProtocol.encode(cmd) + "\n").withCString { write(fd, $0, strlen($0)) }
        var data = Data()
        var byte: UInt8 = 0
        while data.count < 4096, read(fd, &byte, 1) == 1, byte != 10 { data.append(byte) }
        let reply = String(decoding: data, as: UTF8.self)
        if Json.get(reply, "ok") == "true" { return .success(Json.get(reply, "mesaj") ?? "") }
        return .failure(HelperClientError.refused(Json.get(reply, "mesaj") ?? reply))
    }
}
