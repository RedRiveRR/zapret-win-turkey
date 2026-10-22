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

    ; Gerçek tarama çökmeden dizi döndürür. (Yalnızca okur; hiçbir şeyi kapatmaz.)
    Local $aScan = _ConflictScan($sOur)
    _AssertTrue(IsArray($aScan), "tarama dizi döndürür")

    ; --- _ServiceExePath ---
    _AssertEq(_ServiceExePath('"C:\Users\a b\zapret\bin\zapret\zapret-winws\winws2.exe" --wf-l3=ipv4 --lua-init="@C:\x.lua"'), _
            "C:\Users\a b\zapret\bin\zapret\zapret-winws\winws2.exe", "tırnaklı yol")
    _AssertEq(_ServiceExePath("C:\Users\a b\zapret\bin\dnscrypt-proxy\dnscrypt-proxy.exe -config dnscrypt-proxy.toml"), _
            "C:\Users\a b\zapret\bin\dnscrypt-proxy\dnscrypt-proxy.exe", "tırnaksız, boşluklu yol + argüman")
    _AssertEq(_ServiceExePath("C:\x\svc.EXE"), "C:\x\svc.EXE", "argümansız")
    _AssertEq(_ServiceExePath('"C:\yarım'), "C:\yarım", "kapanmamış tırnak çökmez")
    _AssertEq(_ServiceExePath(Null), "", "Null PathName")

    ; --- _ForeignServiceScan: yalnızca okur. _HandleForeignServices testte ASLA çağrılmaz
    ; (geliştirme makinesindeki canlı kurulumun servislerini kaldırır).
    Local $aSvc = _ForeignServiceScan($sOur)
    _AssertTrue(IsArray($aSvc), "servis taraması dizi döndürür")
    If IsArray($aSvc) And UBound($aSvc) > 0 Then _AssertEq(UBound($aSvc, 2), 2, "servis satırı 2 sütunlu")
EndFunc
