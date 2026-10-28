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

    ; --- Arka plan kontrolü program içinde (H32: zamanlanmış görev yok) ---
    _AssertFalse(_HealthBackgroundDue(29 * 60000, -1), "29 dk: henüz değil")
    _AssertTrue(_HealthBackgroundDue(30 * 60000, -1), "30 dk dolunca kontrol")
    _AssertFalse(_HealthBackgroundDue(5 * 60000, 10000), "ağ geleli 10 sn: bekle")
    _AssertTrue(_HealthBackgroundDue(5 * 60000, 30000), "ağ geleli 30 sn: kontrol")
    _AssertFalse(_HealthBackgroundDue(5 * 60000, -1), "ağ olayı yok, süre dolmadı")
    _AssertTrue(_HealthNetCameUp("0.0.0.0", "192.168.1.50"), "adres geldi")
    _AssertTrue(_HealthNetCameUp("", "192.168.1.50"), "ilk adres")
    _AssertTrue(_HealthNetCameUp("127.0.0.1", "10.0.0.5"), "geri döngüden gerçek adrese")
    _AssertTrue(_HealthNetCameUp("192.168.1.50", "192.168.0.20"), "başka ağa geçildi")
    _AssertFalse(_HealthNetCameUp("192.168.1.50", "192.168.1.50"), "değişiklik yok")
    _AssertFalse(_HealthNetCameUp("192.168.1.50", "0.0.0.0"), "ağ gitti")
    _AssertFalse(_HealthNetCameUp("192.168.1.50", "169.254.10.1"), "DHCP alınamadı (APIPA) gelmiş sayılmaz")
    _AssertEq($HEALTH_ARG_CHILD, "/uygulamadan", "alt süreç işareti")
    _AssertFalse(_ScheduleExists("zwt-olmayan-gorev-123"), "olmayan görev yok sayılır")

    ; --- _HealthGuiIsOpen: görünür pencere sayılır, gizli (tepsideki) sayılmaz ---
    Local $sApp = "ZWT Test Uygulamasi"
    Local $hW = GUICreate($sApp & " v9.9", 100, 50)
    _AssertFalse(_HealthGuiIsOpen($sApp), "gizli pencere (tepsi) açık sayılmaz")
    GUISetState(@SW_SHOW, $hW)
    _AssertTrue(_HealthGuiIsOpen($sApp), "görünür pencere açık sayılır")
    GUISetState(@SW_HIDE, $hW)
    _AssertFalse(_HealthGuiIsOpen($sApp), "tepsiye gizlenince yine açık sayılmaz")
    GUIDelete($hW)
    _AssertFalse(_HealthGuiIsOpen($sApp), "pencere yoksa açık sayılmaz")
    ; --- Açılış hızlı kontrolü kararı ---
    _AssertEq(_HealthQuickVerdict(True, False), "tamam", "Discord açılıyorsa tamam")
    _AssertEq(_HealthQuickVerdict(False, True), "onar", "Discord kapalı, internet var: onar")
    _AssertEq(_HealthQuickVerdict(False, False), "internet yok", "internet yoksa onarım önerilmez")

EndFunc

Func __TestHealthRow(ByRef $a, $i, $s, $fScore)
    __SmartFillRow($a, $i, $s, "t")
    $a[$i][$SMART_COL_SCORE] = $fScore
    $a[$i][$SMART_COL_PHASE] = 2
EndFunc
