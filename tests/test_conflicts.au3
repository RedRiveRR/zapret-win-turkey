#include-once
#include "Assert.au3"
#include "..\lib\Conflicts.au3"

Func _TestConflicts()
    Local $sOur = "C:\Apps\zapret-win-turkey"
    Local $sDesc

    _AssertEq(_ConflictClassify("goodbyedpi.exe", "C:\x\goodbyedpi.exe", $sOur, $sDesc), $CONFLICT_BLOCKING, "GoodbyeDPI engelleyici")
    _AssertEq($sDesc, "GoodbyeDPI", "GoodbyeDPI açıklaması")
    _AssertEq(_ConflictClassify("GoodbyeDPI.EXE", "", $sOur, $sDesc), $CONFLICT_BLOCKING, "ad büyük/küçük harf duyarsız")
    _AssertEq(_ConflictClassify("ciadpi.exe", "C:\byedpi\ciadpi.exe", $sOur, $sDesc), $CONFLICT_BLOCKING, "ByeDPI engelleyici")

    _AssertEq(_ConflictClassify("winws2.exe", $sOur & "\bin\zapret\zapret-winws\winws2.exe", $sOur, $sDesc), $CONFLICT_NONE, "kendi winws2 çakışma değil")
    _AssertEq(_ConflictClassify("winws.exe", "C:\zapret-discord-youtube\bin\winws.exe", $sOur, $sDesc), $CONFLICT_BLOCKING, "başka klasördeki winws engelleyici")
    _AssertTrue(StringInStr($sDesc, "C:\zapret-discord-youtube\bin\winws.exe") > 0, "açıklamada yabancı yol var")
    _AssertEq(_ConflictClassify("winws.exe", "C:\Apps\zapret-win-turkey-eski\winws.exe", $sOur, $sDesc), $CONFLICT_BLOCKING, "benzer önekli kardeş klasör yabancı sayılır")
    _AssertEq(_ConflictClassify("winws.exe", Null, $sOur, $sDesc), $CONFLICT_NONE, "yolu okunamayan winws çakışma sayılmaz")

    _AssertEq(_ConflictClassify("warp-svc.exe", "C:\Program Files\Cloudflare\warp-svc.exe", $sOur, $sDesc), $CONFLICT_INFO, "WARP yalnızca bilgi")
    _AssertEq(_ConflictClassify("explorer.exe", "C:\Windows\explorer.exe", $sOur, $sDesc), $CONFLICT_NONE, "ilgisiz süreç")
    _AssertEq($sDesc, "", "ilgisiz süreçte açıklama boş")

    ; Gerçek tarama çökmeden boş/dizi döndürür (test makinesinde çakışan araç olmamalı).
    Local $aScan = _ConflictScan($sOur)
    _AssertTrue(IsArray($aScan), "tarama dizi döndürür")
EndFunc
