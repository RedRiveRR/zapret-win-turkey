#include-once
#include "Assert.au3"
#include "..\lib\Diag.au3"

Func _TestDiag()
    ; --- _PsQuote ---
    _AssertEq(_PsQuote("C:\a b\c"), "'C:\a b\c'", "basit yol tırnaklanır")
    _AssertEq(_PsQuote("C:\Ali'nin\x"), "'C:\Ali''nin\x'", "tek tırnak kaçışlanır")

    ; --- _DiagRedact: pakete giren metinde kişisel bilgiler maskelenir (değerler uydurma) ---
    _AssertEq(_DiagRedact("kart IP 192.168.1.50, ev ağı geçidi 192.168.1.1", "Ali"), "kart IP 192.168.x.x, ev ağı geçidi 192.168.x.x", "ev ağı IP'si")
    _AssertEq(_DiagRedact("10.0.0.7 ve 172.20.3.4", "Ali"), "10.x.x.x ve 172.20.x.x", "diğer özel aralıklar")
    _AssertEq(_DiagRedact("DNS 1.1.1.1 -> 162.159.136.232", "Ali"), "DNS 1.1.1.1 -> 162.159.136.232", "genel adresler kalır")
    _AssertEq(_DiagRedact("172.32.0.1 özel değil", "Ali"), "172.32.0.1 özel değil", "172.32 özel aralıkta değil")
    _AssertEq(_DiagRedact("mac=02:00:00:aa:bb:cc", "Ali"), "mac=xx:xx:xx:xx:xx:xx", "MAC")
    _AssertEq(_DiagRedact("DNS 2001:db8:10::53, fe80::1%12", "Ali"), "DNS <ipv6>, <ipv6>", "IPv6")
    _AssertEq(_DiagRedact("2026-10-27 14:58:54 [BILGI] x", "Ali"), "2026-10-27 14:58:54 [BILGI] x", "saat korunur")
    _AssertEq(_DiagRedact("time=2026-01-05T09:15:30.400+03:00", "Ali"), "time=2026-01-05T09:15:30.400+03:00", "zaman damgası korunur")
    _AssertEq(_DiagRedact('--lua-desync="multidisorder:pos=2,midsld:seqovl=1"', "Ali"), '--lua-desync="multidisorder:pos=2,midsld:seqovl=1"', "strateji korunur")
    _AssertEq(_DiagRedact("C:\Users\Ali\Desktop\x.log", "Ali"), "C:\Users\<kullanıcı>\Desktop\x.log", "kullanıcı adı")
    _AssertEq(_DiagRedact("C:\Users\Alican\x", "Ali"), "C:\Users\Alican\x", "benzer ad değişmez")
    _AssertEq(_DiagRedact("Zapret2 v1.0.5.2", "Ali"), "Zapret2 v1.0.5.2", "sürüm numarası korunur")

    ; --- _DiagCandidateFiles ---
    Local $sRoot = @TempDir & "\zwt-test-diag-root"
    DirRemove($sRoot, 1)
    DirCreate($sRoot & "\logs")
    DirCreate($sRoot & "\config")
    FileWrite($sRoot & "\logs\app.log", "x")
    FileWrite($sRoot & "\config\config.ini", "[Settings]")
    FileWrite($sRoot & "\config\autohostlist.txt", "ozel-site.com")
    Local $aFiles = _DiagCandidateFiles($sRoot)
    _AssertEq(UBound($aFiles), 2, "yalnızca mevcut aday dosyalar")
    Local $sJoined = ""
    For $s In $aFiles
        $sJoined &= $s & ";"
    Next
    _AssertEq($sJoined, "logs\app.log;config\config.ini;", "aday dosyalar sırayla")
    _AssertFalse(StringInStr($DIAG_FILES, "autohostlist") > 0, "autohostlist (gizlilik) aday listesinde yok")

    ; --- _DiagCreateBundle (gerçek ZIP) ---
    Local $sZip = @TempDir & "\zwt-test-diag.zip"
    _AssertTrue(_DiagCreateBundle($sRoot, $sZip), "ZIP oluşturulur")
    _AssertTrue(FileGetSize($sZip) > 0, "ZIP boş değil")
    FileDelete($sZip)
    DirRemove($sRoot, 1)
EndFunc
