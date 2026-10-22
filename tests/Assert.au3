#include-once

Global $__g_iTestPass = 0
Global $__g_iTestFail = 0

; Konsola UTF-8 bayt olarak yaz; AutoIt varsayılan olarak ANSI yazar ve Türkçe karakterler bozulur.
Func _TestOut($sText)
    ConsoleWrite(BinaryToString(StringToBinary($sText, 4), 1))
EndFunc

Func _AssertEq($vActual, $vExpected, $sName)
    If $vActual == $vExpected Then
        $__g_iTestPass += 1
    Else
        $__g_iTestFail += 1
        _TestOut("FAIL: " & $sName & @CRLF & "   beklenen: [" & $vExpected & "]" & @CRLF & "   gelen:    [" & $vActual & "]" & @CRLF)
    EndIf
EndFunc

Func _AssertTrue($bValue, $sName)
    _AssertEq($bValue ? "True" : "False", "True", $sName)
EndFunc

Func _AssertFalse($bValue, $sName)
    _AssertEq($bValue ? "True" : "False", "False", $sName)
EndFunc

Func _AssertSummary()
    _TestOut(@CRLF & "Sonuç: " & $__g_iTestPass & " geçti, " & $__g_iTestFail & " başarısız" & @CRLF)
    Return ($__g_iTestFail = 0) ? 0 : 1
EndFunc
