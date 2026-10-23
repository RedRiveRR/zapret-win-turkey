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
    _AssertEq(_WebJsonGet($s, "stratejiDetay"), "Zapret2 motoru, auto filtre", "motor ve filtre özeti")
    _AssertEq(_WebJsonGet($s, "onarim"), "Onarım: 19:00 sağlıklı", "onarım durumu")
    $s = _WebStateJson("MANUEL MOD AKTİF", "■   Durdur", True, "Turk Telekom", "Zapret (klasik motor)", "", "")
    _AssertEq(_WebJsonGet($s, "calisiyor"), "true", "Durdur yazıyorsa çalışıyor")
    _AssertEq(_WebJsonGet($s, "stratejiDetay"), "Klasik motor", "filtre yoksa yalnız motor")
    _AssertEq(_WebJsonGet($s, "onarim"), "Servis kurulunca etkinleşir", "servis yoksa onarım açıklaması")
EndFunc
