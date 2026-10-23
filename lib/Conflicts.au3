#include-once
#include "Process.au3"
#include "Log.au3"
#include "Network.au3"
#include "Install.au3"

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

; Servis PathName değerinden çalıştırılabilir dosya yolunu çıkarır.
;   "C:\a b\winws2.exe" --x   ->  C:\a b\winws2.exe
;   C:\a b\dnscrypt-proxy.exe -config x.toml  ->  C:\a b\dnscrypt-proxy.exe
Func _ServiceExePath($sPathName)
    If Not IsString($sPathName) Then Return ""
    $sPathName = StringStripWS($sPathName, 3)
    If StringLeft($sPathName, 1) = '"' Then
        Local $iEnd = StringInStr($sPathName, '"', 0, 1, 2)
        If $iEnd = 0 Then Return StringTrimLeft($sPathName, 1)
        Return StringMid($sPathName, 2, $iEnd - 2)
    EndIf
    Local $aM = StringRegExp($sPathName, "(?i)^(.*?\.exe)(\s|$)", 1)
    If @error Then Return $sPathName
    Return $aM[0]
EndFunc

; Bu programın klasörü dışını gösteren ZapretService / dnscrypt-proxy servislerini bulur.
; [n][2] (servis adı, exe yolu) döndürür. Genelde eski bir sürümün başka klasöre
; çıkarılmasından sonra kalan servislerdir.
Func _ForeignServiceScan($sOurDir)
    Local $aOut[0][2]
    Local $oComErr = ObjEvent("AutoIt.Error", "__ProcessComError")
    #forceref $oComErr
    Local $oWMI = ObjGet("winmgmts:\\.\root\cimv2")
    If Not IsObj($oWMI) Then Return $aOut
    Local $oSvcs = $oWMI.ExecQuery("SELECT Name, PathName FROM Win32_Service WHERE Name='ZapretService' OR Name='dnscrypt-proxy'")
    If Not IsObj($oSvcs) Then Return $aOut
    For $oSvc In $oSvcs
        Local $sExe = _ServiceExePath($oSvc.PathName)
        If $sExe = "" Or _PathIsUnderDir($sExe, $sOurDir) Then ContinueLoop
        Local $iRow = UBound($aOut)
        ReDim $aOut[$iRow + 1][2]
        $aOut[$iRow][0] = $oSvc.Name
        $aOut[$iRow][1] = $sExe
    Next
    Return $aOut
EndFunc

; Servis korumalı bir kurulumdaysa (Program Files) ve bu kopya değilse, servis eski değil
; asıl kurulumdur; bu kopya (ör. eski yedek klasör) onu kaldırmamalıdır (H18).
Func _ForeignServiceIsMain($sOurDir, $sSvcExe)
    Return _InstallIsProtected($sSvcExe) And Not _InstallIsProtected($sOurDir)
EndFunc

