#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=bin\zapret\zapret-winws\winws2.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=Zapret Multi-Engine Windows Türkiye - Zapret & Zapret2 Kontrol Aracı
#AutoIt3Wrapper_Res_Fileversion=4.5.1.0
#AutoIt3Wrapper_Res_ProductVersion=4.5.1
#AutoIt3Wrapper_Res_LegalCopyright=Ali Mali
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

; --- GUI Tasarımı (Discord benzeri koyu tema, ui/Theme.au3) ---
_UiInit()
Global Const $UI_W = 920, $UI_H = 600, $UI_SB = 232, $UI_CX = 252, $UI_CW = 648
Global $hGUI = GUICreate($APP_NAME & " v" & $APP_VERSION, $UI_W, $UI_H)
_UiDarkWindow($hGUI)

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

; Sayfa sistemi: [sayfa][denetimler]
Global Const $PAGE_HOME = 0, $PAGE_ANALYZE = 1, $PAGE_SERVICE = 2, $PAGE_LAN = 3, $PAGE_DNS = 4, $PAGE_SETTINGS = 5
Global $g_aPageCtrl[6][40], $g_aPageCount[6] = [0, 0, 0, 0, 0, 0], $g_iPage = -1
Global $g_aNav[6]
Global $g_sUiLastStatus = "", $g_sUiLastRun = ""

; --- Kenar çubuğu ---
_UiCard(0, 0, $UI_SB, $UI_H, $UI_SIDEBAR, 0)
_UiIcon($UI_ICON_SHIELD, 18, 20, 36, 36, 20, $UI_ACCENT)
_UiLabel("Zapret", 60, 16, 160, 26, 15, $UI_TEXT, 700, 0, $UI_FONT_SEMI)
_UiLabel("Windows Türkiye", 60, 42, 160, 18, 9, $UI_MUTED)
Global $aNavText[6] = ["Ana Sayfa", "Analiz", "Servis", "Ağ Paylaşımı", "DNS", "Ayarlar"]
Global $aNavIcon[6] = [$UI_ICON_HOME, $UI_ICON_SEARCH, $UI_ICON_HEART, $UI_ICON_SHARE, $UI_ICON_GLOBE, $UI_ICON_SETTINGS]
For $i = 0 To 5
    $g_aNav[$i] = _UiNavItem($aNavIcon[$i], $aNavText[$i], 12, 92 + $i * 46, $UI_SB - 24)
Next
Global $lblFooter = _UiLabel("", 20, $UI_H - 56, $UI_SB - 30, 40, 8.5, $UI_MUTED)

; İşlem sürerken görünen ince ilerleme çubuğu (tüm sayfalarda, başlığın altında)
Local $pBar = GUICtrlCreateProgress($UI_CX, 84, $UI_CW, 4, $PBS_MARQUEE)
GUICtrlSetState(-1, $GUI_HIDE)

