#include-once
#include "Assert.au3"
#include "..\lib\Diag.au3"

Func _TestDiag()
    ; --- _PsQuote ---
    _AssertEq(_PsQuote("C:\a b\c"), "'C:\a b\c'", "basit yol tırnaklanır")
    _AssertEq(_PsQuote("C:\Ali'nin\x"), "'C:\Ali''nin\x'", "tek tırnak kaçışlanır")

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
