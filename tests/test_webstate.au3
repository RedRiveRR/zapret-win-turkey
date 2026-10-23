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
EndFunc

Func _StringRepeatW($s, $n)
    Local $r = ""
    For $i = 1 To $n
        $r &= $s
    Next
    Return $r
EndFunc