; --- 0) Ana Sayfa ---
_MainPageHeader($PAGE_HOME, "Ana Sayfa", "Discord ve Roblox erişimini buradan yönetin.")
_MainPage($PAGE_HOME, _UiCard($UI_CX, 98, $UI_CW, 146))
Global $lblStatusDot = _MainPage($PAGE_HOME, _UiLabel("●", $UI_CX + 22, 118, 34, 40, 22, $UI_YELLOW, 400, BitOR($SS_CENTER, $SS_CENTERIMAGE)))
Local $lblStatusText = _MainPage($PAGE_HOME, _UiLabel("SİSTEM HAZIRLANIYOR...", $UI_CX + 66, 116, 360, 34, 16, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
Local $lblStrategyInfo = _MainPage($PAGE_HOME, _UiLabel("Strateji Durumu: Kontrol Ediliyor...", $UI_CX + 68, 152, 360, 20, 9.5, $UI_TEXT2))
Global $lblStatusHint = _MainPage($PAGE_HOME, _UiLabel("", $UI_CX + 68, 176, 360, 40, 9, $UI_MUTED))
Local $btnRunZapret = _MainPage($PAGE_HOME, _UiButton("▶   Başlat", $UI_CX + $UI_CW - 206, 130, 182, 54, $UI_KIND_SUCCESS, 12, 12))
GUICtrlSetState($btnRunZapret, $GUI_DISABLE)

; MOTOR / STRATEJİ / FİLTRE kartları
Global $aCardTitle[3] = ["MOTOR", "STRATEJİ", "FİLTRE"]
For $i = 0 To 2
    _MainPage($PAGE_HOME, _UiCard($UI_CX + $i * 222, 262, 204, 104))
    _MainPage($PAGE_HOME, _UiLabel($aCardTitle[$i], $UI_CX + $i * 222 + 18, 278, 170, 18, 8.5, $UI_MUTED, 700))
Next
Local $cmbEngine = _MainPage($PAGE_HOME, GUICtrlCreateCombo("Zapret2 (yeni motor)", $UI_CX + 18, 304, 168, 24, $CBS_DROPDOWNLIST))
GUICtrlSetData($cmbEngine, "Zapret (klasik motor)")
If $iniEngine == "1" Then GUICtrlSetData($cmbEngine, "Zapret (klasik motor)", "Zapret (klasik motor)")
GUICtrlSetFont($cmbEngine, 10, 400, 0, $UI_FONT)
GUICtrlSetState($cmbEngine, $GUI_DISABLE)

Global $cmbStrategy = _MainPage($PAGE_HOME, GUICtrlCreateCombo("Analiz Sonucu", $UI_CX + 240, 304, 168, 24, $CBS_DROPDOWNLIST))
GUICtrlSetFont($cmbStrategy, 10, 400, 0, $UI_FONT)
GUICtrlSetState($cmbStrategy, $GUI_DISABLE)

Global $cmbFilter = _MainPage($PAGE_HOME, GUICtrlCreateCombo("Kapalı (tüm trafik)", $UI_CX + 462, 304, 168, 24, $CBS_DROPDOWNLIST))
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
GUICtrlSetFont($cmbFilter, 10, 400, 0, $UI_FONT)
GUICtrlSetState($cmbFilter, $GUI_DISABLE)
_UiDarkControl($cmbEngine)
_UiDarkControl($cmbStrategy)
_UiDarkControl($cmbFilter)

_MainPage($PAGE_HOME, _UiCard($UI_CX, 384, $UI_CW, 112))
_MainPage($PAGE_HOME, _UiIcon($UI_ICON_INFO, $UI_CX + 18, 400, 28, 28, 14, $UI_ACCENT))
_MainPage($PAGE_HOME, _UiLabel("İpucu", $UI_CX + 54, 402, 300, 22, 11, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
_MainPage($PAGE_HOME, _UiLabel("Discord bağlanmıyorsa Analiz > Hızlı akıllı test ile en uygun stratejiyi bulun. " & _
        "Tarayıcıda denemek yanıltıcıdır; Discord uygulamasını tamamen kapatıp yeniden açarak deneyin.", $UI_CX + 54, 428, $UI_CW - 80, 54, 9.5, $UI_TEXT2))

; --- 1) Analiz ---
_MainPageHeader($PAGE_ANALYZE, "Analiz", "İnternet sağlayıcınız için en uygun stratejiyi bulun.")
_MainPage($PAGE_ANALYZE, _UiCard($UI_CX, 98, $UI_CW, 176))
_MainPage($PAGE_ANALYZE, _UiLabel("Akıllı ISS analizi", $UI_CX + 22, 116, 400, 26, 13, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
_MainPage($PAGE_ANALYZE, _UiLabel("Stratejiler Discord'un sohbet sunucusuna, discord.com ve roblox.com'a gerçek bağlantılarla sınanır; " & _
        "en hızlı ve en kararlı olan önerilir. Tam analiz önce ISS'inizi tarar, hızlı test hazır profilleri dener.", $UI_CX + 22, 146, $UI_CW - 44, 44, 9.5, $UI_TEXT2))
Local $btnAnalyze = _MainPage($PAGE_ANALYZE, _UiButton("ISS Analizi (Blockcheck) Yap", $UI_CX + 22, 206, 320, 46, $UI_KIND_PRIMARY, 10.5))
GUICtrlSetState($btnAnalyze, $GUI_DISABLE)
_MainPage($PAGE_ANALYZE, _UiCard($UI_CX, 292, $UI_CW, 96))
_MainPage($PAGE_ANALYZE, _UiLabel("SON AKILLI ANALİZ", $UI_CX + 22, 308, 300, 18, 8.5, $UI_MUTED, 700))
Global $lblSmartLast = _MainPage($PAGE_ANALYZE, _UiLabel("Henüz akıllı analiz yapılmadı.", $UI_CX + 22, 332, $UI_CW - 44, 44, 9.5, $UI_TEXT))

; --- 2) Servis ---
_MainPageHeader($PAGE_SERVICE, "Servis", "Zapret'in bilgisayar açılınca kendiliğinden başlamasını sağlayın.")
_MainPage($PAGE_SERVICE, _UiCard($UI_CX, 98, $UI_CW, 190))
Global $lblSvcDot = _MainPage($PAGE_SERVICE, _UiLabel("●", $UI_CX + 22, 116, 30, 30, 16, $UI_MUTED, 400, BitOR($SS_CENTER, $SS_CENTERIMAGE)))
Global $lblSvcTitle = _MainPage($PAGE_SERVICE, _UiLabel("Servis kurulu değil", $UI_CX + 56, 116, 500, 30, 13, $UI_TEXT, 700, BitOR($SS_LEFT, $SS_CENTERIMAGE), $UI_FONT_SEMI))
Global $lblSvcInfo = _MainPage($PAGE_SERVICE, _UiLabel("", $UI_CX + 22, 152, $UI_CW - 44, 40, 9.5, $UI_TEXT2))
Local $btnInstallService = _MainPage($PAGE_SERVICE, _UiButton("Servis Olarak Yükle (Otomatik Başlat)", $UI_CX + 22, 214, 300, 46, $UI_KIND_PRIMARY, 10.5))
GUICtrlSetState($btnInstallService, $GUI_DISABLE)
Local $btnRemoveService = _MainPage($PAGE_SERVICE, _UiButton("Servis ve Kalıntıları Temizle", $UI_CX + 334, 214, 270, 46, $UI_KIND_DANGER, 10.5))
_MainPage($PAGE_SERVICE, _UiCard($UI_CX, 306, $UI_CW, 108))
_MainPage($PAGE_SERVICE, _UiLabel("Otomatik onarım", $UI_CX + 22, 322, 400, 24, 11.5, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
_MainPage($PAGE_SERVICE, _UiLabel("Discord bağlantısı arka planda kontrol edilir; sorun olursa DNS, yedek stratejiler ve gerekirse hızlı analiz denenir.", _
        $UI_CX + 22, 348, $UI_CW - 220, 44, 9.5, $UI_TEXT2))
Global $btnSvcSettings = _MainPage($PAGE_SERVICE, _UiButton("Onarım Ayarları", $UI_CX + $UI_CW - 178, 340, 156, 40, $UI_KIND_SECONDARY, 10))

; --- 3) Ağ Paylaşımı ---
_MainPageHeader($PAGE_LAN, "Ağ Paylaşımı", "Oyun konsolu, akıllı TV gibi cihazlar da Zapret'ten yararlansın.")
_MainPage($PAGE_LAN, _UiCard($UI_CX, 98, $UI_CW, 186))
_MainPage($PAGE_LAN, _UiLabel("go-pcap2socks ile paylaşım", $UI_CX + 22, 116, 400, 26, 13, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
_MainPage($PAGE_LAN, _UiLabel("Zapret çalışırken kullanılabilir. Npcap kurulu olmalıdır. Diğer cihazda IP ve DNS ayarlarını elle girmeniz gerekir; " & _
        "Wi-Fi yavaşlatabileceği için kablolu bağlantı önerilir. Bilgisayarınız açık kalmalıdır.", $UI_CX + 22, 146, $UI_CW - 44, 56, 9.5, $UI_TEXT2))
Global $btnLanShare = _MainPage($PAGE_LAN, _UiButton("Ağdaki Cihazlarla Paylaş", $UI_CX + 22, 214, 280, 46, $UI_KIND_PRIMARY, 10.5))
GUICtrlSetState($btnLanShare, $GUI_DISABLE)

; --- 4) DNS ---
_MainPageHeader($PAGE_DNS, "DNS", "DNS zehirlenmesine karşı şifreli DNS kullanın.")
_MainPage($PAGE_DNS, _UiCard($UI_CX, 98, $UI_CW, 186))
Global $lblDnsInfo = _MainPage($PAGE_DNS, _UiLabel("Etkin DNS okunuyor...", $UI_CX + 22, 116, $UI_CW - 44, 26, 11.5, $UI_TEXT, 600))
_MainPage($PAGE_DNS, _UiLabel("Program açılışta DNS zehirlenmesini kontrol eder ve gerekirse Cloudflare DNS'e geçmeyi önerir. " & _
        "DNSCrypt ise DNS sorgularını bilgisayarınızda çalışan şifreli bir aracı üzerinden gönderir.", $UI_CX + 22, 146, $UI_CW - 44, 56, 9.5, $UI_TEXT2))
Local $sInitialDnscryptText = ($iniDnscryptInstalled == "1") ? "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır" : "Dnscrypt-proxy servisi kur"
Global $btnDnscrypt = _MainPage($PAGE_DNS, _UiButton($sInitialDnscryptText, $UI_CX + 22, 214, 300, 46, $UI_KIND_SECONDARY, 10.5))

; --- 5) Ayarlar ---
_MainPageHeader($PAGE_SETTINGS, "Ayarlar", "Otomatik onarım, güncelleme ve destek.")
_MainPage($PAGE_SETTINGS, _UiCard($UI_CX, 98, $UI_CW, 136))
Global $btnPageSettings = _MainPage($PAGE_SETTINGS, _UiButton("Ayarları Aç", $UI_CX + 22, 120, 190, 42, $UI_KIND_PRIMARY, 10))
Global $btnPageDiag = _MainPage($PAGE_SETTINGS, _UiButton("Tanılama Paketi Oluştur", $UI_CX + 224, 120, 220, 42, $UI_KIND_SECONDARY, 10))
Global $btnPageLogs = _MainPage($PAGE_SETTINGS, _UiButton("Log Klasörünü Aç", $UI_CX + 456, 120, 170, 42, $UI_KIND_SECONDARY, 10))
_MainPage($PAGE_SETTINGS, _UiLabel("Tanılama paketi; log, ayar ve servis durumunu masaüstüne kaydeder. Ziyaret ettiğiniz siteler, IP ve MAC adresleri eklenmez.", _
        $UI_CX + 22, 176, $UI_CW - 44, 40, 9, $UI_MUTED))
_MainPage($PAGE_SETTINGS, _UiCard($UI_CX, 252, $UI_CW, 96))
_MainPage($PAGE_SETTINGS, _UiLabel("Hakkında", $UI_CX + 22, 268, 300, 24, 11.5, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
_MainPage($PAGE_SETTINGS, _UiLabel($APP_NAME & " " & $APP_VERSION & "  ·  github.com/" & $APP_UPDATE_REPO & @CRLF & _
        "Temel: alimali54/zapret-win-turkey  ·  Motor: bol-van/zapret", $UI_CX + 22, 296, $UI_CW - 44, 40, 9, $UI_TEXT2))

; Düğme Array'lerine yeni butonu ekledik ki sistem hazır olduğunda kilitleri otomatik açılsın
Local $aCriticalButtons[7] = [$btnRunZapret, $btnAnalyze, $btnInstallService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]
Local $aOtherButtons[7] = [$btnAnalyze, $btnInstallService, $btnRemoveService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]

_MainShowPage($PAGE_HOME)
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
RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
GUICtrlSetData($lblStatusText, "DNS KONTROL EDİLİYOR...")

Local $isDnsChangedByApp = False

While 1
    Local $isPoisoned = CheckDnsPoisoningSilent()

    If $isPoisoned Then
        _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
		GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; <--- DNS zehirlense bile bu buton hep tıklanabilir olsun!
        GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
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

While 1
    Local $nMsg = GUIGetMsg()
    ; Yeni arayüz: sayfa komutları eski düğme olaylarına çevrilir, durum sayfaya aktarılır.
    If $g_bWebUi Then $nMsg = _WebUiTick($nMsg)

    ; Kenar menüsü, hover ve durum renkleri (ui/Theme.au3)
    If _MainNavClick($nMsg) Then ContinueLoop
    _UiTick($hGUI)
    _MainUiSync()

    ; DNSCrypt çalışırken kuyruğa alınan tıklamaları da atla.
    If $nMsg = $btnDnscrypt And $bDnscryptBusy Then ContinueLoop

    ; Servis kurulumu sırasında kuyruğa alınan tıklamaları da atla.
    If $nMsg = $btnInstallService And $bInstallServiceBusy Then ContinueLoop

    ; Servis kurulum işlemi bittikten 1,5 saniye sonra butonu uygun durumdaysa aç.
    If $bInstallServiceBusy And $hInstallServiceUnlockTimer <> 0 Then
        If TimerDiff($hInstallServiceUnlockTimer) >= 1500 Then
            $bInstallServiceBusy = False
            $hInstallServiceUnlockTimer = 0
            If $bInstallServiceEnableAfterLock And GUICtrlRead($lblStatusText) = "ÇALIŞMAYA HAZIR" Then
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
			; Servis durduktan sonra yeniden başladıysa "DURDU" yazısı takılı kalmasın.
			_RefreshIfServiceRecovered()
		Else
			; 2. Zapret ölmüşse LAN Paylaşım butonunu devre dışı bırak, yazısını sıfırla ve go-pcap2socks'u kapat
			If BitAND(GUICtrlGetState($btnLanShare), $GUI_ENABLE) Then
				GUICtrlSetState($btnLanShare, $GUI_DISABLE)

				If GUICtrlRead($btnLanShare) = "[ ✓ ] Paylaşım Aktif / Durdur" Then
					GUICtrlSetData($btnLanShare, "Ağdaki Cihazlarla Paylaş")
                    GUICtrlSetFont($btnLanShare, 10, 600, 0, "Segoe UI")
					If ProcessExists("go-pcap2socks.exe") Then
						ProcessClose("go-pcap2socks.exe")
						$pcapPID = 0
					EndIf
				EndIf
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
			If GUICtrlRead($lblStatusText) = "SERVİS MODU AKTİF" Then
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
            _MainRefreshServicePage()

        Case $btnPageDiag
            _DiagCreateFromTray()

        Case $btnPageLogs
            ShellExecute(@ScriptDir & "\logs")

        Case $GUI_EVENT_MINIMIZE
            _MainWindowHide()
            TraySetToolTip("Zapret Windows Türkiye Çalışıyor")

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
                    GUICtrlSetData($lblStatusText, "ANALİZ YAPILIYOR...")
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
                    GUICtrlSetData($lblStatusText, "ANALİZ TAMAMLANDI")
                    _RefreshStrategyLabel()
                EndIf
            EndIf

            _MainWindowShow(True)

            ; Analiz akışı içindeki genel buton açma işlemleri kilidi kaldıramasın.
            If GUICtrlRead($lblStatusText) = "DNS ZEHİRLENMESİ SAPTANDI!" Then $bBlockcheckEnableAfterLock = False
            GUICtrlSetState($btnAnalyze, $GUI_DISABLE)
            $hBlockcheckUnlockTimer = TimerInit()
            EndIf ; $bBlockcheckBusy kilit bloğu

		Case $btnLanShare
            If GUICtrlRead($btnLanShare) = "Ağdaki Cihazlarla Paylaş" Then
                ; --- ADIM 1: NPCAP KONTROLÜ ---
                If Not FileExists(@SystemDir & "\Packet.dll") Then
                    GUICtrlSetData($btnLanShare, "Ağdaki Cihazlarla Paylaş")
                    GUICtrlSetFont($btnLanShare, 10, 600, 0, "Segoe UI")
                    MsgBox(8208, "Eksik Bileşen", "HATA: Sistemde Npcap sürücüsü bulunamadı!" & @CRLF & @CRLF & _
                            "go-pcap2socks motorunun çalışabilmesi için Npcap kurulmalıdır." & @CRLF & _
                            "Lütfen npcap.com adresinden indirip kurun.")
                    ContinueLoop
                EndIf

                ; --- SPLASH SCREEN BAŞLANGICI ---
                Local $hSplash = GUICreate("Lütfen Bekleyin", 280, 80, -1, -1, $WS_POPUP, $WS_EX_TOPMOST)
                GUISetBkColor(0xF2F4F7, $hSplash)
                GUICtrlCreateLabel("Güvenlik Duvarı" & @CRLF & "Kontrolleri Yapılıyor...", 10, 20, 260, 40, $SS_CENTER)
                GUICtrlSetFont(-1, 10, 800, 0, "Segoe UI")
                GUICtrlSetColor(-1, 0x2C3E50)
                GUISetState(@SW_SHOW, $hSplash)

                Local $targetPcapExe = @ScriptDir & '\bin\go-pcap2socks\go-pcap2socks.exe'

                If Not HasFirewallRule($targetPcapExe) Then
                    GUISetState(@SW_HIDE, $hSplash)

                    RunWait('powershell -NoProfile -Command "Remove-NetFirewallRule -Program ''' & $targetPcapExe & ''' -ErrorAction SilentlyContinue"', "", @SW_HIDE)
                    RunWait(@ComSpec & ' /c netsh advfirewall firewall delete rule name=all program="' & $targetPcapExe & '"', "", @SW_HIDE)

                    MsgBox(8256, "Güvenlik Duvarı İzni", "go-pcap2socks için ağ izni gerekiyor." & @CRLF & @CRLF & _
                            "1. Birazdan Windows Güvenlik Duvarı uyarısı gelecektir." & @CRLF & _
                            "2. Lütfen gelen ekranda kutucukları işaretleyip 'Erişime izin ver' (Allow) butonuna basın.")

                    Local $tmpPID = Run('"' & $targetPcapExe & '"', @ScriptDir & '\bin\go-pcap2socks', @SW_HIDE)
                    MsgBox(8256, "Onay", "Güvenlik duvarı iznini onayladıysanız Tamam'a basın.")
                    ProcessClose($tmpPID)

                    GUISetState(@SW_SHOW, $hSplash)
                EndIf

                ; --- ADIM 3: SÜRECİ BAŞLATMA ---
                If Not ProcessExists("go-pcap2socks.exe") Then
                    $pcapPID = Run('"' & $targetPcapExe & '"', @ScriptDir & '\bin\go-pcap2socks', @SW_HIDE)
                    _LogInfo("Ağ paylaşımı: go-pcap2socks başlatıldı (PID " & $pcapPID & ")")
                EndIf

                ; --- GERÇEKTEN ÇALIŞIYOR MU KONTROLÜ ---
                Sleep(500)

                If Not ProcessExists("go-pcap2socks.exe") Then
                    GUIDelete($hSplash)
                    GUICtrlSetData($btnLanShare, "Ağdaki Cihazlarla Paylaş")
                    GUICtrlSetFont($btnLanShare, 10, 600, 0, "Segoe UI")
                    $pcapPID = 0
                    MsgBox(16 + 8192, "Başlatma Hatası", "HATA: go-pcap2socks başlatılamadı!" & @CRLF & @CRLF & _
                            "• Sanal bir ağ kartı oluşturan VPN vb program kullanıyorsanız kapatın.")
                    ContinueLoop
                EndIf

                GUIDelete($hSplash)

                ; BAŞARILI DURUM: Butonu Yeşile Boya ve Metni Değiştir
                GUICtrlSetData($btnLanShare, "[ ✓ ] Paylaşım Aktif / Durdur")
                GUICtrlSetFont($btnLanShare, 10, 800, 0, "Segoe UI")

                MsgBox(8256, "go-pcap2socks Ağ Yapılandırması", _
                        "Ağdaki diğer cihazınızda şu IP ayarlarını giriniz:" & @CRLF & @CRLF & _
                        "• IP Aralığı: 172.24.2.10 - 172.24.2.255" & @CRLF & _
                        "• Ağ Geçidi (Gateway): 172.24.2.1" & @CRLF & _
                        "• Alt Ağ Maskesi (Maske): 255.255.0.0" & @CRLF & _
                        "• DNS 1: 1.1.1.1" & @CRLF & _
                        "• DNS 2: 8.8.8.8")
            Else
                ; DURDURMA İŞLEMİ
                If ProcessExists("go-pcap2socks.exe") Then
                    ProcessClose("go-pcap2socks.exe")
                    $pcapPID = 0
                EndIf
                GUICtrlSetData($btnLanShare, "Ağdaki Cihazlarla Paylaş")
                GUICtrlSetFont($btnLanShare, 10, 600, 0, "Segoe UI")
            EndIf

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

            Local $btnText = GUICtrlRead($btnDnscrypt)

            If StringInStr($btnText, "servisi kur") Then
                GUICtrlSetData($lblStatusText, "DNSCRYPT KURULUYOR...")
                _LogInfo("DNSCrypt servisi kuruluyor")

                RunWait('"' & $sProxyPath & '" -service install', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service start', $sProxyDir, @SW_HIDE)
                If Not _SetDNS_Localhost() Then MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)

                GUICtrlSetData($btnDnscrypt, "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır")
                IniWrite($iniPath, "Settings", "DnscryptInstalled", "1")
                ;MsgBox(64 + 8192, "Başarılı", "DNSCrypt servisi kuruldu.")
            Else
                GUICtrlSetData($lblStatusText, "DNSCRYPT KALDIRILIYOR...")
                _LogInfo("DNSCrypt servisi kaldırılıyor")

                RunWait('"' & $sProxyPath & '" -service stop', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service uninstall', $sProxyDir, @SW_HIDE)
                If Not _ResetSystemDNS() Then MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)

                GUICtrlSetData($btnDnscrypt, "Dnscrypt-proxy servisi kur")
                IniWrite($iniPath, "Settings", "DnscryptInstalled", "0")
                ;MsgBox(64 + 8192, "Bilgi", "DNSCrypt servisi kaldırıldı ve DNS otomatiğe (DHCP) alındı.")
            EndIf

            ; --- AÇILIŞTAKİ GÜVENLİ KONTROL AKIŞININ AYNISI (BAŞTAN AÇILMIŞ GİBİ) ---
            GUICtrlSetData($lblStatusText, "DNS TEST EDİLİYOR...")
            Sleep(1000) ; Ağın ve adaptörün kendine gelmesi için bekleme

			Local $isPoisoned = CheckDnsPoisoningSilent()

            If $isPoisoned Then
				_SetButtonsState($aCriticalButtons, $GUI_DISABLE)
				GUICtrlSetState($btnDnscrypt, $GUI_ENABLE) ; DNS zehirlense bile bu buton hep tıklanabilir olsun
				GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
				GUICtrlSetColor($lblStatusText, 0xC0392B)
			Else
				; Zehirlenme yoksa her şey normal devam etsin
				CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $cmbFilter)
				GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)
				_RefreshStrategyLabel()
			EndIf

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
            GUICtrlSetData($btnDnscrypt, "Dnscrypt-proxy servisi kur")
            IniWrite($iniPath, "Settings", "DnscryptInstalled", "0")

            ; --- YENİ EKLENEN ADIM: DNS'i Otomatiğe (DHCP) Al ---
            GUICtrlSetData($lblStatusText, "SİSTEM SIFIRLANIYOR...")
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
    Local $dnscryptVal = (StringInStr(GUICtrlRead($btnDnscrypt), "aktif")) ? "1" : "0"

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

Func ExitApp()
    If $isZapretRunning Then StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
    If ProcessExists("go-pcap2socks.exe") Then ProcessClose("go-pcap2socks.exe")
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
        GUICtrlSetData($btnAnalyze, "ISS Analizi (Blockcheck) Yap")

        GUICtrlSetData($statusID, "ÇALIŞMAYA HAZIR")
        GUICtrlSetColor($statusID, 0x2C3E50)
    EndIf
    _UpdateFilterForStrategy()
EndFunc

; Servis durmuş görünürken winws yeniden çalışıyorsa (Windows/elle yeniden başlatma) durumu
; tazeler ve "servis durdu" uyarısını yeniden silahlandırır; böylece sonraki durmada da uyarılır.
Func _RefreshIfServiceRecovered()
    If GUICtrlRead($lblStatusText) <> "SERVİS YÜKLÜ - DURDU" Then Return
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
        GUICtrlSetData($statusID, "MANUEL MOD AKTİF")
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
Func _MainPage($iPage, $id)
    $g_aPageCtrl[$iPage][$g_aPageCount[$iPage]] = $id
    $g_aPageCount[$iPage] += 1
    Return $id
EndFunc

Func _MainPageHeader($iPage, $sTitle, $sSub)
    _MainPage($iPage, _UiLabel($sTitle, $UI_CX, 22, $UI_CW, 34, 20, $UI_TEXT, 700, 0, $UI_FONT_SEMI))
    _MainPage($iPage, _UiLabel($sSub, $UI_CX, 58, $UI_CW, 20, 10, $UI_TEXT2))
EndFunc

Func _MainShowPage($iPage)
    If $iPage = $g_iPage Then Return
    For $p = 0 To 5
        For $j = 0 To $g_aPageCount[$p] - 1
            _UiSetVisible($g_aPageCtrl[$p][$j], $p = $iPage)
        Next
        _UiButtonSetKind($g_aNav[$p], ($p = $iPage) ? $UI_KIND_NAV_ACTIVE : $UI_KIND_NAV)
    Next
    $g_iPage = $iPage
    Switch $iPage
        Case $PAGE_ANALYZE
            _MainRefreshSmartSummary()
        Case $PAGE_SERVICE
            _MainRefreshServicePage()
        Case $PAGE_DNS
            _MainRefreshDnsInfo()
    EndSwitch
EndFunc

; Önizleme: örnek durumla her sayfanın ekran görüntüsünü alır ve çıkar (sistemde hiçbir şey değiştirmez).
Func _MainUiPreviewAndExit($sDir)
    _UpdateEnginePaths(GUICtrlRead($cmbEngine))
    _LoadStrategyList($iniStrategy)
    _RefreshStrategyLabel()
    GUICtrlSetData($lblStatusText, "ÇALIŞMAYA HAZIR")
    _SetButtonsState($aCriticalButtons, $GUI_ENABLE)
    GUICtrlSetState($btnLanShare, $GUI_ENABLE)
    DirCreate($sDir)
    If $CmdLine[0] >= 3 And $CmdLine[3] = "/yeni-arayuz" Then _WebUiPreviewAndExit($sDir)
    For $p = 0 To 5
        _MainShowPage($p)
        For $k = 1 To 15
            _UiTick($hGUI)
            _MainUiSync()
            Sleep(30)
        Next
        _ScreenCapture_CaptureWnd($sDir & "\sayfa" & $p & ".png", $hGUI)
    Next
    Exit
EndFunc

; Kenar menüsü tıklaması. İşlendiyse True.
Func _MainNavClick($nMsg)
    If $nMsg <= 0 Then Return False
    For $i = 0 To 5
        If $nMsg = $g_aNav[$i] Then
            _MainShowPage($i)
            Return True
        EndIf
    Next
    Return False
EndFunc

; Durum yazısına göre nokta rengi, ipucu satırı ve Başlat/Durdur rengi. Her döngüde çağrılır; yalnız değişince çizer.
Func _MainUiSync()
    Local $s = GUICtrlRead($lblStatusText)
    If $s <> $g_sUiLastStatus Then
        $g_sUiLastStatus = $s
        GUICtrlSetColor($lblStatusText, $UI_TEXT)
        Local $iDot = $UI_YELLOW, $sHint = ""
        If (StringInStr($s, "DURDU") And Not StringInStr($s, "GEÇİCİ")) Or StringInStr($s, "ZEHİRLEN") Then
            $iDot = $UI_RED
        ElseIf StringInStr($s, "AKTİF") Then
            $iDot = $UI_GREEN
        ElseIf StringInStr($s, "ÇALIŞMAYA HAZIR") Then
            $iDot = $UI_MUTED
        EndIf
        Switch $s
            Case "SERVİS MODU AKTİF"
                $sHint = "Bilgisayar açılınca otomatik başlar. Ayrıntılar Servis sekmesinde."
            Case "MANUEL MOD AKTİF"
                $sHint = "Program kapanınca Zapret de durur. Kalıcı kullanım için Servis sekmesine bakın."
            Case "ÇALIŞMAYA HAZIR"
                $sHint = "Başlat'a basın ya da Servis sekmesinden otomatik başlatmayı açın."
            Case "DNS ZEHİRLENMESİ SAPTANDI!"
                $sHint = "DNS sekmesinden şifreli DNS kurun ya da programı yeniden açıp Cloudflare önerisini kabul edin."
            Case "SERVİS YÜKLÜ - DURDU"
                $sHint = "Servis durmuş. Bir program (ör. oyun hile koruması) kapatmış olabilir."
        EndSwitch
        GUICtrlSetColor($lblStatusDot, $iDot)
        GUICtrlSetData($lblStatusHint, $sHint)
        If $g_iPage = $PAGE_SERVICE Then _MainRefreshServicePage()
    EndIf
    Local $r = GUICtrlRead($btnRunZapret)
    If $r <> $g_sUiLastRun Then
        $g_sUiLastRun = $r
        _UiButtonSetKind($btnRunZapret, StringInStr($r, "Durdur") ? $UI_KIND_DANGER : $UI_KIND_SUCCESS)
    EndIf
EndFunc

Func _MainRefreshServicePage()
    Local $s = GUICtrlRead($lblStatusText), $iDot = $UI_MUTED, $sTitle = "Servis kurulu değil"
    If $s = "SERVİS MODU AKTİF" Then
        $iDot = $UI_GREEN
        $sTitle = "Servis çalışıyor"
    ElseIf $s = "SERVİS YÜKLÜ - DURDU" Then
        $iDot = $UI_RED
        $sTitle = "Servis kurulu ama durmuş"
    ElseIf StringInStr($s, "GEÇİCİ") Then
        $iDot = $UI_YELLOW
        $sTitle = "Servis analiz için geçici olarak durduruldu"
    EndIf
    GUICtrlSetColor($lblSvcDot, $iDot)
    GUICtrlSetData($lblSvcTitle, $sTitle)
    Local $bService = $iDot <> $UI_MUTED
    Local $sHealth = _HealthStatusFormat(True, IniRead($iniPath, "Health", "Enabled", "1"), IniRead($iniPath, "Health", "LastCheck", ""), _
            IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
    If $bService Then
        GUICtrlSetData($lblSvcInfo, "Otomatik başlangıç açık  ·  Otomatik yeniden başlatma " & _
                (IniRead($iniPath, "Service", "AutoRestart", "0") = "1" ? "açık" : "kapalı") & "  ·  " & $sHealth)
    Else
        GUICtrlSetData($lblSvcInfo, "Servis kurulursa Zapret bilgisayar açılınca kendiliğinden başlar; programı açık tutmanız gerekmez.")
    EndIf
EndFunc

Func _MainRefreshSmartSummary()
    Local $sPath = _SmartResultsPath()
    If Not FileExists($sPath) Then
        GUICtrlSetData($lblSmartLast, "Henüz akıllı analiz yapılmadı.")
        Return
    EndIf
    Local $sLine = FileReadLine($sPath, 1)
    If StringLeft($sLine, 2) = "# " Then $sLine = StringTrimLeft($sLine, 2)
    GUICtrlSetData($lblSmartLast, $sLine)
EndFunc

Func _MainRefreshDnsInfo()
    Local $s = StringStripWS(_GetActiveAdapterDnsServers(), 3)
    Local $sName = "ISS / modem DNS'i"
    If StringInStr($s, "127.0.0.1") Then
        $sName = "DNSCrypt (yerel, şifreli)"
    ElseIf StringInStr($s, "1.1.1.1") Or StringInStr($s, "1.0.0.1") Then
        $sName = "Cloudflare"
    ElseIf $s = "" Then
        $sName = "otomatik (DHCP)"
    EndIf
    ; Yalnızca IPv4 adresleri gösterilir (IPv6 adresleri satıra sığmıyor).
    Local $sV4 = ""
    For $sAddr In StringSplit($s, ",", 2)
        If $sAddr <> "" And Not StringInStr($sAddr, ":") Then $sV4 &= ($sV4 = "" ? "" : ", ") & $sAddr
    Next
    GUICtrlSetData($lblDnsInfo, "Etkin DNS: " & ($sV4 = "" ? "—" : $sV4) & "  ·  " & $sName)
EndFunc

; Alt satır: motor sürümü + (servis modunda) otomatik onarımın son durumu.
Func _RefreshFooter()
    Local $bService = StringInStr(GUICtrlRead($lblStatusText), "SERVİS") > 0
    Local $sHealth = _HealthStatusFormat($bService, IniRead($iniPath, "Health", "Enabled", "1"), _
            IniRead($iniPath, "Health", "LastCheck", ""), IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
    GUICtrlSetData($lblFooter, $g_sEngineFooter & "  ·  v" & $APP_VERSION & @CRLF & ($sHealth = "" ? "Servis kurulu değil" : $sHealth))
EndFunc

; Tepsi: ayarlar penceresi.
Func _OpenSettings()
    ShowGUI()
    _SettingsUI_Show(@ScriptDir, $serviceName, $APP_NAME, $hGUI)
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
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
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
    GUISetState(@SW_DISABLE, $hGUI)

    Local $isNoBypassNeeded = False
    Local $bUserStopped = False
    Local $aStrategies[1] = [0]

    ; Kullanıcı yeni analiz seçtiği için eski sonuçları geçersiz kıl.
    If FileExists(_BlockcheckResultsPath()) Then FileDelete(_BlockcheckResultsPath())
    If FileExists($logPath) Then FileDelete($logPath)

    Local $hScanGUI = GUICreate("Zapret2 Blockcheck", 360, 170, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hGUI)
    GUISetBkColor(0xFFFFFF, $hScanGUI)
    Local $lblScanTitle = GUICtrlCreateLabel("Taranıyor...", 18, 16, 324, 25, $SS_CENTER)
    GUICtrlSetFont($lblScanTitle, 12, 700, 0, "Segoe UI")
    Local $lblScanElapsed = GUICtrlCreateLabel("Geçen süre: 00:00", 18, 53, 324, 22, $SS_CENTER)
    GUICtrlSetFont($lblScanElapsed, 10, 400, 0, "Segoe UI")
    Local $lblScanCount = GUICtrlCreateLabel("Bulunan strateji: 0", 18, 80, 324, 22, $SS_CENTER)
    GUICtrlSetFont($lblScanCount, 10, 600, 0, "Segoe UI")
    Local $btnStopScan = GUICtrlCreateButton("Analizi Durdur", 70, 115, 220, 32)
    Local $bEnoughHinted = False
    GUISetState(@SW_SHOW, $hScanGUI)

    Local $bashPath = @ScriptDir & "\bin\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\bin\zapret\blockcheck\zapret2\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\bin\zapret\blockcheck", @SW_HIDE)

    If $iPidBash = 0 Then
        GUIDelete($hScanGUI)
        GUISetState(@SW_ENABLE, $hGUI)
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

        Sleep(150)
    WEnd

    ; Analiz doğal olarak bittiğinde de, kullanıcı durdurduğunda da
    ; blockcheck alt süreçlerini temizliyoruz. Yalnızca paketteki cygwin ve
    ; winws süreçleri hedeflenir; kullanıcının açık Git Bash/MSYS oturumları kapanmaz.
    _CleanupBlockcheckProcesses($iPidBash)
    _LogInfo("Blockcheck2 bitti: " & $aStrategies[0] & " strateji, süre " & Int(TimerDiff($hTimer) / 1000) & " sn" & _
            ($bUserStopped ? ", kullanıcı durdurdu" : "") & ($isNoBypassNeeded ? ", engel yok" : ""))

    GUIDelete($hScanGUI)

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

    GUISetState(@SW_ENABLE, $hGUI)
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
    Return _RunAnalysisChoice(_SmartUI_Chooser(FileExists(_BlockcheckResultsPath()), FileExists(_SmartResultsPath()), $hGUI))
EndFunc

; Servis kuruluyken: servisi durdurur, seçilen analizi çalıştırır; strateji değiştiyse servisi
; yeni stratejiyle günceller (DNS'e ve kurtarma ayarına dokunmaz), değişmediyse eski haliyle başlatır.
Func _ServiceStrategyUpdateFlow()
    If Not StringInStr(_ServiceParseBinPath(_ServiceGetConfig($serviceName)), "winws2.exe") Then
        Return MsgBox(48 + 8192, "Servis Stratejisi", "Kurulu servis klasik Zapret motorunu kullanıyor; akıllı analiz yalnızca Zapret2 ile çalışır." & @CRLF & @CRLF & _
                "'Servis ve Kalıntıları Temizle' ile kaldırıp Zapret2 ile yeniden kurabilirsiniz.")
    EndIf
    Local $iChoice = _SmartUI_Chooser(FileExists(_BlockcheckResultsPath()), FileExists(_SmartResultsPath()), $hGUI)
    If $iChoice = $SMARTUI_CANCEL Then Return

    Local $sBefore = StringStripWS(FileRead($strategyFile), 3)
    _LogInfo("Servis stratejisi güncelleme: analiz için servis durduruluyor")
    GUICtrlSetData($lblStatusText, "SERVİS GEÇİCİ OLARAK DURDURULDU")
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
            If _SmartUI_ShowSaved(_SmartResultsPath(), $strategyFile, $winwsPath, $hGUI) <> "" Then _AfterSmartStrategyChosen()
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
    Local $sPrevStatus = GUICtrlRead($lblStatusText)
    GUICtrlSetData($lblStatusText, "AKILLI ANALİZ YAPILIYOR...")
    If Not $bMainAlreadyDisabled Then GUISetState(@SW_DISABLE, $hGUI)
    Local $sTargets = IniRead($iniPath, "SmartAnalysis", "Targets", $SMART_DEFAULT_TARGETS)
    Local $sChosen = _SmartUI_Run($aCand, @ScriptDir, $winwsPath, $sTargets, _SmartResultsPath(), $strategyFile, $hGUI)
    If Not $bMainAlreadyDisabled Then
        GUISetState(@SW_ENABLE, $hGUI)
        _MainWindowShow()
    EndIf
    GUICtrlSetData($lblStatusText, $sPrevStatus)
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
    If Not $bMainAlreadyDisabled Then GUISetState(@SW_DISABLE, $hGUI)

    Local $hTestGUI = GUICreate("Bulunan Stratejileri Test Et", 500, 325, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hGUI)
    GUISetBkColor(0xFFFFFF, $hTestGUI)

    GUICtrlCreateLabel("Bulunan stratejilerden birini seçip test edebilirsin.", 15, 14, 470, 22)
    Local $cmbFoundStrategies = GUICtrlCreateCombo("", 15, 42, 470, 150, BitOR($CBS_DROPDOWNLIST, $WS_VSCROLL))
    Local $sOptions = ""
    For $i = 1 To $aStrategies[0]
        If $sOptions <> "" Then $sOptions &= "|"
        $sOptions &= "Strateji " & $i
    Next
    GUICtrlSetData($cmbFoundStrategies, $sOptions, "Strateji 1")

    GUICtrlCreateLabel("Seçili strateji:", 15, 80, 470, 18)
    Local $edtStrategyPreview = GUICtrlCreateEdit($aStrategies[1], 15, 100, 470, 62, BitOR($ES_READONLY, $ES_AUTOVSCROLL, $WS_VSCROLL))
    Local $lblOobWarning = GUICtrlCreateLabel("", 15, 167, 470, 30)
    GUICtrlSetColor($lblOobWarning, 0xCC0000)
    GUICtrlSetFont($lblOobWarning, 9, 700, 0, "Segoe UI")
    ; Belirgin durum alanı: açık mavi zemin, koyu mavi kalın yazı
    Local $lblTestStatus = GUICtrlCreateLabel("TEST BEKLİYOR  |  Test Et'e basıp Discord/Roblox bağlantını deneyebilirsin.", 15, 202, 470, 38, BitOR($SS_CENTER, $SS_CENTERIMAGE))
    GUICtrlSetBkColor($lblTestStatus, 0xEAF3FF)
    GUICtrlSetColor($lblTestStatus, 0x174EA6)
    GUICtrlSetFont($lblTestStatus, 10, 700, 0, "Segoe UI")

    ; Tek düğme: test kapalıyken başlatır, çalışırken durdurur.
    Local $btnToggleTest = GUICtrlCreateButton("Test Et", 15, 258, 220, 34)
    Local $btnSaveStrategy = GUICtrlCreateButton("Stratejiyi Kaydet", 245, 258, 130, 34)
    Local $btnCloseTest = GUICtrlCreateButton("Kapat", 385, 258, 100, 34)
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
                    GUICtrlSetData($btnToggleTest, "Test Et")
                    GUICtrlSetData($lblTestStatus, "TEST DURDURULDU  |  İstersen başka bir stratejiyi test edebilirsin.")
                    GUICtrlSetBkColor($lblTestStatus, 0xFFF4E5)
                    GUICtrlSetColor($lblTestStatus, 0x8A4B08)
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
                            GUICtrlSetData($btnToggleTest, "Testi Durdur")
                            GUICtrlSetData($lblTestStatus, "TEST ÇALIŞIYOR  |  Discord/Roblox bağlantını dene.")
                            GUICtrlSetBkColor($lblTestStatus, 0xE8F5E9)
                            GUICtrlSetColor($lblTestStatus, 0x1B5E20)
                        Else
                            $bStrategyTestRunning = False
                            GUICtrlSetData($btnToggleTest, "Test Et")
                            GUICtrlSetData($lblTestStatus, "BAŞLATILAMADI  |  WinWS2 dosyasını ve yetkileri kontrol et.")
                            GUICtrlSetBkColor($lblTestStatus, 0xFDECEC)
                            GUICtrlSetColor($lblTestStatus, 0xB71C1C)
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
                GUICtrlSetData($btnToggleTest, "Test Et")
                GUICtrlSetData($lblTestStatus, "TEST ÇALIŞMIYOR | Bir şey süreci sonlandırdı.")
                GUICtrlSetBkColor($lblTestStatus, 0xFDECEC)
                GUICtrlSetColor($lblTestStatus, 0xB71C1C)
            EndIf
        EndIf

        Sleep(30)
    WEnd

    _StopStrategyTest()
    GUIDelete($hTestGUI)

    If Not $bMainAlreadyDisabled Then
        GUISetState(@SW_ENABLE, $hGUI)
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
Func HasFirewallRule($fullPath)
	Local $fixedPath = StringReplace($fullPath, "I", "i")
	Local $psCmd = 'powershell -NoProfile -Command "Get-NetFirewallApplicationFilter -Program ''' & $fixedPath & ''' -ErrorAction SilentlyContinue | Get-NetFirewallRule | Where-Object { $_.Action -eq ''Allow'' -and $_.Enabled -eq ''True'' }"'
	Local $iPID = Run(@ComSpec & ' /c ' & $psCmd, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPID)

    Return (StringLen(StdoutRead($iPID)) > 10)
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
        GUICtrlSetData($btnDnscrypt, "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır")
        IniWrite($iniPath, "Settings", "DnscryptInstalled", "1")
    Else
        GUICtrlSetData($btnDnscrypt, "Dnscrypt-proxy servisi kur")
        IniWrite($iniPath, "Settings", "DnscryptInstalled", "0")
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
    If $CmdLine[0] >= 1 And $CmdLine[1] = "/yeni-arayuz" Then Return True
    Return IniRead($iniPath, "Arayuz", "Yeni", "0") = "1"
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

Func _WebUiOnSize($hWnd, $iMsg, $wParam, $lParam)
    #forceref $iMsg, $wParam, $lParam
    If $hWnd = $hWebGui Then _WV2_Resize()
    Return $GUI_RUNDEFMSG
EndFunc

; Ana döngüde her turda: sayfa mesajlarını işler, durumu aktarır. Dönüş: işlenecek olay.
Func _WebUiTick($nMsg)
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
                _WV2_Post(_WebJsonObj("tip", "tema", "tema", _WebUiTheme()))
            Case "tema"
                Local $sTheme = (_WebJsonGet($sMsg, "tema") = "koyu") ? "koyu" : "acik"
                IniWrite($iniPath, "Arayuz", "Tema", $sTheme)
                _WebUiApplyCaption($sTheme)
            Case "komut"
                Local $sCmd = _WebJsonGet($sMsg, "ad")
                $g_sWebLastJson = "" ; düğme yeniden etkinleşsin diye durum tekrar gönderilir
                ; Uzun bir iş sürerken kuyrukta kalmış komutlar yok sayılır.
                If $iAge > 2000 Then
                    _LogInfo("Yeni arayüz: eskimiş komut yok sayıldı (" & $sCmd & ", " & $iAge & " ms)")
                ElseIf $sCmd = "eskiArayuz" Then
                    _LogInfo("Yeni arayüz: kullanıcı eski arayüze geçti")
                    _WebUiSwitchToOld()
                    Return $nMsg
                ElseIf ($sCmd = "baslat" And Not $isZapretRunning) Or ($sCmd = "durdur" And $isZapretRunning) Then
                    If BitAND(GUICtrlGetState($btnRunZapret), $GUI_ENABLE) Then Return $btnRunZapret
                EndIf
        EndSwitch
    EndIf

    If $g_bWebPageReady And TimerDiff($g_hWebSyncTimer) > 250 Then
        $g_hWebSyncTimer = TimerInit()
        Local $sStatus = GUICtrlRead($lblStatusText)
        ; Onarım durumu 5 sn'de bir veya durum değişince okunur (config.ini'yi her turda okumamak için).
        If $g_hWebHealthTimer = 0 Or TimerDiff($g_hWebHealthTimer) > 5000 Or $sStatus <> $g_sWebLastStatus Then
            $g_hWebHealthTimer = TimerInit()
            $g_sWebLastStatus = $sStatus
            $g_sWebHealth = _HealthStatusFormat(StringInStr($sStatus, "SERVİS") > 0, IniRead($iniPath, "Health", "Enabled", "1"), _
                    IniRead($iniPath, "Health", "LastCheck", ""), IniRead($iniPath, "Health", "LastResult", ""), @YEAR & "/" & @MON & "/" & @MDAY)
        EndIf
        Local $sJson = _WebStateJson($sStatus, GUICtrlRead($btnRunZapret), BitAND(GUICtrlGetState($btnRunZapret), $GUI_ENABLE) <> 0, _
                GUICtrlRead($cmbStrategy), GUICtrlRead($cmbEngine), GUICtrlRead($cmbFilter), $g_sWebHealth)
        If $sJson <> $g_sWebLastJson Then
            $g_sWebLastJson = $sJson
            _WV2_Post($sJson)
        EndIf
    EndIf
    Return $nMsg
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
            FileWriteLine($sLog, "görüntü yeni" & $iShot & ".png: " & GUICtrlRead($lblStatusText))
            If $iShot = 0 And Not $bClicked Then
                _WV2_Exec("document.getElementById('guc').click()")
                $bClicked = True
            EndIf
            $iShot += 1
            If $iShot >= UBound($aStatus) Then ExitLoop
            GUICtrlSetData($lblStatusText, $aStatus[$iShot])
            $hShot = TimerInit()
        EndIf
    WEnd
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
