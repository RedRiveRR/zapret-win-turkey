#include-once
#include <AutoItConstants.au3>
#include <Date.au3>
#include "Log.au3"
#include "Service.au3"
#include "SmartAnalysis.au3"
#include "Network.au3"
#include "Winws.au3"
#include "Strategies.au3"
#include "Schedule.au3"

; =========================================================================
; --- SAĞLIK KONTROLÜ (kendini onaran servis) ---
; Görev Zamanlayıcı tarafından pencere açılmadan çalıştırılır:
;   zapret-win-turkey.exe /saglik
; Yalnızca servis modunda çalışır. Adımlar (her biri başarısızsa sonrakine geçilir):
;   1) gateway.discord.gg / discord.com'a TCP bağlantısı açılıyor mu?  -> sağlıklı
;   2) Servis durmuşsa: yalnızca kullanıcı otomatik yeniden başlatmaya izin verdiyse
;      başlat (ADR-007: hile koruma kapattıysa inatla açma); yoksa bildir ve çık.
;   3) DNS zehirliyse ve izin varsa Cloudflare'e al.
;   4) Son akıllı analizin yedek stratejilerini (en fazla 3) sırayla dene.
;   5) İzin varsa ve günde $HEALTH_MAX_ANALYZE_PER_DAY sınırı aşılmadıysa hızlı akıllı analiz.
; Ayarlar config.ini [Health]: Enabled, AutoFixDns, AutoAnalyze (varsayılan 1 = açık).
; =========================================================================

Global Const $HEALTH_TASK_NAME = "ZapretWinTurkey Saglik Kontrolu"
Global Const $HEALTH_ARG = "/saglik"
Global Const $HEALTH_INTERVAL_MIN = 30
Global Const $HEALTH_MAX_ANALYZE_PER_DAY = 2
Global Const $HEALTH_MAX_FALLBACK = 3
Global Const $HEALTH_PROBE_HOSTS = "gateway.discord.gg,discord.com"
; Engellenmeyen kontrol hedefleri: hiçbirine ulaşılamıyorsa sorun engelleme değil internet kesintisidir.
Global Const $HEALTH_INTERNET_HOSTS = "www.google.com,www.microsoft.com,1.1.1.1"
; Kısa kopmalarda (modem yeniden başlıyor, Wi-Fi geç bağlanıyor) onarımdan önce bekleme
Global Const $HEALTH_RETRY_DELAY_MS = 15000
; Oturum açılışında ağ geç gelebilir: internet yoksa bu kadar kez, aralıklarla yeniden bakılır (~2 dk).
Global Const $HEALTH_NET_WAIT_TRIES = 4, $HEALTH_NET_WAIT_MS = 30000

; Sonuç kodları
Global Const $HEALTH_OK = 0              ; zaten sağlıklı
Global Const $HEALTH_FIXED = 1           ; sorun vardı, onarıldı
Global Const $HEALTH_FAILED = 2          ; onarılamadı
Global Const $HEALTH_SKIPPED = 3         ; çalışmadı (servis yok, pencere açık, kapalı...)
Global Const $HEALTH_SERVICE_STOPPED = 4 ; servis durmuş, yeniden başlatma izni yok
Global Const $HEALTH_NO_INTERNET = 5     ; internet yok; hiçbir şey değiştirilmedi

; ------------------------------------------------------------------------
; Saf yardımcılar (birim testli)
; ------------------------------------------------------------------------

; Servis binPath'inden filtre modunu çıkarır (stratejiyi değiştirirken aynı filtre korunur).
Func _HealthFilterModeFromBinPath($sBinPath)
    If StringInStr($sBinPath, "--hostlist-auto") Then Return $WINWS_FILTER_AUTO
    If StringInStr($sBinPath, "--hostlist=") Then Return $WINWS_FILTER_MANUAL
    Return $WINWS_FILTER_OFF
EndFunc

