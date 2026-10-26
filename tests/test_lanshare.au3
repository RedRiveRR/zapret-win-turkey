#include-once
#include "Assert.au3"
#include "..\lib\LanShare.au3"

Func _TestLanShare()
    ; --- Npcap tespiti ---
    _AssertTrue(_LanNpcapState(True, False, ""), "uyumlu mod DLL'i yeterli")
    _AssertTrue(_LanNpcapState(False, True, ""), "System32\Npcap DLL'i yeterli")
    _AssertTrue(_LanNpcapState(False, False, "var"), "sürücü servisi yeterli")
    _AssertFalse(_LanNpcapState(False, False, ""), "hiçbiri yoksa kurulu değil")

    ; --- Alt ağ seçimi ---
    _AssertEq(_LanPickPrefix("192.168.1.34"), "172.24", "ev ağı 192.168: varsayılan 172.24")
    _AssertEq(_LanPickPrefix("172.24.5.10,192.168.56.1"), "10.77", "172.24 kullanılıyorsa 10.77")
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
    Local $s = _LanBuildConfig("172.24.0.0/16", "172.24.2.1", "192.168.1.105")
    _AssertTrue(StringInStr($s, '"network": "172.24.0.0/16", "localIP": "172.24.2.1", "interfaceGateway": "192.168.1.105"') > 0, "kart kendi IP'siyle seçilir")
    _AssertTrue(StringInStr($s, '"dstPort": "53", "outboundTag": "dns-out"') > 0, "DNS bilgisayara yönlenir")
    _AssertTrue(StringInStr(_LanBuildConfig("10.77.0.0/16", "10.77.2.1", ""), "interfaceGateway") = 0, "geçit bilinmiyorsa alan yazılmaz")

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
EndFunc
