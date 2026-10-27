#include-once
#include "Assert.au3"
#include "..\lib\Update.au3"
#include "..\lib\SelfUpdate.au3"
#include "..\lib\Version.au3"

Func _TestUpdate()
    ; --- _VersionCompare ---
    _AssertEq(_VersionCompare("v4.6", "4.5"), 1, "v4.6 > 4.5")
    _AssertEq(_VersionCompare("4.5", "v4.5"), 0, "baştaki v yok sayılır")
    _AssertEq(_VersionCompare("4.5", "4.5.0"), 0, "eksik bölüm 0 sayılır")
    _AssertEq(_VersionCompare("3.8.1", "3.8"), 1, "3.8.1 > 3.8")
    _AssertEq(_VersionCompare("4.10", "4.9"), 1, "sayısal karşılaştırma (4.10 > 4.9)")
    _AssertEq(_VersionCompare("4.2", "4.5"), -1, "4.2 < 4.5")
    _AssertEq(_VersionCompare("v4.6-beta", "4.6"), 0, "ön ek/son ek sayıları etkilemez")

    ; --- _IsVersionTag ---
    _AssertTrue(_IsVersionTag("v4.6"), "v4.6 geçerli")
    _AssertTrue(_IsVersionTag("3.8.1"), "3.8.1 geçerli")
    _AssertTrue(_IsVersionTag(" v4.6 " & @CRLF), "boşluklu etiket geçerli")
    _AssertFalse(_IsVersionTag(""), "boş geçersiz")
    _AssertFalse(_IsVersionTag("Not Found"), "hata metni geçersiz")
    _AssertFalse(_IsVersionTag("<html>"), "HTML geçersiz")

    ; --- Fork kendi sürümlerine bakmalı (upstream'e yönlendirmek geliştirmeleri kaybettirir) ---
    _AssertEq($APP_UPDATE_REPO, "RedRiveRR/zapret-win-turkey", "güncelleme kontrolü fork'a bakar")
    _AssertTrue(StringInStr($APP_RELEASES_URL, "RedRiveRR/") > 0, "indirme sayfası fork'un sürümleri")
    _AssertTrue(_IsVersionTag("v4.5.1-fork"), "fork etiket biçimi geçerli")
    _AssertEq(_VersionCompare("v4.5.1-fork", "4.5"), 1, "v4.5.1-fork > 4.5")
    _AssertTrue(_IsVersionTag("v4.5.1-RedRiveRR"), "takma adlı etiket geçerli")
    _AssertEq(_VersionCompare("v" & $APP_VERSION, $APP_VERSION), 0, "kendi sürümünde bildirim yok")
    _AssertEq(_VersionCompare("v4.5.1-RedRiveRR", $APP_VERSION), -1, "eski taslak etiketi bildirilmez")
    _AssertEq(_VersionCompare("v" & (Int(StringLeft($APP_VERSION, StringInStr($APP_VERSION, ".") - 1)) + 1) & ".0.0", $APP_VERSION), 1, "sonraki sürüm bildirilir")

    ; --- _UpdatePoll: sorgu başlatılmadıysa boş ---
    _AssertEq(_UpdatePoll("4.5"), "", "başlatılmamış sorgu boş döner")
    ; --- Güncelleme sorgusu başarısızlık metni ---
    _AssertEq(_UpdateFailText("HATA 404"), "henüz yayınlanmış sürüm yok", "404: yayınlanmış sürüm yok")
    _AssertEq(_UpdateFailText("HATA 0"), "GitHub'a ulaşılamadı (bağlantı yok)", "bağlantı yok")
    _AssertEq(_UpdateFailText("HATA 403"), "GitHub'a ulaşılamadı (HTTP 403)", "HTTP hata kodu")
    _AssertEq(_UpdateFailText(""), "sürüm bilgisi alınamadı", "boş çıktı")
    _AssertTrue(_IsVersionTag("v4.5.1-RedRiveRR"), "fork sürüm etiketi geçerli")
    _AssertEq(_VersionCompare("v4.5.1-RedRiveRR", "4.5.1"), 0, "fork etiketi aynı sürüm sayılır")
    ; --- Kendini güncelleme (saf parçalar; değerler uydurma) ---
    _AssertEq(_UpdateAssetName("v5.2.0"), "RedRiveRR-Zapret-v5.2.0.zip", "ana paket adı")
    _AssertEq(_UpdateAssetName("v5.2.0", True), "RedRiveRR-Zapret-Lite-v5.2.0.zip", "lite paket adı")
    Local $sH1 = "9070808fe5b045993fc7000d1ed2699489ca356bb6fd6306efdd378e0ed2d5f6"
    Local $sSums = $sH1 & "  RedRiveRR-Zapret-v5.2.0.zip" & @LF & StringUpper("aa" & StringTrimLeft($sH1, 2)) & "  RedRiveRR-Zapret-Lite-v5.2.0.zip" & @LF
    _AssertEq(_UpdateSumFor($sSums, "RedRiveRR-Zapret-v5.2.0.zip"), $sH1, "özet bulunur")
    _AssertEq(_UpdateSumFor($sSums, "RedRiveRR-Zapret-Lite-v5.2.0.zip"), "aa" & StringTrimLeft($sH1, 2), "büyük harfli özet küçültülür")
    _AssertEq(_UpdateSumFor($sSums, "RedRiveRR-Zapret-v5.2.zip"), "", "benzer ad eşleşmez")
    _AssertEq(_UpdateSumFor("bozuk satır", "x.zip"), "", "bozuk dosya")
    Local $sRepo = "RedRiveRR/zapret-win-turkey"
    _AssertTrue(_UpdateUrlAllowed("https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/RedRiveRR-Zapret-v5.2.0.zip", $sRepo), "kendi release adresi")
    _AssertFalse(_UpdateUrlAllowed("https://github.com/baskasi/zapret-win-turkey/releases/download/v5.2.0/x.zip", $sRepo), "başka depo")
    _AssertFalse(_UpdateUrlAllowed("http://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/x.zip", $sRepo), "https olmayan")
    _AssertFalse(_UpdateUrlAllowed("https://github.com.kotu.example/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/x.zip", $sRepo), "sahte alan adı")
    _AssertFalse(_UpdateUrlAllowed("https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/../x.zip", $sRepo), "üst klasöre çıkış")
    Local $sJson = '{"assets":[{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/SHA256SUMS.txt"},' & _
            '{"name":"RedRiveRR-Zapret-v5.2.0.zip","browser_download_url":"https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/RedRiveRR-Zapret-v5.2.0.zip"}]}'
    _AssertEq(_UpdateAssetUrl($sJson, "RedRiveRR-Zapret-v5.2.0.zip"), "https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/RedRiveRR-Zapret-v5.2.0.zip", "JSON'dan paket adresi")
    _AssertEq(_UpdateAssetUrl($sJson, "SHA256SUMS.txt"), "https://github.com/RedRiveRR/zapret-win-turkey/releases/download/v5.2.0/SHA256SUMS.txt", "JSON'dan özet adresi")
    _AssertEq(_UpdateAssetUrl($sJson, "RedRiveRR-Zapret-Lite-v5.2.0.zip"), "", "olmayan dosya")
    _AssertTrue(StringInStr(_UpdateTempDir("v5.2.0"), "zwt-guncelleme-v5.2.0") > 0, "geçici klasör adı")
    _AssertFalse(StringInStr(_UpdateTempDir("v5/../x"), "/") > 0, "etiket klasör adına güvenli çevrilir")
EndFunc
