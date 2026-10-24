#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>

; =========================================================================
; --- GÖREV ZAMANLAYICI ---
; Sağlık kontrolü görevini kurar/kaldırır. Tetikleyiciler:
;   - oturum açılışında (1 dk gecikmeyle),
;   - her $iIntervalMin dakikada bir,
;   - ağ bağlantısı kurulduğunda (NetworkProfile olay 10000, 30 sn gecikmeyle).
; Görev kullanıcının hesabıyla, "en yüksek ayrıcalıklarla" (UAC sormadan) çalışır;
; aynı anda birden fazla örnek çalışmaz, 20 dk'da zorla durdurulur.
; =========================================================================

Func _ScheduleXmlEscape($s)
    $s = StringReplace($s, "&", "&amp;")
    $s = StringReplace($s, "<", "&lt;")
    $s = StringReplace($s, ">", "&gt;")
    Return StringReplace($s, '"', "&quot;")
EndFunc

; Görev tanımı XML'i (saf fonksiyon).
Func _ScheduleBuildXml($sCommand, $sArguments, $sWorkDir, $sUser, $iIntervalMin, $sDescription)
    Local $sU = _ScheduleXmlEscape($sUser)
    Local $sSub = "&lt;QueryList&gt;&lt;Query Id=&quot;0&quot; Path=&quot;Microsoft-Windows-NetworkProfile/Operational&quot;&gt;" & _
            "&lt;Select Path=&quot;Microsoft-Windows-NetworkProfile/Operational&quot;&gt;*[System[(EventID=10000)]]&lt;/Select&gt;" & _
            "&lt;/Query&gt;&lt;/QueryList&gt;"
    Return '<?xml version="1.0" encoding="UTF-16"?>' & @CRLF & _
            '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' & @CRLF & _
            '  <RegistrationInfo><Description>' & _ScheduleXmlEscape($sDescription) & '</Description></RegistrationInfo>' & @CRLF & _
            '  <Triggers>' & @CRLF & _
            '    <LogonTrigger><Enabled>true</Enabled><UserId>' & $sU & '</UserId><Delay>PT1M</Delay></LogonTrigger>' & @CRLF & _
            '    <TimeTrigger><Repetition><Interval>PT' & $iIntervalMin & 'M</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>' & _
            '<StartBoundary>2026-01-01T00:00:00</StartBoundary><Enabled>true</Enabled></TimeTrigger>' & @CRLF & _
            '    <EventTrigger><Enabled>true</Enabled><Delay>PT30S</Delay><Subscription>' & $sSub & '</Subscription></EventTrigger>' & @CRLF & _
            '  </Triggers>' & @CRLF & _
            '  <Principals><Principal id="Author"><UserId>' & $sU & '</UserId><LogonType>InteractiveToken</LogonType>' & _
            '<RunLevel>HighestAvailable</RunLevel></Principal></Principals>' & @CRLF & _
            '  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' & _
            '<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT20M</ExecutionTimeLimit>' & _
            '<StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled></Settings>' & @CRLF & _
            '  <Actions Context="Author"><Exec><Command>' & _ScheduleXmlEscape($sCommand) & '</Command><Arguments>' & _
            _ScheduleXmlEscape($sArguments) & '</Arguments><WorkingDirectory>' & _ScheduleXmlEscape($sWorkDir) & _
            '</WorkingDirectory></Exec></Actions>' & @CRLF & _
            '</Task>'
EndFunc

; Bu programı çalıştıracak komut ve argümanlar (derlenmemişse AutoIt3.exe + betik).
Func _ScheduleSelfCommand(ByRef $sCommand, ByRef $sArguments, $sExtraArg)
    If @Compiled Then
        $sCommand = @ScriptFullPath
        $sArguments = $sExtraArg
    Else
        $sCommand = @AutoItExe
        $sArguments = '"' & @ScriptFullPath & '" ' & $sExtraArg
    EndIf
EndFunc

; Görevi kurar (varsa üzerine yazar). Dönüş: schtasks çıkış kodu (0 = başarılı).
Func _ScheduleInstall($sTaskName, $sCommand, $sArguments, $sWorkDir, $iIntervalMin, $sDescription)
    Local $sXmlPath = @TempDir & "\zwt-task-" & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & ".xml"
    Local $h = FileOpen($sXmlPath, $FO_OVERWRITE + $FO_UNICODE)
    If $h = -1 Then Return -1
    FileWrite($h, _ScheduleBuildXml($sCommand, $sArguments, $sWorkDir, @LogonDomain & "\" & @UserName, $iIntervalMin, $sDescription))
    FileClose($h)
    Local $iRc = RunWait(@ComSpec & ' /c schtasks /Create /TN "' & $sTaskName & '" /XML "' & $sXmlPath & '" /F', "", @SW_HIDE)
    FileDelete($sXmlPath)
    Return $iRc
EndFunc

Func _ScheduleRemove($sTaskName)
    Return RunWait(@ComSpec & ' /c schtasks /Delete /TN "' & $sTaskName & '" /F', "", @SW_HIDE)
EndFunc

Func _ScheduleExists($sTaskName)
    Return RunWait(@ComSpec & ' /c schtasks /Query /TN "' & $sTaskName & '"', "", @SW_HIDE) = 0
EndFunc

; Görevin tanımı (XML). Görev yoksa "".
Func _ScheduleQueryXml($sTaskName)
    Local $iPid = Run(@ComSpec & ' /c schtasks /Query /TN "' & $sTaskName & '" /XML', "", @SW_HIDE, $STDOUT_CHILD)
    If $iPid = 0 Then Return ""
    ProcessWaitClose($iPid, 10)
    Local $s = StdoutRead($iPid)
    Return StringInStr($s, "<Task") ? $s : ""
EndFunc

; Görev bu komutu mu çalıştırıyor? (ör. exe yeniden adlandırıldıysa görev eski yolu gösterir)
Func _ScheduleXmlHasCommand($sXml, $sCommand)
    Return StringInStr($sXml, "<Command>" & _ScheduleXmlEscape($sCommand) & "</Command>") > 0
EndFunc

; Görevin çalıştırdığı komut (XML kaçışları çözülmüş). Yoksa "".
Func _ScheduleXmlCommand($sXml)
    Local $a = StringRegExp($sXml, "<Command>(.*?)</Command>", 1)
    If @error Then Return ""
    Local $s = StringReplace($a[0], "&quot;", '"')
    $s = StringReplace($s, "&lt;", "<")
    $s = StringReplace($s, "&gt;", ">")
    Return StringReplace($s, "&amp;", "&")
EndFunc