; Servis exe yolundan kurulum kökünü çıkarır (...\bin\zapret\... öncesi). Bulunamazsa "".
Func _ForeignServiceRoot($sSvcExe)
    Local $iPos = StringInStr($sSvcExe, "\bin\zapret\")
    If $iPos = 0 Then Return ""
    Return StringLeft($sSvcExe, $iPos - 1)
EndFunc

; Açılışta başka klasöre ait servisleri kullanıcıya sorup kaldırır.
; dnscrypt-proxy kaldırılırsa DNS 127.0.0.1'de kalıp internet kesilmesin diye DNS otomatiğe alınır.
; Kullanıcı reddederse program çalışmaya devam eder.
; Servis Program Files'taki asıl kuruluma aitse hiçbir şey kaldırılmaz; kullanıcıya asıl kurulumu
; açması önerilir. False dönerse çağıran program kapanmalıdır (asıl kurulum açıldı).
Func _HandleForeignServices($sOurDir)
    Local $aSvcs = _ForeignServiceScan($sOurDir)
    If UBound($aSvcs) = 0 Then Return True

    For $i = 0 To UBound($aSvcs) - 1
        If $aSvcs[$i][0] = "ZapretService" And _ForeignServiceIsMain($sOurDir, $aSvcs[$i][1]) Then
            Local $sMain = _ForeignServiceRoot($aSvcs[$i][1])
            _LogWarn("Asıl kurulumun servisi bulundu (" & $aSvcs[$i][1] & "); bu kopya (" & $sOurDir & ") servisi kaldırmayacak")
            Local $sMainExe = $sMain & "\" & @ScriptName
            Local $bCanOpen = $sMain <> "" And FileExists($sMainExe)
            Local $iAns = MsgBox(($bCanOpen ? 36 : 48) + 8192, "Asıl Kurulum Başka Klasörde", _
                    "Zapret servisi asıl kurulumunuzda çalışıyor:" & @CRLF & ($sMain = "" ? $aSvcs[$i][1] : $sMain) & @CRLF & @CRLF & _
                    "Şu an açtığınız kopya ise başka bir klasörde (muhtemelen eski bir yedek):" & @CRLF & $sOurDir & @CRLF & @CRLF & _
                    "Servise dokunulmayacak." & ($bCanOpen ? @CRLF & @CRLF & "Bu kopya kapatılıp asıl kurulum açılsın mı? (önerilir)" : ""))
            If $bCanOpen And $iAns = 6 Then
                _LogInfo("Kullanıcı asıl kurulumu açtı: " & $sMainExe)
                ShellExecute($sMainExe, "", $sMain)
                Return False
            EndIf
            Return True
        EndIf
    Next

    Local $sList = "", $bDnscrypt = False
    For $i = 0 To UBound($aSvcs) - 1
        $sList &= "• " & $aSvcs[$i][0] & "  →  " & $aSvcs[$i][1] & @CRLF
        If $aSvcs[$i][0] = "dnscrypt-proxy" Then $bDnscrypt = True
        _LogWarn("Başka klasöre ait servis: " & $aSvcs[$i][0] & " -> " & $aSvcs[$i][1])
    Next

    Local $iResponse = MsgBox(36 + 8192, "Eski Kurulum Servisleri", "Başka bir klasördeki (muhtemelen eski) kurulumun servisleri bulundu:" & @CRLF & @CRLF & $sList & @CRLF & _
            "Bu servisler bu klasördeki programla birlikte çalışmaz. Kaldırılsın mı?" & @CRLF & _
            ($bDnscrypt ? @CRLF & "DNSCrypt kaldırılınca DNS ayarınız otomatiğe (DHCP) alınır; isterseniz bu programdan tekrar kurabilirsiniz." & @CRLF : "") & @CRLF & _
            "Hayır derseniz program yine açılır, ancak Zapret düzgün çalışmayabilir.")
    If $iResponse <> 6 Then
        _LogInfo("Kullanıcı eski kurulum servislerini kaldırmayı reddetti")
        Return True
    EndIf

    For $i = 0 To UBound($aSvcs) - 1
        RunWait(@ComSpec & " /c sc stop " & $aSvcs[$i][0] & " & sc delete " & $aSvcs[$i][0], "", @SW_HIDE)
    Next
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14 & sc stop monkey & sc delete monkey", "", @SW_HIDE)
    If $bDnscrypt Then _ResetSystemDNS()
    _LogInfo("Eski kurulum servisleri kaldırıldı")
    Return True
EndFunc

; PID'yi kapatır; 5 sn içinde kapanmazsa taskkill /F dener. Kapandıysa True.
Func __ConflictClosePid($iPid)
    ProcessClose($iPid)
    If ProcessWaitClose($iPid, 5) Then Return True
    RunWait(@ComSpec & " /c taskkill /F /T /PID " & $iPid, "", @SW_HIDE)
    Return ProcessWaitClose($iPid, 2) = 1
EndFunc
