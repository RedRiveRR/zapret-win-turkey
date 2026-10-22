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

; WMI erişim hatalarında betiğin çökmesini engeller.
Func __ProcessComError($oError)
    #forceref $oError
EndFunc
