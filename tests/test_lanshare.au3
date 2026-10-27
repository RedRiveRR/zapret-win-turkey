#include-once
#include "Assert.au3"
#include "..\lib\LanShare.au3"

Func _TestLanShare()
    ; --- Npcap tespiti ---
    _AssertEq(_LanNpcapState(True, True, "var"), "var", "uyumlu mod DLL'i: hazır")
    _AssertEq(_LanNpcapState(False, True, "var"), "uyumsuz", "yalnız System32\Npcap: uyumlu mod kapalı")
    _AssertEq(_LanNpcapState(False, False, "var"), "uyumsuz", "yalnız sürücü servisi: uyumlu mod kapalı")
    _AssertEq(_LanNpcapState(False, False, ""), "yok", "hiçbiri yoksa kurulu değil")
    _AssertTrue(StringInStr(_LanNpcapMessage("uyumsuz"), "WinPcap API-compatible") > 0, "uyumsuz mesajı")
    _AssertEq(_LanNpcapMessage("var"), "", "hazırsa mesaj yok")

    ; --- MTU ---
    _AssertEq(_LanParseMtu("Gateway: 172.24.2.1" & @LF & "MTU: 1486"), "1486", "MTU satırı")
    _AssertEq(_LanParseMtu("level=INFO msg=settings mtu=1472"), "1472", "anahtar=değer biçimi")
    _AssertEq(_LanParseMtu("gateway 172.24.2.1"), "", "MTU yoksa boş")
    ; go-pcap2socks'un gerçek çıktısı (2026-10-27 deneme çalıştırması)
    _AssertEq(_LanParseMtu('time=2026-10-27T00:10:50.775+03:00 level=INFO msg="  Gateway:        172.24.2.1"' & @LF & _
            'time=2026-10-27T00:10:50.775+03:00 level=INFO msg="  MTU:            1486 (or lower)"'), "1486", "gerçek çıktıdaki MTU")
    _AssertEq(_LanParseMtu("mtu: 12"), "", "anlamsız değer yok sayılır")

    ; --- Alt ağ seçimi ---
    _AssertEq(_LanPickPrefix("192.168.1.34"), "172.24", "ev ağı 192.168: varsayılan 172.24")
    _AssertEq(_LanPickPrefix("172.24.5.10,192.168.77.1"), "10.77", "172.24 kullanılıyorsa 10.77")
    _AssertEq(_LanPickPrefix("172.24.1.2,10.77.0.5"), "172.29", "ikisi de doluysa 172.29")
    _AssertEq(_LanPickPrefix("172.240.1.1"), "172.24", "172.240 ile 172.24 karışmaz")
    _AssertEq(_LanPickPrefix(""), "172.24", "IP bilinmiyorsa varsayılan")

    ; --- Cihaz ayarları ---
    Local $a = _LanPlan("172.24")
    _AssertEq($a[0], "172.24.0.0/16", "ağ")
    _AssertEq($a[1], "172.24.2.1", "ağ geçidi")
    _AssertEq($a[2], "255.255.0.0", "maske")
    _AssertEq($a[3], "172.24.2.50", "ilk cihaz IP'si")
    _AssertEq(_LanDeviceIP("10.77", 3), "10.77.2.52", "üçüncü cihaz")
    _AssertEq(_LanDeviceIP("10.77", 0), "10.77.2.50", "alt sınır")

    ; --- Yapılandırma ---
    Local $s = _LanBuildConfig("172.24.0.0/16", "172.24.2.1", "192.168.1.50")
    _AssertTrue(StringInStr($s, '"network": "172.24.0.0/16", "localIP": "172.24.2.1", "interfaceGateway": "192.168.1.50"') > 0, "kart kendi IP'siyle seçilir")
    _AssertTrue(StringInStr($s, '"dstPort": "53", "outboundTag": "dns-out"') > 0, "DNS bilgisayara yönlenir")
    _AssertTrue(StringInStr(_LanBuildConfig("10.77.0.0/16", "10.77.2.1", ""), "interfaceGateway") = 0, "geçit bilinmiyorsa alan yazılmaz")
    _AssertTrue(StringInStr(_LanBuildConfig("10.77.0.0/16", "10.77.2.1", "", "127.0.0.1:5354"), '"servers": [ { "address": "127.0.0.1:5354" } ]') > 0, "tek DNS sunucusu")
    _AssertTrue(StringInStr(_LanBuildConfig("10.77.0.0/16", "10.77.2.1", "", "1.1.1.1:53|8.8.8.8:53|local"), _
            '{ "address": "1.1.1.1:53" }, { "address": "8.8.8.8:53" }, { "address": "local" }') > 0, "sıralı DNS listesi")

    ; --- Paylaşım DNS'i ---
    _AssertTrue(_LanPcUsesLocalDns("127.0.0.1,::1"), "DNSCrypt kullanan bilgisayar")
    _AssertFalse(_LanPcUsesLocalDns("1.1.1.1,1.0.0.1"), "Cloudflare DNSCrypt değil")
    _AssertFalse(_LanPcUsesLocalDns("127.0.0.10"), "127.0.0.10 DNSCrypt sayılmaz")
    ; DNSCrypt servisi kurulu ve çalışıyorsa ikinci kopya açılmaz
    _AssertEq(_LanDnsMode(True, True, False), "sistem", "çalışan DNSCrypt servisi kullanılır")
    _AssertEq(_LanDnsMode(True, False, True), "paylasim", "DNSCrypt cevap vermiyorsa paylaşım DNS'i")
    _AssertEq(_LanDnsMode(False, False, True), "paylasim", "DNSCrypt yoksa paylaşım DNS'i")
    _AssertEq(_LanDnsMode(False, False, False), "sifresiz", "hiçbiri yoksa şifresiz")
    _AssertEq(_LanDnsServers("sistem"), "127.0.0.1:53", "sistem DNSCrypt adresi")
    _AssertEq(_LanDnsServers("paylasim"), "127.0.0.1:5354", "paylaşım DNS adresi")
    _AssertEq(_LanDnsServers("sifresiz"), "1.1.1.1:53|8.8.8.8:53|local", "şifresiz yedek")
    _AssertTrue(StringInStr(_LanDnsModeText("sifresiz"), "Discord") > 0, "şifresiz uyarısı")
    Local $sToml = "x = 1" & @LF & "listen_addresses = ['127.0.0.1:53', '[::1]:53']" & @LF & "  cache_file = 'public-resolvers.md'" & @LF & "cache_file = 'relays.md'" & @LF & "# cache_file = 'yorum.md'"
    _AssertEq(_LanDnsProxyToml($sToml, 5354), "x = 1" & @LF & "listen_addresses = ['127.0.0.1:5354']" & @LF & "  cache_file = 'paylasim-public-resolvers.md'" & @LF & _
            "cache_file = 'paylasim-relays.md'" & @LF & "# cache_file = 'yorum.md'", "dinleme adresi ve önbellek dosyaları ayrılır, yorumlar değişmez")
    ; --- Güvenlik duvarı kural sayımı (netsh verbose çıktısı) ---
    Local $sExe = "C:\Program Files\Zapret Windows Turkiye\bin\go-pcap2socks\go-pcap2socks.exe"
    Local $sShow = "Rule Name:   x" & @CRLF & "Direction:   In" & @CRLF & "Program:                              " & $sExe & @CRLF & @CRLF & _
            "Rule Name:   x" & @CRLF & "Direction:   Out" & @CRLF & "Program:                              " & $sExe & @CRLF
    _AssertEq(_LanFirewallRuleCount($sShow, $sExe), 2, "giriş + çıkış kuralı")
    _AssertEq(_LanFirewallRuleCount($sShow & $sShow, $sExe), 4, "yinelenmiş kurallar sayılır")
    _AssertEq(_LanFirewallRuleCount("No rules match the specified criteria.", $sExe), 0, "kural yok")
    _AssertEq(_LanFirewallRuleCount("Rule Name: x" & @CRLF & "Direction: In", $sExe), 0, "verbose olmayan çıktıda Program satırı yok")
    _AssertEq(_LanDnsQuery("a.bc", 0x1234), Binary("0x123401000001000000000000016102626300" & "00010001"), "DNS sorgu paketi")

    ; --- Kart bilgisi ---
    Local $aA = _LanParseAdapter("Wi-Fi|Intel(R) Wi-Fi 6 AX201|192.168.1.1|192.168.1.34,172.20.0.1|Native 802.11|192.168.1.34" & @CRLF)
    _AssertEq($aA[0], "Wi-Fi", "kart adı")
    _AssertEq($aA[1], "192.168.1.1", "ev ağı geçidi")
    _AssertEq($aA[2], "192.168.1.34,172.20.0.1", "IP'ler")
    _AssertTrue($aA[3], "Wi-Fi tanınır")
    _AssertEq($aA[4], "192.168.1.34", "kartın kendi IP'si")
    $aA = _LanParseAdapter("Ethernet|Realtek PCIe GbE|192.168.1.1|192.168.1.20,10.0.0.5|802.3|192.168.1.20,192.168.1.21")
    _AssertFalse($aA[3], "Ethernet Wi-Fi değil")
    _AssertEq($aA[4], "192.168.1.20", "kartta birden fazla IP varsa ilki")
    $aA = _LanParseAdapter("Ethernet|x|192.168.1.1|192.168.1.20|802.3")
    _AssertEq($aA[0], "", "eski biçim (kart IP'si yok) geçersiz")
    $aA = _LanParseAdapter("")
    _AssertEq($aA[0], "", "boş çıktı")

    ; --- Hata nedeni ---
    _AssertTrue(StringInStr(_LanErrorReason("couldn't load wpcap.dll"), "Npcap") > 0, "Npcap hatası")
    _AssertTrue(StringInStr(_LanErrorReason("Failed to setup PCAP capture"), "ağ kartı") > 0, "kart hatası")
    _AssertEq(_LanErrorReason("başka bir şey"), "", "bilinmeyen hata")
    _AssertEq(_LanErrorReason('time=x level=INFO msg="Using ethernet interface" interface=Ethernet'), "", "normal açılış satırı hata sayılmaz")
    _AssertTrue(StringInStr(_LanErrorReason('time=x level=ERROR msg="Failed to setup PCAP capture"'), "ağ kartı") > 0, "hata satırındaki kart sorunu")

    ; --- Bağlı cihazlar (go-pcap2socks satır biçimi; değerler uydurma) ---
    _AssertEq(_LanLogTime('time=2026-01-05T09:15:30.123+03:00 level=INFO msg="x"'), "2026/01/05 09:15:30", "zaman damgası")
    _AssertEq(_LanLogTime("zamansız satır"), "", "zaman yoksa boş")
    Local $aDev[0][5]
    Local $sOut = 'time=2026-01-05T09:15:30.100+03:00 level=INFO msg="Using ethernet interface" interface=Ethernet mac=02:00:00:00:00:aa' & @CRLF & _
            'time=2026-01-05T09:15:30.400+03:00 level=INFO msg="Device 172.24.2.50 (02:00:00:00:00:01) joined the network"' & @CRLF & _
            'time=2026-01-05T09:15:31.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.50:50000 dest=203.0.113.10:443' & @CRLF & _
            'time=2026-01-05T09:15:32.000+03:00 level=INFO msg="[UDP] Connection" source=172.24.2.50:50001 dest=1.1.1.1:53' & @CRLF
    _AssertEq(_LanDevicesUpdate($aDev, $sOut), 1, "bir cihaz katıldı")
    _AssertEq(UBound($aDev), 1, "kart satırı cihaz sayılmaz")
    _AssertEq($aDev[0][0], "172.24.2.50", "cihaz IP'si")
    _AssertEq($aDev[0][1], "2026/01/05 09:15:30", "ilk görülme")
    _AssertEq($aDev[0][2], "2026/01/05 09:15:32", "son etkinlik")
    _AssertEq($aDev[0][3], 2, "bağlantı sayısı (katılma satırı sayılmaz)")
    _AssertEq(_LanDevicesUpdate($aDev, 'time=2026-01-05T09:20:00.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.51:40000 dest=203.0.113.11:443'), 1, _
            "katılma satırı olmadan bağlanan cihaz da görünür")
    _AssertEq(_LanDevicesUpdate($aDev, 'time=2026-01-05T09:21:00.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.50:50002 dest=203.0.113.10:443'), 0, _
            "bilinen cihaz yeni sayılmaz")
    _AssertEq($aDev[0][2], "2026/01/05 09:21:00", "son etkinlik güncellenir")
    _AssertFalse(StringInStr(_WebLanDevicesJson($aDev, "2026/01/05 09:21:30"), "02:00:00") > 0, "MAC adresi JSON'a girmez")
    _AssertEq(_LanDeviceAgo("2026/01/05 09:21:00", "2026/01/05 09:21:30"), "Etkin", "yakın zamanda etkin")
    _AssertEq(_LanDeviceAgo("2026/01/05 09:21:00", "2026/01/05 09:26:10"), "5 dk önce", "dakika önce")
    _AssertEq(_LanDeviceAgo("2026/01/05 09:21:00", "2026/01/05 11:00:00"), "09:21'de", "bir saatten eski")
    _AssertEq(_LanDeviceAgo("", "2026/01/05 11:00:00"), "", "zaman yoksa boş")
    Local $sJ = _WebLanDevicesJson($aDev, "2026/01/05 09:21:30")
    _AssertEq(_WebJsonGet(StringRegExpReplace($sJ, "^\[|,\{.*$", ""), "ip"), "172.24.2.50", "JSON ilk cihaz")
    _AssertTrue(StringInStr($sJ, '"etkin":true') > 0, "etkin bayrağı")
    Local $aBos[0][5]
    _AssertEq(_WebLanDevicesJson($aBos, "2026/01/05 09:21:30"), "[]", "cihaz yoksa boş dizi")

    ; --- Cihaz türü (OUI tablosundan; MAC adresinin geri kalanı uydurma) ---
    Local $sVendors = "# baslik" & @CRLF & "00041F" & @TAB & "PlayStation" & @CRLF & "0009BF" & @TAB & "Nintendo" & @CRLF
    _AssertEq(_LanVendorFromMac("00:04:1f:00:00:01", $sVendors), "PlayStation", "OUI'den üretici")
    _AssertEq(_LanVendorFromMac("00-09-BF-12-34-56", $sVendors), "Nintendo", "tireli yazım")
    _AssertEq(_LanVendorFromMac("00:11:22:33:44:55", $sVendors), "", "tabloda olmayan üretici")
    _AssertTrue(StringInStr(_LanVendorFromMac("02:00:00:00:00:01", $sVendors), "Gizli") = 1, "rastgele (yerel) MAC")
    _AssertTrue(StringInStr(_LanVendorFromMac("DA:A1:19:00:00:01", $sVendors), "Gizli") = 1, "rastgele MAC (x2/x6/xA/xE)")
    _AssertEq(_LanVendorFromMac("00:04:1F", $sVendors), "", "eksik MAC")
    _AssertEq(_LanVendorFromMac("00:04:1f:00:00:01", ""), "", "tablo yoksa boş")
    Local $aK[0][5]
    _LanDevicesUpdate($aK, 'time=2026-01-05T09:15:30.400+03:00 level=INFO msg="Device 172.24.2.60 (00:04:1f:00:00:09) joined the network"', $sVendors)
    _AssertEq($aK[0][4], "PlayStation", "katılma satırından tür")
    _LanDevicesUpdate($aK, 'time=2026-01-05T09:15:40.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.60:1 dest=203.0.113.1:443', $sVendors)
    _AssertEq($aK[0][4], "PlayStation", "bağlantı satırı türü silmez")
    _AssertTrue(StringInStr(_WebLanDevicesJson($aK, "2026/01/05 09:15:50"), '"tur":"PlayStation"') > 0, "JSON'da tür")
    _AssertFalse(StringInStr(_WebLanDevicesJson($aK, "2026/01/05 09:15:50"), "00:04:1f") > 0, "MAC JSON'a girmez")
    _AssertEq(_LanDeviceAgo("2026/01/05 09:21:00", "2026/01/05 09:21:59"), "Etkin", "60 sn içinde etkin")
    _AssertEq(_LanDeviceAgo("2026/01/05 09:21:00", "2026/01/05 09:22:05"), "1 dk önce", "60 sn sonra etkin değil")

    ; --- Kayıt küçültme: bağlantı satırları ve MAC adresleri kalıcı kayıtta kalmaz ---
    Local $sRaw = 'time=2026-01-05T09:00:00.000+03:00 level=INFO msg="Using ethernet interface" interface=Ethernet mac=02:00:00:00:00:aa' & @CRLF & _
            'time=2026-01-05T09:00:01.000+03:00 level=INFO msg="Device 172.24.2.50 (00:04:1f:00:00:01) joined the network"' & @CRLF & _
            'time=2026-01-05T09:00:02.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.50:50000 dest=203.0.113.10:443' & @CRLF & _
            'time=2026-01-05T09:00:03.000+03:00 level=ERROR msg="Failed to setup PCAP capture"' & @CRLF
    Local $sSmall = _LanLogCompact($sRaw)
    _AssertFalse(StringInStr($sSmall, "203.0.113.10") > 0, "hedef adresler silinir")
    _AssertFalse(StringInStr($sSmall, "00:04:1f") > 0, "cihaz MAC'i maskelenir")
    _AssertFalse(StringInStr($sSmall, "02:00:00:00:00:aa") > 0, "kart MAC'i maskelenir")
    _AssertTrue(StringInStr($sSmall, "Device 172.24.2.50") > 0, "katılma satırı kalır")
    _AssertTrue(StringInStr($sSmall, "Failed to setup PCAP capture") > 0, "hata satırı kalır")
    _AssertEq(_LanLogCompact(""), "", "boş kayıt")
    Local $sCRoot = @TempDir & "\zwt-lan-kucult-" & @MSEC
    DirCreate($sCRoot & "\logs")
    FileWrite($sCRoot & $LAN_LOG_REL, $sRaw)
    _AssertTrue(_LanLogCompactFile($sCRoot), "dosya küçültüldü")
    _AssertFalse(StringInStr(FileRead($sCRoot & $LAN_LOG_REL), "Connection") > 0, "dosyada bağlantı satırı kalmadı")
    _AssertFalse(_LanLogCompactFile($sCRoot), "ikinci kez değişmez")
    _AssertEq(_LanLogSize($sCRoot), FileGetSize($sCRoot & $LAN_LOG_REL), "boyut (kapalı dosya)")
    DirRemove($sCRoot, 1)
    _AssertFalse(_LanLogCompactFile($sCRoot), "kayıt yoksa hata vermez")

    ; --- Artımlı okuma: yalnız yeni kısım, yarım satır bekletilir, dosya yenilenince sıfırlanır ---
    Local $sRoot = @TempDir & "\zwt-lan-dev-" & @MSEC
    DirCreate($sRoot & "\logs")
    Local $sLog = $sRoot & $LAN_LOG_REL
    _LanDevicesReset()
    _AssertEq(_LanDevicesPoll($sRoot), 0, "log yokken")
    FileWrite($sLog, 'time=2026-01-05T09:15:30.400+03:00 level=INFO msg="Device 172.24.2.50 (02:00:00:00:00:01) joined the network"' & @LF & _
            'time=2026-01-05T09:15:31.000+03:00 level=INFO msg="[TCP] Connection" source=172.24.2.5')
    _AssertEq(_LanDevicesPoll($sRoot), 1, "ilk cihaz okundu")
    _AssertEq($__g_aLanDevices[0][3], 0, "yarım satır henüz işlenmedi")
    FileWrite($sLog, '0:50000 dest=203.0.113.10:443' & @LF)
    _AssertEq(_LanDevicesPoll($sRoot), 0, "tamamlanan satır yeni cihaz değil")
    _AssertEq($__g_aLanDevices[0][3], 1, "tamamlanan satır işlendi")
    _AssertEq(_LanDevicesPoll($sRoot), 0, "değişiklik yoksa okuma yok")
    FileDelete($sLog)
    FileWrite($sLog, 'time=2026-01-05T10:00:00.000+03:00 level=INFO msg="Device 172.24.2.52 (02:00:00:00:00:03) joined the network"' & @LF)
    _AssertEq(_LanDevicesPoll($sRoot), 1, "yeniden başlayan logda yeni oturum")
    _AssertEq(UBound($__g_aLanDevices), 1, "eski oturumun cihazları silindi")
    _LanDevicesReset()
    DirRemove($sRoot, 1)
EndFunc