; Stratejinin servis binPath'inde kullanılıp kullanılmadığı (tırnak/kaçış farkı yok sayılır).
Func _HealthBinPathUsesStrategy($sBinPath, $sStrategy)
    Local $sB = StringReplace(StringReplace($sBinPath, '\"', '"'), '"', "")
    Local $sS = StringReplace(StringStripWS($sStrategy, 7), '"', "")
    If $sS = "" Then Return False
    Return StringInStr($sB, " " & $sS & " ") > 0 Or StringRight($sB, StringLen($sS) + 1) = " " & $sS
EndFunc

; Son akıllı analiz sonuçlarından yedek stratejiler: puanı > 0, şu an kullanılan hariç, en fazla $iMax.
Func _HealthFallbackStrategies($sResultsPath, $sCurrentBinPath, $iMax)
    Local $aOut[0], $sSum
    Local $aRows = _SmartLoadResults($sResultsPath, $sSum)
    For $i = 0 To UBound($aRows) - 1
        If UBound($aOut) >= $iMax Then ExitLoop
        If $aRows[$i][$SMART_COL_SCORE] <= 0 Then ContinueLoop
        If _HealthBinPathUsesStrategy($sCurrentBinPath, $aRows[$i][$SMART_COL_STRATEGY]) Then ContinueLoop
        ReDim $aOut[UBound($aOut) + 1]
        $aOut[UBound($aOut) - 1] = $aRows[$i][$SMART_COL_STRATEGY]
    Next
    Return $aOut
EndFunc

; "YYYY/MM/DD HH:MM:SS" biçiminde şimdiki zaman (_DateDiff ile uyumlu).
Func _HealthNow()
    Return @YEAR & "/" & @MON & "/" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
EndFunc

; Virgülle ayrılmış zaman damgalarından son 24 saattekileri bırakır.
Func _HealthPruneTimes($sTimes, $sNow)
    Local $sOut = ""
    For $s In StringSplit($sTimes, ",", 2)
        $s = StringStripWS($s, 3)
        If $s = "" Then ContinueLoop
        Local $iH = _DateDiff("h", $s, $sNow)
        If @error Or $iH < 0 Or $iH >= 24 Then ContinueLoop
        $sOut &= ($sOut = "" ? "" : ",") & $s
    Next
    Return $sOut
EndFunc

; Son 24 saatte $iMax'tan az otomatik analiz yapıldıysa True.
Func _HealthCanAnalyze($sTimes, $sNow, $iMax)
    Local $sKept = _HealthPruneTimes($sTimes, $sNow)
    If $sKept = "" Then Return True
    StringReplace($sKept, ",", "")
    Return (@extended + 1) < $iMax
EndFunc

; Ana pencere alt satırı için kısa durum metni. Servis yoksa "".
;   $sLastCheck: "YYYY/MM/DD HH:MM:SS", $sToday: "YYYY/MM/DD"
Func _HealthStatusFormat($bService, $sEnabled, $sLastCheck, $sLastResult, $sToday)
    If Not $bService Then Return ""
    If $sEnabled = "0" Then Return "Onarım: kapalı"
    If StringLen($sLastCheck) < 16 Then Return "Onarım: açık, henüz kontrol yok"
    Local $sWhen = StringMid($sLastCheck, 12, 5)
    If StringLeft($sLastCheck, 10) <> $sToday Then $sWhen = StringMid($sLastCheck, 9, 2) & "." & StringMid($sLastCheck, 6, 2) & " " & $sWhen
    Return "Onarım: " & $sWhen & ($sLastResult = "" ? "" : " " & $sLastResult)
EndFunc

