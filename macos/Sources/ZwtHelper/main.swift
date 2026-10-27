// RedRiveRR Zapret yönetici yardımcısı (root LaunchDaemon). Spec 7.4:
// - Unix soketi HelperPaths.socket; yalnız --uid ile verilen kullanıcı ve root bağlanabilir (getpeereid).
// - Yalnız sabit komutlar (HelperProtocol): proxyOn (yalnız 127.0.0.1:<port>), proxyOff, status.
// - Proxy açıkken sahip uygulama ölürse ya da tpws kapısı art arda cevap vermezse proxy geri alınır.
import Foundation
import Darwin
import ZapretCore

func argValue(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

guard let uidText = argValue("--uid"), let allowedUid = uid_t(uidText) else {
    FileHandle.standardError.write("kullanım: zwt-helper --uid <kullanıcı uid>\n".data(using: .utf8)!)
    exit(2)
}

let keeper = ProxyKeeper()
keeper.restoreLeftover() // önceki çökmeden kalan yedek varsa proxy'yi geri al

// Bekçi: 2 sn'de bir sahip PID ve tpws kapısı
let timer = DispatchSource.makeTimerSource(queue: keeper.queue)
timer.schedule(deadline: .now() + 2, repeating: 2)
timer.setEventHandler { keeper.tick() }
timer.resume()

// Soket
let path = HelperPaths.socket
unlink(path)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { perror("socket"); exit(1) }
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in path.utf8CString.withUnsafeBytes { buf.copyMemory(from: $0) } }
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard bound == 0, listen(server, 8) == 0 else { perror("bind/listen"); exit(1) }
chmod(path, 0o666) // erişim getpeereid ile denetlenir

while true {
    let conn = accept(server, nil, nil)
    if conn < 0 { continue }
    var peerUid: uid_t = 0, peerGid: gid_t = 0
    guard getpeereid(conn, &peerUid, &peerGid) == 0, peerUid == allowedUid || peerUid == 0 else { close(conn); continue }
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var data = Data()
    var byte: UInt8 = 0
    while data.count < 4096, read(conn, &byte, 1) == 1, byte != 10 { data.append(byte) }
    let reply: String
    switch HelperProtocol.decode(String(decoding: data, as: UTF8.self)) {
    case .failure(let e):
        reply = HelperProtocol.encodeReply(ok: false, message: "reddedildi: \(e)")
    case .success(let cmd):
        reply = keeper.queue.sync { keeper.handle(cmd) }
    }
    _ = (reply + "\n").withCString { write(conn, $0, strlen($0)) }
    close(conn)
}
