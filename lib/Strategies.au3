#include-once

; =========================================================================
; --- HAZIR ISS STRATEJİLERİ ---
; Stratejiler config\strategies.ini dosyasından okunur ([Zapret2] ve [Zapret1]
; bölümleri, "Profil Adı=parametreler"). Dosya ya da bölüm yoksa aşağıdaki
; gömülü varsayılanlar kullanılır. GUI'ye bağımlı değildir.
; =========================================================================

; Motor için gömülü varsayılan stratejileri [n][2] (ad, parametreler) dizisi olarak döndürür.
Func _StrategyDefaults($sEngine)
    If $sEngine = "Zapret2" Then
        Local $aZ2[7][2] = [ _
                ["Turk Telekom", "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"], _
                ["Superonline", "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"], _
                ["Vodafone", "--payload=tls_client_hello --lua-desync=multisplit:blob=fake_default_tls:ip_ttl=5:pos=2:nodrop:repeats=1"], _
                ["Turksat Kablonet", "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"], _
                ["Telekom Mobil", "--payload=tls_client_hello --lua-desync=fake:blob=0x00000000:ip_ttl=5:repeats=1"], _
                ["Turkcell Mobil", "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"], _
                ["Vodafone Mobil", "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"]]
        Return $aZ2
    EndIf
    Local $aZ1[8][2] = [ _
            ["Turk Telekom", "--dpi-desync=fake --dpi-desync-ttl=4"], _
            ["TT Alternatif", "--dpi-desync=fake --dpi-desync-ttl=3"], _
            ["Superonline", "--dpi-desync=fake --dpi-desync-fooling=md5sig"], _
            ["SOL Alternatif", "--dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-ttl=3"], _
            ["Vodafone", "--dpi-desync=fake,multisplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=1,midsld"], _
            ["Turkcell Mobil", "--dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=3"], _
            ["Vodafone Mobil", "--dpi-desync=multisplit --dpi-desync-split-pos=2"], _
            ["Telekom Mobil", "--dpi-desync=fake --dpi-desync-ttl=5"]]
    Return $aZ1
EndFunc

; Motor için stratejileri INI'den yükler; okunamazsa gömülü varsayılanları döndürür.
; @extended: 1 = INI'den okundu, 0 = varsayılan kullanıldı.
Func _StrategyLoad($sIniPath, $sEngine)
    Local $sSection = ($sEngine = "Zapret2") ? "Zapret2" : "Zapret1"
    Local $aSection = IniReadSection($sIniPath, $sSection)
    If @error Or $aSection[0][0] = 0 Then Return SetExtended(0, _StrategyDefaults($sEngine))

    Local $aOut[$aSection[0][0]][2]
    Local $iCount = 0
    For $i = 1 To $aSection[0][0]
        Local $sName = StringStripWS($aSection[$i][0], 3)
        Local $sValue = StringStripWS($aSection[$i][1], 3)
        ; "|" combo ayırıcısıdır, ada giremez; "Analiz Sonucu" ayrılmış addır.
        If $sName = "" Or $sValue = "" Or StringInStr($sName, "|") Or $sName = "Analiz Sonucu" Then ContinueLoop
        $aOut[$iCount][0] = $sName
        $aOut[$iCount][1] = $sValue
        $iCount += 1
    Next
    If $iCount = 0 Then Return SetExtended(0, _StrategyDefaults($sEngine))
    ReDim $aOut[$iCount][2]
    Return SetExtended(1, $aOut)
EndFunc

; Combo için "Ad1|Ad2|..." biçiminde ad listesi döndürür.
Func _StrategyNames(ByRef $aStrategies)
    Local $sNames = ""
    For $i = 0 To UBound($aStrategies) - 1
        If $sNames <> "" Then $sNames &= "|"
        $sNames &= $aStrategies[$i][0]
    Next
    Return $sNames
EndFunc

; Ada göre strateji parametrelerini döndürür; bulunamazsa "".
Func _StrategyGet(ByRef $aStrategies, $sName)
    For $i = 0 To UBound($aStrategies) - 1
        If $aStrategies[$i][0] == $sName Then Return $aStrategies[$i][1]
    Next
    Return ""
EndFunc

; Adın listede olup olmadığını döndürür.
Func _StrategyExists(ByRef $aStrategies, $sName)
    For $i = 0 To UBound($aStrategies) - 1
        If $aStrategies[$i][0] == $sName Then Return True
    Next
    Return False
EndFunc