; Sonuç kodunun kullanıcıya gösterilecek açıklaması.
Func _HealthResultText($iCode)
    Switch $iCode
        Case $HEALTH_OK
            Return "Discord bağlantısı sağlıklı; bir şey yapılmadı."
        Case $HEALTH_FIXED
            Return "Sorun bulundu ve onarıldı."
        Case $HEALTH_FAILED
            Return "Sorun onarılamadı; servis eski stratejisinde. 'ISS Analizi' ile tam analiz yapabilirsiniz."
        Case $HEALTH_SKIPPED
            Return "Kontrol yapılmadı (servis kurulu değil, otomatik onarım kapalı ya da Zapret2 servisi değil)."
        Case $HEALTH_SERVICE_STOPPED
            Return "Servis durmuş; otomatik yeniden başlatma kapalı olduğu için başlatılmadı."
        Case $HEALTH_NO_INTERNET
            Return "İnternet bağlantısı yok; hiçbir şey değiştirilmedi."
    EndSwitch
    Return "Bilinmeyen sonuç (" & $iCode & ")."
EndFunc

; ------------------------------------------------------------------------
; Çalışma anı
; ------------------------------------------------------------------------

; Tek hedefe TCP + TLS1.3 bağlantısı (en fazla $iTries deneme). Açıldıysa True.
Func __HealthProbeHost($sCurl, $sNull, $sHost, $iTries)
    For $i = 1 To $iTries
        Local $iPid = Run(_SmartProbeCommand($sCurl, $sNull, $sHost, $SMART_TLS13, 5), "", @SW_HIDE, $STDOUT_CHILD)
        If $iPid = 0 Then ContinueLoop
        ProcessWaitClose($iPid, 8)
        If ProcessExists($iPid) Then ProcessClose($iPid)
        Local $fMs
        If _SmartParseCurlOutput(StdoutRead($iPid), $fMs) Then Return True
    Next
    Return False
EndFunc

; Discord hedeflerinin hepsi açılıyorsa True (her biri 2 deneme).
Func _HealthProbe($sCurl, $sNull)
    For $sHost In StringSplit($HEALTH_PROBE_HOSTS, ",", 2)
        If Not __HealthProbeHost($sCurl, $sNull, $sHost, 2) Then Return False
    Next
    Return True
EndFunc

; Engellenmeyen kontrol hedeflerinden en az birine ulaşılıyorsa internet var demektir.
Func _HealthInternetUp($sCurl, $sNull)
    For $sHost In StringSplit($HEALTH_INTERNET_HOSTS, ",", 2)
        If __HealthProbeHost($sCurl, $sNull, $sHost, 1) Then Return True
    Next
    Return False
EndFunc

; Program penceresi ekranda görünüyorsa (kullanıcı arayüzde analiz vb. yapıyor olabilir) True.
; Tepsiye küçültülmüş (gizli) pencere sayılmaz: aksi halde program tepside açıkken onarım hiç çalışmazdı.
Func _HealthGuiIsOpen($sAppName)
    Local $sTitle = "[REGEXPTITLE:^\Q" & $sAppName & " v\E]"
    If Not WinExists($sTitle) Then Return False
    Return BitAND(WinGetState($sTitle), 2) = 2 ; 2 = görünür
EndFunc

; Servis stratejisini değiştirip bağlantıyı yeniden dener. Çalıştıysa True.
Func __HealthTryStrategy($sRoot, $sName, $sWinwsPath, $sStrategy, $sFilterMode, $sCurl, $sNull)
    Local $sArgs = _BuildWinwsArgs("Zapret2", $sWinwsPath, $sStrategy, $sFilterMode, $sRoot & "\config\excludelist.txt", _
            $sRoot & "\config\autohostlist.txt", $sRoot & "\config\hostlist.txt")
    If Not _ServiceUpdateArgs($sName, $sWinwsPath, $sArgs) Then Return False
    Sleep(1500)
    Return _HealthProbe($sCurl, $sNull)
EndFunc

Func __HealthNotify($sTitle, $sText)
    _LogInfo("Sağlık kontrolü bildirimi: " & $sTitle & " - " & $sText)
    TrayTip($sTitle, $sText, 10, 1)
    Sleep(6000)
EndFunc

