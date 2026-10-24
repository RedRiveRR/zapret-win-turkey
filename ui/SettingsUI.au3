#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include "Theme.au3"
#include "..\lib\Health.au3"
#include "..\lib\Service.au3"
#include "..\lib\Schedule.au3"
#include "..\lib\Log.au3"

; =========================================================================
; --- AYARLAR PENCERESİ (koyu tema) ---
; config.ini'deki otomatik onarım, servis yeniden başlatma ve güncelleme
; seçeneklerini değiştirir; servis kuruluysa görevi ve kurtarma ayarını hemen
; uygular. "Şimdi kontrol et" sağlık kontrolünü elle çalıştırır.
; =========================================================================

Func __SettingsUI_StatusText($sIni, $bService, $bTask)
    Local $sLast = IniRead($sIni, "Health", "LastCheck", "")
    Local $sRes = IniRead($sIni, "Health", "LastResult", "")
    Return "Servis: " & ($bService ? "kurulu" : "kurulu değil") & "   ·   Onarım görevi: " & ($bTask ? "kurulu" : "yok") & @CRLF & _
            "Son kontrol: " & ($sLast = "" ? "henüz yok" : $sLast & ($sRes = "" ? "" : " — " & $sRes))
EndFunc

; Ayarlar penceresini gösterir. Kaydedildiyse True.
; $bWebUiOption: "Yeni arayüzü kullan" anahtarı gösterilsin mi (yalnızca ana sürüm; [Arayuz] Yeni)
Func _SettingsUI_Show($sRoot, $sServiceName, $sAppName, $hParent, $bWebUiOption = False)
    Local $sIni = $sRoot & "\config\config.ini"
    Local $bService = _ServiceIsInstalled($sServiceName)
    Local $bTask = _ScheduleExists($HEALTH_TASK_NAME)

    GUISetState(@SW_DISABLE, $hParent)
    Local $aMark = _UiMark()
    Local $iExtra = $bWebUiOption ? 36 : 0
    Local $h = _UiWindow("Ayarlar", 560, 548 + $iExtra, $hParent)
    _UiLabel("Ayarlar", 24, 18, 400, 32, 18, $UI_TEXT, 700, 0, $UI_FONT_SEMI)

    ; Otomatik onarım
    _UiCard(24, 62, 512, 200)
    _UiLabel("OTOMATİK ONARIM (SERVİS MODUNDA)", 44, 78, 460, 18, 8.5, $UI_MUTED, 700)
    Local $tglHealth = _UiToggle("Discord bağlantısını arka planda kontrol et ve onar", 44, 104, 470, _
            IniRead($sIni, "Health", "Enabled", "1") = "1" And ($bTask Or Not $bService))
    _UiLabel("Oturum açılışında, 30 dakikada bir ve ağ bağlantısı değişince.", 96, 128, 420, 18, 8.5, $UI_MUTED)
    Local $tglDns = _UiToggle("DNS zehirlenmesi varsa DNS'i Cloudflare'e al", 44, 156, 470, IniRead($sIni, "Health", "AutoFixDns", "1") = "1")
    Local $tglAnalyze = _UiToggle("Gerekirse hızlı akıllı analiz yap (günde en fazla " & $HEALTH_MAX_ANALYZE_PER_DAY & ")", 44, 192, 470, _
            IniRead($sIni, "Health", "AutoAnalyze", "1") = "1")
    _UiLabel("İnternet tamamen kesikse hiçbir şey değiştirilmez.", 96, 216, 420, 18, 8.5, $UI_MUTED)

    ; Servis
    _UiCard(24, 276, 512, 92)
    _UiLabel("SERVİS", 44, 292, 300, 18, 8.5, $UI_MUTED, 700)
    Local $tglRestart = _UiToggle("Servis kapanırsa yeniden başlat (en fazla 2 kez)", 44, 316, 470, IniRead($sIni, "Service", "AutoRestart", "0") = "1")
    _UiLabel("Hile korumalı (anti-cheat) oyun oynuyorsanız kapalı tutmanız önerilir.", 96, 340, 420, 18, 8.5, $UI_YELLOW)

    ; Genel
    _UiCard(24, 382, 512, 56 + $iExtra)
    Local $tglUpdate = _UiToggle("Açılışta yeni sürüm kontrolü yap", 44, 398, 470, IniRead($sIni, "Settings", "UpdateCheck", "1") <> "0")
    Local $tglWebUi = 0
    If $bWebUiOption Then $tglWebUi = _UiToggle("Yeni arayüz (kapatırsan eski arayüz açılır, sonraki açılışta)", 44, 434, 470, IniRead($sIni, "Arayuz", "Yeni", "1") = "1")

    Local $lblStatus = _UiLabel(__SettingsUI_StatusText($sIni, $bService, $bTask), 24, 448 + $iExtra, 512, 36, 8.5, $UI_TEXT2)

    Local $btnCheck = _UiButton("Şimdi kontrol et", 24, 494 + $iExtra, 150, 36, $UI_KIND_SECONDARY, 9.5, 8, $UI_BG)
    Local $btnSave = _UiButton("Kaydet", 300, 494 + $iExtra, 116, 36, $UI_KIND_PRIMARY, 10, 8, $UI_BG)
    Local $btnClose = _UiButton("Kapat", 424, 494 + $iExtra, 112, 36, $UI_KIND_SECONDARY, 10, 8, $UI_BG)
    If Not $bService Then GUICtrlSetState($btnCheck, $GUI_DISABLE)
    GUISetState(@SW_SHOW, $h)

    Local $bSaved = False
    While 1
        Local $nMsg = GUIGetMsg()
        _UiTick($h)
        If _UiToggleHandle($nMsg) Then ContinueLoop
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop
            Case $btnCheck
                GUICtrlSetState($btnCheck, $GUI_DISABLE)
                GUICtrlSetData($lblStatus, "Kontrol ediliyor... (onarım gerekirse 1-2 dakika sürebilir)")
                Local $iR = _HealthRun($sRoot, $sServiceName, $sAppName, True)
                _LogInfo("Ayarlar: elle sağlık kontrolü sonucu " & $iR)
                MsgBox(64 + 8192, "Sağlık Kontrolü", _HealthResultText($iR), 0, $h)
                GUICtrlSetData($lblStatus, __SettingsUI_StatusText($sIni, $bService, _ScheduleExists($HEALTH_TASK_NAME)))
                GUICtrlSetState($btnCheck, $GUI_ENABLE)
            Case $btnSave
                Local $bHealth = _UiToggleGet($tglHealth)
                Local $bRestart = _UiToggleGet($tglRestart)
                IniWrite($sIni, "Health", "AutoFixDns", _UiToggleGet($tglDns) ? "1" : "0")
                IniWrite($sIni, "Health", "AutoAnalyze", _UiToggleGet($tglAnalyze) ? "1" : "0")
                IniWrite($sIni, "Settings", "UpdateCheck", _UiToggleGet($tglUpdate) ? "1" : "0")
                Local $sWebNote = ""
                If $bWebUiOption Then
                    Local $sWebNew = _UiToggleGet($tglWebUi) ? "1" : "0"
                    If $sWebNew <> IniRead($sIni, "Arayuz", "Yeni", "1") Then $sWebNote = @CRLF & "Arayüz değişikliği programı yeniden açınca geçerli olur."
                    IniWrite($sIni, "Arayuz", "Yeni", $sWebNew)
                EndIf
                _SettingsApplyRestart($sIni, $sServiceName, $bService, $bRestart)
                Local $sNote = _SettingsApplyHealth($sIni, $bService, $bHealth)
                If $sNote <> "" Then $sNote = @CRLF & $sNote
                $sNote &= $sWebNote
                _LogInfo("Ayarlar kaydedildi: onarım=" & $bHealth & " dns=" & _UiToggleGet($tglDns) & " analiz=" & _UiToggleGet($tglAnalyze) & _
                        " yenidenbaşlat=" & $bRestart & " güncelleme=" & _UiToggleGet($tglUpdate))
                MsgBox(64 + 8192, "Ayarlar", "Ayarlar kaydedildi." & $sNote, 0, $h)
                $bSaved = True
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($h)
    _UiRelease($aMark)
    GUISetState(@SW_ENABLE, $hParent)
    Return $bSaved
