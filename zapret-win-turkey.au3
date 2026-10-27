#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=ui\simge\kilit.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=RedRiveRR Zapret - Discord erişimi için Zapret ve Zapret2 kontrol aracı
#AutoIt3Wrapper_Res_Fileversion=5.1.1.0
#AutoIt3Wrapper_Res_ProductVersion=5.1.1
#AutoIt3Wrapper_Res_LegalCopyright=Ali Mali (zapret-win-turkey), RedRiveRR
#AutoIt3Wrapper_Res_Language=1055
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <File.au3>
#include <MsgBoxConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <ProgressConstants.au3>
#include <TrayConstants.au3>
#include <ComboConstants.au3>
#include <EditConstants.au3>
#include <GuiComboBox.au3>
#include "lib\Process.au3"
#include "lib\Blockcheck.au3"
#include "lib\Network.au3"
#include "lib\Winws.au3"
#include "lib\Strategies.au3"
#include "lib\Version.au3"
#include "lib\Log.au3"
#include "lib\Conflicts.au3"
#include "lib\Update.au3"
#include "lib\Diag.au3"
#include "lib\SmartAnalysis.au3"
#include "lib\Service.au3"
#include "ui\SmartAnalysisUI.au3"
#include "lib\Health.au3"
#include "lib\Schedule.au3"
#include "ui\SettingsUI.au3"
#include "ui\Theme.au3"
#include "ui\WebView2.au3"
#include "lib\WebState.au3"
#include "lib\AppState.au3"
#include "lib\LanShare.au3"
#include <ScreenCapture.au3>
#include "lib\Install.au3"

; --- BAŞSIZ SAĞLIK KONTROLÜ (Görev Zamanlayıcı: /saglik) ---
; Pencere açılmaz; servis modunda Discord bağlantısını kontrol edip gerekirse onarır (lib/Health.au3).
If $CmdLine[0] >= 1 And $CmdLine[1] = $HEALTH_ARG Then
    _LogInit(@ScriptDir & "\logs\app.log")
    Exit _HealthRun(@ScriptDir, "ZapretService", $APP_NAME)
EndIf

; --- GELİŞTİRİCİ: ARAYÜZ ÖNİZLEMESİ (/arayuz-onizleme <klasör>) ---
; Açılış kontrollerini (çakışma, eski servisler, DNS, WinDivert temizliği) atlar; her sayfanın
; ekran görüntüsünü klasöre kaydedip çıkar. Çalışan bir kuruluma/servise dokunmaz.
Global $g_sUiPreviewDir = ""
; Yeni arayüz (WebView2): config.ini [Arayuz] Yeni=1 veya /yeni-arayuz ile açılır.
Global $g_bWebUi = False, $hWebGui = 0, $g_bWebPageReady = False, $g_sWebLastJson = ""
Global $g_hWebStartTimer = 0, $g_hWebSyncTimer = 0, $g_hWebHealthTimer = 0, $g_sWebHealth = "", $g_sWebLastStatus = ""
; Yeni arayüzün Strateji ekranı: seçilen analiz türü (-1 = seçici penceresi açılır), son gönderilen mesaj
Global $g_iWebAnalysisChoice = -1, $g_sWebLastStratJson = "", $g_hWebStratTimer = 0, $g_sWebSmartStamp = ""
Global $g_sWebSmartSummary = "", $g_aWebSmartRows[0][1]
; Servis ekranı: servis durumu 5 sn'de, onarım görevi 30 sn'de bir okunur (sc/schtasks süreç başlatır)
Global $g_sWebLastSvcJson = "", $g_hWebSvcTimer = 0, $g_hWebTaskTimer = 0, $g_sWebSvcState = "", $g_bWebTaskExists = False
Global $g_bWebHealthIni = True, $g_bWebRestartIni = False, $g_sWebSvcHealth = ""
; DNS ekranı: etkin DNS sunucuları ("?" = okunmadı; PowerShell gerektirir, yalnızca sekme açılınca ve değişiklikten sonra okunur)
Global $g_sWebDnsServers = "?", $g_bWebDnsReread = False, $g_sWebLastDnsJson = ""
Global $g_sWebLastOtherJson = "", $g_sWebUpdateIni = "1"
Global $g_sPrevTestShot = "" ; önizleme: deneme penceresi görüntüsünün yolu
Global $g_hWebYieldTimer = 0
Global $g_sPrevBusyLeft = "" ; önizleme: alt pencere kapanırken kuyrukta kalan mesaj
$g_sUiYieldHook = "_UiYield"
If $CmdLine[0] >= 2 And $CmdLine[1] = "/arayuz-onizleme" Then $g_sUiPreviewDir = $CmdLine[2]

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
_LogInfo("=== " & $APP_NAME & " v" & $APP_VERSION & " başlatıldı | Windows " & @OSVersion & " " & @OSBuild & " " & @OSArch)