; Tam sağlık kontrolü. Dönüş: $HEALTH_* sonuç kodu.
;   $bFromGui: ayarlar penceresindeki "Şimdi kontrol et" (pencere açık kontrolü ve Enabled atlanır)
Func _HealthRun($sRoot, $sName, $sAppName, $bFromGui = False)
    Local $sIni = $sRoot & "\config\config.ini"
    If Not $bFromGui And IniRead($sIni, "Health", "Enabled", "1") <> "1" Then Return $HEALTH_SKIPPED
    If Not _ServiceIsInstalled($sName) Then Return $HEALTH_SKIPPED
    _ServiceMigrateDhcpFilter($sName) ; eski servis açılışta DHCP'yi bozuyordu (H31)
    If Not $bFromGui And _HealthGuiIsOpen($sAppName) Then Return $HEALTH_SKIPPED

    Local $sBin = _ServiceParseBinPath(_ServiceGetConfig($sName))
    If Not StringInStr($sBin, "winws2.exe") Then Return $HEALTH_SKIPPED ; yalnız Zapret2 servisi onarılır
    Local $sWinwsPath = $sRoot & "\bin\zapret\zapret-winws\winws2.exe"
    Local $sNull, $sCurl = _SmartFindCurl($sRoot, $sNull)
    If $sCurl = "" Then Return $HEALTH_SKIPPED
    IniWrite($sIni, "Health", "LastCheck", _HealthNow())

    ; 2) Servis durmuş mu?
    If _ServiceGetState($sName) <> "RUNNING" Then
        If IniRead($sIni, "Service", "AutoRestart", "0") <> "1" Then
            ; Yalnızca durum değişince logla/bildir (30 dk'da bir tekrar etmesin).
            If IniRead($sIni, "Health", "LastResult", "") <> "durmuş" Then
                _LogWarn("Sağlık kontrolü: servis durmuş; otomatik yeniden başlatma kapalı olduğu için başlatılmadı")
                __HealthNotify("Zapret servisi durmuş", "Bir program (ör. oyun hile koruması) Zapret'i kapatmış olabilir. Programı açıp yeniden başlatabilirsiniz.")
            EndIf
            IniWrite($sIni, "Health", "LastResult", "durmuş")
            Return $HEALTH_SERVICE_STOPPED
        EndIf
        _LogWarn("Sağlık kontrolü: servis durmuş, otomatik yeniden başlatma izinli olduğu için başlatılıyor")
        _ServiceStart($sName)
        Sleep(1500)
    EndIf

    ; 1) Bağlantı
    If _HealthProbe($sCurl, $sNull) Then
        If IniRead($sIni, "Health", "LastResult", "") <> "sağlıklı" Then _LogInfo("Sağlık kontrolü: Discord bağlantısı sağlıklı")
        IniWrite($sIni, "Health", "LastResult", "sağlıklı")
        Return $HEALTH_OK
    EndIf
    ; Kesinti mi engelleme mi? İnternet yoksa hiçbir şeyi değiştirme. Arka plan kontrolünde ağın
    ; gelmesi beklenir (2026-10-24: oturum açılışındaki kontrol ağdan önce çalışıp vazgeçmişti).
    If Not _HealthInternetUp($sCurl, $sNull) And Not __HealthWaitInternet($sCurl, $sNull, $sAppName, $bFromGui) Then
        If IniRead($sIni, "Health", "LastResult", "") <> "internet yok" Then _LogWarn("Sağlık kontrolü: internet bağlantısı yok; onarım yapılmadı")
        IniWrite($sIni, "Health", "LastResult", "internet yok")
        Return $HEALTH_NO_INTERNET
    EndIf
    ; Kısa kopma olabilir: bekleyip bir kez daha dene.
    Sleep($HEALTH_RETRY_DELAY_MS)
    If _HealthProbe($sCurl, $sNull) Then
        IniWrite($sIni, "Health", "LastResult", "sağlıklı")
        Return $HEALTH_OK
    EndIf
    _LogWarn("Sağlık kontrolü: internet var ama Discord'a bağlanılamıyor, onarım deneniyor")

    ; 3) DNS
    If CheckDnsPoisoningSilent() Then
        If IniRead($sIni, "Health", "AutoFixDns", "1") = "1" And _SetSystemDNS() Then
            Sleep(1500)
            If _HealthProbe($sCurl, $sNull) Then Return __HealthDone($sIni, "DNS zehirlenmesi Cloudflare DNS ile giderildi.")
        Else
            Return __HealthFail($sIni, "DNS zehirlenmesi var ama otomatik DNS düzeltme kapalı ya da yapılamadı.")
        EndIf
    EndIf

    ; 4) Yedek stratejiler
    Local $sFilter = _HealthFilterModeFromBinPath($sBin)
    Local $aFallback = _HealthFallbackStrategies($sRoot & "\config\smart_results.tsv", $sBin, $HEALTH_MAX_FALLBACK)
    For $sStrategy In $aFallback
        _LogInfo("Sağlık kontrolü: yedek strateji deneniyor: " & $sStrategy)
        If __HealthTryStrategy($sRoot, $sName, $sWinwsPath, $sStrategy, $sFilter, $sCurl, $sNull) Then
            __HealthSaveStrategy($sRoot, $sStrategy)
            Return __HealthDone($sIni, "Yedek stratejiye geçildi.")
        EndIf
    Next

    ; 5) Sınırlı otomatik akıllı analiz
    Local $sTimes = IniRead($sIni, "Health", "AnalyzeTimes", "")
    If IniRead($sIni, "Health", "AutoAnalyze", "1") = "1" And _HealthCanAnalyze($sTimes, _HealthNow(), $HEALTH_MAX_ANALYZE_PER_DAY) Then
        Local $sKept = _HealthPruneTimes($sTimes, _HealthNow())
        IniWrite($sIni, "Health", "AnalyzeTimes", $sKept & ($sKept = "" ? "" : ",") & _HealthNow())
        _LogInfo("Sağlık kontrolü: otomatik hızlı akıllı analiz başlıyor")
        _ServiceStop($sName)
        _KillProcessesUnderDir($sRoot & "\bin\zapret\zapret-winws")
        Local $aCand[0][2]
        If FileExists($sRoot & "\config\strategy2.txt") Then _SmartAddCandidate($aCand, FileRead($sRoot & "\config\strategy2.txt"), "Kayıtlı")
        Local $aPresets = _StrategyLoad($sRoot & "\config\strategies.ini", "Zapret2")
        For $i = 0 To UBound($aPresets) - 1
            _SmartAddCandidate($aCand, $aPresets[$i][1], "Hazır: " & $aPresets[$i][0])
        Next
        Local $sSum, $aRows = _SmartAnalyze($aCand, $sWinwsPath, $sCurl, $sNull, _
                IniRead($sIni, "SmartAnalysis", "Targets", $SMART_DEFAULT_TARGETS), "", $sSum)
        _LogInfo("Sağlık kontrolü: otomatik analiz: " & $sSum)
        If UBound($aRows) > 0 And $aRows[0][$SMART_COL_SCORE] > 0 Then
            _SmartSaveResults($sRoot & "\config\smart_results.tsv", $aRows, $sSum)
            If __HealthTryStrategy($sRoot, $sName, $sWinwsPath, $aRows[0][$SMART_COL_STRATEGY], $sFilter, $sCurl, $sNull) Then
                __HealthSaveStrategy($sRoot, $aRows[0][$SMART_COL_STRATEGY])
                Return __HealthDone($sIni, "Otomatik analizle yeni strateji bulundu (puan " & $aRows[0][$SMART_COL_SCORE] & ").")
            EndIf
        EndIf
    EndIf

    ; Hiçbiri işe yaramadı: servisi onarım öncesi stratejisine geri döndür (son denenen yedekte kalmasın).
    If _ServiceParseBinPath(_ServiceGetConfig($sName)) <> $sBin Then
        Local $bRestored = _ServiceRestoreBinPath($sName, $sBin)
        _LogInfo("Sağlık kontrolü: onarım başarısız, servis orijinal stratejiye " & ($bRestored ? "geri döndürüldü" : "GERİ DÖNDÜRÜLEMEDİ"))
    ElseIf _ServiceGetState($sName) <> "RUNNING" Then
        _ServiceStart($sName)
    EndIf
    Return __HealthFail($sIni, "Otomatik onarım başarısız; servis eski stratejisinde bırakıldı. Programı açıp 'ISS Analizi' ile tam analiz yapabilirsiniz.")
