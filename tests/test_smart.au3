#include-once
#include "Assert.au3"
#include "..\lib\SmartAnalysis.au3"

Func _TestSmart()
    ; --- _SmartParseTargets ---
    Local $aT = _SmartParseTargets($SMART_DEFAULT_TARGETS)
    _AssertEq(UBound($aT), 4, "varsayılan 4 hedef")
    _AssertEq($aT[0][0], "gateway.discord.gg", "ilk hedef gateway")
    _AssertEq($aT[0][1], 3, "gateway ağırlığı 3")
    Local $aT2 = _SmartParseTargets(" Discord.com , bozuk host:2, roblox.com:0 ,,cdn.x.com:2.5,a.b.c:1")
    _AssertEq(UBound($aT2), 3, "geçersiz host atlanır, boşluklar silinir")
    _AssertEq($aT2[0][0], "discord.com", "küçük harfe çevrilir")
    _AssertEq($aT2[1][1], 1, "0/eksik ağırlık 1 olur")
    _AssertEq($aT2[2][1], 2.5, "ondalık ağırlık")

    ; --- _SmartProbeCommand ---
    _AssertEq(_SmartProbeCommand("C:\c\curl.exe", "/dev/null", "discord.com", $SMART_TLS12, 3), _
            '"C:\c\curl.exe" -4 -s -o "/dev/null" -m 3 --tlsv1.2 --tls-max 1.2 -w "%{exitcode}|%{http_code}|%{time_total}" https://discord.com/', "TLS 1.2 komutu")
    _AssertTrue(StringInStr(_SmartProbeCommand("c", "NUL", "a.com", $SMART_TLS13, 4), " --tlsv1.3 -w ") > 0, "TLS 1.3 komutu")

    ; --- _SmartParseCurlOutput ---
    Local $fMs
    _AssertTrue(_SmartParseCurlOutput("0|404|0.234" & @CRLF, $fMs), "exit 0 başarılı (HTTP 404 de olsa)")
    _AssertEq(Round($fMs), 234, "süre ms'ye çevrilir")
    _AssertFalse(_SmartParseCurlOutput("35|000|0.051", $fMs), "exit 35 (reset) başarısız")
    _AssertEq($fMs, 0, "başarısızda süre 0")
    _AssertTrue(_SmartParseCurlOutput("|200|0.1", $fMs), "eski curl: exitcode boş, HTTP>0 başarılı")
    _AssertFalse(_SmartParseCurlOutput("|000|3.0", $fMs), "eski curl: HTTP 0 başarısız")
    _AssertFalse(_SmartParseCurlOutput("", $fMs), "boş çıktı başarısız")

    ; --- _SmartComplexity ---
    _AssertEq(_SmartComplexity("--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"), 0, "tek desync, sade")
    _AssertEq(_SmartComplexity("--lua-desync=fake:blob=x:ip_ttl=5:repeats=3 --lua-desync=multisplit:pos=2"), 1.5 + 1 + 1 + 0.5, "çoklu desync + repeats + fake + ttl")

    ; --- _SmartSuccessRatio ---
    Local $aTg[2][2] = [["gateway.discord.gg", 3], ["discord.com", 1]]
    Local $aBl[2] = [True, True]
    Local $aAll[2][4] = [[3, 3, 3, 3], [3, 3, 3, 3]]
    _AssertEq(_SmartSuccessRatio($aAll, $aTg, $aBl), 1, "tamamı başarılı = 1")
    Local $aHalf[2][4] = [[0, 3, 0, 3], [3, 3, 3, 3]]
    _AssertEq(Round(_SmartSuccessRatio($aHalf, $aTg, $aBl), 3), 0.25, "gateway (ağırlık 3) başarısızsa oran 1/4")
    Local $aBl2[2] = [False, True]
    _AssertEq(_SmartSuccessRatio($aHalf, $aTg, $aBl2), 1, "engelsiz hedef (gateway) sayılmaz")
    Local $aOnly12[2][4] = [[3, 3, 0, 3], [3, 3, 0, 3]]
    _AssertEq(Round(_SmartSuccessRatio($aOnly12, $aTg, $aBl), 3), 0.4, "yalnız TLS1.2 geçerse oran 1/(1+1.5)")
    _AssertEq(_SmartSuccessRatio($aOnly12, $aTg, $aBl, True), 0, "TLS1.3 oranı 0")

    ; --- _SmartScore ---
    Local $sSimple = "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
    _AssertEq(_SmartScore(1, 150, $sSimple), 100, "tam başarı + hızlı + sade = 100")
    _AssertEq(_SmartScore(0, 100, $sSimple), 0, "başarısız = 0")
    _AssertTrue(_SmartScore(1, 150, $sSimple) > _SmartScore(1, 900, $sSimple), "hızlı olan önde")
    _AssertTrue(_SmartScore(1, 150, $sSimple) > _SmartScore(1, 150, "--lua-desync=fake:repeats=6 --lua-desync=multisplit"), "sade olan önde")
    _AssertEq(_SmartScore(1, 150, "--lua-desync=oob:x"), 70, "OOB 30 puan ceza alır")
    _AssertTrue(_SmartScore(0.9, 150, $sSimple) > _SmartScore(0.6, 150, $sSimple), "başarı en baskın etken")

    ; --- _SmartAddCandidate ---
    Local $aC[0][2]
    _SmartAddCandidate($aC, '--payload="tls_client_hello" --lua-desync="multidisorder:pos=2:seqovl=1"', "Tarama")
    _SmartAddCandidate($aC, "--payload=tls_client_hello  --lua-desync=multidisorder:pos=2:seqovl=1", "Hazır: Turk Telekom")
    _SmartAddCandidate($aC, "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1", "Hazır: Turk Telekom")
    _SmartAddCandidate($aC, "--lua-desync=fake", "Tarama")
    _SmartAddCandidate($aC, "   ", "Boş")
    _AssertEq(UBound($aC), 2, "tırnak/boşluk farklı tekrarlar birleşir, boşlar atlanır")
    _AssertEq($aC[0][1], "Tarama, Hazır: Turk Telekom", "kaynaklar birleşir, tekrar etmez")

    ; --- _SmartRank ---
    Local $aR[4][$SMART_COL_COUNT]
    __TestSmartRow($aR, 0, "a", 90, 300, 1)
    __TestSmartRow($aR, 1, "b", 80, 200, 2)
    __TestSmartRow($aR, 2, "c", 95, 200, 2)
    __TestSmartRow($aR, 3, "d", 95, 100, 2)
    _SmartRank($aR)
    _AssertEq($aR[0][0] & $aR[1][0] & $aR[2][0] & $aR[3][0], "dcba", "faz 2 önce, sonra puan, eşitlikte düşük gecikme")

    ; --- Kaydet / yükle ---
    Local $sTmp = @TempDir & "\zwt-test-smart.tsv", $sSum
    _AssertTrue(_SmartSaveResults($sTmp, $aR, "özet satırı" & @CRLF & "ikinci"), "sonuçlar kaydedilir")
    Local $aL = _SmartLoadResults($sTmp, $sSum)
    _AssertEq(UBound($aL), 4, "4 satır geri okunur")
    _AssertEq($aL[0][$SMART_COL_SCORE], 95, "puan sayı olarak okunur")
    _AssertTrue(StringInStr($sSum, "özet satırı ikinci") > 0, "özet tek satır olarak saklanır")
    FileDelete($sTmp)
    _AssertEq(UBound(_SmartLoadResults(@TempDir & "\zwt-yok.tsv", $sSum)), 0, "dosya yoksa boş")

    ; --- _SmartEstimateMinutes ---
    _AssertEq(_SmartEstimateMinutes(110), 8, "110 aday ~8 dk")
    _AssertEq(_SmartEstimateMinutes(5), 1, "5 aday ~1 dk")

    ; --- Taban ölçüm motoru (zapret olmadan, gerçek ağ). Yalnızca curl çalıştırır; ağ yoksa da çökmemeli.
    Local $sNull, $sCurl = _SmartFindCurl(@ScriptDir & "\..", $sNull)
    If $sCurl <> "" Then
        Local $aTg1 = _SmartParseTargets("example.com:1")
        Local $aM, $fAvg
        Local $iR = _SmartMeasure("", "", $aTg1, 1, 4, $sCurl, $sNull, "", 0, 1, "", $aM, $fAvg)
        _AssertEq($iR, 1, "bypass'sız ölçüm tamamlanır")
        _AssertEq($aM[0][1] + $aM[0][3], 2, "TLS 1.2 + 1.3 iki deneme yapıldı")
    EndIf
EndFunc

Func __TestSmartRow(ByRef $a, $i, $s, $fScore, $fMs, $iPhase)
    __SmartFillRow($a, $i, $s, "t")
    $a[$i][$SMART_COL_SCORE] = $fScore
    $a[$i][$SMART_COL_MS] = $fMs
    $a[$i][$SMART_COL_PHASE] = $iPhase
EndFunc
