#include-once
#include "Process.au3"
#include "Log.au3"

; =========================================================================
; --- ÇAKIŞMA TESPİTİ ---
; Zapret ile aynı anda çalışamayan DPI atlatma araçlarını bulur.
; =========================================================================

Global Const $CONFLICT_NONE = 0
Global Const $CONFLICT_BLOCKING = 1 ; kapatılmadan Zapret çalışmaz
Global Const $CONFLICT_INFO = 2     ; yalnızca loglanır

; Süreci sınıflandırır. $sDesc'e açıklama yazılır. Dönüş: $CONFLICT_* sabiti.
;   $sOurDir: bu programın kök klasörü; buradan çalışan winws çakışma sayılmaz.
Func _ConflictClassify($sName, $sExePath, $sOurDir, ByRef $sDesc)
    $sDesc = ""
    Switch StringLower($sName)
        Case "goodbyedpi.exe"
            $sDesc = "GoodbyeDPI"
            Return $CONFLICT_BLOCKING
        Case "ciadpi.exe"
            $sDesc = "ByeDPI"
            Return $CONFLICT_BLOCKING
        Case "winws.exe", "winws2.exe"
            ; Yolu okunamayan winws (erişim yok) için temkinli davran: çakışma sayma.
            If Not IsString($sExePath) Or $sExePath = "" Then Return $CONFLICT_NONE
            If _PathIsUnderDir($sExePath, $sOurDir) Then Return $CONFLICT_NONE
            $sDesc = "Başka bir Zapret kurulumu (" & $sExePath & ")"
            Return $CONFLICT_BLOCKING
        Case "warp-svc.exe"
            $sDesc = "Cloudflare WARP"
            Return $CONFLICT_INFO
    EndSwitch
    Return $CONFLICT_NONE
EndFunc

; Çalışan süreçleri tarar. Engelleyici çakışmaları [n][3] (ad, PID, açıklama) dizisi olarak döndürür.
; Bilgi amaçlı çakışmalar yalnızca loglanır.
Func _ConflictScan($sOurDir)
    Local $aOut[0][3]
    Local $oComErr = ObjEvent("AutoIt.Error", "__ProcessComError")
    #forceref $oComErr
    Local $oWMI = ObjGet("winmgmts:\\.\root\cimv2")
    If Not IsObj($oWMI) Then Return $aOut
    Local $oProcs = $oWMI.ExecQuery("SELECT Name, ProcessId, ExecutablePath FROM Win32_Process " & _
            "WHERE Name='goodbyedpi.exe' OR Name='ciadpi.exe' OR Name='winws.exe' OR Name='winws2.exe' OR Name='warp-svc.exe'")
    If Not IsObj($oProcs) Then Return $aOut

    Local $sDesc
    For $oProc In $oProcs
        Local $iKind = _ConflictClassify($oProc.Name, $oProc.ExecutablePath, $sOurDir, $sDesc)
        If $iKind = $CONFLICT_INFO Then
            _LogInfo("Bilgi: " & $sDesc & " çalışıyor")
        ElseIf $iKind = $CONFLICT_BLOCKING Then
            Local $iRow = UBound($aOut)
            ReDim $aOut[$iRow + 1][3]
            $aOut[$iRow][0] = $oProc.Name
            $aOut[$iRow][1] = $oProc.ProcessId
            $aOut[$iRow][2] = $sDesc
        EndIf
    Next
    Return $aOut
EndFunc

; Açılışta çakışmaları kontrol eder; varsa kullanıcıya sorup kapatır.
; Kullanıcı reddederse False döner (program kapanmalı).
Func _HandleStartupConflicts($sOurDir)
    Local $aConflicts = _ConflictScan($sOurDir)
    If UBound($aConflicts) = 0 Then Return True

    Local $sList = "", $bGoodbye = False
    For $i = 0 To UBound($aConflicts) - 1
        $sList &= "• " & $aConflicts[$i][2] & @CRLF
        If StringLower($aConflicts[$i][0]) = "goodbyedpi.exe" Then $bGoodbye = True
        _LogWarn("Çakışma: " & $aConflicts[$i][2] & " (PID " & $aConflicts[$i][1] & ")")
    Next

    Local $iResponse = MsgBox(52, "Çakışma Saptandı", "Zapret ile aynı anda çalışamayan program(lar) bulundu:" & @CRLF & @CRLF & $sList & @CRLF & _
            "Bunları kapatmak" & ($bGoodbye ? " ve GoodbyeDPI servisini kaldırmak" : "") & " istiyor musunuz?" & @CRLF & _
            "Hayır derseniz program kapanır.")
    If $iResponse <> 6 Then
        _LogInfo("Kullanıcı çakışan programları kapatmayı reddetti, çıkılıyor")
        Return False
    EndIf

    ; Süreçler PID ile kapatılır; böylece bu programın kendi winws'ine dokunulmaz.
    Local $bClosed = True
    For $i = 0 To UBound($aConflicts) - 1
        If Not __ConflictClosePid($aConflicts[$i][1]) Then $bClosed = False
    Next

    If $bGoodbye Then
        RunWait(@ComSpec & ' /c sc stop "GoodbyeDPI" & sc delete "GoodbyeDPI" & sc stop "WinDivert" & sc delete "WinDivert" & sc stop "WinDivert14" & sc delete "WinDivert14"', "", @SW_HIDE)
    EndIf

    If $bClosed Then
        _LogInfo("Çakışan programlar kapatıldı")
        MsgBox(64, "Bilgi", "Çakışan programlar kapatıldı. Program başlatılıyor." & @CRLF & @CRLF & _
                "Not: Bu programlar servis olarak kuruluysa yeniden başlayabilir; kendi kaldırma araçlarıyla kaldırın.")
    Else
        _LogError("Çakışan programlar kapatılamadı")
        MsgBox(48, "Uyarı", "Çakışan programların bir kısmı kapatılamadı. Zapret düzgün çalışmayabilir." & @CRLF & @CRLF & _
                "Görev Yöneticisi'nden elle kapatmayı deneyin.")
    EndIf
    Return True
EndFunc

; PID'yi kapatır; 5 sn içinde kapanmazsa taskkill /F dener. Kapandıysa True.
Func __ConflictClosePid($iPid)
    ProcessClose($iPid)
    If ProcessWaitClose($iPid, 5) Then Return True
    RunWait(@ComSpec & " /c taskkill /F /T /PID " & $iPid, "", @SW_HIDE)
    Return ProcessWaitClose($iPid, 2) = 1
EndFunc