EndFunc

; Servis kurulduktan sonra sorulur: otomatik onarım (sağlık kontrolü görevi) kurulsun mu?
; Cevap config.ini [Health] Enabled'da saklanır. Kurulduysa True.
Func _HealthOfferSetup($sIni)
    Local $iAns = MsgBox(4 + 32 + 8192, "Otomatik Onarım", _
            "Zapret'in Discord bağlantısını arka planda kontrol edip sorun olunca kendini onarması istensin mi? (önerilen)" & @CRLF & @CRLF & _
            "• Oturum açılışında, 30 dakikada bir ve ağ bağlantısı değişince kısa bir kontrol yapılır." & @CRLF & _
            "• Sorun varsa sırasıyla: DNS düzeltme, son analizdeki yedek stratejiler, gerekirse hızlı analiz (günde en fazla " & $HEALTH_MAX_ANALYZE_PER_DAY & ")." & @CRLF & _
            "• Servis kapatılmışsa (ör. oyun hile koruması) yalnızca 'otomatik yeniden başlatma'ya izin verdiyseniz açılır; aksi halde sadece bildirilir.")
    If $iAns <> 6 Then
        IniWrite($sIni, "Health", "Enabled", "0")
        _ScheduleRemove($HEALTH_TASK_NAME)
        _LogInfo("Otomatik onarım kullanıcı tarafından kapatıldı")
        Return False
    EndIf
    IniWrite($sIni, "Health", "Enabled", "1")
    Local $iRc = _HealthInstallTask()
    If $iRc <> 0 Then
        MsgBox(48 + 8192, "Otomatik Onarım", "Zamanlanmış görev oluşturulamadı (hata kodu " & $iRc & "). Servis yine de çalışır.")
        Return False
    EndIf
    Return True
