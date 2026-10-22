#include-once

; =========================================================================
; --- BLOCKCHECK LOG AYRIŞTIRMA ---
; GUI'ye bağımlı değildir; birim testleri tests/test_blockcheck.au3 içinde.
; =========================================================================

Func _CollectStrategiesFromText($sText, ByRef $aStrategies)
    Local $aLines = StringSplit(StringStripCR($sText), @LF)
    If $aLines[0] < 2 Then Return

    For $i = 2 To $aLines[0]
        If Not StringInStr($aLines[$i], "!!!!! AVAILABLE !!!!!") Then ContinueLoop
        If StringInStr($aLines[$i], "iana.org") Then ContinueLoop

        Local $sPrevLine = $aLines[$i - 1]
        If StringInStr($sPrevLine, "iana.org") Then ContinueLoop

        Local $targetStr = "--wf-tcp-out=443"
        Local $startPos = StringInStr($sPrevLine, $targetStr)
        If $startPos = 0 Then ContinueLoop

        Local $cutPoint = $startPos + StringLen($targetStr)
        Local $sRawStrategy = StringStripWS(StringMid($sPrevLine, $cutPoint), 3)
        If $sRawStrategy = "" Then ContinueLoop

        Local $sStrategy = _FormatStrategyQuotes($sRawStrategy)
        Local $bExists = False
        For $j = 1 To $aStrategies[0]
            If $aStrategies[$j] = $sStrategy Then
                $bExists = True
                ExitLoop
            EndIf
        Next

        If Not $bExists Then
            ReDim $aStrategies[UBound($aStrategies) + 1]
            $aStrategies[0] += 1
            $aStrategies[$aStrategies[0]] = $sStrategy
        EndIf
    Next
EndFunc

Func _FormatStrategyQuotes($sRawStrategy)
    Local $aParams = StringSplit($sRawStrategy, " ", 1)
    Local $sFormattedStrategy = ""
    For $j = 1 To $aParams[0]
        Local $sCurrentParam = $aParams[$j]
        Local $iFirstEq = StringInStr($sCurrentParam, "=")
        If $iFirstEq > 0 Then
            Local $sParamName = StringLeft($sCurrentParam, $iFirstEq)
            Local $sParamValue = StringMid($sCurrentParam, $iFirstEq + 1)
            $sCurrentParam = $sParamName & '"' & $sParamValue & '"'
        EndIf
        $sFormattedStrategy &= $sCurrentParam & " "
    Next
    Return StringStripWS($sFormattedStrategy, 3)
EndFunc

; Log'da (iana.org dışında) çalışan sonuç satırı var ama hiçbir strateji
; çıkarılamadıysa True: blockcheck'in log biçimi değişmiş olabilir.
Func _BlockcheckLooksUnparsed($sLog, $iFound)
    If $iFound > 0 Then Return False
    Local $aLines = StringSplit(StringStripCR($sLog), @LF, 2)
    For $i = 1 To UBound($aLines) - 1
        If Not StringInStr($aLines[$i], "!!!!! AVAILABLE !!!!!") Then ContinueLoop
        If StringInStr($aLines[$i], "iana.org") Or StringInStr($aLines[$i - 1], "iana.org") Then ContinueLoop
        Local $aProbe[1] = [0]
        _CollectStrategiesFromText($aLines[$i - 1] & @LF & $aLines[$i], $aProbe)
        If $aProbe[0] = 0 Then Return True
    Next
    Return False
EndFunc

; Zapret1 blockcheck logundaki son "SUMMARY" bloğunu bulur ve ardından gelen
; satırdaki stratejiyi (--dpi ile başlayan kısım) tırnaklamadan döndürür.
; Bulunamazsa "" döner. SUMMARY son satırdaysa dizi dışına çıkmaz.
Func _ParseSummaryStrategy($sText)
    Local $aLines = StringSplit(StringStripCR($sText), @LF)
    For $i = $aLines[0] To 1 Step -1
        If Not StringInStr($aLines[$i], "SUMMARY") Then ContinueLoop
        If $i + 1 > $aLines[0] Then ContinueLoop
        Local $pos = StringInStr($aLines[$i + 1], "--dpi")
        If $pos > 0 Then Return StringStripWS(StringMid($aLines[$i + 1], $pos), 3)
    Next
    Return ""
EndFunc
