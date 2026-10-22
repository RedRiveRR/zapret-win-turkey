#include-once
#include "Assert.au3"
#include "..\lib\Log.au3"

Func _TestLog()
    ; --- _LogFormatLine ---
    _AssertEq(_LogFormatLine("BILGI", "Zapret başlatıldı", "2026-10-22 21:00:00"), "2026-10-22 21:00:00 [BILGI] Zapret başlatıldı", "satır biçimi")
    _AssertEq(_LogFormatLine("HATA", "satır1" & @CRLF & "satır2" & @LF & @LF & "satır3", "T"), "T [HATA] satır1 | satır2 | satır3", "çok satırlı mesaj tek satıra iner")
    _AssertEq(_LogFormatLine("UYARI", "  boşluklu  " & @CRLF, "T"), "T [UYARI] boşluklu", "baş/son boşluk ve satır sonu atılır")

    ; --- _LogInit / _Log ---
    Local $sDir = @TempDir & "\zwt-test-logs"
    DirRemove($sDir, 1)
    Local $sPath = $sDir & "\app.log"
    _LogInit($sPath)
    _AssertTrue(FileExists($sDir), "log klasörü oluşturulur")
    _LogInfo("ilk satır")
    _LogError("ikinci" & @CRLF & "satır")
    Local $aLines = StringSplit(StringStripWS(FileRead($sPath), 2), @CRLF, 1)
    _AssertEq($aLines[0], 2, "iki satır yazıldı")
    _AssertTrue(StringRegExp($aLines[1], "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[BILGI\] ilk satır$"), "zaman damgalı BILGI satırı")
    _AssertTrue(StringInStr($aLines[2], "[HATA] ikinci | satır") > 0, "HATA satırı")

    ; --- _LogRotateIfNeeded ---
    _AssertFalse(_LogRotateIfNeeded($sPath, 1024 * 1024), "küçük dosya döndürülmez")
    _AssertTrue(_LogRotateIfNeeded($sPath, 10), "büyük dosya döndürülür")
    _AssertTrue(FileExists($sPath & ".1") And Not FileExists($sPath), "app.log.1 oluşur, app.log boşalır")
    _AssertFalse(_LogRotateIfNeeded($sDir & "\yok.log", 10), "olmayan dosya döndürülmez")

    ; Başlatılmamış log çökmez.
    $__g_sLogPath = ""
    _LogInfo("yazılmamalı")
    _AssertFalse(FileExists($sPath), "başlatılmamışken yazılmaz")
    DirRemove($sDir, 1)
EndFunc
