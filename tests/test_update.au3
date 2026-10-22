#include-once
#include "Assert.au3"
#include "..\lib\Update.au3"

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

    ; --- _UpdatePoll: sorgu başlatılmadıysa boş ---
    _AssertEq(_UpdatePoll("4.5"), "", "başlatılmamış sorgu boş döner")
EndFunc
