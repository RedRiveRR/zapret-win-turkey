#include-once
#include "Assert.au3"
#include "..\lib\Strategies.au3"

Func _TestStrategies()
    ; Refactor öncesi combo listeleri (Analiz Sonucu hariç), sıra korunmalı.
    Local $sOldZ2 = "Turk Telekom|Superonline|Vodafone|Turksat Kablonet|Telekom Mobil|Turkcell Mobil|Vodafone Mobil"
    Local $sOldZ1 = "Turk Telekom|TT Alternatif|Superonline|SOL Alternatif|Vodafone|Turkcell Mobil|Vodafone Mobil|Telekom Mobil"

    Local $aD2 = _StrategyDefaults("Zapret2")
    Local $aD1 = _StrategyDefaults("Zapret1")
    _AssertEq(_StrategyNames($aD2), $sOldZ2, "Zapret2 varsayılan ad sırası")
    _AssertEq(_StrategyNames($aD1), $sOldZ1, "Zapret1 varsayılan ad sırası")
    _AssertEq(_StrategyGet($aD2, "Vodafone"), "--payload=tls_client_hello --lua-desync=multisplit:blob=fake_default_tls:ip_ttl=5:pos=2:nodrop:repeats=1", "Zapret2 Vodafone")
    _AssertEq(_StrategyGet($aD1, "SOL Alternatif"), "--dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-ttl=3", "Zapret1 SOL Alternatif")
    _AssertEq(_StrategyGet($aD1, "Yok"), "", "olmayan profil boş döner")
    _AssertEq(_StrategyGet($aD1, "turk telekom"), "", "ad karşılaştırması büyük/küçük harf duyarlı")

    ; Repodaki config\strategies.ini gömülü varsayılanlarla birebir aynı olmalı.
    Local $sRepoIni = @ScriptDir & "\..\config\strategies.ini"
    _AssertTrue(FileExists($sRepoIni), "config\strategies.ini mevcut")
    Local $aI2 = _StrategyLoad($sRepoIni, "Zapret2")
    _AssertEq(@extended, 1, "Zapret2 INI'den okundu")
    _AssertEq(__StrategyDump($aI2), __StrategyDump($aD2), "INI Zapret2 = varsayılan")
    Local $aI1 = _StrategyLoad($sRepoIni, "Zapret1")
    _AssertEq(__StrategyDump($aI1), __StrategyDump($aD1), "INI Zapret1 = varsayılan")

    ; Dosya yoksa varsayılan.
    Local $aMissing = _StrategyLoad(@TempDir & "\zwt-yok-12345.ini", "Zapret1")
    _AssertEq(@extended, 0, "dosya yoksa varsayılan kullanılır")
    _AssertEq(_StrategyNames($aMissing), $sOldZ1, "dosya yoksa varsayılan liste")

    ; Geçersiz satırlar atlanır, kullanıcı profili eklenebilir.
    Local $sTmp = @TempDir & "\zwt-test-strategies.ini"
    FileDelete($sTmp)
    FileWrite($sTmp, "[Zapret2]" & @CRLF & "Benim ISS=--lua-desync=fake" & @CRLF & "Bozuk|Ad=--x" & @CRLF & _
            "Analiz Sonucu=--y" & @CRLF & "Boş Değer=" & @CRLF)
    Local $aCustom = _StrategyLoad($sTmp, "Zapret2")
    _AssertEq(_StrategyNames($aCustom), "Benim ISS", "geçersiz adlar ve boş değerler atlanır")
    Local $aNoZ1 = _StrategyLoad($sTmp, "Zapret1")
    _AssertEq(@extended, 0, "bölüm yoksa varsayılan")
    _AssertEq(UBound($aNoZ1), 8, "bölüm yoksa 8 varsayılan profil")
    FileDelete($sTmp)
EndFunc

Func __StrategyDump(ByRef $a)
    Local $s = ""
    For $i = 0 To UBound($a) - 1
        $s &= $a[$i][0] & "=" & $a[$i][1] & ";"
    Next
    Return $s
EndFunc
