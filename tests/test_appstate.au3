#include-once
#include "Assert.au3"
#include "..\lib\AppState.au3"

Func _TestAppState()
    Local $sOld = _StateStatus()
    _AssertEq($sOld, "SİSTEM HAZIRLANIYOR...", "açılış durumu")
    _StateSetStatus("SERVİS MODU AKTİF")
    _AssertEq(_StateStatus(), "SERVİS MODU AKTİF", "durum yazılır ve okunur")
    _StateSetStatus(5)
    _AssertEq(_StateStatus(), "5", "durum metne çevrilir")
    _StateSetStatus($sOld)

    _AssertFalse(_StateLanOn(), "paylaşım başlangıçta kapalı")
    _StateSetLanOn(True)
    _AssertTrue(_StateLanOn(), "paylaşım açık")
    _StateSetLanOn(1)
    _AssertTrue(_StateLanOn(), "sayı 1 açık sayılır")
    _StateSetLanOn("evet")
    _AssertFalse(_StateLanOn(), "yalnız True/1 açık sayılır")
    _StateSetLanOn(False)
    _AssertFalse(_StateLanOn(), "paylaşım kapalı")
EndFunc
