import Foundation

/// Ağ geçidi trafiğini karşılayan SNI kurtarmalı ön proxy'nin kapısı (uygulama açar, yardımcının yapılandırması yazar).
public enum GatewayPorts { public static let socks = 1082 }

/// Ağ geçidi paylaşımı (Windows ile aynı yöntem): go-pcap2socks yerel ağda sahte bir ağ geçidi olur; cihaz IP/geçit/DNS'i
/// elle girer. TCP 80/443 SNI kurtarmalı ön proxy'ye (tpws), DNS bu Mac'in çözücüsüne, geri kalanı (ses UDP) doğrudan.
public struct GatewayPlan: Equatable {
    public let network: String
    public let gateway: String
    public let deviceIP: String
    public let mask: String
    /// Cihaza dış DNS verilir: geçidin kendi adresine giden DNS go-pcap2socks'ta yanıtlanmıyor (Windows H23). Port 53 kuralı
    /// sorguyu yakalayıp Mac'in çözücüsüne yollar; Discord adlarının zehirli yanıtlarını SNI kurtarma düzeltir.
    public let dns = "1.1.1.1"
    public let dns2 = "8.8.8.8"

    /// go-pcap2socks: "MTU: <arayüz − 14> (or lower)".
    public static func deviceMTU(interfaceMTU: Int) -> Int { interfaceMTU - 14 }

    /// Ev ağı 172.24/16 ise çakışmasın diye 10.77/16.
    public static func make(lanAddress: String?) -> GatewayPlan {
        let base = (lanAddress.flatMap(Socks5.ipv4Bytes).map { $0[0] == 172 && $0[1] == 24 } ?? false) ? "10.77" : "172.24"
        return GatewayPlan(network: "\(base).0.0/16", gateway: "\(base).2.1", deviceIP: "\(base).2.50", mask: "255.255.0.0")
    }

    /// go-pcap2socks yapılandırması (yardımcı yazar, root'a ait konumda).
    public func config(socksPort: Int, interfaceAddress: String?) -> String {
        var pcap: [String: Any] = ["network": network, "localIP": gateway]
        if let a = interfaceAddress { pcap["interfaceGateway"] = a }
        let obj: [String: Any] = [
            "pcap": pcap,
            "dns": ["servers": [["address": "local"]]],
            "routing": ["rules": [["dstPort": "53", "outboundTag": "dns-out"], ["dstPort": "80,443", "outboundTag": "zapret"]]],
            "outbounds": [["tag": "", "direct": [String: Any]()], ["tag": "zapret", "socks": ["address": "127.0.0.1:\(socksPort)"]],
                          ["tag": "dns-out", "dns": [String: Any]()]],
            "capture": ["enabled": false],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Araç çıktısındaki "Device <IP> (<MAC>) joined the network" satırlarından cihaz IP'leri (ilk görülme sırasıyla).
    public static func devices(inLog log: String) -> [String] {
        var out: [String] = []
        for line in log.components(separatedBy: .newlines) {
            guard let r = line.range(of: "Device "), line.contains("joined the network") else { continue }
            let ip = line[r.upperBound...].prefix { $0 != " " }
            if Socks5.ipv4Bytes(String(ip)) != nil, !out.contains(String(ip)) { out.append(String(ip)) }
        }
        return out
    }

    public static func mtu(ifconfig: String) -> Int? {
        guard let r = ifconfig.range(of: " mtu ") else { return nil }
        return Int(ifconfig[r.upperBound...].prefix { $0.isNumber })
    }
}
