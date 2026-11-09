#include-once

; =========================================================================
; --- BLOCKCHECK LOG AYRIŞTIRMA ---
; GUI'ye bağımlı değildir; birim testleri tests/test_blockcheck.au3 içinde.
; =========================================================================

; Analizde denenen alan adları (blockcheck DOMAINS ortam değişkeni). Paketteki blockcheck betikleri
; varsayılan olarak yalnız roblox.com'u dener; Roblox açık, Discord engelli hatlarda analiz
; "engel yok" deyip bitiyordu (H38). Engelsiz hedef birkaç saniyede geçilir.
Global Const $BLOCKCHECK_DOMAINS = "discord.com roblox.com"

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
        ; Engelsiz hedef: zapret'siz deneme başarılı (strateji satırı yoktur).
        If StringInStr($aLines[$i - 1], "checking without DPI bypass") Then ContinueLoop
        Local $aProbe[1] = [0]
        _CollectStrategiesFromText($aLines[$i - 1] & @LF & $aLines[$i], $aProbe)
        If $aProbe[0] = 0 Then Return True
    Next
    Return False
EndFunc

; SUMMARY'de denenen her alan adı için "working without bypass" satırı varsa True (gerçekten engel yok).
; Biçimler: Zapret2 "curl_test_https_tls12 ipv4 roblox.com : ...", Zapret1 "ipv4 roblox.com curl_test_https_tls12 : ...".
Func _BlockcheckNoBypassNeeded($sLog, $sDomains)
    Local $aDomains = StringSplit(StringStripWS($sDomains, 7), " ", 2)
    Local $aLines = StringSplit(StringStripCR($sLog), @LF, 2)
    For $sDom In $aDomains
        If $sDom = "" Then Return False
        Local $bFree = False
        For $sLine In $aLines
            If Not StringInStr($sLine, ": working without bypass") Then ContinueLoop
            If StringInStr(" " & StringStripWS($sLine, 7) & " ", " " & $sDom & " ") Then
                $bFree = True
                ExitLoop
            EndIf
        Next
        If Not $bFree Then Return False
    Next
    Return True
EndFunc

; Zapret1 blockcheck logundaki son "SUMMARY" bloğunda (boş satıra kadar) ilk stratejiyi
; (--dpi ile başlayan kısım) tırnaklamadan döndürür. Birden çok alan adında ilk satır engelsiz
; hedef olabilir (H38). Bulunamazsa "" döner.
Func _ParseSummaryStrategy($sText)
    Local $aLines = StringSplit(StringStripCR($sText), @LF)
    For $i = $aLines[0] To 1 Step -1
        If Not StringInStr($aLines[$i], "SUMMARY") Then ContinueLoop
        For $j = $i + 1 To $aLines[0]
            If StringStripWS($aLines[$j], 8) = "" Then ExitLoop
            Local $pos = StringInStr($aLines[$j], "--dpi")
            If $pos > 0 Then Return StringStripWS(StringMid($aLines[$j], $pos), 3)
        Next
    Next
    Return ""
EndFunc
