#include-once

; =========================================================================
; Yeni arayüz (WebView2) ile program arasındaki mesajlar için yardımcılar.
; Sayfa düz JSON nesneleri gönderir: {"tip":"komut","ad":"durdur"}.
; GUI'ye bağlı değildir; tests/test_webmsg.au3 ile sınanır.
; =========================================================================

; JSON nesnesinden üst düzey bir alanın değerini döndürür. Metin alanlarında kaçışlar
; çözülür; sayı/true/false/null düz metin olarak döner. Alan yoksa "" ve @error=1.
Func _WebJsonGet($sJson, $sKey)
    Local $sPat = '"' & StringRegExpReplace($sKey, "([\\^$.|?*+()\[\]{}])", "\\$1") & '"\s*:\s*'
    Local $a = StringRegExp($sJson, $sPat & '"((?:[^"\\]|\\.)*)"', 1)
    If Not @error Then Return __WebJsonUnescape($a[0])
    $a = StringRegExp($sJson, $sPat & '(-?[0-9.eE+-]+|true|false|null)', 1)
    If Not @error Then Return $a[0]
    Return SetError(1, 0, "")
EndFunc

; Metni JSON metin değeri olarak (tırnaklarıyla) döndürür.
Func _WebJsonStr($s)
    $s = StringReplace($s, "\", "\\")
    $s = StringReplace($s, '"', '\"')
    $s = StringReplace($s, @CR, "\r")
    $s = StringReplace($s, @LF, "\n")
    $s = StringReplace($s, @TAB, "\t")
    ; Diğer denetim karakterleri
    Local $sOut = ""
    For $i = 1 To StringLen($s)
        Local $c = StringMid($s, $i, 1)
        If AscW($c) < 0x20 Then
            $sOut &= "\u" & StringLower(Hex(AscW($c), 4))
        Else
            $sOut &= $c
        EndIf
    Next
    Return '"' & $sOut & '"'
EndFunc

; Anahtar/değer çiftlerinden JSON nesnesi kurar: _WebJsonObj("tip", "durum", "mod", "Servis")
; Değer sayı veya Boolean ise tırnaksız yazılır.
Func _WebJsonObj($k1, $v1, $k2 = Default, $v2 = Default, $k3 = Default, $v3 = Default, $k4 = Default, $v4 = Default, _
        $k5 = Default, $v5 = Default, $k6 = Default, $v6 = Default)
    Local $aK[6] = [$k1, $k2, $k3, $k4, $k5, $k6]
    Local $aV[6] = [$v1, $v2, $v3, $v4, $v5, $v6]
    Local $s = ""
    For $i = 0 To 5
        If $aK[$i] = Default Then ExitLoop
        If $s <> "" Then $s &= ","
        $s &= _WebJsonStr($aK[$i]) & ":" & __WebJsonValue($aV[$i])
    Next
    Return "{" & $s & "}"
EndFunc

; Yerel dosya yolunu WebView2'nin açabileceği file:/// adresine çevirir
; (boşluk, # , % ve ASCII dışı karakterler yüzde kodlanır).
Func _WebFileUrl($sPath)
    Local $b = StringToBinary(StringReplace($sPath, "\", "/"), 4) ; UTF-8
    Local $sOut = ""
    For $i = 1 To BinaryLen($b)
        Local $n = Number(BinaryMid($b, $i, 1))
        Local $c = Chr($n)
        If ($n >= 0x30 And $n <= 0x39) Or ($n >= 0x41 And $n <= 0x5A) Or ($n >= 0x61 And $n <= 0x7A) Or StringInStr("/:-_.~", $c, 1) Then
            $sOut &= $c
        Else
            $sOut &= "%" & Hex($n, 2)
        EndIf
    Next
    Return "file:///" & $sOut
EndFunc

Func __WebJsonValue($v)
    If IsBool($v) Then Return $v ? "true" : "false"
    If IsNumber($v) Then Return String($v)
    Return _WebJsonStr(String($v))
EndFunc

Func __WebJsonUnescape($s)
    If Not StringInStr($s, "\") Then Return $s
    Local $sOut = "", $i = 1, $n = StringLen($s)
    While $i <= $n
        Local $c = StringMid($s, $i, 1)
        If $c <> "\" Or $i = $n Then
            $sOut &= $c
            $i += 1
            ContinueLoop
        EndIf
        Local $e = StringMid($s, $i + 1, 1)
        Switch $e
            Case "n"
                $sOut &= @LF
            Case "r"
                $sOut &= @CR
            Case "t"
                $sOut &= @TAB
            Case "b"
                $sOut &= Chr(8)
            Case "f"
                $sOut &= Chr(12)
            Case "u"
                $sOut &= ChrW(Dec(StringMid($s, $i + 2, 4)))
                $i += 4
            Case Else ; \" \\ \/
                $sOut &= $e
        EndSwitch
        $i += 2
    WEnd
    Return $sOut
EndFunc