EndFunc

; Sağlık kontrolü görevini kurar. Dönüş: schtasks çıkış kodu (0 = başarılı).
Func _HealthInstallTask()
    Local $sCmd, $sArgs
    _ScheduleSelfCommand($sCmd, $sArgs, $HEALTH_ARG)
    Local $iRc = _ScheduleInstall($HEALTH_TASK_NAME, $sCmd, $sArgs, @ScriptDir, $HEALTH_INTERVAL_MIN, _
            "RedRiveRR Zapret: Discord bağlantısını kontrol eder, gerekirse servisi onarır.")
    _LogInfo("Otomatik onarım görevi kuruldu (schtasks çıkış kodu " & $iRc & "): " & $sCmd & " " & $sArgs)
    Return $iRc
EndFunc

; Servis kaldırılınca sağlık kontrolü görevi de kaldırılır.
Func _HealthRemoveTask()
    If _ScheduleExists($HEALTH_TASK_NAME) Then
        _ScheduleRemove($HEALTH_TASK_NAME)
        _LogInfo("Otomatik onarım görevi kaldırıldı")
    EndIf
EndFunc

Func __HealthSaveStrategy($sRoot, $sStrategy)
    Local $h = FileOpen($sRoot & "\config\strategy2.txt", 2)
    If $h = -1 Then Return
    FileWrite($h, $sStrategy)
    FileClose($h)
EndFunc

Func __HealthDone($sIni, $sText)
    IniWrite($sIni, "Health", "LastResult", "onarıldı")
    __HealthNotify("Zapret onarıldı", $sText)
    Return $HEALTH_FIXED
EndFunc

