#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=bin\zapret\zapret-winws\winws2.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=Zapret Windows Türkiye Lite
#AutoIt3Wrapper_Res_Fileversion=4.5.0.0
#AutoIt3Wrapper_Res_ProductVersion=4.5
#AutoIt3Wrapper_Res_LegalCopyright=Ali Mali
#AutoIt3Wrapper_Res_Language=1055
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <MsgBoxConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <TrayConstants.au3>
#include <ComboConstants.au3>
#include <AutoItConstants.au3>
#include "lib\Network.au3"
#include "lib\Process.au3"
#include "lib\Winws.au3"
#include "lib\Strategies.au3"
#include "lib\Version.au3"
#include "lib\Log.au3"
#include "lib\Conflicts.au3"
#include "lib\Update.au3"
#include "lib\Diag.au3"
#include "lib\SmartAnalysis.au3"
#include "ui\SmartAnalysisUI.au3"

#include <ProgressConstants.au3>

; --- ZIP / TEMP KLASÖRÜ KONTROLÜ ---
Local $currentDir = @ScriptDir
If StringInStr($currentDir, @TempDir) Or StringInStr($currentDir, "Temporary Internet Files") Or StringInStr($currentDir, "vfs") Then
    MsgBox(16, "Hata: Arşivden Çalıştırma Saptandı", _
            "Programı ZIP dosyasının içinden doğrudan çalıştırmayın!" & @CRLF & @CRLF & _
            "1. ZIP dosyasındaki tüm dosyaları normal bir klasöre çıkarın." & @CRLF & _
            "2. Ardından programı o klasörden tekrar başlatın.")
    Exit
EndIf

_LogInit(@ScriptDir & "\logs\app.log")
_LogInfo("=== " & $APP_NAME & " v" & $APP_VERSION & " Lite başlatıldı | Windows " & @OSVersion & " " & @OSBuild & " " & @OSArch)

