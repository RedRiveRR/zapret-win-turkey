#include-once

; =========================================================================
; --- SÜREÇ YARDIMCILARI ---
; GUI'ye bağımlı değildir; ana ve lite sürüm tarafından ortak kullanılır.
; =========================================================================

; $sPath, $sDir klasörünün (veya alt klasörlerinin) içinde mi? Büyük/küçük harf duyarsız.
Func _PathIsUnderDir($sPath, $sDir)
    If Not IsString($sPath) Or $sPath = "" Or $sDir = "" Then Return False
    Local $sPrefix = StringLower(StringRegExpReplace($sDir, "[\\/]+$", "")) & "\"
    Local $sNorm = StringLower(StringReplace($sPath, "/", "\"))
    Return StringLeft($sNorm, StringLen($sPrefix)) = $sPrefix
EndFunc

; Çalıştırılabilir dosyası $sDir altında olan tüm süreçleri kapatır.
; Sistemdeki diğer bash.exe / sh.exe gibi süreçlere (Git Bash, WSL vb.) dokunmaz.
; Kapatılan süreç sayısını döndürür.
Func _KillProcessesUnderDir($sDir)
    Local $oComErr = ObjEvent("AutoIt.Error", "__ProcessComError")
    #forceref $oComErr
    Local $oWMI = ObjGet("winmgmts:\\.\root\cimv2")
    If Not IsObj($oWMI) Then Return 0

    Local $oProcs = $oWMI.ExecQuery("SELECT ProcessId, ExecutablePath FROM Win32_Process")
    If Not IsObj($oProcs) Then Return 0

    Local $iKilled = 0
    For $oProc In $oProcs
        If _PathIsUnderDir($oProc.ExecutablePath, $sDir) Then
            If ProcessClose($oProc.ProcessId) Then $iKilled += 1
        EndIf
    Next
    Return $iKilled
EndFunc

; Bir süreci alt süreçleriyle birlikte kapatır.
Func _KillProcessTree($iPid)
    If $iPid <= 0 Or Not ProcessExists($iPid) Then Return
    RunWait(@ComSpec & " /c taskkill /F /T /PID " & $iPid, "", @SW_HIDE)
EndFunc

; Verilen adlardaki tüm süreçleri kapatır. $iTimeoutMs içinde kapanmayanlar için
; taskkill /F denenir. Hepsi kapandıysa True, hâlâ çalışan varsa False döner.
Func _CloseProcessesByName($aNames, $iTimeoutMs = 5000)
    Local $hTimer = TimerInit()
    While __AnyProcessExists($aNames)
        For $sName In $aNames
            ProcessClose($sName)
        Next
        If TimerDiff($hTimer) > $iTimeoutMs Then ExitLoop
        Sleep(100)
    WEnd

    If __AnyProcessExists($aNames) Then
        For $sName In $aNames
            RunWait(@ComSpec & " /c taskkill /F /T /IM " & $sName, "", @SW_HIDE)
        Next
    EndIf
    Return Not __AnyProcessExists($aNames)
EndFunc

Func __AnyProcessExists($aNames)
    For $sName In $aNames
        If ProcessExists($sName) Then Return True
    Next
    Return False
EndFunc

; WMI erişim hatalarında betiğin çökmesini engeller.
Func __ProcessComError($oError)
    #forceref $oError
EndFunc