Func __HealthFail($sIni, $sText)
    _LogError("Sağlık kontrolü: " & $sText)
    If IniRead($sIni, "Health", "LastResult", "") <> "başarısız" Then __HealthNotify("Discord'a ulaşılamıyor", $sText)
    IniWrite($sIni, "Health", "LastResult", "başarısız")
    Return $HEALTH_FAILED
EndFunc

; İnternet gelene kadar bekler (yalnızca arka plan kontrolünde). Geldiyse True; program
; penceresi açılırsa beklemeyi bırakır (kullanıcı kendisi bakıyor).
Func __HealthWaitInternet($sCurl, $sNull, $sAppName, $bFromGui)
    If $bFromGui Then Return False
    For $i = 1 To $HEALTH_NET_WAIT_TRIES
        Sleep($HEALTH_NET_WAIT_MS)
        If _HealthGuiIsOpen($sAppName) Then Return False
        If _HealthInternetUp($sCurl, $sNull) Then
            _LogInfo("Sağlık kontrolü: internet " & Int($i * $HEALTH_NET_WAIT_MS / 1000) & " sn sonra geldi")
            Return True
        EndIf
    Next
    Return False
EndFunc

; Açılış hızlı kontrolü kararı: Discord açılıyorsa "tamam", açılmıyor ama internet varsa "onar", yoksa "internet yok".
Func _HealthQuickVerdict($bDiscordOk, $bInternetUp)
    If $bDiscordOk Then Return "tamam"
    Return $bInternetUp ? "onar" : "internet yok"
EndFunc

; Program açılışında servis çalışırken hızlı bağlantı kontrolü (en fazla ~15 sn): her Discord hedefi bir kez.
; Dönüş: _HealthQuickVerdict; curl bulunamazsa "".
Func _HealthQuickCheck($sRoot)
    Local $sNull, $sCurl = _SmartFindCurl($sRoot, $sNull)
    If $sCurl = "" Then Return ""
    Local $bOk = True
    For $sHost In StringSplit($HEALTH_PROBE_HOSTS, ",", 2)
        If Not __HealthProbeHost($sCurl, $sNull, $sHost, 1) Then
            $bOk = False
            ExitLoop
        EndIf
    Next
    If $bOk Then Return "tamam"
    Return _HealthQuickVerdict(False, _HealthInternetUp($sCurl, $sNull))
EndFunc

; Görev bu programı çalıştırmıyorsa (exe yeniden adlandırıldı/taşındı: 2026-10-24 "zapret-win-turkey.exe" ->
; "RedRiveRR Zapret.exe") görevi bu exe için yeniden kurar. Yalnız derlenmiş programda. Kurulduysa True.
Func _HealthTaskRepair()
    If Not @Compiled Then Return False
    Local $sXml = _ScheduleQueryXml($HEALTH_TASK_NAME)
    If $sXml = "" Then Return False
    Local $sCmd, $sArgs
    _ScheduleSelfCommand($sCmd, $sArgs, $HEALTH_ARG)
    Local $sTaskCmd = _ScheduleXmlCommand($sXml)
    If Not _HealthTaskShouldRepair($sTaskCmd, $sCmd, FileExists($sTaskCmd) = 1) Then Return False
    _LogInfo("Otomatik onarım görevi " & $sTaskCmd & " gösteriyordu; " & $sCmd & " için yeniden kuruluyor")
    Return _HealthInstallTask() = 0
EndFunc

; Görev yeniden kurulmalı mı? Yalnızca görevin exe'si silinmişse ya da aynı klasördeyse (yeniden adlandırma).
; Başka klasördeki bir kopya (ör. eski yedek, H18) asıl kurulumun görevini kendine çekmez.
Func _HealthTaskShouldRepair($sTaskCmd, $sOurCmd, $bTaskCmdExists)
    If $sTaskCmd = "" Or $sTaskCmd = $sOurCmd Then Return False
    If Not $bTaskCmdExists Then Return True
    Return StringRegExpReplace($sTaskCmd, "\\[^\\]*$", "") = StringRegExpReplace($sOurCmd, "\\[^\\]*$", "")
EndFunc