; --- GÜVENLİK UYARILARINI KALDIR ---
RunWait('powershell -Command "Get-ChildItem -Path ''' & @ScriptDir & ''' -Recurse | Unblock-File"', "", @SW_HIDE)

; --- ESKİ KURULUM SERVİSLERİ (başka klasörü gösteren ZapretService / dnscrypt-proxy) ---
_HandleForeignServices(@ScriptDir)

; --- ÇAKIŞMA KONTROLÜ (GoodbyeDPI, ByeDPI, başka klasörden çalışan Zapret) ---
If Not _HandleStartupConflicts(@ScriptDir) Then Exit

Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

; --- Ayarlar ve Dosya Yolları ---
Local $serviceName = "ZapretService"
Local $hostlistPath = @ScriptDir & "\config\autohostlist.txt"
Local $normalHostlistPath = @ScriptDir & "\config\hostlist.txt"
Local $iniPath = @ScriptDir & "\config\config.ini"
Local $exludelistPath = @ScriptDir & "\config\excludelist.txt"
Global $strategiesIniPath = @ScriptDir & "\config\strategies.ini"
Global $g_aStrategies = _StrategyDefaults("Zapret2")

; --- CONFIG DOSYASINDAN AYARLARI OKU ---
Local $iniEngine = IniRead($iniPath, "Settings", "ActiveEngine", "0") ; 0 = Zapret2, 1 = Zapret1
Local $iniStrategy = IniRead($iniPath, "Settings", "ActiveStrategy", "Turk Telekom")
; 0 = Kapalı, 1 = Auto, 2 = Manuel
Local $iniFilterMode = IniRead($iniPath, "Settings", "FilterMode", "1")

; --- DİNAMİK MOTOR DEĞİŞKENLERİ ---
Global $winwsPath = ""
Global $currentEngine = "Zapret2"

; --- Global Durum Değişkenleri ---
Global $isZapretRunning = False
Global $zapretPID = 0
Global $bServiceStoppedWarned = False
Global $bDnsReset = True

; Servis kurulum butonuna art arda tıklamayı engelleyen kilit.
Global $bInstallServiceBusy = False
Global $hInstallServiceUnlockTimer = 0
Global $bInstallServiceEnableAfterLock = True

; --- GUI Tasarımı ---
Global $hGUI = GUICreate($APP_NAME & " v" & $APP_VERSION & " Lite", 400, 405)
GUISetBkColor(0xFFFFFF)

; --- Tepsi Menüsü ---
Local $trayShow = TrayCreateItem("Göster")
TrayItemSetOnEvent(-1, "ShowGUI")
TrayCreateItem("Hazır profilleri akıllı test et")
TrayItemSetOnEvent(-1, "_LiteSmartFromTray")
TrayCreateItem("Tanılama paketi oluştur")
TrayItemSetOnEvent(-1, "_DiagCreateFromTray")
TrayCreateItem("")
Local $trayExit = TrayCreateItem("Kapat")
TrayItemSetOnEvent(-1, "_SaveConfigAndExit")
TraySetOnEvent($TRAY_EVENT_PRIMARYDOUBLE, "ShowGUI")
TraySetClick(16)

; --- Üst Durum Paneli ---
Local $lblStatusBg = GUICtrlCreateLabel("", 15, 15, 370, 75)
GUICtrlSetBkColor(-1, 0xF2F4F7)
Local $lblStatusText = GUICtrlCreateLabel("SİSTEM HAZIRLANIYOR...", 15, 30, 370, 25, $SS_CENTER)
GUICtrlSetFont(-1, 12, 800, 0, "Segoe UI")
GUICtrlSetColor(-1, 0xE67E22)

Local $pBar = GUICtrlCreateProgress(15, 75, 370, 15, $PBS_MARQUEE)
GUICtrlSetState(-1, $GUI_HIDE)

Local $lblStrategyInfo = GUICtrlCreateLabel("Strateji Durumu: Kontrol Ediliyor...", 15, 55, 370, 20, $SS_CENTER)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x666666)

; =========================================================================
; --- 1. ANA BUTON (EN ÜSTE ALINDI) ---
; =========================================================================
Local $btnRunZapret = GUICtrlCreateButton("ZAPRET'İ BAŞLAT", 50, 95, 300, 55)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 11, 800, 0, "Segoe UI")

; MOTOR
GUICtrlCreateLabel("Motor:", 50, 177, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Local $cmbEngine = GUICtrlCreateCombo("Zapret2 (Yeni LUA Motoru)", 175, 174, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetData(-1, "Zapret (Eski Klasik Motor)")
If $iniEngine == "1" Then GUICtrlSetData($cmbEngine, "Zapret (Eski Klasik Motor)", "Zapret (Eski Klasik Motor)")
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; STRATEJİ
GUICtrlCreateLabel("Strateji:", 50, 212, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbStrategy = GUICtrlCreateCombo("Turk Telekom", 175, 209, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; FİLTRE
GUICtrlCreateLabel("Filtre:", 50, 247, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbFilter = GUICtrlCreateCombo("Kapalı (Tüm trafik)", 175, 244, 175, 25, $CBS_DROPDOWNLIST)
Global $sFilterSelectionBeforeOOB = ""
Global $bFilterWasEnabledBeforeOOB = False
Global $bOOBFilterLock = False
GUICtrlSetData(-1, "Auto (Zapret oluşturur)|Manuel ('hostlist.txt' İçeriği)")

; INI'den okunan değere göre varsayılanı seç
If $iniFilterMode == "1" Then
    GUICtrlSetData($cmbFilter, "Auto (Zapret oluşturur)", "Auto (Zapret oluşturur)")
ElseIf $iniFilterMode == "2" Then
    GUICtrlSetData($cmbFilter, "Manuel ('hostlist.txt' İçeriği)", "Manuel ('hostlist.txt' İçeriği)")
Else
    GUICtrlSetData($cmbFilter, "Kapalı (Tüm trafik)", "Kapalı (Tüm trafik)")
EndIf
$sFilterSelectionBeforeOOB = GUICtrlRead($cmbFilter)

GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; =========================================================================
; --- LITE SÜRÜMÜNÜN TEMEL İŞLEMLERİ ---
; =========================================================================
Local $btnInstallService = GUICtrlCreateButton("Servis Olarak Yükle (Otomatik Başlat)", 50, 290, 300, 35)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnRemoveService = GUICtrlCreateButton("Servis ve Kalıntıları Temizle", 50, 335, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Global $lblFooter = GUICtrlCreateLabel("Zapret Windows Türkiye Lite", 0, 380, 400, 20, $SS_CENTER)
GUICtrlSetFont(-1, 10, 400, 0, "Consolas")
GUICtrlSetColor(-1, 0xBDC3C7)

Local $aCriticalButtons[5] = [$btnRunZapret, $btnInstallService, $cmbEngine, $cmbStrategy, $cmbFilter]
Local $aOtherButtons[5] = [$btnInstallService, $btnRemoveService, $cmbEngine, $cmbStrategy, $cmbFilter]

GUISetState(@SW_SHOW)

; --- İLK YOLLARI VE STRATEJİ LİSTESİNİ DOĞRULA ---
_UpdateEnginePaths(GUICtrlRead($cmbEngine))
_LoadStrategyList($iniStrategy)
_RefreshStrategyLabel()
_UpdateFilterForStrategy()

; --- GÜVENLİ AÇILIŞ AKIŞI VE DİNAMİK DNS ZEHİRLENMESİ KONTROL DÖNGÜSÜ ---
RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
GUICtrlSetData($lblStatusText, "DNS KONTROL EDİLİYOR...")

Local $isDnsChangedByApp = False

While 1
    Local $isPoisoned = CheckDnsPoisoningSilent()

    If $isPoisoned Then
        _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
        GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
        GUICtrlSetColor($lblStatusText, 0xC0392B)

        ; 2. TUR: Uygulama DNS değiştirdi ama hala zehirliyse (TT engelliyorsa)
        If $isDnsChangedByApp Then
            MsgBox(48 + 8192, "Kritik Uyarı", "Düz DNS değişikliği işe yaramadı, port 53'e müdahale var." & @CRLF & @CRLF & _
                    "Düz DNS değişikliği işe yaramadı. YogaDNS gibi harici bir DNS istemcisi kullanmayı deneyebilirsiniz.")
            ExitLoop
        EndIf

        ; 1. TUR: Zehirlenme ilk kez saptandıysa soru sor
        Local $iAsk = MsgBox(36 + 8192, "DNS Zehirlenmesi Saptandı", _
                "ISS tarafından DNS Zehirlenmesi saptandı!" & @CRLF & @CRLF & _
                "Sistem DNS adresiniz Cloudflare (1.1.1.1 / 1.0.0.1) olarak ayarlansın mı?")

        If $iAsk = 6 Then ; EVET
            GUICtrlSetData($lblStatusText, "DNS AYARLANIYOR...")
            If Not _SetSystemDNS() Then
                MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)
                ExitLoop
            EndIf
            $isDnsChangedByApp = True
            GUICtrlSetData($lblStatusText, "DNS TEST EDİLİYOR...")
            Sleep(1000)
            ContinueLoop ; Döngüyü başa sar, nslookup ile yeni DNS'i test et
        Else ; HAYIR
            ExitLoop
        EndIf
    Else
        ; Zehirlenme yoksa her şey normal devam etsin
        CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
        _RefreshStrategyLabel()
        ExitLoop
    EndIf
WEnd

; --- GÜNCELLEME KONTROLÜ (arka planda; config.ini'de UpdateCheck=0 ile kapatılır) ---
If IniRead($iniPath, "Settings", "UpdateCheck", "1") <> "0" Then _UpdateStartCheck($APP_UPDATE_REPO)

; --- Ana Döngü ---
Local $hProcessTimer = TimerInit()

While 1
    Local $nMsg = GUIGetMsg()

    ; Servis kurulumu sırasında kuyruğa alınan tıklamaları atla.
    If $nMsg = $btnInstallService And $bInstallServiceBusy Then ContinueLoop

    If $bInstallServiceBusy And $hInstallServiceUnlockTimer <> 0 Then
        If TimerDiff($hInstallServiceUnlockTimer) >= 1500 Then
            $bInstallServiceBusy = False
            $hInstallServiceUnlockTimer = 0
            If $bInstallServiceEnableAfterLock And GUICtrlRead($lblStatusText) = "ÇALIŞMAYA HAZIR" Then
                GUICtrlSetState($btnInstallService, $GUI_ENABLE)
            EndIf
        EndIf
    EndIf

    ; Zapret motorunun beklenmedik kapanmasını izle.
    If TimerDiff($hProcessTimer) > 1000 Then
        Local $bZapretAlive = ProcessExists("winws.exe") Or ProcessExists("winws2.exe")
        If Not $bZapretAlive Then
            If $isZapretRunning Then
                _LogError("Manuel mod: winws beklenmedik şekilde kapandı (çökme veya dış müdahale)")
                StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
                MsgBox(16 + 8192, "Uyarı: Zapret Kapatıldı", "Zapret motoru beklenmedik bir şekilde kapandı veya dışarıdan sonlandırıldı!" & @CRLF & @CRLF & _
                    "Sisteminizdeki Anti-Cheat yazılımları Zapret'i kapatmış olabilir.")
            EndIf
            If GUICtrlRead($lblStatusText) = "SERVİS MODU AKTİF" Then
                CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            EndIf
        Else
            ; Servis durduktan sonra yeniden başladıysa "DURDU" yazısı takılı kalmasın.
            _RefreshIfServiceRecovered()
        EndIf
        _UpdatePollAndNotify($APP_VERSION, $APP_RELEASES_URL)
        $hProcessTimer = TimerInit()
    EndIf

    Switch $nMsg
        Case $GUI_EVENT_CLOSE
            _SaveConfigAndExit()

        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)
            TraySetToolTip("Zapret Windows Türkiye Lite")

        Case $cmbEngine
            _UpdateEnginePaths(GUICtrlRead($cmbEngine))
            _LoadStrategyList("Turk Telekom")
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            _RefreshStrategyLabel()

        Case $cmbStrategy
            _RefreshStrategyLabel()
            _UpdateFilterForStrategy()

        Case $btnRunZapret
            If $isZapretRunning = False Then
                StartWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            Else
                StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            EndIf

        Case $btnInstallService
            If $bInstallServiceBusy Then ContinueLoop
            $bInstallServiceBusy = True
            $hInstallServiceUnlockTimer = 0
            $bInstallServiceEnableAfterLock = (BitAND(GUICtrlGetState($btnInstallService), $GUI_ENABLE) <> 0)
            GUICtrlSetState($btnInstallService, $GUI_DISABLE)
            InstallServiceClean($cmbFilter)
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            GUICtrlSetState($btnInstallService, $GUI_DISABLE)
            $hInstallServiceUnlockTimer = TimerInit()

        Case $btnRemoveService
            RemoveService()
            GUICtrlSetData($lblStatusText, "SİSTEM SIFIRLANIYOR...")
            $bDnsReset = _ResetSystemDNS()
            Local $isPoisonedAfterCleanup = CheckDnsPoisoningSilent()
            If Not $isPoisonedAfterCleanup Then CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            _RefreshStrategyLabel()
            If $bDnsReset Then
                MsgBox(64 + 8192, "Bilgi", "Zapret servisleri ve kalıntıları temizlendi. DNS ayarları otomatiğe (DHCP) alındı.")
            Else
                MsgBox(48 + 8192, "Bilgi", "Zapret servisleri ve kalıntıları temizlendi." & @CRLF & @CRLF & $NET_MSG_NO_ADAPTER)
            EndIf
            If $isPoisonedAfterCleanup Then
                _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
                GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
                GUICtrlSetColor($lblStatusText, 0xC0392B)
            Else
                CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
                _RefreshStrategyLabel()
            EndIf
    EndSwitch
WEnd

; --- YENİ YARDIMCI FONKSİYONLAR ---

; --- MOTORA GÖRE HAZIR STRATEJİ LİSTESİNİ DOLDURAN FONKSİYON ---
Func _LoadStrategyList($sDefaultToSelect)
    $g_aStrategies = _StrategyLoad($strategiesIniPath, $currentEngine)
    ; Lite sürümde analiz yok; kayıtlı seçim listede değilse ilk profil seçilir.
    If Not _StrategyExists($g_aStrategies, $sDefaultToSelect) Then $sDefaultToSelect = $g_aStrategies[0][0]
    GUICtrlSetData($cmbStrategy, "")
    GUICtrlSetData($cmbStrategy, _StrategyNames($g_aStrategies), $sDefaultToSelect)
EndFunc

Func _GetActiveStrategyString()
    Return _StrategyGet($g_aStrategies, GUICtrlRead($cmbStrategy))
EndFunc

Func _UpdateFilterForStrategy()
    Local $sStrategy = _GetActiveStrategyString()
    Local $bHasOOB = StringInStr($sStrategy, "oob") > 0

    If $bHasOOB Then
        If Not $bOOBFilterLock Then
            $sFilterSelectionBeforeOOB = GUICtrlRead($cmbFilter)
            $bOOBFilterLock = True
        EndIf
        GUICtrlSetData($cmbFilter, "")
        GUICtrlSetData($cmbFilter, "Filtre Uygulanamaz", "Filtre Uygulanamaz")
        GUICtrlSetColor($cmbFilter, 0xCC0000)
        GUICtrlSetState($cmbFilter, $GUI_DISABLE)
    ElseIf $bOOBFilterLock Then
        GUICtrlSetData($cmbFilter, "")
        GUICtrlSetData($cmbFilter, "Kapalı (Tüm trafik)|Auto (Zapret oluşturur)|Manuel ('hostlist.txt' İçeriği)", $sFilterSelectionBeforeOOB)
        GUICtrlSetColor($cmbFilter, 0x000000)
        GUICtrlSetState($cmbFilter, $GUI_ENABLE)
        $bOOBFilterLock = False
    EndIf
EndFunc

Func _RefreshStrategyLabel()
    Local $sel = GUICtrlRead($cmbStrategy)
    GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: Hazır Profil (" & $sel & ")")
EndFunc

Func _SaveConfigAndExit()
    Local $engineVal = ($currentEngine == "Zapret2") ? "0" : "1"
    Local $stratVal = GUICtrlRead($cmbStrategy)

    ; OOB stratejisinde filtre kutusu geçici olarak "Filtre Uygulanamaz" olur.
    ; Config'e bu geçici metni değil, OOB öncesindeki gerçek filtre seçimini kaydet.
    Local $filterSel = GUICtrlRead($cmbFilter)
    If $bOOBFilterLock And $sFilterSelectionBeforeOOB <> "" Then
        $filterSel = $sFilterSelectionBeforeOOB
    EndIf

    Local $filterModeVal = "0"
    If StringInStr($filterSel, "Auto") Then
        $filterModeVal = "1"
    ElseIf StringInStr($filterSel, "Manuel") Then
        $filterModeVal = "2"
    EndIf

    IniWrite($iniPath, "Settings", "ActiveEngine", $engineVal)
    IniWrite($iniPath, "Settings", "ActiveStrategy", $stratVal)
    IniWrite($iniPath, "Settings", "FilterMode", $filterModeVal)

    ExitApp()
EndFunc

Func _UpdateEnginePaths($sEngineSelected)
    If StringInStr($sEngineSelected, "Zapret2") Then
        $currentEngine = "Zapret2"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws2.exe"
        GUICtrlSetData($lblFooter, "Zapret2 v" & $ENGINE_ZAPRET2_VERSION)
    Else
        $currentEngine = "Zapret1"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws.exe"
        GUICtrlSetData($lblFooter, "Zapret v" & $ENGINE_ZAPRET1_VERSION)
    EndIf
EndFunc

Func ShowGUI()
    GUISetState(@SW_SHOW, $hGUI)
    GUISetState(@SW_RESTORE, $hGUI)
EndFunc

Func ExitApp()
    If $isZapretRunning Then StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
    Exit
EndFunc

Func _SetButtonsState(ByRef $aBtnArray, $iState)
    For $i = 0 To UBound($aBtnArray) - 1
        GUICtrlSetState($aBtnArray[$i], $iState)
    Next
EndFunc

#include <Constants.au3>

Func CheckServiceStatus($manualBtn, $statusID, $lockArray, $chkID)
    Local $iPid = Run(@ComSpec & " /c sc query " & $serviceName, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPid)
    Local $sOutput = StdoutRead($iPid)

    If StringInStr($sOutput, "SERVICE_NAME") Then
        Local $iPidCfg = Run(@ComSpec & " /c sc qc " & $serviceName, "", @SW_HIDE, $STDOUT_CHILD)
        ProcessWaitClose($iPidCfg)
        Local $sCfgOut = StdoutRead($iPidCfg)

        ; Servis çalışıyorsa menüyü ayarla
        If StringInStr($sCfgOut, "--hostlist-auto") Then
            GUICtrlSetData($chkID, "Auto (Zapret oluşturur)")
        ElseIf StringInStr($sCfgOut, "--hostlist=") Then
            GUICtrlSetData($chkID, "Manuel ('hostlist.txt' İçeriği)")
        Else
            GUICtrlSetData($chkID, "Kapalı (Tüm trafik)")
        EndIf

        GUICtrlSetState($manualBtn, $GUI_DISABLE)
        _SetButtonsState($lockArray, $GUI_DISABLE)

        ; --- YENİ EKLENEN KISIM: SERVİS DURUMUNU (RUNNING/STOPPED) KONTROL ET ---
        If StringInStr($sOutput, "RUNNING") Then
            GUICtrlSetData($statusID, "SERVİS MODU AKTİF")
            GUICtrlSetColor($statusID, 0x27AE60)
        Else
            ; Servis yüklü ama durmuş!
            GUICtrlSetData($statusID, "SERVİS YÜKLÜ - DURDU")
            GUICtrlSetColor($statusID, 0xC0392B) ; Kırmızı renkle uyar

            ; Kullanıcıyı yalnızca bir kez uyar (sürekli MsgBox çıkıp darlamasın)
            If Not $bServiceStoppedWarned Then
                $bServiceStoppedWarned = True
                _LogError("Servis yüklü ama durmuş durumda")
                MsgBox(16 + 8192, "Uyarı: Servis Durdurulmuş", "Zapret servisi sisteme yüklü ancak şu anda DURMUŞ durumda!" & @CRLF & @CRLF & _
                        "Sisteminizdeki Anti-Cheat yazılımları Zapret'i tehdit olarak algılayıp kapatmış olabilir.")
            EndIf
        EndIf
    Else
        GUICtrlSetState($manualBtn, $GUI_ENABLE)
        _SetButtonsState($lockArray, $GUI_ENABLE)

        GUICtrlSetData($statusID, "ÇALIŞMAYA HAZIR")
        GUICtrlSetColor($statusID, 0x2C3E50)
    EndIf
    _UpdateFilterForStrategy()
EndFunc

Func StartWinws($ctrlID, $statusID, $aBtns)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Lütfen hazır stratejilerden birini seçin.")

    Local $fullCommand = '"' & $winwsPath & '" ' & _BuildActiveWinwsArgs($activeStrategy)

    ;ClipPut($fullCommand)
    $zapretPID = Run($fullCommand, @ScriptDir & "\bin\zapret\zapret-winws\", @SW_HIDE)
    _LogInfo("Manuel başlat (" & $currentEngine & ", " & GUICtrlRead($cmbStrategy) & ", PID " & $zapretPID & "): " & $fullCommand)

    If $zapretPID > 0 Then
        ; --- 1. ARAYÜZÜ ANINDA GÜNCELLE (Kullanıcıya anında tepki ver) ---
        $isZapretRunning = True
        GUICtrlSetData($ctrlID, "DURDUR")
        GUICtrlSetData($statusID, "MANUEL MOD AKTİF")
        GUICtrlSetColor($statusID, 0xE67E22)
        _SetButtonsState($aBtns, $GUI_DISABLE)

        ; --- 2. ARKA PLANDA 1 SANİYE BEKLE VE KONTROL ET ---
        Sleep(500)

        If Not ProcessExists($zapretPID) Then
            ; --- 3. EĞER EXE ÇÖKTÜYSE HER ŞEYİ ESKİ HALİNE (SİSTEM HAZIR) DÖNDÜR ---
            $isZapretRunning = False
            $zapretPID = 0

            GUICtrlSetData($ctrlID, "ZAPRET'İ BAŞLAT")
            ; CheckServiceStatus fonksiyonumuz zaten yazıları yeşil yapıp butonları açma işini kusursuz yapıyor
            CheckServiceStatus($ctrlID, $statusID, $aBtns, $cmbFilter)

            _LogError("Manuel başlat: winws 500 ms içinde kapandı")
            MsgBox(16 + 8192, "Başlatma Hatası", "Zapret motoru başlatılamadı veya anında çöktü!" & @CRLF & @CRLF & _
                    "Sisteminizdeki Anti-Cheat yazılımları Zapret'i tehdit olarak algılayıp kapatmış olabilir.")
        EndIf
    Else
        _LogError("Manuel başlat: winws çalıştırılamadı: " & $winwsPath)
        MsgBox(16 + 8192, "Dosya Bulunamadı", "WinWS exe dosyası bulunamadı veya çalıştırılamadı!")
    EndIf
EndFunc

; Seçili motor, strateji ve filtreye göre winws argümanlarını oluşturur; gereken hostlist dosyasını hazırlar.
Func _BuildActiveWinwsArgs($sStrategy)
    Local $sFilterMode = _WinwsFilterModeFromText(GUICtrlRead($cmbFilter))
    _EnsureHostlistFile($sFilterMode, $sStrategy, $hostlistPath, $normalHostlistPath)
    Return _BuildWinwsArgs($currentEngine, $winwsPath, $sStrategy, $sFilterMode, $exludelistPath, $hostlistPath, $normalHostlistPath)
EndFunc

; Servis durmuş görünürken winws yeniden çalışıyorsa (Windows/elle yeniden başlatma) durumu
; tazeler ve "servis durdu" uyarısını yeniden silahlandırır; böylece sonraki durmada da uyarılır.
Func _RefreshIfServiceRecovered()
    If GUICtrlRead($lblStatusText) <> "SERVİS YÜKLÜ - DURDU" Then Return
    _LogInfo("Servis yeniden çalışıyor")
    $bServiceStoppedWarned = False
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
EndFunc

; Tepsi: hazır profilleri akıllı analizle sınar, en uygununu seçtirir.
Func _LiteSmartFromTray()
    If $currentEngine <> "Zapret2" Then Return MsgBox(48 + 8192, "Akıllı Analiz", "Akıllı analiz yalnızca Zapret2 motoruyla çalışır.")
    If GUICtrlRead($lblStatusText) <> "ÇALIŞMAYA HAZIR" Then
        Return MsgBox(48 + 8192, "Akıllı Analiz", "Akıllı analiz için Zapret kapalı olmalı ve DNS sorunu olmamalı (durum: ÇALIŞMAYA HAZIR).")
    EndIf
    Local $aCand[0][2]
    For $i = 0 To UBound($g_aStrategies) - 1
        _SmartAddCandidate($aCand, $g_aStrategies[$i][1], "Hazır: " & $g_aStrategies[$i][0])
    Next
    ShowGUI()
    GUICtrlSetData($lblStatusText, "AKILLI ANALİZ YAPILIYOR...")
    GUISetState(@SW_DISABLE, $hGUI)
    Local $sChosen = _SmartUI_Run($aCand, @ScriptDir, $winwsPath, IniRead($iniPath, "SmartAnalysis", "Targets", $SMART_DEFAULT_TARGETS), _
            @ScriptDir & "\config\smart_results.tsv", "", $hGUI)
    GUISetState(@SW_ENABLE, $hGUI)
    GUICtrlSetData($lblStatusText, "ÇALIŞMAYA HAZIR")
    If $sChosen = "" Then Return
    ; Lite'ta "Analiz Sonucu" yok: aynı parametreli ilk hazır profil seçilir.
    For $i = 0 To UBound($g_aStrategies) - 1
        If StringReplace($g_aStrategies[$i][1], '"', "") == StringReplace($sChosen, '"', "") Then
            _LoadStrategyList($g_aStrategies[$i][0])
            _RefreshStrategyLabel()
            _UpdateFilterForStrategy()
            ExitLoop
        EndIf
    Next
EndFunc

Func StopWinws($ctrlID, $statusID, $aBtns)
    If ProcessExists($zapretPID) Then ProcessClose($zapretPID)
    ; Süreç kapatılamazsa (yetki, takılı sürücü) arayüz sonsuz döngüde kilitlenmesin.
    Local $aWinws[2] = ["winws2.exe", "winws.exe"]
    If Not _CloseProcessesByName($aWinws) Then
        _LogError("Durdur: winws kapatılamadı")
        MsgBox(48 + 8192, "Uyarı", "Zapret motoru (winws) kapatılamadı." & @CRLF & @CRLF & _
                "Görev Yöneticisi'nden elle sonlandırmanız veya bilgisayarı yeniden başlatmanız gerekebilir.")
    EndIf
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
    _LogInfo("Manuel mod durduruldu")
    $isZapretRunning = False
    GUICtrlSetData($ctrlID, "ZAPRET'İ BAŞLAT")
    CheckServiceStatus($ctrlID, $statusID, $aBtns, $cmbFilter)
EndFunc

Func InstallServiceClean($chkID)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Lütfen hazır stratejilerden birini seçin.")

    Local $binArgs = _BuildActiveWinwsArgs($activeStrategy)

    Local $fullBinPath = '"' & $winwsPath & '" ' & $binArgs
    $fullBinPath = StringReplace($fullBinPath, '"', '\"')

    RemoveService()
    Sleep(500)

    Local $iCreate = RunWait(@ComSpec & " /c sc create " & $serviceName & ' binPath= "' & $fullBinPath & '" start= auto', "", @SW_HIDE)
    _LogInfo("Servis kur (" & $currentEngine & ", " & GUICtrlRead($cmbStrategy) & "): sc create çıkış kodu " & $iCreate & " | " & $binArgs)
    If $iCreate = 0 Then
        RunWait(@ComSpec & " /c sc start " & $serviceName, "", @SW_HIDE)
        MsgBox(64 + 8192, "Başarılı", "Seçilen profil servis olarak kuruldu.")
    Else
        MsgBox(16 + 8192, "Servis Kurulamadı", "Windows servisi oluşturulamadı (sc create hata kodu " & $iCreate & ")." & @CRLF & @CRLF & _
                "'Servis ve Kalıntıları Temizle' butonuna basıp tekrar deneyin. Sorun sürerse logs\app.log dosyasıyla birlikte bildirin.")
    EndIf
EndFunc

Func RemoveService()
    _LogInfo("Servis ve WinDivert kalıntıları kaldırılıyor")
    RunWait(@ComSpec & " /c sc stop " & $serviceName & " & sc delete " & $serviceName & " & sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
EndFunc
