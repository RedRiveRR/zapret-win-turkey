#include-once
#include "Assert.au3"
#include "..\lib\Health.au3"
#include "..\lib\Schedule.au3"

Func _TestHealth()
    Local $sBin = '"C:\Z\bin\zapret\zapret-winws\winws2.exe" --wf-l3=ipv4 --hostlist-exclude="C:\Z\config\excludelist.txt" ' & _
            '--payload="tls_client_hello" --lua-desync="multidisorder:pos=2:seqovl=1" --lua-init="@C:\Z\lua\zapret-lib.lua" --hostlist-auto="C:\Z\config\autohostlist.txt"'

    ; --- _HealthFilterModeFromBinPath ---
    _AssertEq(_HealthFilterModeFromBinPath($sBin), $WINWS_FILTER_AUTO, "auto filtre")
    _AssertEq(_HealthFilterModeFromBinPath('x --hostlist="C:\h.txt"'), $WINWS_FILTER_MANUAL, "manuel filtre")
    _AssertEq(_HealthFilterModeFromBinPath("x --lua-desync=oob"), $WINWS_FILTER_OFF, "filtresiz")

    ; --- _HealthBinPathUsesStrategy ---
    _AssertTrue(_HealthBinPathUsesStrategy($sBin, '--payload="tls_client_hello" --lua-desync="multidisorder:pos=2:seqovl=1"'), "kullanılan strateji tanınır")
    _AssertTrue(_HealthBinPathUsesStrategy(StringReplace($sBin, '"', '\"'), "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"), "kaçışlı binPath ve tırnaksız strateji")
    _AssertFalse(_HealthBinPathUsesStrategy($sBin, "--lua-desync=multidisorder:pos=2"), "önek olan farklı strateji eşleşmez")
    _AssertFalse(_HealthBinPathUsesStrategy($sBin, ""), "boş strateji eşleşmez")

    ; --- _HealthFallbackStrategies ---
    Local $sTmp = @TempDir & "\zwt-test-health.tsv"
    Local $aR[4][$SMART_COL_COUNT]
    __TestHealthRow($aR, 0, '--payload="tls_client_hello" --lua-desync="multidisorder:pos=2:seqovl=1"', 99)
    __TestHealthRow($aR, 1, "--lua-desync=fake:a", 98)
    __TestHealthRow($aR, 2, "--lua-desync=fake:b", 0)
    __TestHealthRow($aR, 3, "--lua-desync=multisplit:c", 90)
    _SmartSaveResults($sTmp, $aR, "test")
    Local $aF = _HealthFallbackStrategies($sTmp, $sBin, 3)
    _AssertEq(UBound($aF), 2, "kullanılan ve puanı 0 olan atlanır")
    If UBound($aF) = 2 Then _AssertEq($aF[0] & "|" & $aF[1], "--lua-desync=fake:a|--lua-desync=multisplit:c", "sıra korunur")
    _AssertEq(UBound(_HealthFallbackStrategies($sTmp, $sBin, 1)), 1, "en fazla $iMax")
    FileDelete($sTmp)
    _AssertEq(UBound(_HealthFallbackStrategies(@TempDir & "\zwt-yok.tsv", $sBin, 3)), 0, "sonuç dosyası yoksa boş")

    ; --- Analiz hız sınırı ---
    Local $sNow = "2026/10/23 12:00:00"
    _AssertEq(_HealthPruneTimes("2026/10/22 11:00:00,2026/10/23 01:00:00, ,bozuk", $sNow), "2026/10/23 01:00:00", "24 saatten eski ve bozuk kayıtlar atılır")
    _AssertTrue(_HealthCanAnalyze("", $sNow, 2), "hiç analiz yoksa izin")
    _AssertTrue(_HealthCanAnalyze("2026/10/23 01:00:00", $sNow, 2), "1 analizden sonra izin")
    _AssertFalse(_HealthCanAnalyze("2026/10/23 01:00:00,2026/10/23 09:00:00", $sNow, 2), "2 analizden sonra yasak")
    _AssertTrue(_HealthCanAnalyze("2026/10/22 01:00:00,2026/10/23 09:00:00", $sNow, 2), "eskiyen kayıt sayılmaz")

    ; --- _HealthStatusFormat (ana pencere alt satırı) ---
    _AssertEq(_HealthStatusFormat(False, "1", "2026/10/23 10:30:00", "sağlıklı", "2026/10/23"), "", "servis yoksa gösterge yok")
    _AssertEq(_HealthStatusFormat(True, "0", "", "", "2026/10/23"), "Onarım: kapalı", "kapalı")
    _AssertEq(_HealthStatusFormat(True, "1", "", "", "2026/10/23"), "Onarım: açık, henüz kontrol yok", "henüz kontrol yok")
    _AssertEq(_HealthStatusFormat(True, "1", "2026/10/23 10:30:05", "sağlıklı", "2026/10/23"), "Onarım: 10:30 sağlıklı", "bugün: yalnız saat")
    _AssertEq(_HealthStatusFormat(True, "1", "2026/10/22 23:05:00", "onarıldı", "2026/10/23"), "Onarım: 22.10 23:05 onarıldı", "dün: gün.ay saat")
    _AssertEq(_HealthStatusFormat(True, "1", "2026/10/23 10:30:05", "", "2026/10/23"), "Onarım: 10:30", "sonuç boşsa yalnız saat")

    ; --- _HealthResultText ---
    _AssertTrue(StringInStr(_HealthResultText($HEALTH_NO_INTERNET), "İnternet") > 0, "internet yok metni")
    _AssertTrue(StringInStr(_HealthResultText($HEALTH_SERVICE_STOPPED), "yeniden başlatma kapalı") > 0, "servis durmuş metni")
    _AssertTrue(StringInStr(_HealthResultText(99), "Bilinmeyen") > 0, "bilinmeyen kod")

    ; --- Görev XML'i: Windows XML ayrıştırıcısıyla geçerli mi? ---
    Local $sXml = _ScheduleBuildXml("C:\A & B\zapret-win-turkey.exe", "/saglik", "C:\A & B", "PC\Ali", 30, "Açıklama <test>")
    Local $oDoc = ObjCreate("Msxml2.DOMDocument.6.0")
    _AssertTrue(IsObj($oDoc) And $oDoc.loadXML(StringReplace($sXml, 'encoding="UTF-16"', "")), "görev XML'i geçerli")
    _AssertTrue(StringInStr($sXml, "<Command>C:\A &amp; B\zapret-win-turkey.exe</Command>") > 0, "yol XML-kaçışlı")
    _AssertTrue(StringInStr($sXml, "<Interval>PT30M</Interval>") > 0, "30 dk aralık")
    _AssertTrue(StringInStr($sXml, "EventID=10000") > 0, "ağ bağlantısı tetikleyicisi")
    _AssertTrue(StringInStr($sXml, "<RunLevel>HighestAvailable</RunLevel>") > 0, "en yüksek ayrıcalık")
    _AssertTrue(StringInStr($sXml, "<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>") > 0, "tek örnek")
    _AssertFalse(_ScheduleExists("zwt-olmayan-gorev-123"), "olmayan görev yok sayılır")
EndFunc

Func __TestHealthRow(ByRef $a, $i, $s, $fScore)
    __SmartFillRow($a, $i, $s, "t")
    $a[$i][$SMART_COL_SCORE] = $fScore
    $a[$i][$SMART_COL_PHASE] = 2
EndFunc
