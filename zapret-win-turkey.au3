#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=bin\zapret\zapret-winws\winws2.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=Zapret Multi-Engine Windows Türkiye - Zapret & Zapret2 Kontrol Aracı
#AutoIt3Wrapper_Res_Fileversion=4.5.0.0
#AutoIt3Wrapper_Res_ProductVersion=4.5
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

; --- ZIP / TEMP KLASÖRÜ KONTROLÜ ---
Local $currentDir = @ScriptDir
If StringInStr($currentDir, @TempDir) Or StringInStr($currentDir, "Temporary Internet Files") Or StringInStr($currentDir, "vfs") Then
    MsgBox(16, "Hata: Arşivden Çalıştırma Saptandı", _
            "Programı ZIP dosyasının içinden doğrudan çalıştırmayın!" & @CRLF & @CRLF & _
            "1. ZIP dosyasındaki tüm dosyaları normal bir klasöre çıkarın." & @CRLF & _
            "2. Ardından programı o klasörden tekrar başlatın.")
    Exit
EndIf

; --- GÜVENLİK UYARILARINI KALDIR ---
RunWait('powershell -Command "Get-ChildItem -Path ''' & @ScriptDir & ''' -Recurse | Unblock-File"', "", @SW_HIDE)

; --- ÇAKIŞMA KONTROLÜ (GoodbyeDPI) ---
If ProcessExists("goodbyedpi.exe") Then
    Local $iResponse = MsgBox(52, "Çakışma Saptandı", "GoodbyeDPI aktif gözüküyor, Zapret'in çalışması için GoodbyeDPI sonlandırılmalı." & @CRLF & @CRLF & _
            "GoodbyeDPI'ı kapatmak ve varsa servisini kaldırmak istiyor musunuz?")
    If $iResponse = 6 Then
        ProcessClose("goodbyedpi.exe")
        While ProcessExists("goodbyedpi.exe")
            Sleep(100)
        WEnd
        RunWait(@ComSpec & ' /c sc stop "GoodbyeDPI" & sc delete "GoodbyeDPI" & sc stop "WinDivert" & sc delete "WinDivert" & sc stop "WinDivert14" & sc delete "WinDivert14"', "", @SW_HIDE)
		MsgBox(64, "Bilgi", "GoodbyeDPI ve servisleri başarıyla kaldırıldı. Program başlatılıyor.")
	Else
        Exit
    EndIf
EndIf

Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

; --- Ayarlar ve Dosya Yolları ---
Local $serviceName = "ZapretService"
Local $hostlistPath = @ScriptDir & "\config\autohostlist.txt"
Local $normalHostlistPath = @ScriptDir & "\config\hostlist.txt"
Local $iniPath = @ScriptDir & "\config\config.ini"
Local $exludelistPath = @ScriptDir & "\config\excludelist.txt"

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

; --- GUI Tasarımı ---
Global $hGUI = GUICreate("Zapret Windows Türkiye v4.5", 400, 535)
GUISetBkColor(0xFFFFFF)

; --- Tepsi Menüsü ---
Local $trayShow = TrayCreateItem("Göster")
TrayItemSetOnEvent(-1, "ShowGUI")
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

; =========================================================================
; --- 2. AYARLAR (DROPDOWN MENÜLER) ---
; =========================================================================
; MOTOR
GUICtrlCreateLabel("Motor:", 50, 168, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Local $cmbEngine = GUICtrlCreateCombo("Zapret2 (Yeni LUA Motoru)", 175, 165, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetData(-1, "Zapret (Eski Klasik Motor)")
If $iniEngine == "1" Then GUICtrlSetData($cmbEngine, "Zapret (Eski Klasik Motor)", "Zapret (Eski Klasik Motor)")
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; STRATEJİ
GUICtrlCreateLabel("Strateji:", 50, 203, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbStrategy = GUICtrlCreateCombo("Analiz Sonucu", 175, 200, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; FİLTRE
GUICtrlCreateLabel("Filtre:", 50, 238, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbFilter = GUICtrlCreateCombo("Kapalı (Tüm trafik)", 175, 235, 175, 25, $CBS_DROPDOWNLIST)
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
; --- 3. AĞ PAYLAŞIMI VE DİĞER BUTONLAR ---
; =========================================================================
Global $btnLanShare = GUICtrlCreateButton("Ağdaki Cihazlarla Paylaş", 50, 280, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

Local $btnAnalyze = GUICtrlCreateButton("ISS Analizi (Blockcheck) Yap", 50, 325, 300, 35)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnInstallService = GUICtrlCreateButton("Servis Olarak Yükle (Otomatik Başlat)", 50, 370, 300, 35)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

; --- DNSCRYPT BUTONU ---
Local $sInitialDnscryptText = ($iniDnscryptInstalled == "1") ? "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır" : "Dnscrypt-proxy servisi kur"
Global $btnDnscrypt = GUICtrlCreateButton($sInitialDnscryptText, 50, 415, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnRemoveService = GUICtrlCreateButton("Servis ve Kalıntıları Temizle", 50, 460, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Global $lblFooter = GUICtrlCreateLabel("Zapret Multi-Engine v2.7.0", 0, 505, 400, 20, $SS_CENTER)
GUICtrlSetFont(-1, 10, 400, 0, "Consolas")
GUICtrlSetColor(-1, 0xBDC3C7)

; Düğme Array'lerine yeni butonu ekledik ki sistem hazır olduğunda kilitleri otomatik açılsın
Local $aCriticalButtons[7] = [$btnRunZapret, $btnAnalyze, $btnInstallService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]
Local $aOtherButtons[7] = [$btnAnalyze, $btnInstallService, $btnRemoveService, $cmbEngine, $cmbStrategy, $cmbFilter, $btnDnscrypt]

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

; --- Ana Döngü ---
Local $hProcessTimer = TimerInit() ; ZAMANLAYICIYI BAŞLAT (Bunu While 1'in hemen üstüne koy)

; --- AÇILIŞTA DNSCRYPT SERVİS DURUMUNU KONTROL ET ---
_CheckDnscryptStatus()

While 1
    Local $nMsg = GUIGetMsg()

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
	$hProcessTimer = TimerInit()
	EndIf

    Switch $nMsg
        Case $GUI_EVENT_CLOSE
            _SaveConfigAndExit()

        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)
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

            ; Zapret2 için önceki analiz sonuçları saklanır ve tekrar açılabilir.
            Local $bStartNewAnalysis = True
            If $currentEngine = "Zapret2" And FileExists(_BlockcheckResultsPath()) Then
                Local $iPreviousChoice = MsgBox(35 + 8192, "Önceki Blockcheck Sonucu", _
                    "Önceki analizde bulunan stratejiler açılsın mı?" & @CRLF & @CRLF & _
                    "Evet: Önceki sonuçları aç" & @CRLF & _
                    "Hayır: Yeni analiz başlat" & @CRLF & _
                    "İptal: Vazgeç")

                If $iPreviousChoice = 6 Then
                    Local $aPreviousStrategies[1] = [0]
                    _LoadBlockcheckResults($aPreviousStrategies)
                    If $aPreviousStrategies[0] > 0 Then
                        _ShowStrategyTestWindow($aPreviousStrategies)
                    Else
                        MsgBox(48 + 8192, "Sonuç Bulunamadı", "Kayıtlı sonuç dosyası boş veya okunamadı. Yeni analiz başlatabilirsiniz.")
                    EndIf
                    $bStartNewAnalysis = False
                ElseIf $iPreviousChoice = 2 Then
                    $bStartNewAnalysis = False
                EndIf
                ; Hayır (7) seçilirse yeni analiz akışına devam edilir.
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

			GUISetState(@SW_SHOW, $hGUI)
            GUISetState(@SW_RESTORE, $hGUI)
            WinActivate($hGUI)
            WinWaitActive($hGUI, "", 2)

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

                RunWait('"' & $sProxyPath & '" -service install', $sProxyDir, @SW_HIDE)
                RunWait('"' & $sProxyPath & '" -service start', $sProxyDir, @SW_HIDE)
                If Not _SetDNS_Localhost() Then MsgBox(48 + 8192, "Uyarı", $NET_MSG_NO_ADAPTER)

                GUICtrlSetData($btnDnscrypt, "[ ✓ ] Dnscrypt-proxy Aktif / Kaldır")
                IniWrite($iniPath, "Settings", "DnscryptInstalled", "1")
                ;MsgBox(64 + 8192, "Başarılı", "DNSCrypt servisi kuruldu.")
            Else
                GUICtrlSetData($lblStatusText, "DNSCRYPT KALDIRILIYOR...")

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
    GUICtrlSetData($cmbStrategy, "")
    If $currentEngine == "Zapret2" Then
        GUICtrlSetData($cmbStrategy, "Analiz Sonucu|Turk Telekom|Superonline|Vodafone|Turksat Kablonet|Telekom Mobil|Turkcell Mobil|Vodafone Mobil", $sDefaultToSelect)
    Else
        GUICtrlSetData($cmbStrategy, "Analiz Sonucu|Turk Telekom|TT Alternatif|Superonline|SOL Alternatif|Vodafone|Turkcell Mobil|Vodafone Mobil|Telekom Mobil", $sDefaultToSelect)
    EndIf
EndFunc

Func _GetActiveStrategyString()
    Local $sel = GUICtrlRead($cmbStrategy)
    If $sel == "Analiz Sonucu" Then
        Return StringStripWS(FileRead($strategyFile), 3)
    EndIf

    If $currentEngine == "Zapret2" Then
        Switch $sel
            Case "Turk Telekom"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
            Case "Superonline"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
            Case "Vodafone"
                Return '--payload=tls_client_hello --lua-desync=multisplit:blob=fake_default_tls:ip_ttl=5:pos=2:nodrop:repeats=1'
			Case "Turksat Kablonet"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
			Case "Telekom Mobil"
                Return '--payload=tls_client_hello --lua-desync=fake:blob=0x00000000:ip_ttl=5:repeats=1'
			Case "Turkcell Mobil"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
			Case "Vodafone Mobil"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
			EndSwitch
    Else
        Switch $sel
            Case "Turk Telekom"
                Return "--dpi-desync=fake --dpi-desync-ttl=4"
            Case "TT Alternatif"
                Return "--dpi-desync=fake --dpi-desync-ttl=3"
            Case "Superonline"
                Return "--dpi-desync=fake --dpi-desync-fooling=md5sig"
            Case "SOL Alternatif"
                Return "--dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-ttl=3"
			Case "Vodafone"
                Return "--dpi-desync=fake,multisplit --dpi-desync-fooling=badseq --dpi-desync-split-pos=1,midsld"
            Case "Turkcell Mobil"
                Return "--dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=3"
            Case "Vodafone Mobil"
                Return "--dpi-desync=multisplit --dpi-desync-split-pos=2"
			Case "Telekom Mobil"
                Return "--dpi-desync=fake --dpi-desync-ttl=5"
        EndSwitch
    EndIf
    Return ""
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
    If $sel == "Analiz Sonucu" Then
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil (Analiz Gerekli)"))
    Else
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: Hazır Profil (" & $sel & ")")
    EndIf
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

    ; Değişkeni burada 'Local' olarak tanımlıyoruz
    Local $dnscryptVal = (StringInStr(GUICtrlRead($btnDnscrypt), "aktif")) ? "1" : "0"

    IniWrite($iniPath, "Settings", "ActiveEngine", $engineVal)
    IniWrite($iniPath, "Settings", "ActiveStrategy", $stratVal)
    IniWrite($iniPath, "Settings", "FilterMode", $filterModeVal)
    IniWrite($iniPath, "Settings", "DnscryptInstalled", $dnscryptVal)

    ExitApp()
EndFunc

Func _UpdateEnginePaths($sEngineSelected)
    If StringInStr($sEngineSelected, "Zapret2") Then
        $currentEngine = "Zapret2"
        $strategyFile = @ScriptDir & "\config\strategy2.txt"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws2.exe"
        $blockcheckPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck2.cmd"
        $logPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck2.log"
        GUICtrlSetData($lblFooter, "Zapret2 v1.0.5.2")
    Else
        $currentEngine = "Zapret1"
        $strategyFile = @ScriptDir & "\config\strategy.txt"
        $winwsPath = @ScriptDir & "\bin\zapret\zapret-winws\winws.exe"
        $blockcheckPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck.cmd"
        $logPath = @ScriptDir & "\bin\zapret\blockcheck\blockcheck.log"
        GUICtrlSetData($lblFooter, "Zapret v72.12")
    EndIf
EndFunc

Func ShowGUI()
    GUISetState(@SW_SHOW, $hGUI)
    GUISetState(@SW_RESTORE, $hGUI)
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
            GUICtrlSetData($chkID, "Auto (Zapret oluşturur)")
        ElseIf StringInStr($sCfgOut, "--hostlist=") Then
            GUICtrlSetData($chkID, "Manuel ('hostlist.txt' İçeriği)")
        Else
            GUICtrlSetData($chkID, "Kapalı (Tüm trafik)")
        EndIf

        GUICtrlSetState($manualBtn, $GUI_DISABLE)
        _SetButtonsState($lockArray, $GUI_DISABLE)

		GUICtrlSetState($btnDnscrypt, $GUI_ENABLE)

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
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    Local $fullCommand = '"' & $winwsPath & '" ' & _BuildActiveWinwsArgs($activeStrategy)

    ;ClipPut($fullCommand)
    $zapretPID = Run($fullCommand, @ScriptDir & "\bin\zapret\zapret-winws\", @SW_HIDE)

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

            MsgBox(16 + 8192, "Başlatma Hatası", "Zapret motoru başlatılamadı veya anında çöktü!" & @CRLF & @CRLF & _
                    "Sisteminizdeki Anti-Cheat yazılımları Zapret'i tehdit olarak algılayıp kapatmış olabilir.")
        EndIf
    Else
        MsgBox(16 + 8192, "Dosya Bulunamadı", "WinWS exe dosyası bulunamadı veya çalıştırılamadı!")
    EndIf
EndFunc

; Seçili motor, strateji ve filtreye göre winws argümanlarını oluşturur; gereken hostlist dosyasını hazırlar.
Func _BuildActiveWinwsArgs($sStrategy)
    Local $sFilterMode = _WinwsFilterModeFromText(GUICtrlRead($cmbFilter))
    _EnsureHostlistFile($sFilterMode, $sStrategy, $hostlistPath, $normalHostlistPath)
    Return _BuildWinwsArgs($currentEngine, $winwsPath, $sStrategy, $sFilterMode, $exludelistPath, $hostlistPath, $normalHostlistPath)
EndFunc

Func StopWinws($ctrlID, $statusID, $aBtns)
    If ProcessExists($zapretPID) Then ProcessClose($zapretPID)
    ; Süreç kapatılamazsa (yetki, takılı sürücü) arayüz sonsuz döngüde kilitlenmesin.
    Local $aWinws[2] = ["winws2.exe", "winws.exe"]
    If Not _CloseProcessesByName($aWinws) Then
        MsgBox(48 + 8192, "Uyarı", "Zapret motoru (winws) kapatılamadı." & @CRLF & @CRLF & _
                "Görev Yöneticisi'nden elle sonlandırmanız veya bilgisayarı yeniden başlatmanız gerekebilir.")
    EndIf
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
    $isZapretRunning = False
    GUICtrlSetData($ctrlID, "ZAPRET'İ BAŞLAT")
    CheckServiceStatus($ctrlID, $statusID, $aBtns, $cmbFilter)
EndFunc

Func InstallServiceClean($chkID)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    Local $binArgs = _BuildActiveWinwsArgs($activeStrategy)

    Local $fullBinPath = '"' & $winwsPath & '" ' & $binArgs
    $fullBinPath = StringReplace($fullBinPath, '"', '\"')

    RemoveService()
    Sleep(500)

    If RunWait(@ComSpec & " /c sc create " & $serviceName & ' binPath= "' & $fullBinPath & '" start= auto', "", @SW_HIDE) = 0 Then
        RunWait(@ComSpec & " /c sc start " & $serviceName, "", @SW_HIDE)
        MsgBox(64 + 8192, "Başarılı", "Seçilen profil servis olarak kuruldu.")
    EndIf
EndFunc

Func RemoveService()
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
    Local $btnStopScan = GUICtrlCreateButton("Analizi Durdur", 95, 115, 170, 32)
    GUISetState(@SW_SHOW, $hScanGUI)

    Local $bashPath = @ScriptDir & "\bin\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\bin\zapret\blockcheck\zapret2\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\bin\zapret\blockcheck", @SW_HIDE)

    If $iPidBash = 0 Then
        GUIDelete($hScanGUI)
        GUISetState(@SW_ENABLE, $hGUI)
        GUISetState(@SW_SHOW, $hGUI)
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
            $hUiTimer = TimerInit()
        EndIf

        Sleep(150)
    WEnd

    ; Analiz doğal olarak bittiğinde de, kullanıcı durdurduğunda da
    ; blockcheck alt süreçlerini temizliyoruz. Yalnızca paketteki cygwin ve
    ; winws süreçleri hedeflenir; kullanıcının açık Git Bash/MSYS oturumları kapanmaz.
    _CleanupBlockcheckProcesses($iPidBash)

    GUIDelete($hScanGUI)

    ; Sonuçları kalıcı dosyaya yaz: pencere kapatılsa bile ana menüden yeniden açılabilir.
    If $aStrategies[0] > 0 Then
        If Not _SaveBlockcheckResults($aStrategies) Then
            MsgBox(48 + 8192, "Sonuçlar Kaydedilemedi", _
                "Stratejiler bu oturumda kullanılabilir ancak sonuç dosyasına kaydedilemedi:" & @CRLF & _BlockcheckResultsPath())
        EndIf
    EndIf

    If $aStrategies[0] > 0 Then
        _ShowStrategyTestWindow($aStrategies, True)
    ElseIf $isNoBypassNeeded Then
        MsgBox(64 + 8192, "Bilgi: Zapret2 Analiz Tamamlandı", _
            "İnternet hattınızda herhangi bir DPI / sansür kısıtlaması saptanmadı.")
    ElseIf $bUserStopped Then
        MsgBox(48 + 8192, "Analiz Durduruldu", "Analiz durduruldu. Kullanılabilir strateji bulunamadı.")
    Else
        MsgBox(16 + 8192, "Başarısız", "Analiz tamamlandı ancak kullanılabilir strateji bulunamadı.")
    EndIf

    GUISetState(@SW_ENABLE, $hGUI)
    GUISetState(@SW_SHOW, $hGUI)
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
        GUISetState(@SW_SHOW, $hGUI)
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