; --- GÜVENLİK UYARILARINI KALDIR ---
RunWait('powershell -Command "Get-ChildItem -Path ''' & @ScriptDir & ''' -Recurse | Unblock-File"', "", @SW_HIDE)

; --- ESKİ KURULUM SERVİSLERİ (başka klasörü gösteren ZapretService / dnscrypt-proxy) ---
If $g_sUiPreviewDir = "" And Not _HandleForeignServices(@ScriptDir) Then Exit

; --- ÇAKIŞMA KONTROLÜ (GoodbyeDPI, ByeDPI, başka klasörden çalışan Zapret) ---
If $g_sUiPreviewDir = "" And Not _HandleStartupConflicts(@ScriptDir) Then Exit

Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

; --- Ayarlar ve Dosya Yolları ---
Local $serviceName = "ZapretService"
Local $hostlistPath = @ScriptDir & "\config\autohostlist.txt"
Local $normalHostlistPath = @ScriptDir & "\config\hostlist.txt"
Local $iniPath = @ScriptDir & "\config\config.ini"
Local $exludelistPath = @ScriptDir & "\config\excludelist.txt"
Global $strategiesIniPath = @ScriptDir & "\config\strategies.ini"
; Paketle gelen varsayılan site listeleri (config\varsayilan\) yalnız eksikse kopyalanır.
_InstallEnsureConfigDefaults(@ScriptDir)
; Önceki oturumdan (ör. çökme) kalmış paylaşım kaydındaki bağlantı satırları silinir.
If Not ProcessExists("go-pcap2socks.exe") Then _LanLogCompactFile(@ScriptDir)
Global $g_aStrategies = _StrategyDefaults("Zapret2")

; --- CONFIG DOSYASINDAN AYARLARI OKU ---
Local $iniEngine = IniRead($iniPath, "Settings", "ActiveEngine", "0") ; 0 = Zapret2, 1 = Zapret1
Local $iniStrategy = IniRead($iniPath, "Settings", "ActiveStrategy", "Analiz Sonucu")
; 0 = Kapalı, 1 = Auto, 2 = Manuel
Local $iniFilterMode = IniRead($iniPath, "Settings", "FilterMode", "1")
Local $iniDnscryptInstalled = IniRead($iniPath, "Settings", "DnscryptInstalled", "0") ; <--- YENİ EKLENEN

; --- DİNAMİK MOTOR DEĞİŞKENLERİ ---
Global $strategyFile = ""
Global $winwsPath = ""
Global $blockcheckPath = ""
Global $logPath = ""
Global $currentEngine = "Zapret2"

; --- Global Durum Değişkenleri ---
Global $isZapretRunning = False
Global $zapretPID = 0
Global $pcapPID = 0
; Ağ paylaşımı: kullanılan cihaz ayarları (_LanPlan), kart (_LanParseAdapter), son hata, otomatik yeniden başlatma sayısı
Global $g_aLanPlan[5] = ["", "", "", "", ""], $g_aLanAdapter[5] = ["", "", "", False, ""], $g_sLanError = "", $g_iLanRestarts = 0
; Yeni arayüzün paylaşım sayfası: Npcap durumu ("var/uyumsuz/yok", "" = okunmadı), cihaz MTU'su, son gönderilen mesaj
Global $g_sLanNpcap = "", $g_sLanMtu = "", $g_sWebLastLanJson = ""
; Yeni arayüz: paylaşım başlat/durdur bitti, sayfadaki "Başlatılıyor…" kilidi açılsın (bir sonraki eşitlemede "bitti").
Global $g_bWebLanDone = False
Global $bServiceStoppedWarned = False
Global $bDnsReset = True
Global $g_sEngineFooter = ""
Global $g_iFooterTicks = 0
Global $strategyTestPID = 0

; Blockcheck butonuna art arda tıklanmasını engelleyen kilit.
Global $bBlockcheckBusy = False
Global $hBlockcheckUnlockTimer = 0
Global $bBlockcheckEnableAfterLock = True

; DNSCrypt butonuna art arda tıklamayı engelleyen kilit.
Global $bDnscryptBusy = False
Global $hDnscryptUnlockTimer = 0

; Servis kurulum butonuna art arda tıklamayı engelleyen kilit.
Global $bInstallServiceBusy = False
Global $hInstallServiceUnlockTimer = 0
Global $bInstallServiceEnableAfterLock = True

; --- Klasik pencere: alimali54/zapret-win-turkey v4.5'in özgün arayüzü (yeni arayüzde "Eski arayüze geç") ---
; Alt pencereler (Ayarlar, analiz) ui/Theme.au3 ile çizilir. Başlık "$APP_NAME v..." kalmalı: sağlık kontrolü
; açık programı başlıktan tanır.
_UiInit()
Global $hGUI = GUICreate($APP_NAME & " v" & $APP_VERSION, 400, 580)
GUISetBkColor(0xFFFFFF, $hGUI)

; --- Tepsi Menüsü ---
Local $trayShow = TrayCreateItem("Göster")
TrayItemSetOnEvent(-1, "ShowGUI")
TrayCreateItem("Ayarlar...")
TrayItemSetOnEvent(-1, "_OpenSettings")
TrayCreateItem("Tanılama paketi oluştur")
TrayItemSetOnEvent(-1, "_DiagCreateFromTray")
TrayCreateItem("")
Local $trayExit = TrayCreateItem("Kapat")
TrayItemSetOnEvent(-1, "_SaveConfigAndExit")
TraySetOnEvent($TRAY_EVENT_PRIMARYDOUBLE, "ShowGUI")
TraySetClick(16)
TraySetToolTip($APP_NAME)
; Derlenmemiş çalıştırmada (geliştirme/önizleme) tepside de kilit simgesi; derlenmiş exe kendi simgesini kullanır.
If Not @Compiled And FileExists(@ScriptDir & "\ui\simge\kilit.ico") Then TraySetIcon(@ScriptDir & "\ui\simge\kilit.ico")


; --- Üst Durum Paneli ---
Global $lblStatusBg = GUICtrlCreateLabel("", 15, 15, 370, 75)
GUICtrlSetBkColor(-1, 0xF2F4F7)
GUICtrlSetState(-1, $GUI_DISABLE)
Local $lblStatusText = GUICtrlCreateLabel("SİSTEM HAZIRLANIYOR...", 15, 30, 370, 25, $SS_CENTER)
GUICtrlSetFont(-1, 12, 800, 0, "Segoe UI")
GUICtrlSetColor(-1, 0xE67E22)
GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)

Local $pBar = GUICtrlCreateProgress(15, 75, 370, 15, $PBS_MARQUEE)
GUICtrlSetState(-1, $GUI_HIDE)

Local $lblStrategyInfo = GUICtrlCreateLabel("Strateji Durumu: Kontrol Ediliyor...", 15, 55, 370, 20, $SS_CENTER)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x666666)
GUICtrlSetBkColor(-1, $GUI_BKCOLOR_TRANSPARENT)

; --- Ana düğme ---
Local $btnRunZapret = GUICtrlCreateButton("▶   Başlat", 50, 95, 300, 55)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 11, 800, 0, "Segoe UI")

; --- Motor / Strateji / Filtre (öğe metinleri program mantığında kullanılır, değiştirmeyin) ---
GUICtrlCreateLabel("Motor:", 50, 168, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Local $cmbEngine = GUICtrlCreateCombo("Zapret2 (yeni motor)", 175, 165, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetData($cmbEngine, "Zapret (klasik motor)")
If $iniEngine == "1" Then GUICtrlSetData($cmbEngine, "Zapret (klasik motor)", "Zapret (klasik motor)")
GUICtrlSetFont($cmbEngine, 9, 400, 0, "Segoe UI")
GUICtrlSetState($cmbEngine, $GUI_DISABLE)

GUICtrlCreateLabel("Strateji:", 50, 203, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbStrategy = GUICtrlCreateCombo("Analiz Sonucu", 175, 200, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetFont($cmbStrategy, 9, 400, 0, "Segoe UI")
GUICtrlSetState($cmbStrategy, $GUI_DISABLE)

GUICtrlCreateLabel("Filtre:", 50, 238, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbFilter = GUICtrlCreateCombo("Kapalı (tüm trafik)", 175, 235, 175, 25, $CBS_DROPDOWNLIST)
Global $sFilterSelectionBeforeOOB = ""
Global $bFilterWasEnabledBeforeOOB = False
Global $bOOBFilterLock = False
GUICtrlSetData($cmbFilter, "Auto (otomatik liste)|Manuel (hostlist.txt)")
; INI'den okunan değere göre varsayılanı seç
If $iniFilterMode == "1" Then
    GUICtrlSetData($cmbFilter, "Auto (otomatik liste)", "Auto (otomatik liste)")
ElseIf $iniFilterMode == "2" Then
    GUICtrlSetData($cmbFilter, "Manuel (hostlist.txt)", "Manuel (hostlist.txt)")
Else
    GUICtrlSetData($cmbFilter, "Kapalı (tüm trafik)", "Kapalı (tüm trafik)")
EndIf
$sFilterSelectionBeforeOOB = GUICtrlRead($cmbFilter)
GUICtrlSetFont($cmbFilter, 9, 400, 0, "Segoe UI")
GUICtrlSetState($cmbFilter, $GUI_DISABLE)

; --- Ağ paylaşımı ve diğer düğmeler ---
Global $btnLanShare = GUICtrlCreateButton("Ağdaki Cihazlarla Paylaş", 50, 280, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

Local $btnAnalyze = GUICtrlCreateButton("ISS Analizi (Blockcheck) Yap", 50, 325, 300, 35)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnInstallService = GUICtrlCreateButton("Servis Olarak Yükle (Otomatik Başlat)", 50, 370, 300, 35)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $sInitialDnscryptText = ($iniDnscryptInstalled == "1") ? "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır" : "Dnscrypt-proxy servisi kur"
Global $btnDnscrypt = GUICtrlCreateButton($sInitialDnscryptText, 50, 415, 300, 35)
_StateSetCryptOn($iniDnscryptInstalled == "1") ; düğmenin ilk metniyle aynı başlangıç
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnRemoveService = GUICtrlCreateButton("Servis ve Kalıntıları Temizle", 50, 460, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

; Bu fork'un eklemeleri: ayarlar penceresi ve yeni arayüze dönüş.
Global $btnPageSettings = GUICtrlCreateButton("Ayarlar", 50, 505, 145, 30)
GUICtrlSetFont(-1, 9.5, 600, 0, "Segoe UI")
Global $btnNewUi = GUICtrlCreateButton("Yeni arayüz", 205, 505, 145, 30)
GUICtrlSetFont(-1, 9.5, 600, 0, "Segoe UI")

Global $lblFooter = GUICtrlCreateLabel("", 0, 543, 400, 32, $SS_CENTER)
GUICtrlSetFont(-1, 8.5, 400, 0, "Consolas")
GUICtrlSetColor(-1, 0x95A5A6)

; Klasik pencerede yer almayan ama yeni arayüzün komutlarını ana döngüye taşıyan olay kimlikleri (gizli).
Global $btnSvcSettings = __ClassicHidden(), $btnPageDiag = __ClassicHidden(), $btnPageLogs = __ClassicHidden()

; Düğme Array'lerine yeni butonu ekledik ki sistem hazır olduğunda kilitleri otomatik açılsın
Local $aCriticalButtons[7] = [$btnRunZapret, $btnAnalyze, $btnInstallService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]
Local $aOtherButtons[7] = [$btnAnalyze, $btnInstallService, $btnRemoveService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]

If $g_sUiPreviewDir = "" And _WebUiWanted() Then
    _WebUiStart()
Else
    GUISetState(@SW_SHOW, $hGUI)
EndIf
If $g_sUiPreviewDir <> "" Then _MainUiPreviewAndExit($g_sUiPreviewDir)

; --- İLK YOLLARI VE STRATEJİ LİSTESİNİ DOĞRULA ---
_UpdateEnginePaths(GUICtrlRead($cmbEngine))
_LoadStrategyList($iniStrategy)
_RefreshStrategyLabel()
_UpdateFilterForStrategy()

; --- GÜVENLİ AÇILIŞ AKIŞI VE DİNAMİK DNS ZEHİRLENMESİ KONTROL DÖNGÜSÜ ---
_ServiceDriverCleanup($serviceName)
_SetStatus("DNS KONTROL EDİLİYOR...")

Local $isDnsChangedByApp = False

While 1
    Local $isPoisoned = CheckDnsPoisoningSilent()

    If $isPoisoned Then
        _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
		GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; <--- DNS zehirlense bile bu buton hep tıklanabilir olsun!
        _SetStatus("DNS ZEHİRLENMESİ SAPTANDI!")
        GUICtrlSetColor($lblStatusText, 0xC0392B)

        ; 2. TUR: Uygulama DNS değiştirdi ama hala zehirliyse (TT engelliyorsa)
        If $isDnsChangedByApp Then
            MsgBox(48 + 8192, "Kritik Uyarı", "Düz DNS değişikliği işe yaramadı, port 53'e müdahale var." & @CRLF & @CRLF & _
                    "Yapabilecekleriniz şunlar:" & @CRLF & @CRLF & _
                    "1- Program içinden dnscrypt-proxy servisi kurmak" & @CRLF & @CRLF & _
                    "2- YogaDNS gibi harici bir DNS client'i kullanmak")
            ExitLoop
        EndIf

        ; 1. TUR: Zehirlenme ilk kez saptandıysa soru sor
        Local $iAsk = MsgBox(36 + 8192, "DNS Zehirlenmesi Saptandı", _
                "ISS tarafından DNS Zehirlenmesi saptandı!" & @CRLF & @CRLF & _
                "Sistem DNS adresiniz Cloudflare (1.1.1.1 / 1.0.0.1) olarak ayarlansın mı?")

        If $iAsk = 6 Then ; EVET
            _SetStatus("DNS AYARLANIYOR...")
            If Not _SetSystemDNS() Then
                MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)
                ExitLoop
            EndIf
            $isDnsChangedByApp = True
            _SetStatus("DNS TEST EDİLİYOR...")
            Sleep(1000)
            ContinueLoop ; Döngüyü başa sar, nslookup ile yeni DNS'i test et
        Else ; HAYIR
			GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; <--- HAYIR dese bile bu buton açık kalsın!
            ExitLoop
        EndIf
    Else
        ; Zehirlenme yoksa her şey normal devam etsin
        CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
		GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; <--- Sistem hazır olduğunda butonu aktif et!
        _RefreshStrategyLabel()
        ExitLoop
    EndIf
WEnd

; --- GÜNCELLEME KONTROLÜ (arka planda; config.ini'de UpdateCheck=0 ile kapatılır) ---
If IniRead($iniPath, "Settings", "UpdateCheck", "1") <> "0" Then _UpdateStartCheck($APP_UPDATE_REPO)

; --- Ana Döngü ---
Local $hProcessTimer = TimerInit() ; ZAMANLAYICIYI BAŞLAT (Bunu While 1'in hemen üstüne koy)

; --- AÇILIŞTA DNSCRYPT SERVİS DURUMUNU KONTROL ET ---
_CheckDnscryptStatus()

; --- Exe adı/yolu değiştiyse otomatik onarım görevini bu programa yönelt ---
_HealthTaskRepair()

; --- SERVİS ÇALIŞIYORSA DISCORD'A GERÇEKTEN ULAŞILIYOR MU? ---
_StartupServiceCheck()

While 1
    Local $nMsg = GUIGetMsg()
    ; Yeni arayüz: sayfa komutları eski düğme olaylarına çevrilir, durum sayfaya aktarılır.
    If $g_bWebUi Then $nMsg = _WebUiTick($nMsg)

    ; Kenar menüsü, hover ve durum renkleri (ui/Theme.au3)
    _UiTick($hGUI)

    ; DNSCrypt çalışırken kuyruğa alınan tıklamaları da atla.
    If $nMsg = $btnDnscrypt And $bDnscryptBusy Then ContinueLoop

    ; Servis kurulumu sırasında kuyruğa alınan tıklamaları da atla.
    If $nMsg = $btnInstallService And $bInstallServiceBusy Then ContinueLoop

    ; Servis kurulum işlemi bittikten 1,5 saniye sonra butonu uygun durumdaysa aç.
    If $bInstallServiceBusy And $hInstallServiceUnlockTimer <> 0 Then
        If TimerDiff($hInstallServiceUnlockTimer) >= 1500 Then
            $bInstallServiceBusy = False
            $hInstallServiceUnlockTimer = 0
            If $bInstallServiceEnableAfterLock And _StateStatus() = "ÇALIŞMAYA HAZIR" Then
                GUICtrlSetState($btnInstallService, $GUI_ENABLE)
            EndIf
        EndIf
    EndIf

    ; DNSCrypt işlemi bittikten sonra 1,5 saniye daha kilitli tut.
    If $bDnscryptBusy And $hDnscryptUnlockTimer <> 0 Then
        If TimerDiff($hDnscryptUnlockTimer) >= 1500 Then
            $bDnscryptBusy = False
            $hDnscryptUnlockTimer = 0
            GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)
        EndIf
    EndIf

    ; Kilitliyken kuyruğa girmiş eski tıklamaları da işlemeden atla.
    If $nMsg = $btnAnalyze And $bBlockcheckBusy Then ContinueLoop

    ; İşlem tamamlandıktan sonra kısa bir süre daha kilidi koru; hızlı/önceden kuyruğa alınmış
    ; tıklamalar bu aralıkta etkisiz kalır.
    If $bBlockcheckBusy And $hBlockcheckUnlockTimer <> 0 Then
        If TimerDiff($hBlockcheckUnlockTimer) >= 1500 Then
            $bBlockcheckBusy = False
            $hBlockcheckUnlockTimer = 0
            If $bBlockcheckEnableAfterLock Then GUICtrlSetState($btnAnalyze, $GUI_ENABLE)
        EndIf
    EndIf

	; --- ZAPRET ÇALIŞMA DURUMU VE ÇÖKME KONTROLÜ ---
    ; Sadece 1000 milisaniyede (1 saniyede) bir kontrol et! CPU'yu yorma.
    If TimerDiff($hProcessTimer) > 1000 Then
		Local $bZapretAlive = ProcessExists("winws.exe") Or ProcessExists("winws2.exe")

		If $bZapretAlive Then
			; 1. Zapret yaşıyorsa LAN Paylaşım butonunu aktif et
			If BitAND(GUICtrlGetState($btnLanShare), $GUI_DISABLE) Then GUICtrlSetState($btnLanShare, $GUI_ENABLE)
			_LanShareWatch()
			; Servis durduktan sonra yeniden başladıysa "DURDU" yazısı takılı kalmasın.
			_RefreshIfServiceRecovered()
		Else
			; 2. Zapret ölmüşse LAN Paylaşım butonunu devre dışı bırak, yazısını sıfırla ve go-pcap2socks'u kapat
			If BitAND(GUICtrlGetState($btnLanShare), $GUI_ENABLE) Then
				GUICtrlSetState($btnLanShare, $GUI_DISABLE)

				If _StateLanOn() Then _LanShareStop()
			EndIf

			; 3. Zapret ölmüşse VE bizim arayüz hala "Çalışıyor" modundaysa (Çökme veya Harici Kapatma durumu)
			If $isZapretRunning Then
				_LogError("Manuel mod: winws beklenmedik şekilde kapandı (çökme veya dış müdahale)")
				StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
				; Kullanıcıya Fortnite ve Anti-Cheat uyarısını ver
				MsgBox(16 + 8192, "Uyarı: Zapret Kapatıldı", "Zapret motoru beklenmedik bir şekilde çöktü veya dışarıdan sonlandırıldı!" & @CRLF & @CRLF & _
                    "Sisteminizdeki Anti-Cheat yazılımları Zapret'i tehdit olarak algılayıp kapatmış olabilir.")
			EndIf

			; 4. YENİ: Zapret ölmüşse VE arayüz hala "SERVİS MODU AKTİF" diyorsa (Servis Modu Çökme durumu)
			If _StateStatus() = "SERVİS MODU AKTİF" Then
				; Sistemi kontrol fonksiyonuna yolla, o zaten "DURDU" yazdırıp ortak uyarıyı verecek!
				CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
			EndIf

		EndIf
		_UpdatePollAndNotify($APP_VERSION, $APP_RELEASES_URL)
		; Alt satırdaki onarım durumunu 30 sn'de bir tazele (sağlık kontrolü arka planda yazar).
		$g_iFooterTicks += 1
		If $g_iFooterTicks >= 30 Then
		    $g_iFooterTicks = 0
		    _RefreshFooter()
		EndIf
	$hProcessTimer = TimerInit()
	EndIf

    Switch $nMsg
        Case $GUI_EVENT_CLOSE
            _SaveConfigAndExit()

        Case $btnPageSettings, $btnSvcSettings
            _OpenSettings()

        Case $btnPageDiag
            _DiagCreateFromTray()

        Case $btnNewUi
            _WebUiSwitchToNew()

        Case $btnPageLogs
            ShellExecute(@ScriptDir & "\logs")

        Case $GUI_EVENT_MINIMIZE
            _MainWindowHide()
            TraySetToolTip($APP_NAME & " çalışıyor")

        Case $cmbEngine
            _UpdateEnginePaths(GUICtrlRead($cmbEngine))
            _LoadStrategyList("Analiz Sonucu")
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            _RefreshStrategyLabel()

        Case $cmbStrategy
            _RefreshStrategyLabel()
            _UpdateFilterForStrategy()

		Case $btnAnalyze
            ; Kilit ilk iş olarak, herhangi bir MsgBox açılmadan önce konur.
            If Not $bBlockcheckBusy Then
                $bBlockcheckBusy = True
                $hBlockcheckUnlockTimer = 0
                $bBlockcheckEnableAfterLock = (BitAND(GUICtrlGetState($btnAnalyze), $GUI_ENABLE) <> 0)
                GUICtrlSetState($btnAnalyze, $GUI_DISABLE)

            ; Servis kuruluysa: servis stratejisini güncelleme akışı.
            ; Değilse Zapret2: tam analiz / hızlı akıllı test / önceki sonuçlar seçimi.
            Local $bStartNewAnalysis = True
            If _ServiceIsInstalled($serviceName) Then
                _ServiceStrategyUpdateFlow()
                $bStartNewAnalysis = False
            ElseIf $currentEngine = "Zapret2" Then
                $bStartNewAnalysis = _HandleZapret2AnalysisChoice()
            EndIf

            If $bStartNewAnalysis Then
                If $currentEngine = "Zapret2" Then
					Local $iConfirm = 1
				Else
					Local $iConfirm = MsgBox(33 + 8192, "Bilgi", "Analiz işlemi 5-10 dakika sürebilir." & @CRLF & "Lütfen bitene kadar bekleyin.")
				EndIf

				If $iConfirm = 1 Then
                    _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
                    GUICtrlSetState($btnRemoveService, $GUI_DISABLE)
                    _SetStatus("ANALİZ YAPILIYOR...")
                    GUICtrlSetState($pBar, $GUI_SHOW)
                    GUICtrlSetData($lblStrategyInfo, "")
                    GUICtrlSendMsg($pBar, $PBM_SETMARQUEE, True, 50)

                    If $currentEngine = "Zapret2" Then
                        RunBlockcheck2($btnAnalyze)
                    Else
                        RunBlockcheck($btnAnalyze)
                    EndIf

                    GUICtrlSendMsg($pBar, $PBM_SETMARQUEE, False, 0)
                    GUICtrlSetState($pBar, $GUI_HIDE)
                    _SetButtonsState($aCriticalButtons, $GUI_ENABLE)
                    GUICtrlSetState($btnRemoveService, $GUI_ENABLE)
                    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
                    _SetStatus("ANALİZ TAMAMLANDI")
                    _RefreshStrategyLabel()
                EndIf
            EndIf

            _MainWindowShow(True)

            ; Analiz akışı içindeki genel buton açma işlemleri kilidi kaldıramasın.
            If _StateStatus() = "DNS ZEHİRLENMESİ SAPTANDI!" Then $bBlockcheckEnableAfterLock = False
            GUICtrlSetState($btnAnalyze, $GUI_DISABLE)
            $hBlockcheckUnlockTimer = TimerInit()
            EndIf ; $bBlockcheckBusy kilit bloğu

		Case $btnLanShare
            If Not _StateLanOn() Then
                $g_iLanRestarts = 0
                _LanShareStart(True)
            Else
                _LanShareStop()
            EndIf
            $g_bWebLanDone = True

        Case $btnRunZapret
            If $isZapretRunning = False Then
                StartWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            Else
                StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            EndIf

        Case $btnInstallService
            ; Kilidi fonksiyonlardan ve olası mesaj pencerelerinden önce koy.
            If $bInstallServiceBusy Then ContinueLoop
            $bInstallServiceBusy = True
            $hInstallServiceUnlockTimer = 0
            $bInstallServiceEnableAfterLock = (BitAND(GUICtrlGetState($btnInstallService), $GUI_ENABLE) <> 0)
            GUICtrlSetState($btnInstallService, $GUI_DISABLE)

            InstallServiceClean($cmbFilter)
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)

            ; Yardımcı fonksiyonlar butonu yeniden açmış olsa bile kilit süresince kapalı tut.
            GUICtrlSetState($btnInstallService, $GUI_DISABLE)
            $hInstallServiceUnlockTimer = TimerInit()

        Case $btnDnscrypt
            ; Kilidi ilk iş olarak, dosya kontrolü veya uzun işlemler başlamadan önce koy.
            If $bDnscryptBusy Then ContinueLoop
            $bDnscryptBusy = True
            $hDnscryptUnlockTimer = 0
            GUICtrlSetState($btnDnscrypt, $GUI_DISABLE)

            Local $sProxyDir = @ScriptDir & "\bin\dnscrypt-proxy"
            Local $sProxyPath = $sProxyDir & "\dnscrypt-proxy.exe"

            If Not FileExists($sProxyPath) Then
                MsgBox(16, "Hata", "DNSCrypt dosyası bulunamadı!" & @CRLF & $sProxyPath)
                $hDnscryptUnlockTimer = TimerInit()
                ContinueLoop
            EndIf

            If Not _StateCryptOn() Then
                _SetStatus("DNSCRYPT KURULUYOR...")
                _LogInfo("DNSCrypt servisi kuruluyor")

                RunWait('"' & $sProxyPath & '" -service install', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service start', $sProxyDir, @SW_HIDE)
                If Not _SetDNS_Localhost() Then MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)

                _DnscryptSetOn(True)
                ;MsgBox(64 + 8192, "Başarılı", "DNSCrypt servisi kuruldu.")
            Else
                _SetStatus("DNSCRYPT KALDIRILIYOR...")
                _LogInfo("DNSCrypt servisi kaldırılıyor")

                RunWait('"' & $sProxyPath & '" -service stop', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service uninstall', $sProxyDir, @SW_HIDE)
                If Not _ResetSystemDNS() Then MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)

                _DnscryptSetOn(False)
                ;MsgBox(64 + 8192, "Bilgi", "DNSCrypt servisi kaldırıldı ve DNS otomatiğe (DHCP) alındı.")
            EndIf

            ; --- AÇILIŞTAKİ GÜVENLİ KONTROL AKIŞININ AYNISI (BAŞTAN AÇILMIŞ GİBİ) ---
            _DnsRecheckAfterChange()

            ; Yardımcı fonksiyonlar butonu tekrar açmış olsa bile işlem sonunda kilitle.
            ; Kuyrukta bekleyen tıklamalar kilit süresince ana döngüde atlanır.
            GUICtrlSetState($btnDnscrypt, $GUI_DISABLE)
            $hDnscryptUnlockTimer = TimerInit()

		Case $btnRemoveService
            RemoveService()

			; --- DNSCRYPT SERVİSİNİ VE KALINTILARINI DA TEMİZLE ---
            Local $sProxyDir = @ScriptDir & "\bin\dnscrypt-proxy"
            Local $sProxyPath = $sProxyDir & "\dnscrypt-proxy.exe"
            If FileExists($sProxyPath) Then
                RunWait('"' & $sProxyPath & '" -service stop', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service uninstall', $sProxyDir, @SW_HIDE)
            EndIf
            _DnscryptSetOn(False)

            ; --- YENİ EKLENEN ADIM: DNS'i Otomatiğe (DHCP) Al ---
            _SetStatus("SİSTEM SIFIRLANIYOR...")
            $bDnsReset = _ResetSystemDNS()

            $isPoisoned = CheckDnsPoisoningSilent()
            If Not $isPoisoned Then CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
            _RefreshStrategyLabel()
            If $bDnsReset Then
                MsgBox(64 + 8192, "Bilgi", "WinDivert, Zapret, Dnscrypt temizlendi ve DNS ayarları otomatiğe (DHCP) alındı.")
            Else
                MsgBox(48 + 8192, "Bilgi", "WinDivert, Zapret, Dnscrypt temizlendi." & @CRLF & @CRLF & $NET_MSG_NO_ADAPTER)
            EndIf

			If $isPoisoned Then
				_SetButtonsState($aCriticalButtons, $GUI_DISABLE)
				GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; <--- Servisler temizlense ve zehirlenme olsa bile bu buton hep açık kalacak!
				_SetStatus("DNS ZEHİRLENMESİ SAPTANDI!")
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
    GUICtrlSetData($cmbStrategy, "")
    GUICtrlSetData($cmbStrategy, "Analiz Sonucu|" & _StrategyNames($g_aStrategies), $sDefaultToSelect)
EndFunc

Func _GetActiveStrategyString()
    Local $sel = GUICtrlRead($cmbStrategy)
    If $sel == "Analiz Sonucu" Then
        Return StringStripWS(FileRead($strategyFile), 3)
    EndIf
    Return _StrategyGet($g_aStrategies, $sel)
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
        GUICtrlSetData($cmbFilter, "Kapalı (tüm trafik)|Auto (otomatik liste)|Manuel (hostlist.txt)", $sFilterSelectionBeforeOOB)
        GUICtrlSetColor($cmbFilter, 0x000000)
        GUICtrlSetState($cmbFilter, $GUI_ENABLE)
        $bOOBFilterLock = False
    EndIf
EndFunc

Func _RefreshStrategyLabel()
    Local $sel = GUICtrlRead($cmbStrategy)
    If $sel == "Analiz Sonucu" Then
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil (Analiz Gerekli)"))
    Else
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: Hazır Profil (" & $sel & ")")
    EndIf
EndFunc

Func _SaveConfigAndExit()
    _SaveConfig()
    ExitApp()
EndFunc

; Seçili motor, strateji, filtre ve DNSCrypt durumunu config.ini'ye yazar.
Func _SaveConfig()
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

    ; Değişkeni burada 'Local' olarak tanımlıyoruz
    Local $dnscryptVal = _StateCryptOn() ? "1" : "0"

    IniWrite($iniPath, "Settings", "ActiveEngine", $engineVal)
    IniWrite($iniPath, "Settings", "ActiveStrategy", $stratVal)
    IniWrite($iniPath, "Settings", "FilterMode", $filterModeVal)
    IniWrite($iniPath, "Settings", "DnscryptInstalled", $dnscryptVal)

EndFunc

Func _UpdateEnginePaths($sEngineSelected)
    If StringInStr($sEngineSelected, "Zapret2") Then
        $currentEngine = "Zapret2"
        $strategyFile = @ScriptDir & "\config\strategy2.txt"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws2.exe"
        $blockcheckPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck2.cmd"
        $logPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck2.log"
        $g_sEngineFooter = "Zapret2 v" & $ENGINE_ZAPRET2_VERSION
        _RefreshFooter()
    Else
        $currentEngine = "Zapret1"
        $strategyFile = @ScriptDir & "\config\strategy.txt"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws.exe"
        $blockcheckPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck.cmd"
        $logPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck.log"
        $g_sEngineFooter = "Zapret v" & $ENGINE_ZAPRET1_VERSION
        _RefreshFooter()
    EndIf
EndFunc

Func ShowGUI()
    _MainWindowShow(True)
EndFunc

; Etkin arayüzün penceresini gösterir (yeni arayüz açıksa onu, değilse eskisini).
Func _MainWindowShow($bActivate = False)
    Local $h = $g_bWebUi ? $hWebGui : $hGUI
    GUISetState(@SW_SHOW, $h)
    If $bActivate Then
        GUISetState(@SW_RESTORE, $h)
        WinActivate($h)
        WinWaitActive($h, "", 2)
    EndIf
EndFunc

Func _MainWindowHide()
    GUISetState(@SW_HIDE, $g_bWebUi ? $hWebGui : $hGUI)
EndFunc

; Ana durumu yazar: durum modülü tek kaynaktır; eski arayüzün etiketi de güncellenir (Aşama 2.1).
; CheckServiceStatus/StartWinws'e verilen $statusID her yerde $lblStatusText'tir.
Func _SetStatus($sStatus)
    _StateSetStatus($sStatus)
    GUICtrlSetData($lblStatusText, $sStatus)
EndFunc

; Alt pencerelerin sahibi: kullanıcının gördüğü ana pencere (yeni arayüzde gizli eski pencere değil).
Func _MainWindowHandle()
    Return $g_bWebUi ? $hWebGui : $hGUI
EndFunc

Func ExitApp()
    If $isZapretRunning Then StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
    If $pcapPID > 0 Or ProcessExists("go-pcap2socks.exe") Then _LanStop($pcapPID, @ScriptDir)
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
            GUICtrlSetData($chkID, "Auto (otomatik liste)")
        ElseIf StringInStr($sCfgOut, "--hostlist=") Then
            GUICtrlSetData($chkID, "Manuel (hostlist.txt)")
        Else
            GUICtrlSetData($chkID, "Kapalı (tüm trafik)")
        EndIf

        GUICtrlSetState($manualBtn, $GUI_DISABLE)
        _SetButtonsState($lockArray, $GUI_DISABLE)

		GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)

        ; Zapret2 servisi kuruluyken analiz butonu "servis stratejisini güncelle" olarak açık kalır.
        If StringInStr($sCfgOut, "winws2.exe") Then
            GUICtrlSetData($btnAnalyze, "Servis Stratejisini Güncelle (Analiz)")
            GUICtrlSetState($btnAnalyze, $GUI_ENABLE)
        EndIf

        ; --- YENİ EKLENEN KISIM: SERVİS DURUMUNU (RUNNING/STOPPED) KONTROL ET ---
        If StringInStr($sOutput, "RUNNING") Then
            _SetStatus("SERVİS MODU AKTİF")
            GUICtrlSetColor($statusID, 0x27AE60)
        Else
            ; Servis yüklü ama durmuş!
            _SetStatus("SERVİS YÜKLÜ - DURDU")
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
        GUICtrlSetData($btnAnalyze, "ISS Analizi (Blockcheck) Yap")

        _SetStatus("ÇALIŞMAYA HAZIR")
        GUICtrlSetColor($statusID, 0x2C3E50)
    EndIf
    _UpdateFilterForStrategy()
EndFunc

; Servis durmuş görünürken winws yeniden çalışıyorsa (Windows/elle yeniden başlatma) durumu
; tazeler ve "servis durdu" uyarısını yeniden silahlandırır; böylece sonraki durmada da uyarılır.
Func _RefreshIfServiceRecovered()
    If _StateStatus() <> "SERVİS YÜKLÜ - DURDU" Then Return
    _LogInfo("Servis yeniden çalışıyor")
    $bServiceStoppedWarned = False
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
EndFunc

Func StartWinws($ctrlID, $statusID, $aBtns)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    Local $fullCommand = '"' & $winwsPath & '" ' & _BuildActiveWinwsArgs($activeStrategy)

    ;ClipPut($fullCommand)
    $zapretPID = Run($fullCommand, @ScriptDir & "\bin\zapret\zapret-winws\", @SW_HIDE)
    _LogInfo("Manuel başlat (" & $currentEngine & ", " & GUICtrlRead($cmbStrategy) & ", PID " & $zapretPID & "): " & $fullCommand)

    If $zapretPID > 0 Then
        ; --- 1. ARAYÜZÜ ANINDA GÜNCELLE (Kullanıcıya anında tepki ver) ---
        $isZapretRunning = True
        GUICtrlSetData($ctrlID, "■   Durdur")
        _SetStatus("MANUEL MOD AKTİF")
        GUICtrlSetColor($statusID, 0xE67E22)
        _SetButtonsState($aBtns, $GUI_DISABLE)

        ; --- 2. ARKA PLANDA 1 SANİYE BEKLE VE KONTROL ET ---
        Sleep(500)

        If Not ProcessExists($zapretPID) Then
            ; --- 3. EĞER EXE ÇÖKTÜYSE HER ŞEYİ ESKİ HALİNE (SİSTEM HAZIR) DÖNDÜR ---
            $isZapretRunning = False
            $zapretPID = 0

            GUICtrlSetData($ctrlID, "▶   Başlat")
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

; =========================================================================
; --- ARAYÜZ: SAYFALAR, MENÜ VE DURUM SENKRONU ---
; =========================================================================

; Denetimi bir sayfaya kaydeder (sayfa değişince gösterilir/gizlenir).
; Klasik pencerede görünmeyen, yalnızca program mantığının yazdığı gizli denetim.
Func __ClassicHidden()
    Local $id = GUICtrlCreateLabel("", 0, 0, 0, 0)
    GUICtrlSetState($id, $GUI_HIDE)
    Return $id
EndFunc

; Önizleme (/arayuz-onizleme <klasör>): klasik pencerenin görüntüsünü alır ve çıkar.
Func _MainUiPreviewAndExit($sDir)
    _UpdateEnginePaths(GUICtrlRead($cmbEngine))
    _LoadStrategyList($iniStrategy)
    _RefreshStrategyLabel()
    _SetStatus("ÇALIŞMAYA HAZIR")
    _SetButtonsState($aCriticalButtons, $GUI_ENABLE)
    GUICtrlSetState($btnLanShare, $GUI_ENABLE)
    DirCreate($sDir)
    If $CmdLine[0] >= 3 And $CmdLine[3] = "/yeni-arayuz" Then _WebUiPreviewAndExit($sDir)
    GUISetState(@SW_SHOW, $hGUI)
    Local $aStatus[3] = ["ÇALIŞMAYA HAZIR", "SERVİS MODU AKTİF", "DNS ZEHİRLENMESİ SAPTANDI!"]
    Local $aColor[3] = [0x2C3E50, 0x27AE60, 0xC0392B]
    For $p = 0 To 2
        _SetStatus($aStatus[$p])
        GUICtrlSetColor($lblStatusText, $aColor[$p])
        _RefreshFooter()
        Local $hT = TimerInit()
        While TimerDiff($hT) < 400
            GUIGetMsg()
        WEnd
        _ScreenCapture_CaptureWnd($sDir & "\klasik" & $p & ".png", $hGUI)
    Next
    ; "Yeni arayüz" düğmesi: klasik pencereden yeni arayüze dönüş
    _WebUiSwitchToNew()
    Local $hW = TimerInit()
    While TimerDiff($hW) < 5000 And Not ($g_bWebUi And $g_bWebPageReady)
        _WebUiTick(GUIGetMsg())
    WEnd
    Sleep(800)
    FileWriteLine($sDir & "\klasik.log", "yeni arayüze dönüş: yeni arayüz=" & $g_bWebUi & ", sayfa hazır=" & $g_bWebPageReady & _
            ", klasik görünür=" & (BitAND(WinGetState($hGUI), 2) = 2))
    If $g_bWebUi Then _ScreenCapture_CaptureWnd($sDir & "\klasikten-yeni.png", $hWebGui)
    Exit
EndFunc

; Alt satır: motor sürümü + (servis modunda) otomatik onarımın son durumu.
Func _RefreshFooter()
    Local $bService = StringInStr(_StateStatus(), "SERVİS") > 0
    Local $sHealth = _HealthStatusFormat($bService, IniRead($iniPath, "Health", "Enabled", "1"), _
            IniRead($iniPath, "Health", "LastCheck", ""), IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
    GUICtrlSetData($lblFooter, $g_sEngineFooter & "  ·  v" & $APP_VERSION & @CRLF & ($sHealth = "" ? "Servis kurulu değil" : $sHealth))
EndFunc

; Tepsi: ayarlar penceresi.
Func _OpenSettings()
    ShowGUI()
    _SettingsUI_Show(@ScriptDir, $serviceName, $APP_NAME, _MainWindowHandle(), True)
    _RefreshFooter()
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
    _ServiceDriverCleanup($serviceName)
    _LogInfo("Manuel mod durduruldu")
    $isZapretRunning = False
    GUICtrlSetData($ctrlID, "▶   Başlat")
    CheckServiceStatus($ctrlID, $statusID, $aBtns, $cmbFilter)
EndFunc

Func InstallServiceClean($chkID)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    ; Korumasız klasördeyse (ör. C:\Users\...) önce Program Files'a taşımayı öner (lib/Install.au3).
    _SaveConfig()
    Local $sLoc = _InstallCheckBeforeService(@ScriptName)
    If $sLoc = "iptal" Then Return
    If $sLoc = "taşındı" Then ExitApp()

    Local $binArgs = _BuildActiveWinwsArgs($activeStrategy)

    ; Otomatik yeniden başlatma isteğe bağlı ve varsayılan kapalı (ADR-007: anti-cheat ile çatışma riski).
    Local $bRecovery = _ServiceAskRecovery($iniPath)

    RemoveService()
    Sleep(500)

    Local $iCreate = _ServiceInstall($serviceName, $winwsPath, $binArgs, $bRecovery)
    _LogInfo("Servis kur (" & $currentEngine & ", " & GUICtrlRead($cmbStrategy) & ", otomatik yeniden başlatma " & ($bRecovery ? "açık" : "kapalı") & _
            "): sc create çıkış kodu " & $iCreate & " | " & $binArgs)
    If $iCreate = 0 Then
        MsgBox(64 + 8192, "Başarılı", "Seçilen profil servis olarak kuruldu. Bilgisayar açılınca otomatik başlar." & @CRLF & @CRLF & _
                ($bRecovery ? "Servis kapanırsa Windows en fazla 2 kez (10 sn ve 60 sn sonra) yeniden başlatır." : "Servis kapanırsa otomatik yeniden başlatılmaz; program uyarır."))
        _HealthOfferSetup($iniPath)
    Else
        MsgBox(16 + 8192, "Servis Kurulamadı", "Windows servisi oluşturulamadı (sc create hata kodu " & $iCreate & ")." & @CRLF & @CRLF & _
                "'Servis ve Kalıntıları Temizle' butonuna basıp tekrar deneyin. Sorun sürerse logs\app.log dosyasıyla birlikte bildirin.")
    EndIf
EndFunc

Func RemoveService()
    _LogInfo("Servis ve WinDivert kalıntıları kaldırılıyor")
    _HealthRemoveTask()
    RunWait(@ComSpec & " /c sc stop " & $serviceName & " & sc delete " & $serviceName & " & sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
EndFunc

; =========================================================================
; --- ZAPRET 1 ANALİZ FONKSİYONLARI ---
; =========================================================================
Func RunBlockcheck($ctrlID)
    Local $isNoBypassNeeded = False
    If FileExists($logPath) Then FileDelete($logPath)
    Local $bashPath = @ScriptDir & "\bin\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\bin\zapret\blockcheck\zapret\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\bin\zapret\blockcheck", @SW_HIDE)
    If $iPidBash = 0 Then
        MsgBox(16 + 8192, "Analiz Başlatılamadı", "Blockcheck süreci başlatılamadı.")
        Return
    EndIf
    Local $hWaitTimer = TimerInit()
    While Not FileExists($logPath)
        Sleep(100)
        If TimerDiff($hWaitTimer) > 10000 Then ExitLoop
    WEnd
    ; Sistemdeki başka bash.exe süreçlerini (Git Bash, WSL vb.) değil, yalnızca bizim başlattığımızı bekle.
    While ProcessExists($iPidBash)
        Sleep(1000)
        Local $hFile = FileOpen($logPath, 0)
        If $hFile <> -1 Then
            Local $sContent = FileRead($hFile)
            FileClose($hFile)
            If StringInStr($sContent, "working without bypass") Or StringInStr($sContent, "not blocked") Then
                $isNoBypassNeeded = True
                ExitLoop
            EndIf
        EndIf
    WEnd
    ; Erken çıkışta (engel yok) blockcheck arka planda çalışmaya devam etmesin.
    _CleanupBlockcheckProcesses($iPidBash)
    If $isNoBypassNeeded Then
        MsgBox(64 + 8192, "Bilgi: Zapret1 Analiz Tamamlandı", _
                "İnternet hattınızda herhangi bir DPI / Sansür kısıtlaması saptanmadı!")
    Else
        ExtractSummary($logPath)
    EndIf
EndFunc

Func ExtractSummary($filePath)
    If Not FileExists($filePath) Then Return MsgBox(16 + 8192, "Başarısız", "Analiz log dosyası bulunamadı.")
    Local $strategy = _ParseSummaryStrategy(FileRead($filePath))
    _LogInfo("Blockcheck1 bitti: " & ($strategy = "" ? "strateji bulunamadı" : $strategy))
    If $strategy <> "" Then
        Local $sFormatted = _FormatStrategyQuotes($strategy)
        Local $hFile = FileOpen($strategyFile, 2)
        If $hFile <> -1 Then
            FileWrite($hFile, $sFormatted)
            FileClose($hFile)
            MsgBox(64 + 8192, "Başarılı", "Analiz tamamlandı. Zapret1 için strateji ayıklandı.")
        EndIf
    Else
        MsgBox(16 + 8192, "Başarısız", "Strateji bulunamadı.")
    EndIf
EndFunc

; =========================================================================
; --- ZAPRET 2 ANALİZ FONKSİYONU ---
; =========================================================================
Func _BlockcheckResultsPath()
    Return @ScriptDir & "\config\blockcheck2_strategies.txt"
EndFunc

Func _SaveBlockcheckResults(ByRef $aStrategies)
    Local $sPath = _BlockcheckResultsPath()
    Local $hFile = FileOpen($sPath, 2)
    If $hFile = -1 Then Return False

    For $i = 1 To $aStrategies[0]
        FileWriteLine($hFile, $aStrategies[$i])
    Next
    FileClose($hFile)
    Return True
EndFunc

Func _LoadBlockcheckResults(ByRef $aStrategies)
    Local $sPath = _BlockcheckResultsPath()
    If Not FileExists($sPath) Then Return False

    Local $sContent = FileRead($sPath)
    If @error Or $sContent = "" Then Return False

    Local $aLines = StringSplit(StringStripCR($sContent), @LF, 1)
    Local $aLoaded[1] = [0]
    For $i = 1 To $aLines[0]
        Local $sStrategy = StringStripWS($aLines[$i], 3)
        If $sStrategy = "" Then ContinueLoop

        Local $bExists = False
        For $j = 1 To $aLoaded[0]
            If $aLoaded[$j] = $sStrategy Then
                $bExists = True
                ExitLoop
            EndIf
        Next
        If Not $bExists Then
            ReDim $aLoaded[UBound($aLoaded) + 1]
            $aLoaded[0] += 1
            $aLoaded[$aLoaded[0]] = $sStrategy
        EndIf
    Next

    $aStrategies = $aLoaded
    Return ($aStrategies[0] > 0)
EndFunc

Func RunBlockcheck2($ctrlID)
    ; Ana pencereyi modal olarak kilitle; popup sadece ana pencerenin önünde kalsın.
    GUISetState(@SW_DISABLE, _MainWindowHandle())

    Local $isNoBypassNeeded = False
    Local $bUserStopped = False
    Local $aStrategies[1] = [0]

    ; Kullanıcı yeni analiz seçtiği için eski sonuçları geçersiz kıl.
    If FileExists(_BlockcheckResultsPath()) Then FileDelete(_BlockcheckResultsPath())
    If FileExists($logPath) Then FileDelete($logPath)

    Local $aScanMark = _UiMark()
    Local $hScanGUI = _UiWindow("Sağlayıcı taraması", 380, 196, _MainWindowHandle())
    Local $lblScanTitle = _UiLabel("Taranıyor...", 24, 20, 332, 28, 13, $UI_TEXT, 700, 0, $UI_FONT_SEMI)
    _UiCard(24, 58, 332, 60)
    Local $lblScanElapsed = _UiLabel("Geçen süre: 00:00", 40, 68, 300, 20, 10, $UI_TEXT2)
    Local $lblScanCount = _UiLabel("Bulunan strateji: 0", 40, 90, 300, 20, 10, $UI_TEXT, 600)
    Local $btnStopScan = _UiButton("Analizi Durdur", 24, 136, 332, 40, $UI_KIND_SECONDARY, 10, 10, $UI_BG)
    Local $bEnoughHinted = False
    GUISetState(@SW_SHOW, $hScanGUI)

    Local $bashPath = @ScriptDir & "\bin\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\bin\zapret\blockcheck\zapret2\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\bin\zapret\blockcheck", @SW_HIDE)

    If $iPidBash = 0 Then
        GUIDelete($hScanGUI)
        _UiRelease($aScanMark)
        GUISetState(@SW_ENABLE, _MainWindowHandle())
        _MainWindowShow()
        MsgBox(16 + 8192, "Analiz Başlatılamadı", "Blockcheck2 süreci başlatılamadı.")
        Return
    EndIf

    Local $hTimer = TimerInit()
    Local $hUiTimer = TimerInit()

    ; İlk çalışan stratejide durmak yerine, analiz devam ettiği sürece
    ; logdaki tüm benzersiz AVAILABLE stratejilerini topluyoruz.
    While ProcessExists($iPidBash)
        Local $nMsg = GUIGetMsg()
        If $nMsg = $btnStopScan Or $nMsg = $GUI_EVENT_CLOSE Then
            $bUserStopped = True
            ExitLoop
        EndIf

        If FileExists($logPath) Then
            Local $hFile = FileOpen($logPath, 0)
            If $hFile <> -1 Then
                Local $sContent = FileRead($hFile)
                FileClose($hFile)

                Local $sFiltered = StringReplace($sContent, "iana.org", "IGNORE")
                If StringInStr($sFiltered, "!!!!! AVAILABLE !!!!!") Then
                    _CollectStrategiesFromText($sContent, $aStrategies)
                EndIf
                If StringInStr($sContent, "working without bypass") Or StringInStr($sContent, "not blocked") Then
                    $isNoBypassNeeded = True
                EndIf
            EndIf
        EndIf

        If TimerDiff($hUiTimer) >= 250 Then
            Local $iSeconds = Int(TimerDiff($hTimer) / 1000)
            GUICtrlSetData($lblScanElapsed, "Geçen süre: " & StringFormat("%02d:%02d", Int($iSeconds / 60), Mod($iSeconds, 60)))
            GUICtrlSetData($lblScanCount, "Bulunan strateji: " & $aStrategies[0])
            ; Akıllı analiz en fazla birkaç yüz aday denediğinden taramayı sonuna kadar beklemeye gerek yok.
            If $aStrategies[0] >= 60 And Not $bEnoughHinted Then
                $bEnoughHinted = True
                GUICtrlSetData($btnStopScan, "Yeterli — akıllı analize geç")
                GUICtrlSetData($lblScanTitle, "Taranıyor... (yeterli strateji bulundu)")
            EndIf
            $hUiTimer = TimerInit()
        EndIf

        _UiTick($hScanGUI)
        Sleep(150)
    WEnd

    ; Analiz doğal olarak bittiğinde de, kullanıcı durdurduğunda da
    ; blockcheck alt süreçlerini temizliyoruz. Yalnızca paketteki cygwin ve
    ; winws süreçleri hedeflenir; kullanıcının açık Git Bash/MSYS oturumları kapanmaz.
    _CleanupBlockcheckProcesses($iPidBash)
    _LogInfo("Blockcheck2 bitti: " & $aStrategies[0] & " strateji, süre " & Int(TimerDiff($hTimer) / 1000) & " sn" & _
            ($bUserStopped ? ", kullanıcı durdurdu" : "") & ($isNoBypassNeeded ? ", engel yok" : ""))

    GUIDelete($hScanGUI)
    _UiRelease($aScanMark)

    ; Sonuçları kalıcı dosyaya yaz: pencere kapatılsa bile ana menüden yeniden açılabilir.
    If $aStrategies[0] > 0 Then
        If Not _SaveBlockcheckResults($aStrategies) Then
            MsgBox(48 + 8192, "Sonuçlar Kaydedilemedi", _
                "Stratejiler bu oturumda kullanılabilir ancak sonuç dosyasına kaydedilemedi:" & @CRLF & _BlockcheckResultsPath())
        EndIf
    EndIf

    If $aStrategies[0] > 0 Then
        Local $iSmart = MsgBox(36 + 8192, "Akıllı Analiz", $aStrategies[0] & " çalışan strateji bulundu." & @CRLF & @CRLF & _
                "En uygun olanı otomatik belirlemek için akıllı analiz yapılsın mı? (tahmini " & _SmartEstimateMinutes($aStrategies[0]) & " dk)" & @CRLF & @CRLF & _
                "Hayır: listeyi açıp stratejileri elle denersiniz.")
        If $iSmart = 6 Then
            Local $aCand = _BuildSmartCandidates($aStrategies, False)
            _RunSmartAnalysisFlow($aCand, True)
        Else
            _ShowStrategyTestWindow($aStrategies, True)
        EndIf
    ElseIf _BlockcheckLooksUnparsed(FileRead($logPath), 0) Then
        _LogError("Blockcheck2: logda çalışan sonuç var ama strateji ayrıştırılamadı (log biçimi değişmiş olabilir)")
        MsgBox(48 + 8192, "Sonuç Okunamadı", "Analiz çalışan stratejiler buldu ancak sonuçlar okunamadı; blockcheck'in log biçimi değişmiş olabilir." & @CRLF & @CRLF & _
                "Tepsi menüsünden 'Tanılama paketi oluştur' ile logu gönderebilirsiniz. Bu sırada 'Hızlı akıllı test' ile hazır profilleri deneyebilirsiniz.")
    ElseIf $isNoBypassNeeded Then
        MsgBox(64 + 8192, "Bilgi: Zapret2 Analiz Tamamlandı", _
            "İnternet hattınızda herhangi bir DPI / sansür kısıtlaması saptanmadı.")
    ElseIf $bUserStopped Then
        MsgBox(48 + 8192, "Analiz Durduruldu", "Analiz durduruldu. Kullanılabilir strateji bulunamadı.")
    Else
        MsgBox(16 + 8192, "Başarısız", "Analiz tamamlandı ancak kullanılabilir strateji bulunamadı.")
    EndIf

    GUISetState(@SW_ENABLE, _MainWindowHandle())
    _MainWindowShow()
EndFunc

; =========================================================================
; --- AKILLI ANALİZ ENTEGRASYONU ---
; =========================================================================
Func _SmartResultsPath()
    Return @ScriptDir & "\config\smart_results.tsv"
EndFunc

; Zapret2 analiz seçici. Yeni blockcheck taraması başlatılacaksa True döner.
Func _HandleZapret2AnalysisChoice()
    Return _RunAnalysisChoice(_AnalysisChooser())
EndFunc

; Analiz türü: yeni arayüzde seçildiyse o, değilse seçici penceresi.
Func _AnalysisChooser()
    If $g_iWebAnalysisChoice <> -1 Then
        Local $iChoice = $g_iWebAnalysisChoice
        $g_iWebAnalysisChoice = -1
        Return $iChoice
    EndIf
    Return _SmartUI_Chooser(FileExists(_BlockcheckResultsPath()), FileExists(_SmartResultsPath()), _MainWindowHandle())
EndFunc

; Servis kuruluyken: servisi durdurur, seçilen analizi çalıştırır; strateji değiştiyse servisi
; yeni stratejiyle günceller (DNS'e ve kurtarma ayarına dokunmaz), değişmediyse eski haliyle başlatır.
Func _ServiceStrategyUpdateFlow()
    If Not StringInStr(_ServiceParseBinPath(_ServiceGetConfig($serviceName)), "winws2.exe") Then
        Return MsgBox(48 + 8192, "Servis Stratejisi", "Kurulu servis klasik Zapret motorunu kullanıyor; akıllı analiz yalnızca Zapret2 ile çalışır." & @CRLF & @CRLF & _
                "'Servis ve Kalıntıları Temizle' ile kaldırıp Zapret2 ile yeniden kurabilirsiniz.")
    EndIf
    Local $iChoice = _AnalysisChooser()
    If $iChoice = $SMARTUI_CANCEL Then Return

    Local $sBefore = StringStripWS(FileRead($strategyFile), 3)
    _LogInfo("Servis stratejisi güncelleme: analiz için servis durduruluyor")
    _SetStatus("SERVİS GEÇİCİ OLARAK DURDURULDU")
    _ServiceStop($serviceName)
    ; Servis duruşu sonrası WinDivert'in bırakılması için
    _KillProcessesUnderDir(@ScriptDir & "\bin\zapret\zapret-winws")

    If _RunAnalysisChoice($iChoice) Then RunBlockcheck2($btnAnalyze)

    Local $sAfter = StringStripWS(FileRead($strategyFile), 3)
    Local $bOk
    If $sAfter <> "" And $sAfter <> $sBefore Then
        _LoadStrategyList("Analiz Sonucu")
        Local $sArgs = _BuildActiveWinwsArgs($sAfter)
        $bOk = _ServiceUpdateArgs($serviceName, $winwsPath, $sArgs)
        _LogInfo("Servis stratejisi güncellendi (" & ($bOk ? "çalışıyor" : "BAŞLATILAMADI") & "): " & $sArgs)
        If $bOk Then
            MsgBox(64 + 8192, "Servis Güncellendi", "Servis yeni stratejiyle yeniden başlatıldı:" & @CRLF & $sAfter)
        Else
            MsgBox(16 + 8192, "Servis Güncellenemedi", "Servis yeni stratejiyle başlatılamadı. logs\app.log dosyasına bakın.")
        EndIf
    Else
        $bOk = _ServiceStart($serviceName)
        _LogInfo("Servis stratejisi değişmedi, servis eski haliyle " & ($bOk ? "başlatıldı" : "BAŞLATILAMADI"))
        If Not $bOk Then MsgBox(16 + 8192, "Servis Başlatılamadı", "Servis yeniden başlatılamadı. logs\app.log dosyasına bakın.")
    EndIf
    $bServiceStoppedWarned = False
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
EndFunc

; Seçici sonucunu uygular. Yeni blockcheck taraması gerekiyorsa True döner (çağıran başlatır).
Func _RunAnalysisChoice($iChoice)
    Switch $iChoice
        Case $SMARTUI_FULL
            Return True
        Case $SMARTUI_QUICK
            Local $aNone[1] = [0]
            Local $aCand = _BuildSmartCandidates($aNone, True)
            _RunSmartAnalysisFlow($aCand, False)
        Case $SMARTUI_PREV_SMART
            If _SmartUI_ShowSaved(_SmartResultsPath(), $strategyFile, $winwsPath, _MainWindowHandle()) <> "" Then _AfterSmartStrategyChosen()
        Case $SMARTUI_PREV_LIST
            Local $aPrev[1] = [0]
            _LoadBlockcheckResults($aPrev)
            If $aPrev[0] > 0 Then
                _ShowStrategyTestWindow($aPrev)
            Else
                MsgBox(48 + 8192, "Sonuç Bulunamadı", "Kayıtlı sonuç dosyası boş veya okunamadı. Yeni analiz başlatabilirsiniz.")
            EndIf
    EndSwitch
    Return False
EndFunc

; Aday listesi: $aFound (1 tabanlı, [0]=adet) + istenirse hazır profiller ve önceki tarama.
; Kayıtlı "Analiz Sonucu" stratejisi her zaman eklenir (karşılaştırma için).
Func _BuildSmartCandidates(ByRef $aFound, $bIncludeExtras)
    Local $aC[0][2]
    For $i = 1 To $aFound[0]
        _SmartAddCandidate($aC, $aFound[$i], "Tarama")
    Next
    If HasValidStrategy() Then _SmartAddCandidate($aC, StringStripWS(FileRead($strategyFile), 3), "Kayıtlı")
    If $bIncludeExtras Then
        Local $aPresets = _StrategyLoad($strategiesIniPath, "Zapret2")
        For $i = 0 To UBound($aPresets) - 1
            _SmartAddCandidate($aC, $aPresets[$i][1], "Hazır: " & $aPresets[$i][0])
        Next
        Local $aPrev[1] = [0]
        _LoadBlockcheckResults($aPrev)
        For $i = 1 To $aPrev[0]
            _SmartAddCandidate($aC, $aPrev[$i], "Önceki tarama")
        Next
    EndIf
    Return $aC
EndFunc

; Akıllı analizi çalıştırır; seçilen strateji "Analiz Sonucu" olarak kaydedilir ve seçilir.
Func _RunSmartAnalysisFlow(ByRef $aCand, $bMainAlreadyDisabled)
    _LogInfo("Akıllı analiz başlıyor: " & UBound($aCand) & " aday")
    Local $sPrevStatus = _StateStatus()
    _SetStatus("AKILLI ANALİZ YAPILIYOR...")
    If Not $bMainAlreadyDisabled Then GUISetState(@SW_DISABLE, _MainWindowHandle())
    Local $sTargets = IniRead($iniPath, "SmartAnalysis", "Targets", $SMART_DEFAULT_TARGETS)
    Local $sChosen = _SmartUI_Run($aCand, @ScriptDir, $winwsPath, $sTargets, _SmartResultsPath(), $strategyFile, _MainWindowHandle())
    If Not $bMainAlreadyDisabled Then
        GUISetState(@SW_ENABLE, _MainWindowHandle())
        _MainWindowShow()
    EndIf
    _SetStatus($sPrevStatus)
    If $sChosen <> "" Then _AfterSmartStrategyChosen()
EndFunc

Func _AfterSmartStrategyChosen()
    _LoadStrategyList("Analiz Sonucu")
    _RefreshStrategyLabel()
    _UpdateFilterForStrategy()
EndFunc

Func _CleanupBlockcheckProcesses($iPidBash)
    ; Analiz sırasında manuel mod ve servis butonları kilitli olduğundan bin\zapret
    ; altında çalışan her süreç (cygwin bash/sh/tee, test için açılan winws) blockcheck'e aittir.
    _KillProcessTree($iPidBash)
    _KillProcessesUnderDir(@ScriptDir & "\bin\zapret")
EndFunc

Func _ShowStrategyTestWindow(ByRef $aStrategies, $bMainAlreadyDisabled = False)
    ; Önceki sonuçlar ana menüden açılırsa burada modal kilitle; analiz akışından gelirse kilit zaten aktiftir.
    If Not $bMainAlreadyDisabled Then GUISetState(@SW_DISABLE, _MainWindowHandle())

    Local $aTestMark = _UiMark()
    Local $hTestGUI = _UiWindow("Bulunan stratejileri dene", 520, 372, _MainWindowHandle())

    _UiLabel("Bulunan stratejilerden birini seçip deneyebilirsin.", 24, 18, 472, 22, 11, $UI_TEXT, 600, 0, $UI_FONT_SEMI)
    Local $cmbFoundStrategies = GUICtrlCreateCombo("", 24, 48, 472, 150, BitOR($CBS_DROPDOWNLIST, $WS_VSCROLL))
    GUICtrlSetFont($cmbFoundStrategies, 10, 400, 0, $UI_FONT)
    _UiDarkControl($cmbFoundStrategies)
    Local $sOptions = ""
    For $i = 1 To $aStrategies[0]
        If $sOptions <> "" Then $sOptions &= "|"
        $sOptions &= "Strateji " & $i
    Next
    GUICtrlSetData($cmbFoundStrategies, $sOptions, "Strateji 1")

    _UiLabel("SEÇİLİ STRATEJİ", 24, 88, 300, 18, 8.5, $UI_MUTED, 700)
    Local $edtStrategyPreview = GUICtrlCreateEdit($aStrategies[1], 24, 108, 472, 62, BitOR($ES_READONLY, $ES_AUTOVSCROLL, $WS_VSCROLL), 0)
    GUICtrlSetBkColor($edtStrategyPreview, $UI_CARD)
    GUICtrlSetColor($edtStrategyPreview, $UI_TEXT)
    GUICtrlSetFont($edtStrategyPreview, 9, 400, 0, "Consolas")
    _UiDarkControl($edtStrategyPreview, "DarkMode_Explorer")
    Local $lblOobWarning = _UiLabel("", 24, 176, 472, 30, 9, 0xFF9AA2, 700)
    ; Belirgin durum alanı (renkler yeni tasarımın koyu temasından)
    Local $lblTestStatus = GUICtrlCreateLabel("Deneme bekliyor. 'Dene'ye basıp Discord/Roblox bağlantını deneyebilirsin.", 24, 212, 472, 44, BitOR($SS_CENTER, $SS_CENTERIMAGE))
    GUICtrlSetBkColor($lblTestStatus, 0x2A2B4D)
    GUICtrlSetColor($lblTestStatus, 0xB9BAFA)
    GUICtrlSetFont($lblTestStatus, 10, 600, 0, $UI_FONT_SEMI)

    ; Tek düğme: test kapalıyken başlatır, çalışırken durdurur.
    Local $btnToggleTest = _UiButton("Dene", 24, 304, 200, 40, $UI_KIND_PRIMARY, 10.5, 10, $UI_BG)
    Local $btnSaveStrategy = _UiButton("Stratejiyi kaydet", 234, 304, 150, 40, $UI_KIND_SECONDARY, 10, 10, $UI_BG)
    Local $btnCloseTest = _UiButton("Kapat", 394, 304, 102, 40, $UI_KIND_SECONDARY, 10, 10, $UI_BG)
    Local $bStrategyTestRunning = False
    GUISetState(@SW_SHOW, $hTestGUI)

    Local $bDone = False
    Local $iSelected = 1
    _UpdateOobWarning($aStrategies[$iSelected], $lblOobWarning)
    While Not $bDone
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnCloseTest
                _StopStrategyTest()
                $bDone = True

            Case $cmbFoundStrategies
                $iSelected = Int(StringTrimLeft(GUICtrlRead($cmbFoundStrategies), 8))
                If $iSelected >= 1 And $iSelected <= $aStrategies[0] Then
                    GUICtrlSetData($edtStrategyPreview, $aStrategies[$iSelected])
                    _UpdateOobWarning($aStrategies[$iSelected], $lblOobWarning)
                EndIf

            Case $btnToggleTest
                If $bStrategyTestRunning Then
                    ; Çalışan testi durdur.
                    _StopStrategyTest()
                    $bStrategyTestRunning = False
                    GUICtrlSetData($btnToggleTest, "Dene")
                    GUICtrlSetData($lblTestStatus, "Deneme durduruldu. İstersen başka bir stratejiyi deneyebilirsin.")
                    GUICtrlSetBkColor($lblTestStatus, 0x33291A)
                    GUICtrlSetColor($lblTestStatus, 0xF0C274)
                Else
                    ; Testi başlat.
                    $iSelected = Int(StringTrimLeft(GUICtrlRead($cmbFoundStrategies), 8))
                    If $iSelected >= 1 And $iSelected <= $aStrategies[0] Then
                        _UpdateOobWarning($aStrategies[$iSelected], $lblOobWarning)
                        _StopStrategyTest()
                        Local $sTestCommand = _BuildStrategyTestCommand($aStrategies[$iSelected])
                        $strategyTestPID = Run($sTestCommand, @ScriptDir & "\bin\zapret\zapret-winws\", @SW_HIDE)
                        If $strategyTestPID > 0 Then
                            $bStrategyTestRunning = True
                            GUICtrlSetData($btnToggleTest, "Denemeyi durdur")
                            GUICtrlSetData($lblTestStatus, "Deneme çalışıyor. Discord/Roblox bağlantını dene.")
                            GUICtrlSetBkColor($lblTestStatus, 0x17302A)
                            GUICtrlSetColor($lblTestStatus, 0x7FDBAE)
                        Else
                            $bStrategyTestRunning = False
                            GUICtrlSetData($btnToggleTest, "Dene")
                            GUICtrlSetData($lblTestStatus, "Başlatılamadı. winws2 dosyasını ve yönetici yetkisini kontrol et.")
                            GUICtrlSetBkColor($lblTestStatus, 0x3A1E22)
                            GUICtrlSetColor($lblTestStatus, 0xFF9AA2)
                        EndIf
                    EndIf
                EndIf

            Case $btnSaveStrategy
                $iSelected = Int(StringTrimLeft(GUICtrlRead($cmbFoundStrategies), 8))
                If $iSelected >= 1 And $iSelected <= $aStrategies[0] Then
                    Local $hStore = FileOpen($strategyFile, 2)
                    If $hStore = -1 Then
                        MsgBox(16 + 8192, "Kayıt Hatası", "Strateji dosyasına yazılamadı:" & @CRLF & $strategyFile)
                    Else
                        FileWrite($hStore, $aStrategies[$iSelected])
                        FileClose($hStore)
                        _LogInfo("Blockcheck2 stratejisi kaydedildi: " & $aStrategies[$iSelected])
                        ; Analiz Sonucu seçiliyken kaydedilen yeni stratejiye göre ana filtre alanını anında güncelle.
                        _UpdateFilterForStrategy()
                        _StopStrategyTest()
                        MsgBox(64 + 8192, "Strateji Kaydedildi", "Seçilen strateji kaydedildi. Ana menüden Analiz Sonucu seçip Zapret'i başlatabilirsiniz.")
                        $bDone = True
                    EndIf
                EndIf
        EndSwitch

        ; Test açık görünürken winws2.exe beklenmedik şekilde kapanırsa durumu hemen düzelt.
        If $bStrategyTestRunning Then
            If Not ProcessExists("winws2.exe") Or ($strategyTestPID > 0 And Not ProcessExists($strategyTestPID)) Then
                $bStrategyTestRunning = False
                $strategyTestPID = 0
                GUICtrlSetData($btnToggleTest, "Dene")
                GUICtrlSetData($lblTestStatus, "Deneme durdu: zapret süreci kapandı.")
                GUICtrlSetBkColor($lblTestStatus, 0x3A1E22)
                GUICtrlSetColor($lblTestStatus, 0xFF9AA2)
            EndIf
        EndIf

        _UiTick($hTestGUI)
        Sleep(30)
    WEnd

    _StopStrategyTest()
    GUIDelete($hTestGUI)
    _UiRelease($aTestMark)

    If Not $bMainAlreadyDisabled Then
        GUISetState(@SW_ENABLE, _MainWindowHandle())
        _MainWindowShow()
    EndIf
EndFunc

Func _BuildStrategyTestCommand($sStrategy)
    ; Testler hostlist/hostlist-auto/hostlist-exclude filtreleri olmadan çalışır.
    Return '"' & $winwsPath & '" ' & _BuildWinwsArgs("Zapret2", $winwsPath, $sStrategy, $WINWS_FILTER_OFF)
EndFunc

Func _UpdateOobWarning($sStrategy, $lblOobWarning)
    If StringInStr($sStrategy, "oob") Then
        GUICtrlSetData($lblOobWarning, "UYARI: Bu strateji OOB içeriyor. Filtreler ile çalışmamaktadır. Sistem geneli çalışacaktır. Bazı sitelerde sorun yaratabilir.")
        GUICtrlSetState($lblOobWarning, $GUI_SHOW)
    Else
        GUICtrlSetData($lblOobWarning, "")
    EndIf
EndFunc

Func _StopStrategyTest()
    If $strategyTestPID > 0 And ProcessExists($strategyTestPID) Then ProcessClose($strategyTestPID)
    $strategyTestPID = 0
EndFunc

Func HasValidStrategy()
    If Not FileExists($strategyFile) Then Return False
    Local $sContent = StringStripWS(FileRead($strategyFile), 3)
    Return ($sContent <> "")
EndFunc

; --- Güvenlik Duvarı Sorgu Fonksiyonu ---
; Açılışta servis çalışıyorken Discord'a ulaşılamıyorsa (ör. sağlayıcı engellemeyi değiştirdi, strateji
; artık çalışmıyor) kullanıcıya otomatik onarımı önerir. Pencere açıkken arka plandaki sağlık görevi
; çalışmadığı için bu durum fark edilmiyordu (2026-10-24).
Func _StartupServiceCheck()
    If _StateStatus() <> "SERVİS MODU AKTİF" Then Return
    If Not StringInStr(_ServiceParseBinPath(_ServiceGetConfig($serviceName)), "winws2.exe") Then Return
    _SetStatus("DISCORD BAĞLANTISI KONTROL EDİLİYOR...")
    _WebUiRefreshNow()
    Local $sVerdict = _HealthQuickCheck(@ScriptDir)
    _LogInfo("Açılış bağlantı kontrolü (servis): " & ($sVerdict = "" ? "yapılamadı" : $sVerdict))
    If $sVerdict = "onar" Then
        Local $iAsk = MsgBox(36 + 8192, "Discord'a ulaşılamıyor", "Servis çalışıyor ama Discord'a bağlanılamıyor. Sağlayıcın engelleme yöntemini değiştirmiş olabilir." & @CRLF & @CRLF & _
                "Otomatik onarım denensin mi? Önce kayıtlı yedek stratejiler, gerekirse hızlı analiz denenir (1-5 dakika). Bu sürede Discord bağlantısı kısa süre kopabilir.")
        If $iAsk = 6 Then
            _SetStatus("OTOMATİK ONARIM DENENİYOR...")
            _WebUiRefreshNow()
            Local $iR = _HealthRun(@ScriptDir, $serviceName, $APP_NAME, True)
            _LogInfo("Açılış: kullanıcı onayıyla onarım sonucu " & $iR)
            MsgBox(64 + 8192, "Otomatik Onarım", _HealthResultText($iR))
            _LoadStrategyList("Analiz Sonucu")
        EndIf
    EndIf
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
    _RefreshStrategyLabel()
EndFunc

; --- Ağ paylaşımı (lib/LanShare.au3) ---
; Başlatır; $bInteractive ise sonucu (cihaz ayarları ya da hata nedeni) kullanıcıya gösterir.
Func _LanShareStart($bInteractive)
    Local $sErr
    $g_sLanMtu = ""
    $pcapPID = _LanStart(@ScriptDir, $g_aLanPlan, $g_aLanAdapter, $sErr)
    If $pcapPID = 0 Then
        $g_sLanError = $sErr
        $g_sLanNpcap = _LanNpcapStatus()
        _LanShareSetOn(False)
        If $bInteractive Then _LanShareNotify("Ağ paylaşımı başlamadı", $sErr, True)
        Return False
    EndIf
    $g_sLanError = ""
    $g_sLanNpcap = "var"
    _LanDevicesReset()
    $g_sLanMtu = _LanParseMtu(_LanLogTail(@ScriptDir & $LAN_LOG_REL, 40))
    _LanShareSetOn(True)
    If $bInteractive And $g_bWebUi Then
        _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Paylaşım açık. Cihazda sayfadaki ayarları gir."))
    ElseIf $bInteractive Then
        MsgBox(64 + 8192, "Ağ paylaşımı açık", "Konsol veya TV'nin ağ ayarlarını elle (statik) girin:" & @CRLF & @CRLF & _
                "IP adresi:   " & $g_aLanPlan[3] & "   (ikinci cihaz " & _LanDeviceIP(StringRegExpReplace($g_aLanPlan[1], "\.2\.1$", ""), 2) & " ...)" & @CRLF & _
                "Alt ağ maskesi:   " & $g_aLanPlan[2] & @CRLF & _
                "Ağ geçidi:   " & $g_aLanPlan[1] & @CRLF & _
                "DNS:   1.1.1.1  (ikincil 8.8.8.8)" & @CRLF & _
                ($g_sLanMtu = "" ? "" : "MTU (PS5 ve Switch):   " & $g_sLanMtu & @CRLF) & @CRLF & _
                "Bilgisayar ve cihaz aynı modeme bağlı olmalı; bilgisayar açık kalmalı." & _
                ($g_aLanAdapter[3] ? @CRLF & @CRLF & "Bilgisayar Wi-Fi ile bağlı: paylaşım yavaş olabilir, kablo önerilir." : ""), 0, _MainWindowHandle())
    EndIf
    Return True
EndFunc

Func _LanShareStop()
    _LanStop($pcapPID, @ScriptDir)
    $pcapPID = 0
    _LanDevicesReset()
    _LanShareSetOn(False)
EndFunc

; DNSCrypt durumu tek kaynaktan (lib/AppState); düğme metni yalnız görüntü, config.ini kalıcı kayıt.
Func _DnscryptSetOn($bOn)
    _StateSetCryptOn($bOn)
    GUICtrlSetData($btnDnscrypt, $bOn ? "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır" : "Dnscrypt-proxy servisi kur")
    IniWrite($iniPath, "Settings", "DnscryptInstalled", $bOn ? "1" : "0")
EndFunc

; Paylaşım durumu tek kaynaktan (lib/AppState); klasik penceredeki düğme metni yalnız görüntü.
Func _LanShareSetOn($bOn)
    _StateSetLanOn($bOn)
    GUICtrlSetData($btnLanShare, $bOn ? "[ ✓ ] Paylaşım Aktif / Durdur" : "Ağdaki Cihazlarla Paylaş")
EndFunc

; Ana döngüden saniyede bir: paylaşım açık görünüyor ama süreç düştüyse bir kez yeniden başlatır,
; yine düşerse kapatıp nedenini bildirir (önceden arayüz "aktif" demeye devam ediyordu).
Func _LanShareWatch()
    If Not _StateLanOn() Then Return
    If _LanIsRunning($pcapPID) Then
        If $g_sLanMtu = "" Then $g_sLanMtu = _LanParseMtu(_LanLogTail(@ScriptDir & $LAN_LOG_REL, 40))
        ; Kayıt sınırı (lib/LanShare.au3): çok uzun/yoğun oturumda paylaşım bir kez yeniden başlar, kayıt sıfırlanır.
        If _LanLogSize(@ScriptDir) > $LAN_LOG_MAX_BYTES Then
            _LogWarn("Ağ paylaşımı: kayıt " & Int($LAN_LOG_MAX_BYTES / 1048576) & " MB sınırını aştı; paylaşım yeniden başlatılıyor")
            _LanShareStop()
            If _LanShareStart(False) Then Return
            _LanShareNotify("Ağ paylaşımı durdu", $g_sLanError, False)
            Return
        EndIf
        Local $nDev = UBound($__g_aLanDevices)
        If _LanDevicesPoll(@ScriptDir) > 0 Then
            For $i = $nDev To UBound($__g_aLanDevices) - 1
                _LogInfo("Ağ paylaşımı: cihaz bağlandı " & $__g_aLanDevices[$i][0] & ($__g_aLanDevices[$i][4] = "" ? "" : " (" & $__g_aLanDevices[$i][4] & ")"))
            Next
            Local $iLast = UBound($__g_aLanDevices) - 1
            Local $sWho = ($__g_aLanDevices[$iLast][4] = "" ? "" : $__g_aLanDevices[$iLast][4] & " ") & "(" & $__g_aLanDevices[$iLast][0] & ")"
            _LanShareNotify("Cihaz bağlandı", $sWho & " bu bilgisayar üzerinden internete çıkıyor.", False)
        EndIf
        Return
    EndIf
    Local $sReason = _LanErrorReason(_LanLogTail(@ScriptDir & $LAN_LOG_REL))
    _LogWarn("Ağ paylaşımı beklenmedik şekilde durdu" & ($sReason = "" ? "" : ": " & $sReason))
    If $g_iLanRestarts < 1 Then
        $g_iLanRestarts += 1
        If _LanShareStart(False) Then
            _LogInfo("Ağ paylaşımı otomatik olarak yeniden başlatıldı")
            Return
        EndIf
    EndIf
    _LanShareStop()
    $g_sLanError = ($sReason = "" ? "go-pcap2socks kapandı. Ayrıntı: logs\paylasim.log" : $sReason)
    _LanShareNotify("Ağ paylaşımı durdu", $g_sLanError, False)
EndFunc

; Paylaşım sayfası açılınca: paylaşım kapalıysa kart ve Npcap bilgisini okur (ayarlar önceden görünsün).
Func _WebUiLanRefresh()
    $g_sWebLastLanJson = ""
    If _LanIsRunning($pcapPID) Then Return
    $g_aLanAdapter = _LanReadAdapter()
    $g_sLanNpcap = _LanNpcapStatus()
EndFunc

; Bildirim: yeni arayüzde sayfa içi, değilse ileti kutusu (etkileşimli) ya da tepsi balonu.
Func _LanShareNotify($sTitle, $sText, $bInteractive)
    If $g_bWebUi And $g_bWebPageReady Then
        _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", $sTitle & ": " & $sText))
    ElseIf $bInteractive Then
        MsgBox(48 + 8192, $sTitle, $sText, 0, _MainWindowHandle())
    Else
        TrayTip($sTitle, $sText, 10, 2)
    EndIf
EndFunc

; DNS değiştikten sonra açılıştaki kontrolün aynısı: zehirlenme varsa kritik düğmeler kilitlenir.
Func _DnsRecheckAfterChange()
    _SetStatus("DNS TEST EDİLİYOR...")
    Sleep(1000) ; Ağın ve adaptörün kendine gelmesi için bekleme
    If CheckDnsPoisoningSilent() Then
        _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
        GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; DNS zehirlense bile bu buton hep tıklanabilir olsun
        _SetStatus("DNS ZEHİRLENMESİ SAPTANDI!")
        GUICtrlSetColor($lblStatusText, 0xC0392B)
    Else
        ; Zehirlenme yoksa her şey normal devam etsin
        CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
        GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)
        _RefreshStrategyLabel()
    EndIf
EndFunc

Func _CheckDnscryptStatus()
    Local $sProxyName = "dnscrypt-proxy"

    ; 1. Windows Servisi çalışıyor mu kontrol et
    Local $iPid = Run(@ComSpec & " /c sc query " & $sProxyName, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPid)
    Local $sOutput = StdoutRead($iPid)

    ; 2. Aktif DNS adresi 127.0.0.1 mi kontrol et
    Local $sDnsOut = _GetActiveAdapterDnsServers()

    If StringInStr($sOutput, "RUNNING") And StringInStr($sDnsOut, "127.0.0.1") Then
        _DnscryptSetOn(True)
    Else
        _DnscryptSetOn(False)
    EndIf

    ; Açılışta butonun disabled kalmaması için her kontrol bitiminde açıyoruz
    GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)
EndFunc

; =========================================================================
; --- YENİ ARAYÜZ (WebView2, ui/web) ---
; Eski pencere gizli kalır ve program mantığı ona yazmaya devam eder; yeni pencere
; aynı durumu gösterir, komutları eski düğme olayları olarak ana döngüye verir.
; WebView2 yoksa veya başlamazsa eski arayüz açılır.
; =========================================================================
Func _WebUiWanted()
    ; Yeni arayüz varsayılan (2026-10-24). Eski arayüz: Ayarlar'daki anahtar ([Arayuz] Yeni=0) veya /eski-arayuz.
    If $CmdLine[0] >= 1 And $CmdLine[1] = "/yeni-arayuz" Then Return True
    If $CmdLine[0] >= 1 And $CmdLine[1] = "/eski-arayuz" Then Return False
    Return IniRead($iniPath, "Arayuz", "Yeni", "1") = "1"
EndFunc

Func _WebUiTheme()
    Return IniRead($iniPath, "Arayuz", "Tema", "acik") = "koyu" ? "koyu" : "acik"
EndFunc

Func _WebUiStart()
    ; Başlık eski pencereyle aynı: sağlık kontrolü açık programı başlıktan tanır.
    $hWebGui = GUICreate($APP_NAME & " v" & $APP_VERSION, 460, 660, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU, $WS_MINIMIZEBOX))
    _WebUiApplyCaption(_WebUiTheme())
    GUIRegisterMsg($WM_SIZE, "_WebUiOnSize")
    If Not _WV2_Create($hWebGui, @ScriptDir & "\bin\webview2\WebView2Loader.dll", @LocalAppDataDir & "\RedRiveRR Zapret\WebView2", _
            _WebFileUrl(@ScriptDir & "\ui\web\index.html")) Then
        _WebUiFallback()
        Return
    EndIf
    $g_bWebUi = True
    $g_hWebStartTimer = TimerInit()
    GUISetState(@SW_SHOW, $hWebGui)
    GUISwitch($hGUI)
    _LogInfo("Yeni arayüz başlatılıyor (WebView2 " & _WV2_RuntimeVersion() & ")")
EndFunc

Func _WebUiApplyCaption($sTheme)
    If $sTheme = "koyu" Then
        GUISetBkColor(0x14161B, $hWebGui)
        _WV2_SetCaption($hWebGui, True, 0x14161B)
    Else
        GUISetBkColor(0xF2F4F7, $hWebGui)
        _WV2_SetCaption($hWebGui, False, 0xF2F4F7)
    EndIf
EndFunc

Func _WebUiFallback()
    _LogWarn("Yeni arayüz açılamadı, eski arayüz kullanılıyor: " & _WV2_LastError())
    _WV2_Close()
    If $hWebGui <> 0 Then GUIDelete($hWebGui)
    $hWebGui = 0
    $g_bWebUi = False
    $g_bWebPageReady = False
    GUISwitch($hGUI)
    GUISetState(@SW_SHOW, $hGUI)
EndFunc

; Bu oturum için eski arayüze geçer (yeni arayüzde henüz olmayan işlemler için).
Func _WebUiSwitchToOld()
    _WV2_Close()
    If $hWebGui <> 0 Then GUIDelete($hWebGui)
    $hWebGui = 0
    $g_bWebUi = False
    $g_bWebPageReady = False
    GUISwitch($hGUI)
    _MainWindowShow(True)
EndFunc

; Klasik pencereden yeni arayüze döner (WebView2 açılamazsa klasik pencere kalır).
Func _WebUiSwitchToNew()
    If $g_bWebUi Then Return
    _LogInfo("Kullanıcı yeni arayüze döndü")
    GUISetState(@SW_HIDE, $hGUI)
    $g_bWebPageReady = False
    _WebUiStart()
EndFunc

Func _WebUiOnSize($hWnd, $iMsg, $wParam, $lParam)
    #forceref $iMsg, $wParam, $lParam
    If $hWnd = $hWebGui Then _WV2_Resize()
    Return $GUI_RUNDEFMSG
EndFunc

; Ana döngüde her turda: sayfa mesajlarını işler, durumu aktarır. Dönüş: işlenecek olay.
Func _WebUiTick($nMsg)
    ; Önceki turda seçilen analiz türü o turun olayında kullanıldı (kullanılmadıysa seçici açılsın).
    $g_iWebAnalysisChoice = -1
    Local $iState = _WV2_State()
    If $iState = $WV2_STATE_FAILED Or ($iState = $WV2_STATE_STARTING And TimerDiff($g_hWebStartTimer) > 10000) Then
        _WebUiFallback()
        Return $nMsg
    EndIf

    Local $sMsg = _WV2_NextMessage()
    Local $iAge = @extended
    If $sMsg <> "" Then
        Switch _WebJsonGet($sMsg, "tip")
            Case "hazir"
                $g_bWebPageReady = True
                $g_sWebLastJson = ""
                $g_sWebLastStratJson = ""
                $g_sWebLastOtherJson = ""
                _WebUiServiceRefreshSoon()
                _WV2_Post(_WebJsonObj("tip", "tema", "tema", _WebUiTheme()))
            Case "tema"
                Local $sTheme = (_WebJsonGet($sMsg, "tema") = "koyu") ? "koyu" : "acik"
                IniWrite($iniPath, "Arayuz", "Tema", $sTheme)
                _WebUiApplyCaption($sTheme)
            Case "komut"
                Local $sCmd = _WebJsonGet($sMsg, "ad")
                $g_sWebLastJson = "" ; düğme yeniden etkinleşsin diye durum tekrar gönderilir
                ; Uzun bir iş sürerken kuyrukta kalmış komutlar yok sayılır.
                ; Eşik 10 sn: sayfa yüklenirken (ör. kart bilgisi okunurken) basılan düğme kaybolmasın,
                ; ama dakikalarca süren analiz sırasında kuyrukta kalan tıklamalar yine yok sayılsın.
                If $iAge > 10000 Then
                    _LogInfo("Yeni arayüz: eskimiş komut yok sayıldı (" & $sCmd & ", " & $iAge & " ms)")
                    _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Önceki işlem sürerken basıldığı için uygulanmadı; tekrar dene."))
                ElseIf $sCmd = "eskiArayuz" Then
                    _LogInfo("Yeni arayüz: kullanıcı klasik arayüze geçti")
                    _WebUiSwitchToOld()
                    Return $nMsg
                ElseIf ($sCmd = "baslat" And Not $isZapretRunning) Or ($sCmd = "durdur" And $isZapretRunning) Then
                    If BitAND(GUICtrlGetState($btnRunZapret), $GUI_ENABLE) Then Return $btnRunZapret
                ElseIf $sCmd = "sonuclar" Then
                    $g_sWebLastStratJson = ""
                    If BitAND(GUICtrlGetState($btnAnalyze), $GUI_ENABLE) Then _WebUiShowSmartResults()
                ElseIf $sCmd = "analiz" Then
                    $g_sWebLastStratJson = ""
                    If BitAND(GUICtrlGetState($btnAnalyze), $GUI_ENABLE) Then
                        ; Eski Analiz düğmesiyle aynı akış (servis kuruluysa servis güncellemesi dahil); seçici atlanır.
                        $g_iWebAnalysisChoice = (_WebJsonGet($sMsg, "tur") = "tam") ? $SMARTUI_FULL : $SMARTUI_QUICK
                        Return $btnAnalyze
                    EndIf
                ElseIf $sCmd = "servisKur" Or $sCmd = "servisKaldir" Or $sCmd = "servisAyarlar" Then
                    _WebUiServiceRefreshSoon()
                    Local $idSvcBtn = ($sCmd = "servisKur") ? $btnInstallService : (($sCmd = "servisKaldir") ? $btnRemoveService : $btnSvcSettings)
                    If BitAND(GUICtrlGetState($idSvcBtn), $GUI_ENABLE) Then Return $idSvcBtn
                ElseIf $sCmd = "paylasimYenile" Then
                    _WebUiLanRefresh()
                    $g_bWebLanDone = True
                ElseIf $sCmd = "paylasimBaslat" Or $sCmd = "paylasimDurdur" Then
                    ; Komut hedef durumdur (aç/kapa değil): başlatma sürerken sıraya giren ikinci basış
                    ; paylaşımı hemen kapatıyordu (2026-10-27, H26).
                    If ($sCmd = "paylasimBaslat") <> _StateLanOn() And BitAND(GUICtrlGetState($btnLanShare), $GUI_ENABLE) Then Return $btnLanShare
                    $g_bWebLanDone = True
                ElseIf $sCmd = "npcap" Then
                    ShellExecute("https://npcap.com/#download")
                ElseIf $sCmd = "github" Then
                    ShellExecute("https://github.com/" & $APP_UPDATE_REPO)
                ElseIf $sCmd = "tanilama" Or $sCmd = "kayitlar" Or $sCmd = "ayarlar" Or $sCmd = "temizle" Then
                    $g_sWebLastOtherJson = ""
                    _WebUiServiceRefreshSoon()
                    Local $idOther
                    Switch $sCmd
                        Case "tanilama"
                            $idOther = $btnPageDiag
                        Case "kayitlar"
                            $idOther = $btnPageLogs
                        Case "ayarlar"
                            $idOther = $btnPageSettings
                        Case Else
                            $idOther = $btnRemoveService
                    EndSwitch
                    If BitAND(GUICtrlGetState($idOther), $GUI_ENABLE) Then Return $idOther
                ElseIf $sCmd = "dns" Then
                    $g_bWebDnsReread = True
                    $g_sWebLastDnsJson = ""
                    Local $iDnsEvent = _WebUiDnsCommand(_WebJsonGet($sMsg, "mod"))
                    If $iDnsEvent <> 0 Then Return $iDnsEvent
                EndIf
            Case "dnsYenile"
                $g_bWebDnsReread = True
            Case "kopyala"
                ; Paylaşım sayfasındaki ayarlar (IP, maske...) panoya
                Local $sCopy = _WebJsonGet($sMsg, "metin")
                If StringLen($sCopy) > 0 And StringLen($sCopy) < 64 Then ClipPut($sCopy)
            Case "ayar"
                _WebUiServiceRefreshSoon()
                If $iAge <= 2000 Then _WebUiApplySetting(_WebJsonGet($sMsg, "ad"), _WebJsonGet($sMsg, "deger") = "true")
            Case "secim"
                $g_sWebLastStratJson = ""
                If $iAge <= 2000 Then
                    Local $iCtrl = _WebUiSelectCombo(_WebJsonGet($sMsg, "alan"), _WebJsonGet($sMsg, "deger"))
                    If $iCtrl <> 0 Then Return $iCtrl
                EndIf
        EndSwitch
    EndIf

    If $g_bWebPageReady And TimerDiff($g_hWebSyncTimer) > 250 Then _WebUiSyncAll()
    Return $nMsg
EndFunc

; Yeni pencereye bütün ekranların durumunu gönderir (yalnızca değişen mesajlar gider).
Func _WebUiSyncAll()
    $g_hWebSyncTimer = TimerInit()
    Local $sStatus = _StateStatus()
    ; Onarım durumu 5 sn'de bir veya durum değişince okunur (config.ini'yi her turda okumamak için).
    If $g_hWebHealthTimer = 0 Or TimerDiff($g_hWebHealthTimer) > 5000 Or $sStatus <> $g_sWebLastStatus Then
        $g_hWebHealthTimer = TimerInit()
        $g_sWebLastStatus = $sStatus
        $g_sWebHealth = _HealthStatusFormat(StringInStr($sStatus, "SERVİS") > 0, IniRead($iniPath, "Health", "Enabled", "1"), _
                IniRead($iniPath, "Health", "LastCheck", ""), IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
    EndIf
    Local $sJson = _WebStateJson($sStatus, $isZapretRunning, BitAND(GUICtrlGetState($btnRunZapret), $GUI_ENABLE) <> 0, _
            GUICtrlRead($cmbStrategy), GUICtrlRead($cmbEngine), GUICtrlRead($cmbFilter), $g_sWebHealth)
    If $sJson <> $g_sWebLastJson Then
        $g_sWebLastJson = $sJson
        _WV2_Post($sJson)
    EndIf
    _WebUiSyncStrategy()
    _WebUiSyncService()
    _WebUiSyncDns()
    Local $sPrefix = ""
    If $g_aLanPlan[1] <> "" Then
        $sPrefix = StringRegExpReplace($g_aLanPlan[1], "\.2\.1$", "")
    ElseIf $g_aLanAdapter[0] <> "" Then
        $sPrefix = _LanPickPrefix($g_aLanAdapter[2])
    EndIf
    Local $sLan = _WebLanJson(_LanIsRunning($pcapPID), BitAND(GUICtrlGetState($btnLanShare), $GUI_ENABLE) <> 0, $g_sLanError, _
            $g_sLanNpcap, $g_aLanAdapter[0], $g_aLanAdapter[3], $sPrefix, $g_sLanMtu, _LanDnsModeCurrent(), _
            _WebLanDevicesJson($__g_aLanDevices, _NowCalc()))
    If $g_bWebLanDone Then
        $g_bWebLanDone = False
        $g_sWebLastLanJson = $sLan
        _WV2_Post(_WebJsonAdd($sLan, "bitti", True))
    ElseIf $sLan <> $g_sWebLastLanJson Then
        $g_sWebLastLanJson = $sLan
        _WV2_Post($sLan)
    EndIf
    Local $sOther = _WebOtherJson(_StateLanOn(), BitAND(GUICtrlGetState($btnLanShare), $GUI_ENABLE) <> 0, $g_sWebUpdateIni, _
            $APP_VERSION, $g_sEngineFooter, BitAND(GUICtrlGetState($btnRemoveService), $GUI_ENABLE) <> 0)
    If $sOther <> $g_sWebLastOtherJson Then
        $g_sWebLastOtherJson = $sOther
        _WV2_Post($sOther)
    EndIf
EndFunc

; Uzun işlem veya alt pencere açıkken (ana döngü beklerken) yeni pencereyi canlı tutar: durum
; gönderilir, basılan komutlar "işlem sürüyor" bildirimiyle reddedilir (önceden kuyrukta bekleyip
; sessizce yok sayılıyordu, 2026-10-24 12:34 "temizle"). _UiTick üzerinden çağrılır; ana pencere hariç.
Func _UiYield($hWnd, $bForce = False)
    If Not $g_bWebUi Then Return
    If Not $bForce Then
        If $hWnd = $hGUI Or $hWnd = $hWebGui Then Return
        If TimerDiff($g_hWebYieldTimer) < 200 Then Return
    EndIf
    $g_hWebYieldTimer = TimerInit()
    While 1
        Local $sMsg = _WV2_NextMessage()
        If $sMsg = "" Then ExitLoop
        Switch _WebJsonGet($sMsg, "tip")
            Case "komut", "secim", "ayar"
                $g_sWebLastJson = "" ; kapatılan düğmeler yeniden açılsın
                $g_sWebLastStratJson = ""
                $g_sWebLastSvcJson = ""
                $g_sWebLastDnsJson = ""
                $g_sWebLastOtherJson = ""
                _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Bir işlem sürüyor veya açık bir pencere var; bitince tekrar dene."))
            Case "tema"
                Local $sTheme = (_WebJsonGet($sMsg, "tema") = "koyu") ? "koyu" : "acik"
                IniWrite($iniPath, "Arayuz", "Tema", $sTheme)
                _WebUiApplyCaption($sTheme)
            Case "dnsYenile"
                $g_bWebDnsReread = True
            Case "hazir"
                $g_bWebPageReady = True
                _WV2_Post(_WebJsonObj("tip", "tema", "tema", _WebUiTheme()))
        EndSwitch
    WEnd
    If $g_bWebPageReady Then _WebUiSyncAll()
EndFunc

; Ana döngüden önce süren uzun açılış adımlarında (ör. Discord kontrolü) yeni pencere güncel durumu
; göstersin: sayfa yüklenmeyi bitirene kadar en fazla $iMaxMs bekler, sonra durumu gönderir.
Func _WebUiRefreshNow($iMaxMs = 3000)
    If Not $g_bWebUi Then Return
    Local $hT = TimerInit()
    Do
        GUIGetMsg()
        _UiYield(0, True)
    Until $g_bWebPageReady Or (TimerDiff($hT) > $iMaxMs) Or (_WV2_State() <> $WV2_STATE_READY And TimerDiff($hT) > 1000)
EndFunc

; Servis ekranı bir sonraki turda servis durumunu ve onarım görevini yeniden okusun.
Func _WebUiServiceRefreshSoon()
    $g_hWebSvcTimer = 0
    $g_hWebTaskTimer = 0
    $g_sWebLastSvcJson = ""
EndFunc

Func _WebUiSyncService()
    If $g_hWebSvcTimer = 0 Or TimerDiff($g_hWebSvcTimer) > 5000 Then
        $g_hWebSvcTimer = TimerInit()
        $g_sWebSvcState = _ServiceGetState($serviceName)
        If $g_hWebTaskTimer = 0 Or TimerDiff($g_hWebTaskTimer) > 30000 Then
            $g_hWebTaskTimer = TimerInit()
            $g_bWebTaskExists = _ScheduleExists($HEALTH_TASK_NAME)
        EndIf
        Local $sEnabled = IniRead($iniPath, "Health", "Enabled", "1")
        Local $bService = $g_sWebSvcState <> ""
        ; Ayarlar penceresiyle aynı kural: servis varken görev yoksa onarım kapalı sayılır.
        $g_bWebHealthIni = $sEnabled = "1" And ($g_bWebTaskExists Or Not $bService)
        $g_bWebRestartIni = IniRead($iniPath, "Service", "AutoRestart", "0") = "1"
        $g_sWebUpdateIni = IniRead($iniPath, "Settings", "UpdateCheck", "1")
        $g_sWebSvcHealth = _HealthStatusFormat($bService, $sEnabled, IniRead($iniPath, "Health", "LastCheck", ""), _
                IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
    EndIf
    Local $sJson = _WebServiceJson($g_sWebSvcState, _StateStatus(), $g_bWebHealthIni, $g_bWebRestartIni, $g_sWebSvcHealth, _
            BitAND(GUICtrlGetState($btnInstallService), $GUI_ENABLE) <> 0 And Not $bInstallServiceBusy, _
            BitAND(GUICtrlGetState($btnRemoveService), $GUI_ENABLE) <> 0, BitAND(GUICtrlGetState($btnSvcSettings), $GUI_ENABLE) <> 0)
    If $sJson <> $g_sWebLastSvcJson Then
        $g_sWebLastSvcJson = $sJson
        _WV2_Post($sJson)
    EndIf
EndFunc

Func _WebUiSyncDns()
    If $g_bWebDnsReread Then
        $g_bWebDnsReread = False
        $g_sWebDnsServers = _GetActiveAdapterDnsServers()
    EndIf
    Local $sJson = _WebDnsJson(_StateStatus(), $g_sWebDnsServers, _
            BitAND(GUICtrlGetState($btnDnscrypt), $GUI_ENABLE) <> 0 And Not $bDnscryptBusy)
    If $sJson <> $g_sWebLastDnsJson Then
        $g_sWebLastDnsJson = $sJson
        _WV2_Post($sJson)
    EndIf
EndFunc

; DNS ekranındaki seçim. Şifreli DNS kurma/kaldırma eski DNSCrypt düğmesinin akışıyla (olay döner);
; Cloudflare / sağlayıcı arasında geçiş burada yapılır. Dönüş: işlenecek olay ya da 0.
Func _WebUiDnsCommand($sMode)
    If $bDnscryptBusy Or Not BitAND(GUICtrlGetState($btnDnscrypt), $GUI_ENABLE) Then Return 0
    If $sMode <> "sifreli" And $sMode <> "cloudflare" And $sMode <> "saglayici" Then Return 0
    Local $bCryptOn = _StateCryptOn()
    If $sMode = "sifreli" Then Return $bCryptOn ? 0 : $btnDnscrypt
    If $bCryptOn Then Return $btnDnscrypt ; kaldırınca DNS otomatiğe döner
    If $g_sUiPreviewDir <> "" Then
        _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Önizleme: DNS " & $sMode & " uygulanmadı"))
        Return 0
    EndIf
    $bDnscryptBusy = True
    _SetStatus("DNS AYARLANIYOR...")
    Local $bOk = ($sMode = "cloudflare") ? _SetSystemDNS() : _ResetSystemDNS()
    _LogInfo("Yeni arayüz: DNS seçimi " & $sMode & ($bOk ? "" : " (bağdaştırıcı bulunamadı)"))
    If Not $bOk Then _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Etkin ağ bağdaştırıcısı bulunamadı; DNS değiştirilemedi. VPN kullanıyorsan kapatıp tekrar dene."))
    _DnsRecheckAfterChange()
    $bDnscryptBusy = False
    Return 0
EndFunc

; Servis ekranındaki anahtarı Ayarlar penceresiyle aynı kodla uygular; not varsa sayfada gösterilir.
Func _WebUiApplySetting($sName, $bOn)
    ; Önizlemede gerçek servise/göreve dokunulmaz.
    If $g_sUiPreviewDir <> "" Then
        _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Önizleme: " & $sName & "=" & $bOn & " uygulanmadı"))
        Return
    EndIf
    Local $bService = ($sName = "guncelleme") ? False : _ServiceIsInstalled($serviceName)
    Local $sNote = ""
    Switch $sName
        Case "onarim"
            $sNote = _SettingsApplyHealth($iniPath, $bService, $bOn)
        Case "yenidenBaslat"
            _SettingsApplyRestart($iniPath, $serviceName, $bService, $bOn)
        Case "guncelleme"
            IniWrite($iniPath, "Settings", "UpdateCheck", $bOn ? "1" : "0")
        Case Else
            Return
    EndSwitch
    _LogInfo("Yeni arayüz: ayar " & $sName & "=" & $bOn & ($sNote = "" ? "" : " (" & $sNote & ")"))
    If $sNote <> "" Then _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", $sNote))
EndFunc

; Strateji ekranının durumunu eski denetimlerden ve son akıllı analiz dosyasından gönderir.
; "Tüm sonuçlar": yalnızca bakmak servisi durdurmaz. Servis kuruluysa "Dene" kapalıdır (WinDivert çakışır);
; yeni bir strateji seçilirse servis yalnızca o zaman durdurulup yeni stratejiyle başlatılır.
Func _WebUiShowSmartResults()
    Local $bService = _ServiceIsInstalled($serviceName)
    Local $sBefore = StringStripWS(FileRead($strategyFile), 3)
    If $g_sUiPreviewDir <> "" Then
        _WV2_Post(_WebJsonObj("tip", "bildirim", "metin", "Önizleme: sonuç penceresi açılmadı (servis kurulu: " & $bService & ")"))
        Return
    EndIf
    If _SmartUI_ShowSaved(_SmartResultsPath(), $strategyFile, $winwsPath, _MainWindowHandle(), Not $bService) = "" Then Return
    _AfterSmartStrategyChosen()
    Local $sAfter = StringStripWS(FileRead($strategyFile), 3)
    If Not $bService Or $sAfter = "" Or $sAfter = $sBefore Then Return
    If Not StringInStr(_ServiceParseBinPath(_ServiceGetConfig($serviceName)), "winws2.exe") Then
        MsgBox(48 + 8192, "Servis Stratejisi", "Strateji kaydedildi, ancak kurulu servis klasik Zapret motorunu kullandığı için servise uygulanmadı.")
        Return
    EndIf
    _SetStatus("SERVİS GEÇİCİ OLARAK DURDURULDU")
    Local $sArgs = _BuildActiveWinwsArgs($sAfter)
    Local $bOk = _ServiceUpdateArgs($serviceName, $winwsPath, $sArgs)
    _LogInfo("Servis stratejisi sonuç penceresinden güncellendi (" & ($bOk ? "çalışıyor" : "BAŞLATILAMADI") & "): " & $sArgs)
    If $bOk Then
        MsgBox(64 + 8192, "Servis Güncellendi", "Servis yeni stratejiyle yeniden başlatıldı:" & @CRLF & $sAfter)
    Else
        MsgBox(16 + 8192, "Servis Güncellenemedi", "Servis yeni stratejiyle başlatılamadı. logspp.log dosyasına bakın.")
    EndIf
    $bServiceStoppedWarned = False
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
EndFunc

Func _WebUiSyncStrategy()
    ; Sonuç dosyası 2 sn'de bir, yalnızca değiştiyse yeniden okunur.
    If $g_hWebStratTimer = 0 Or TimerDiff($g_hWebStratTimer) > 2000 Then
        $g_hWebStratTimer = TimerInit()
        Local $sPath = _SmartResultsPath()
        Local $sStamp = FileExists($sPath) ? FileGetTime($sPath, 0, 1) & "/" & FileGetSize($sPath) : ""
        If $sStamp <> $g_sWebSmartStamp Then
            $g_sWebSmartStamp = $sStamp
            $g_aWebSmartRows = _SmartLoadResults($sPath, $g_sWebSmartSummary)
        EndIf
    EndIf
    Local $sJson = _WebStrategyJson(_WebUiComboItems($cmbStrategy), GUICtrlRead($cmbStrategy), GUICtrlRead($cmbEngine), _
            _WebUiComboItems($cmbFilter), GUICtrlRead($cmbFilter), BitAND(GUICtrlGetState($cmbStrategy), $GUI_ENABLE) <> 0, _
            BitAND(GUICtrlGetState($cmbFilter), $GUI_ENABLE) <> 0, BitAND(GUICtrlGetState($btnAnalyze), $GUI_ENABLE) <> 0, _
            $g_sWebSmartSummary, $g_aWebSmartRows)
    If $sJson <> $g_sWebLastStratJson Then
        $g_sWebLastStratJson = $sJson
        _WV2_Post($sJson)
    EndIf
EndFunc

; Açılır kutunun öğeleri, "|" ile ayrılmış.
Func _WebUiComboItems($idCombo)
    Local $a = _GUICtrlComboBox_GetListArray(GUICtrlGetHandle($idCombo))
    If @error Or Not IsArray($a) Then Return ""
    Local $s = ""
    For $i = 1 To $a[0]
        $s &= ($i > 1 ? "|" : "") & $a[$i]
    Next
    Return $s
EndFunc

; Yeni arayüzdeki seçimi eski açılır kutuya uygular. Dönüş: işlenecek olay (kutu kimliği) ya da 0.
; Kutu kapalıysa veya değer listede yoksa hiçbir şey değişmez.
Func _WebUiSelectCombo($sField, $sValue)
    Local $idCombo
    Switch $sField
        Case "strateji"
            $idCombo = $cmbStrategy
        Case "motor"
            $idCombo = $cmbEngine
        Case "filtre"
            $idCombo = $cmbFilter
        Case Else
            Return 0
    EndSwitch
    If Not BitAND(GUICtrlGetState($idCombo), $GUI_ENABLE) Then Return 0
    If GUICtrlRead($idCombo) == $sValue Then Return 0
    Local $hCombo = GUICtrlGetHandle($idCombo)
    Local $iIdx = _GUICtrlComboBox_FindStringExact($hCombo, $sValue)
    If $iIdx < 0 Then Return 0
    _GUICtrlComboBox_SetCurSel($hCombo, $iIdx)
    _LogInfo("Yeni arayüz: " & $sField & " seçildi: " & $sValue)
    Return $idCombo
EndFunc

; Önizleme yardımcısı: $iMs boyunca yeni arayüzü çalıştırır, komutların hangi olaya çevrildiğini kaydeder.
Func __WebUiPreviewPump($iMs, $sLog)
    Local $hT = TimerInit()
    While TimerDiff($hT) < $iMs
        Local $nMsg = _WebUiTick(GUIGetMsg())
        Switch $nMsg
            Case $btnAnalyze
                FileWriteLine($sLog, "Analiz komutu -> btnAnalyze olayı, seçim=" & $g_iWebAnalysisChoice & " (önizlemede çalıştırılmadı)")
            Case $cmbStrategy, $cmbEngine, $cmbFilter
                FileWriteLine($sLog, "Seçim -> kutu olayı " & $nMsg & ": " & GUICtrlRead($nMsg))
            Case $btnDnscrypt
                FileWriteLine($sLog, "DNS komutu -> btnDnscrypt olayı (önizlemede çalıştırılmadı)")
            Case $btnPageDiag, $btnPageLogs, $btnPageSettings, $btnLanShare
                FileWriteLine($sLog, "Diğer komutu -> olay " & $nMsg & " (önizlemede çalıştırılmadı)")
            Case $btnInstallService, $btnRemoveService, $btnSvcSettings
                FileWriteLine($sLog, "Servis komutu -> " & ($nMsg = $btnRemoveService ? "btnRemoveService" : ($nMsg = $btnInstallService ? "btnInstallService" : "btnSvcSettings")) & " olayı (önizlemede çalıştırılmadı)")
        EndSwitch
    WEnd
EndFunc

; Önizleme (/arayuz-onizleme <klasör> /yeni-arayuz): yeni arayüzü örnek durumlarla açar,
; görüntülerini alır, Başlat düğmesinin hangi olaya çevrildiğini kaydeder ve çıkar.
; Hiçbir komut çalıştırılmaz (winws, servis, DNS değişmez).
Func _WebUiPreviewAndExit($sDir)
    Local $sLog = $sDir & "\yeni-arayuz.log"
    FileDelete($sLog)
    GUISetState(@SW_HIDE, $hGUI)
    _WebUiStart()
    FileWriteLine($sLog, "başlatıldı: " & $g_bWebUi & " " & _WV2_LastError())
    Local $aStatus[3] = ["ÇALIŞMAYA HAZIR", "SERVİS MODU AKTİF", "DNS ZEHİRLENMESİ SAPTANDI!"]
    Local $iShot = -1, $hT = TimerInit(), $hShot = 0, $bClicked = False
    While TimerDiff($hT) < 20000 And $g_bWebUi
        Local $nMsg = _WebUiTick(GUIGetMsg())
        If $nMsg = $btnRunZapret Then FileWriteLine($sLog, "Başlat komutu -> btnRunZapret olayı (önizlemede çalıştırılmadı)")
        If Not $g_bWebPageReady Then ContinueLoop
        If $iShot = -1 Then
            $iShot = 0
            $hShot = TimerInit()
        ElseIf TimerDiff($hShot) > 1200 Then
            _ScreenCapture_CaptureWnd($sDir & "\yeni" & $iShot & ".png", $hWebGui)
            FileWriteLine($sLog, "görüntü yeni" & $iShot & ".png: " & _StateStatus())
            If $iShot = 0 And Not $bClicked Then
                _WV2_Exec("document.getElementById('guc').click()")
                $bClicked = True
            EndIf
            $iShot += 1
            If $iShot >= UBound($aStatus) Then ExitLoop
            _SetStatus($aStatus[$iShot])
            $hShot = TimerInit()
        EndIf
    WEnd
    ; Strateji ekranı: denetimler kullanılabilir varsayılır; olaylar yalnızca kaydedilir, işlenmez.
    If $g_bWebUi Then
        GUICtrlSetState($cmbStrategy, $GUI_ENABLE)
        GUICtrlSetState($cmbEngine, $GUI_ENABLE)
        GUICtrlSetState($cmbFilter, $GUI_ENABLE)
        GUICtrlSetState($btnAnalyze, $GUI_ENABLE)
        _WV2_Exec("document.querySelector('nav a[data-gorunum=strateji]').click()")
        __WebUiPreviewPump(1500, $sLog)
        _ScreenCapture_CaptureWnd($sDir & "\strateji.png", $hWebGui)
        _WV2_Exec("document.getElementById('tum-sonuclar').click()")
        __WebUiPreviewPump(800, $sLog)
        FileWriteLine($sLog, "Tüm sonuçlar: Analiz olayı yok (servis durdurulmaz)")
        _WV2_Exec("document.querySelector('[data-tur=tam]').click(); document.getElementById('analiz-baslat').click()")
        __WebUiPreviewPump(1000, $sLog)
        _WV2_Exec("const f = document.getElementById('sec-filtre'); f.value = 'Manuel (hostlist.txt)'; f.dispatchEvent(new Event('change'))")
        __WebUiPreviewPump(1000, $sLog)
        _WV2_Exec("document.getElementById('tema').click()")
        __WebUiPreviewPump(1200, $sLog)
        _ScreenCapture_CaptureWnd($sDir & "\strateji-koyu.png", $hWebGui)
        _WV2_Exec("document.getElementById('tema').click()")
        __WebUiPreviewPump(500, $sLog)
        ; Servis ekranı (servis yalnızca sorgulanır; anahtarlar önizlemede uygulanmaz)
        _WV2_Exec("document.querySelector('nav a[data-gorunum=servis]').click()")
        __WebUiPreviewPump(1500, $sLog)
        _ScreenCapture_CaptureWnd($sDir & "\servis.png", $hWebGui)
        _WV2_Exec("document.getElementById('servis-kaldir').click(); document.querySelector('[data-ayar=onarim]').click()")
        __WebUiPreviewPump(800, $sLog)
        _ScreenCapture_CaptureWnd($sDir & "\servis-onay.png", $hWebGui)
        _WV2_Exec("document.getElementById('servis-kaldir').click()")
        __WebUiPreviewPump(800, $sLog)
        ; DNS ekranı (DNS yalnızca okunur; değişiklik önizlemede uygulanmaz)
        _WV2_Exec("document.querySelector('nav a[data-gorunum=dns]').click()")
        __WebUiPreviewPump(3000, $sLog)
        FileWriteLine($sLog, "DNS okundu: " & _WebDnsMode($g_sWebDnsServers) & " " & _WebDnsIPv4($g_sWebDnsServers))
        _ScreenCapture_CaptureWnd($sDir & "\dns.png", $hWebGui)
        _WV2_Exec("document.querySelector('input[name=dns][value=saglayici]').click(); document.getElementById('dns-uygula').click()")
        __WebUiPreviewPump(4000, $sLog) ; DNS yeniden okunur (PowerShell)
        _ScreenCapture_CaptureWnd($sDir & "\dns-secim.png", $hWebGui)
        ; Diğer ekranı
        _WV2_Exec("document.querySelector('nav a[data-gorunum=diger]').click()")
        __WebUiPreviewPump(1200, $sLog)
        _ScreenCapture_CaptureWnd($sDir & "\diger.png", $hWebGui)
        _WV2_Exec("document.querySelector('[data-komut=tanilama]').click()")
        __WebUiPreviewPump(500, $sLog)
        _WV2_Exec("document.getElementById('temizle').click(); document.getElementById('temizle').click()")
        __WebUiPreviewPump(800, $sLog)
        ; Ağ paylaşımı sayfası (kart ve Npcap yalnızca okunur; go-pcap2socks başlatılmaz)
        _WV2_Exec("document.getElementById('paylasim-ac').click()")
        __WebUiPreviewPump(3500, $sLog)
        FileWriteLine($sLog, "paylaşım sayfası: " & $g_sWebLastLanJson)
        _ScreenCapture_CaptureWnd($sDir & "\paylasim.png", $hWebGui)
    EndIf
    ; Alt pencere açıkken yeni pencere canlı mı? Deneme penceresi açıkken (deneme başlatılmaz)
    ; yeni pencerede bir komuta basılır; "işlem sürüyor" bildirimi beklenir. 1,5 sn sonra pencere kapanır.
    If $g_bWebUi Then
        $g_sPrevTestShot = $sDir & "\deneme-penceresi.png"
        Local $aFake[3] = [2, "--wf-tcp=443 --dpi-desync=fake,multisplit --dpi-desync-split-pos=1,midsld", "--wf-tcp=443 --dpi-desync=multidisorder"]
        AdlibRegister("__WebUiPreviewBusyClick", 500)
        AdlibRegister("__WebUiPreviewShotTest", 1500)
        _ShowStrategyTestWindow($aFake)
        FileWriteLine($sLog, "alt pencere açıkken komut: kuyrukta kalan mesaj=" & ($g_sPrevBusyLeft = "" ? "yok (yanıtlandı)" : $g_sPrevBusyLeft))
    EndIf
    ; Eski arayüze geçiş düğmesi
    If $g_bWebUi Then
        _WV2_Exec("document.querySelector('[data-komut=eskiArayuz]').click()")
        Local $hSw = TimerInit()
        While $g_bWebUi And TimerDiff($hSw) < 5000
            _WebUiTick(GUIGetMsg())
        WEnd
        Sleep(500)
        FileWriteLine($sLog, "eski arayüze geçiş: yeni arayüz=" & $g_bWebUi & ", eski pencere görünür=" & (BitAND(WinGetState($hGUI), 2) = 2))
        _ScreenCapture_CaptureWnd($sDir & "\eski-gecis.png", $hGUI)
    EndIf
    FileWriteLine($sLog, "bitti: yeni arayüz=" & $g_bWebUi & " " & _WV2_LastError())
    Exit
EndFunc

Func __WebUiPreviewShotTest()
    AdlibUnRegister("__WebUiPreviewShotTest")
    _ScreenCapture_CaptureWnd(StringReplace($g_sPrevTestShot, "deneme-penceresi", "mesgul-bildirimi"), $hWebGui)
    Local $h = WinGetHandle("Bulunan stratejileri dene")
    If $h Then
        _ScreenCapture_CaptureWnd($g_sPrevTestShot, $h)
        WinClose($h)
    EndIf
    $g_sPrevBusyLeft = _WV2_NextMessage()
EndFunc

Func __WebUiPreviewBusyClick()
    AdlibUnRegister("__WebUiPreviewBusyClick")
    _WV2_Exec("document.querySelector('[data-komut=tanilama]').click()")
EndFunc