EndFunc

; Otomatik onarımı açar/kapatır; servis kuruluysa onarım görevini hemen kurar/kaldırır.
; Dönüş: kullanıcıya gösterilecek not ("" = not yok). Yeni arayüzün Servis ekranı da kullanır.
Func _SettingsApplyHealth($sIni, $bService, $bHealth)
    IniWrite($sIni, "Health", "Enabled", $bHealth ? "1" : "0")
    If $bService Then
        If $bHealth And Not _ScheduleExists($HEALTH_TASK_NAME) Then
            If _HealthInstallTask() <> 0 Then Return "Uyarı: onarım görevi oluşturulamadı."
        ElseIf Not $bHealth Then
            _HealthRemoveTask()
        EndIf
    ElseIf $bHealth Then
        Return "Otomatik onarım, servis kurulunca etkinleşir."
    EndIf
    Return ""
EndFunc

; "Servis kapanırsa yeniden başlat" ayarını yazar; servis kuruluysa ve değiştiyse servise uygular.
Func _SettingsApplyRestart($sIni, $sServiceName, $bService, $bRestart)
    Local $bPrev = (IniRead($sIni, "Service", "AutoRestart", "0") = "1")
    IniWrite($sIni, "Service", "AutoRestart", $bRestart ? "1" : "0")
    If $bService And $bRestart <> $bPrev Then _ServiceSetRecovery($sServiceName, $bRestart)
EndFunc
