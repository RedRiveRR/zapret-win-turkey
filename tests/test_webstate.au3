#include-once
#include "Assert.au3"
#include "..\lib\WebState.au3"

Func _TestWebState()
    ; --- _WebStatusParts ---
    Local $a = _WebStatusParts("SERVİS MODU AKTİF")
    _AssertEq($a[0], "aktif", "servis modu aktif durumdur")
    _AssertEq($a[2], "Discord'a yol açık", "servis modunda başlık")
    $a = _WebStatusParts("MANUEL MOD AKTİF")
    _AssertEq($a[0], "aktif", "manuel mod aktif durumdur")
    _AssertEq($a[1], "Zapret çalışıyor", "manuel mod rozeti")
    $a = _WebStatusParts("ÇALIŞMAYA HAZIR")
    _AssertEq($a[0], "hazir", "çalışmaya hazır")
    $a = _WebStatusParts("DNS ZEHİRLENMESİ SAPTANDI!")
    _AssertEq($a[0], "hata", "DNS zehirlenmesi hata")
    $a = _WebStatusParts("SERVİS YÜKLÜ - DURDU")
    _AssertEq($a[0], "hata", "durmuş servis hata")
    $a = _WebStatusParts("SERVİS GEÇİCİ DURDURULDU")
    _AssertEq($a[0], "uyari", "geçici durdurma uyarı")
    $a = _WebStatusParts("DNS KONTROL EDİLİYOR...")
    _AssertEq($a[0], "bekliyor", "bilinmeyen durum bekliyor")
    _AssertEq($a[2], "DNS kontrol ediliyor", "bilinmeyen durum başlığı okunur hale gelir")

    ; --- Türkçe harf dönüşümleri ---
    _AssertEq(_WebTrLower("İSTANBUL IŞIK"), "istanbul ışık", "İ->i, I->ı")
    _AssertEq(_WebSentenceCase("İŞLEM SÜRÜYOR"), "İşlem sürüyor", "ilk harf İ korunur")
    _AssertEq(_WebSentenceCase("ISITILIYOR"), "Isıtılıyor", "ilk harf I korunur")
    _AssertEq(_WebSentenceCase("SİSTEM HAZIRLANIYOR"), "Sistem hazırlanıyor", "orta harfler küçülür")
    _AssertEq(_WebLowerFirst("Auto"), "auto", "ilk harf küçülür")

    ; --- _WebStateJson ---
    Local $s = _WebStateJson("SERVİS MODU AKTİF", "▶   Başlat", False, "Analiz Sonucu", "Zapret2 (yeni motor)", "Auto (otomatik liste)", "Onarım: 19:00 sağlıklı")
    _AssertEq(_WebJsonGet($s, "tip"), "durum", "mesaj tipi durum")
    _AssertEq(_WebJsonGet($s, "durum"), "aktif", "durum alanı")
    _AssertEq(_WebJsonGet($s, "calisiyor"), "false", "Başlat yazıyorsa çalışmıyor")
    _AssertEq(_WebJsonGet($s, "dugme"), "false", "düğme kapalı aktarılır")
    _AssertEq(_WebJsonGet($s, "strateji"), "Analiz Sonucu", "strateji adı")
    _AssertEq(_WebJsonGet($s, "stratejiDetay"), "Zapret2 motoru, otomatik site listesi", "motor ve filtre özeti")
    _AssertEq(_WebFilterText("Manuel (hostlist.txt)"), "kendi site listen", "manuel filtre")
    _AssertEq(_WebFilterText("Kapalı (tüm trafik)"), "tüm trafik", "kapalı filtre")
    _AssertEq(_WebFilterText("Filtre Uygulanamaz"), "filtre Uygulanamaz", "bilinmeyen filtre ilk harfi küçülür")
    _AssertEq(_WebJsonGet($s, "onarim"), "Onarım: 19:00 sağlıklı", "onarım durumu")
    $s = _WebStateJson("MANUEL MOD AKTİF", "■   Durdur", True, "Turk Telekom", "Zapret (klasik motor)", "", "")
    _AssertEq(_WebJsonGet($s, "calisiyor"), "true", "Durdur yazıyorsa çalışıyor")
    _AssertEq(_WebJsonGet($s, "stratejiDetay"), "Klasik motor", "filtre yoksa yalnız motor")
    _AssertEq(_WebJsonGet($s, "onarim"), "Servis kurulunca etkinleşir", "servis yoksa onarım açıklaması")

    ; --- Strateji ekranı ---
    _AssertEq(_WebStrategyShort("--filter-tcp=443 --lua-desync=fake:blob=tls --lua-desync=multisplit:pos=1"), "fake + multisplit", "zapret2 yöntemleri")
    _AssertEq(_WebStrategyShort("--dpi-desync=fake,multidisorder --dpi-desync-ttl=5 --new --dpi-desync=fake"), "fake + multidisorder", "klasik yöntemler, tekrarsız")
    _AssertEq(_WebStrategyShort("--wf-tcp=443"), "--wf-tcp=443", "yöntem yoksa metnin kendisi")
    _AssertEq(StringLen(_WebStrategyShort("--x=" & _StringRepeatW("a", 60))), 40, "uzun metin 40 karaktere kısalır")
    _AssertEq(_WebScoreText(99.64), "99,6", "puan virgüllü")
    _AssertEq(_WebScoreText(0), "0,0", "sıfır puan")
    _AssertEq(_WebSmartStatus(0, 2, True), "çalışmadı", "sıfır puan çalışmadı")
    _AssertEq(_WebSmartStatus(80, 1, True), "yalnız eleme", "faz 1")
    _AssertEq(_WebSmartStatus(80, 2, True), "kararlı", "kararlı")
    _AssertEq(_WebSmartStatus(80, 2, False), "dalgalı", "dalgalı")
    _AssertEq(_WebSmartTime("2026-10-23 11:20:05 | 12 aday"), "23.10.2026 11:20", "özet zamanı")
    _AssertEq(_WebSmartTime(""), "", "özet yoksa zaman yok")

    Local $aRows[4][$SMART_COL_COUNT]
    For $i = 0 To 3
        $aRows[$i][$SMART_COL_STRATEGY] = "--lua-desync=s" & $i
        $aRows[$i][$SMART_COL_SCORE] = 90 - $i * 30
        $aRows[$i][$SMART_COL_PHASE] = 2
        $aRows[$i][$SMART_COL_STABLE] = True
    Next
    $s = _WebStrategyJson("Analiz Sonucu|Türk Telekom", "Türk Telekom", "Zapret2 (yeni motor)", "Kapalı (tüm trafik)|Auto (otomatik liste)", _
            "Auto (otomatik liste)", True, False, True, "2026-10-23 11:20:05 | özet", $aRows)
    _AssertEq(_WebJsonGet($s, "tip"), "strateji", "strateji mesajı")
    _AssertEq(_WebJsonGet($s, "secili"), "Türk Telekom", "seçili strateji")
    _AssertEq(_WebJsonGet($s, "filtreAcik"), "false", "filtre kapalı aktarılır")
    _AssertEq(_WebJsonGet($s, "zaman"), "23.10.2026 11:20", "zaman alanı")
    _AssertTrue(StringInStr($s, '"secenekler":["Analiz Sonucu","Türk Telekom"]') > 0, "seçenek dizisi")
    _AssertTrue(StringInStr($s, '"ad":"s2"') > 0, "üçüncü satır gönderilir")
    _AssertTrue(StringInStr($s, '"ad":"s3"') = 0, "en fazla üç satır")
    _AssertTrue(StringInStr($s, '"puan":"30,0","ad":"s2","durum":"kararlı","tam":"--lua-desync=s2","calisti":true') > 0, "satır alanları")
    Local $aNone[0][$SMART_COL_COUNT]
    $s = _WebStrategyJson("", "", "", "", "", False, False, False, "", $aNone)
    _AssertTrue(StringInStr($s, '"sonuclar":[]') > 0, "sonuç yoksa boş dizi")

    ; --- Servis ekranı ---
    Local $aS = _WebServiceParts("", "ÇALIŞMAYA HAZIR")
    _AssertEq($aS[0], "yok", "servis kurulu değil")
    $aS = _WebServiceParts("RUNNING", "SERVİS MODU AKTİF")
    _AssertEq($aS[0], "aktif", "servis çalışıyor")
    _AssertEq($aS[1], "Servis çalışıyor", "çalışan servis başlığı")
    $aS = _WebServiceParts("STOPPED", "SERVİS YÜKLÜ - DURDU")
    _AssertEq($aS[0], "hata", "durmuş servis")
    $aS = _WebServiceParts("STOPPED", "SERVİS GEÇİCİ OLARAK DURDURULDU")
    _AssertEq($aS[0], "uyari", "analiz için durdurma")
    $aS = _WebServiceParts("START_PENDING", "SERVİS MODU AKTİF")
    _AssertEq($aS[0], "uyari", "bekleyen durum")
    _AssertEq(UBound($aS), 3, "üç alan")

    $s = _WebServiceJson("RUNNING", "SERVİS MODU AKTİF", True, False, "Onarım: 19:00 sağlıklı", False, True, True)
    _AssertEq(_WebJsonGet($s, "tip"), "servis", "servis mesajı")
    _AssertEq(_WebJsonGet($s, "kurulu"), "true", "kurulu")
    _AssertEq(_WebJsonGet($s, "onarim"), "true", "onarım açık")
    _AssertEq(_WebJsonGet($s, "yenidenBaslat"), "false", "yeniden başlatma kapalı")
    _AssertEq(_WebJsonGet($s, "onarimNot"), "Son durum: 19:00 sağlıklı", "onarım notu")
    _AssertEq(_WebJsonGet($s, "kurAcik"), "false", "kur düğmesi kapalı")
    _AssertEq(_WebJsonGet($s, "kaldirAcik"), "true", "kaldır düğmesi açık")
    $s = _WebServiceJson("RUNNING", "", False, False, "Onarım: kapalı", False, True, True)
    _AssertEq(_WebJsonGet($s, "onarimNot"), "Kapalı.", "onarım kapalı notu")
    $s = _WebServiceJson("", "", True, False, "", True, False, True)
    _AssertEq(_WebJsonGet($s, "kurulu"), "false", "kurulu değil")
    _AssertEq(_WebJsonGet($s, "onarimNot"), "Servis kurulunca etkinleşir.", "servis yokken onarım notu")

    ; --- DNS ekranı ---
    _AssertEq(_WebDnsMode("127.0.0.1,::1"), "sifreli", "yerel DNSCrypt")
    _AssertEq(_WebDnsMode("1.1.1.1,1.0.0.1,2606:4700:4700::1111"), "cloudflare", "Cloudflare")
    _AssertEq(_WebDnsMode(""), "saglayici", "boş = otomatik")
    _AssertEq(_WebDnsMode("192.168.1.1" & @CRLF), "saglayici", "modem adresi")
    _AssertEq(_WebDnsMode("172.20.0.1"), "saglayici", "172.16/12 özel ağ")
    _AssertEq(_WebDnsMode("172.40.0.1"), "diger", "172.40 özel ağ değil")
    _AssertEq(_WebDnsMode("8.8.8.8,8.8.4.4"), "diger", "başka DNS")
    _AssertEq(_WebDnsIPv4("1.1.1.1,1.0.0.1,2606:4700:4700::1111" & @CRLF), "1.1.1.1, 1.0.0.1", "yalnız IPv4")
    $s = _WebDnsJson("DNS ZEHİRLENMESİ SAPTANDI!", "192.168.1.1", True)
    _AssertEq(_WebJsonGet($s, "durum"), "hata", "zehirli DNS hata")
    _AssertEq(_WebJsonGet($s, "mod"), "saglayici", "mod alanı")
    _AssertEq(_WebJsonGet($s, "degistirAcik"), "true", "değiştirilebilir")
    $s = _WebDnsJson("DNS KONTROL EDİLİYOR...", "?", True)
    _AssertEq(_WebJsonGet($s, "durum"), "bekliyor", "kontrol sürerken bekliyor")
    _AssertEq(_WebJsonGet($s, "degistirAcik"), "false", "sunucular okunmadan değiştirilemez")
    _AssertEq(_WebJsonGet($s, "mod"), "", "okunmamış mod boş")
    $s = _WebDnsJson("SERVİS MODU AKTİF", "1.1.1.1", False)
    _AssertEq(_WebJsonGet($s, "durum"), "aktif", "sorun yok")
    _AssertEq(_WebJsonGet($s, "sunucular"), "1.1.1.1", "sunucular")

    ; --- Diğer ekranı ---
    $s = _WebOtherJson("Ağdaki Cihazlarla Paylaş", True, "1", "4.5.1", "Zapret2 v1.0.5.2", True)
    _AssertEq(_WebJsonGet($s, "tip"), "diger", "diğer mesajı")
    _AssertEq(_WebJsonGet($s, "paylasim"), "false", "paylaşım kapalı")
    _AssertEq(_WebJsonGet($s, "guncelleme"), "true", "güncelleme kontrolü açık")
    _AssertEq(_WebJsonGet($s, "hakkinda"), "Sürüm 4.5.1, Zapret2 motoru 1.0.5.2", "hakkında metni")
    $s = _WebOtherJson("[ ✓ ] Paylaşım Aktif / Durdur", False, "0", "4.5.1", "", False)
    _AssertEq(_WebJsonGet($s, "paylasim"), "true", "paylaşım açık")
    _AssertEq(_WebJsonGet($s, "paylasimAcik"), "false", "paylaşım düğmesi kapalı")
    _AssertEq(_WebJsonGet($s, "guncelleme"), "false", "güncelleme kontrolü kapalı")
    _AssertEq(_WebJsonGet($s, "hakkinda"), "Sürüm 4.5.1", "motor bilinmiyorsa yalnız sürüm")

    ; --- Ağ paylaşımı sayfası ---
    $s = _WebLanJson(True, True, "", "var", "Ethernet", False, "172.24")
    _AssertEq(_WebJsonGet($s, "tip"), "paylasim", "paylaşım mesajı")
    _AssertEq(_WebJsonGet($s, "durum"), "acik", "açık")
    _AssertEq(_WebJsonGet($s, "ip"), "172.24.2.50", "ilk cihaz IP'si")
    _AssertEq(_WebJsonGet($s, "ip2"), "172.24.2.51", "ikinci cihaz IP'si")
    _AssertEq(_WebJsonGet($s, "gecit"), "172.24.2.1", "ağ geçidi")
    _AssertEq(_WebJsonGet($s, "maske"), "255.255.0.0", "maske")
    $s = _WebLanJson(False, False, "Npcap kurulu değil.", "yok", "", False, "")
    _AssertEq(_WebJsonGet($s, "durum"), "hata", "hata durumu")
    _AssertEq(_WebJsonGet($s, "baslatilabilir"), "false", "başlatılamaz")
    _AssertEq(_WebJsonGet($s, "ip"), "", "önek bilinmiyorsa ayar yok")
    $s = _WebLanJson(False, True, "", "", "Wi-Fi", True, "10.77")
    _AssertEq(_WebJsonGet($s, "durum"), "kapali", "kapalı")
    _AssertEq(_WebJsonGet($s, "wifi"), "true", "Wi-Fi")
    _AssertEq(_WebJsonGet($s, "gecit"), "10.77.2.1", "başka önek")
    $s = _WebLanJson(True, True, "", "var", "Ethernet", False, "172.24", "1486")
    _AssertEq(_WebJsonGet($s, "mtu"), "1486", "MTU aktarılır")
EndFunc

Func _StringRepeatW($s, $n)
    Local $r = ""
    For $i = 1 To $n
        $r &= $s
    Next
    Return $r
EndFunc
