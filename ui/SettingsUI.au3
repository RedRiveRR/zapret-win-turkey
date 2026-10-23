#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ButtonConstants.au3>
#include "..\lib\Health.au3"
#include "..\lib\Service.au3"
#include "..\lib\Schedule.au3"
#include "..\lib\Log.au3"

; =========================================================================
; --- AYARLAR PENCERESİ ---
; config.ini'deki otomatik onarım, servis yeniden başlatma ve güncelleme
; seçeneklerini arayüzden değiştirir; servis kuruluysa görevi ve kurtarma
; ayarını hemen uygular. "Şimdi kontrol et" sağlık kontrolünü elle çalıştırır.
; =========================================================================

Func __SettingsUI_Check($id, $bOn)
    GUICtrlSetState($id, $bOn ? $GUI_CHECKED : $GUI_UNCHECKED)
EndFunc

Func __SettingsUI_IsChecked($id)
    Return BitAND(GUICtrlRead($id), $GUI_CHECKED) = $GUI_CHECKED
EndFunc

Func __SettingsUI_StatusText($sIni, $bService, $bTask)
    Local $sLast = IniRead($sIni, "Health", "LastCheck", "")
    Local $sRes = IniRead($sIni, "Health", "LastResult", "")
    Return "Servis: " & ($bService ? "kurulu" : "kurulu değil") & "   |   Onarım görevi: " & ($bTask ? "kurulu" : "yok") & @CRLF & _
            "Son kontrol: " & ($sLast = "" ? "henüz yok" : $sLast & ($sRes = "" ? "" : " — " & $sRes))
EndFunc

; Ayarlar penceresini gösterir. Kaydedildiyse True.
Func _SettingsUI_Show($sRoot, $sServiceName, $sAppName, $hParent)
    Local $sIni = $sRoot & "\config\config.ini"
    Local $bService = _ServiceIsInstalled($sServiceName)
    Local $bTask = _ScheduleExists($HEALTH_TASK_NAME)

    GUISetState(@SW_DISABLE, $hParent)
    Local $h = GUICreate("Ayarlar", 470, 400, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hParent)
    GUISetBkColor(0xFFFFFF, $h)

    GUICtrlCreateGroup("Otomatik onarım (servis modunda)", 15, 10, 440, 150)
    Local $chkHealth = GUICtrlCreateCheckbox("Discord bağlantısını arka planda kontrol et ve gerekirse onar", 30, 32, 410, 22)
    GUICtrlCreateLabel("Oturum açılışında, 30 dakikada bir ve ağ bağlantısı değişince.", 48, 54, 390, 18)
    GUICtrlSetColor(-1, 0x666666)
    Local $chkDns = GUICtrlCreateCheckbox("DNS zehirlenmesi varsa DNS'i Cloudflare'e al", 30, 78, 410, 22)
    Local $chkAnalyze = GUICtrlCreateCheckbox("Yedek stratejiler işe yaramazsa hızlı akıllı analiz yap (günde en fazla " & $HEALTH_MAX_ANALYZE_PER_DAY & ")", 30, 104, 410, 22)
    GUICtrlCreateLabel("İnternet tamamen kesikse hiçbir şey değiştirilmez.", 48, 128, 390, 18)
    GUICtrlSetColor(-1, 0x666666)
    GUICtrlCreateGroup("", -99, -99, 1, 1)

    GUICtrlCreateGroup("Servis", 15, 166, 440, 72)
    Local $chkRestart = GUICtrlCreateCheckbox("Servis kapanırsa yeniden başlat (en fazla 2 kez)", 30, 188, 410, 22)
    GUICtrlCreateLabel("Hile korumalı (anti-cheat) oyun oynuyorsanız kapalı tutmanız önerilir.", 48, 210, 390, 18)
    GUICtrlSetColor(-1, 0x8A4B08)
    GUICtrlCreateGroup("", -99, -99, 1, 1)

    Local $chkUpdate = GUICtrlCreateCheckbox("Açılışta yeni sürüm kontrolü yap", 30, 248, 410, 22)

    Local $lblStatus = GUICtrlCreateLabel(__SettingsUI_StatusText($sIni, $bService, $bTask), 15, 280, 440, 36)
    GUICtrlSetColor($lblStatus, 0x555555)

    Local $btnCheck = GUICtrlCreateButton("Şimdi kontrol et", 15, 340, 140, 34)
    Local $btnSave = GUICtrlCreateButton("Kaydet", 205, 340, 120, 34)
    GUICtrlSetFont($btnSave, 9, 700)
    Local $btnClose = GUICtrlCreateButton("Kapat", 335, 340, 120, 34)
    If Not $bService Then GUICtrlSetState($btnCheck, $GUI_DISABLE)

    __SettingsUI_Check($chkHealth, IniRead($sIni, "Health", "Enabled", "1") = "1" And ($bTask Or Not $bService))
    __SettingsUI_Check($chkDns, IniRead($sIni, "Health", "AutoFixDns", "1") = "1")
    __SettingsUI_Check($chkAnalyze, IniRead($sIni, "Health", "AutoAnalyze", "1") = "1")
    __SettingsUI_Check($chkRestart, IniRead($sIni, "Service", "AutoRestart", "0") = "1")
    __SettingsUI_Check($chkUpdate, IniRead($sIni, "Settings", "UpdateCheck", "1") <> "0")
    GUISetState(@SW_SHOW, $h)

    Local $bSaved = False
    While 1
        Switch GUIGetMsg()
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
                Local $bHealth = __SettingsUI_IsChecked($chkHealth)
                Local $bRestart = __SettingsUI_IsChecked($chkRestart)
                Local $bPrevRestart = (IniRead($sIni, "Service", "AutoRestart", "0") = "1")
                IniWrite($sIni, "Health", "Enabled", $bHealth ? "1" : "0")
                IniWrite($sIni, "Health", "AutoFixDns", __SettingsUI_IsChecked($chkDns) ? "1" : "0")
                IniWrite($sIni, "Health", "AutoAnalyze", __SettingsUI_IsChecked($chkAnalyze) ? "1" : "0")
                IniWrite($sIni, "Service", "AutoRestart", $bRestart ? "1" : "0")
                IniWrite($sIni, "Settings", "UpdateCheck", __SettingsUI_IsChecked($chkUpdate) ? "1" : "0")
                Local $sNote = ""
                If $bService Then
                    If $bHealth And Not _ScheduleExists($HEALTH_TASK_NAME) Then
                        If _HealthInstallTask() <> 0 Then $sNote &= @CRLF & "Uyarı: onarım görevi oluşturulamadı."
                    ElseIf Not $bHealth Then
                        _HealthRemoveTask()
                    EndIf
                    If $bRestart <> $bPrevRestart Then _ServiceSetRecovery($sServiceName, $bRestart)
                ElseIf $bHealth Then
                    $sNote &= @CRLF & "Otomatik onarım, servis kurulunca etkinleşir."
                EndIf
                _LogInfo("Ayarlar kaydedildi: onarım=" & $bHealth & " dns=" & __SettingsUI_IsChecked($chkDns) & " analiz=" & __SettingsUI_IsChecked($chkAnalyze) & _
                        " yenidenbaşlat=" & $bRestart & " güncelleme=" & __SettingsUI_IsChecked($chkUpdate))
                MsgBox(64 + 8192, "Ayarlar", "Ayarlar kaydedildi." & $sNote, 0, $h)
                $bSaved = True
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($h)
    GUISetState(@SW_ENABLE, $hParent)
    Return $bSaved
EndFunc
