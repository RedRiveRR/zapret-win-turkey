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
EndFunc
