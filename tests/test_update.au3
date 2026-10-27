#include-once
#include "Assert.au3"
#include "..\lib\Update.au3"
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
EndFunc
