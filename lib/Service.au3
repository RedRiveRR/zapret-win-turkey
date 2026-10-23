#include-once
#include <AutoItConstants.au3>
#include "Log.au3"
#include "Process.au3"

; =========================================================================
; --- WINDOWS SERVİSİ ---
; Kurma, strateji güncelleme, kaldırma ve durum sorgulama. GUI'ye bağımlı değildir.
; _Service*Parse* ve _ServiceBuildBinPath saf fonksiyonlardır (birim testli).
;
; Kurulumda servis otomatik başlar (gecikmesiz: Discord zapret'ten önce açılıp takılmasın).
; Çökme/kapatılma sonrası otomatik yeniden başlatma İSTEĞE BAĞLIDIR ve varsayılan kapalıdır:
; hile koruma (anti-cheat) yazılımları winws'i kapattığında onu inatla geri açmak oyun
; hesabına risk oluşturabilir (ADR-007). Kullanıcı açarsa yeniden başlatma sınırlıdır.
; =========================================================================

Global Const $SERVICE_DESCRIPTION = "Zapret Windows Türkiye - DPI atlatma motoru (winws). Bu programın Servis düğmeleriyle yönetilir."

; winws yolu ve argümanlardan sc.exe binPath değerini üretir (iç tırnaklar \" ile kaçışlanır).
Func _ServiceBuildBinPath($sExePath, $sArgs)
    Return StringReplace('"' & $sExePath & '" ' & $sArgs, '"', '\"')
EndFunc

; "sc query" çıktısından durum: RUNNING, STOPPED, START_PENDING, STOP_PENDING...
; Servis yoksa "", servis var ama STATE satırı okunamıyorsa "UNKNOWN".
Func _ServiceParseState($sQueryOut)
    If Not StringInStr($sQueryOut, "SERVICE_NAME") Then Return ""
    Local $a = StringRegExp($sQueryOut, "(?m)^\s*STATE\s*:\s*\d+\s+(\w+)", 1)
    If @error Then Return "UNKNOWN"
    Return $a[0]
EndFunc

; "sc qc" çıktısından binPath.
Func _ServiceParseBinPath($sQcOut)
    Local $a = StringRegExp($sQcOut, "(?m)^\s*BINARY_PATH_NAME\s*:\s*(.+?)\s*$", 1)
    If @error Then Return ""
    Return $a[0]
EndFunc

; "sc qc" çıktısından başlangıç türü: "AUTO_START", "AUTO_START (DELAYED)", "DEMAND_START", "DISABLED".
Func _ServiceParseStartType($sQcOut)
    Local $a = StringRegExp($sQcOut, "(?m)^\s*START_TYPE\s*:\s*\d+\s+(\w+)(\s+\(DELAYED\))?", 1)
    If @error Then Return ""
    If UBound($a) > 1 And StringStripWS($a[1], 3) <> "" Then Return $a[0] & " (DELAYED)"
    Return $a[0]
EndFunc

Func __ServiceSc($sArgs)
    Local $iPid = Run(@ComSpec & " /c sc " & $sArgs, "", @SW_HIDE, $STDOUT_CHILD + $STDERR_MERGED)
    If $iPid = 0 Then Return ""
    ProcessWaitClose($iPid, 30)
    Return StdoutRead($iPid)
EndFunc

Func _ServiceGetState($sName)
    Return _ServiceParseState(__ServiceSc("query " & $sName))
EndFunc

Func _ServiceGetConfig($sName)
    Return __ServiceSc("qc " & $sName)
EndFunc

Func _ServiceIsInstalled($sName)
    Return _ServiceGetState($sName) <> ""
EndFunc

; Servis durumunun $sState olmasını bekler (ms). Olduysa True.
Func _ServiceWaitState($sName, $sState, $iTimeoutMs)
    Local $hT = TimerInit()
    While TimerDiff($hT) < $iTimeoutMs
        If _ServiceGetState($sName) = $sState Then Return True
        Sleep(200)
    WEnd
    Return _ServiceGetState($sName) = $sState
EndFunc

; Kurtarma ayarı. Açıkken: çökme/dışarıdan kapatılma sonrası 10 sn ve 60 sn sonra en fazla
; 2 kez yeniden başlatılır, sonra durur (sayaç 24 saatte sıfırlanır) — anti-cheat ile sonsuz
; döngüye girmesin. Kapalıyken kurtarma eylemleri temizlenir. Tekrar çağrılabilir.
Func _ServiceSetRecovery($sName, $bEnable)
    If $bEnable Then
        ; Üçüncü eylem açıkça "none": aksi halde Windows son eylemi (restart) sonsuza dek tekrarlar.
        RunWait(@ComSpec & " /c sc failure " & $sName & " reset= 86400 actions= restart/10000/restart/60000/none/0", "", @SW_HIDE)
        RunWait(@ComSpec & " /c sc failureflag " & $sName & " 1", "", @SW_HIDE)
    Else
        RunWait(@ComSpec & " /c sc failure " & $sName & " reset= 0 actions= none/0", "", @SW_HIDE)
        RunWait(@ComSpec & " /c sc failureflag " & $sName & " 0", "", @SW_HIDE)
    EndIf
EndFunc

; Kullanıcıya otomatik yeniden başlatmayı sorar. Cevap $sIniPath [Service] AutoRestart'ta saklanır
; ve sonraki kurulumda varsayılan düğme olur. İlk kez: varsayılan Hayır (ADR-007).
Func _ServiceAskRecovery($sIniPath)
    Local $bPrev = (IniRead($sIniPath, "Service", "AutoRestart", "0") = "1")
    Local $iAns = MsgBox(($bPrev ? 4 : 4 + 256) + 32 + 8192, "Otomatik Yeniden Başlatma", _
            "Zapret servisi kapanırsa (çökme veya başka bir program tarafından kapatılma) Windows onu otomatik yeniden başlatsın mı?" & @CRLF & @CRLF & _
            "Hile korumalı (anti-cheat) oyun oynuyorsanız HAYIR önerilir: bazı hile korumaları Zapret'i kapatır ve tekrar tekrar açılması hesabınız için risk oluşturabilir." & @CRLF & @CRLF & _
            "Evet derseniz en fazla 2 kez (10 sn ve 60 sn sonra) yeniden başlatılır, sonra durur.")
    Local $bYes = ($iAns = 6)
    IniWrite($sIniPath, "Service", "AutoRestart", $bYes ? "1" : "0")
    Return $bYes
EndFunc

; Servisi kurar ve başlatır. Dönüş: sc create çıkış kodu (0 = başarılı).
Func _ServiceInstall($sName, $sExePath, $sArgs, $bRecovery = False)
    Local $iCreate = RunWait(@ComSpec & " /c sc create " & $sName & ' binPath= "' & _ServiceBuildBinPath($sExePath, $sArgs) & '" start= auto', "", @SW_HIDE)
    If $iCreate <> 0 Then Return $iCreate
    RunWait(@ComSpec & ' /c sc description ' & $sName & ' "' & $SERVICE_DESCRIPTION & '"', "", @SW_HIDE)
    _ServiceSetRecovery($sName, $bRecovery)
    RunWait(@ComSpec & " /c sc start " & $sName, "", @SW_HIDE)
    Return 0
EndFunc

; Kurulu servisin stratejisini (binPath) değiştirip yeniden başlatır; DNS'e dokunmaz.
; Dönüş: True = yeni ayarla çalışıyor.
Func _ServiceUpdateArgs($sName, $sExePath, $sArgs)
    RunWait(@ComSpec & " /c sc stop " & $sName, "", @SW_HIDE)
    _ServiceWaitState($sName, "STOPPED", 10000)
    Local $iCfg = RunWait(@ComSpec & " /c sc config " & $sName & ' binPath= "' & _ServiceBuildBinPath($sExePath, $sArgs) & '"', "", @SW_HIDE)
    If $iCfg <> 0 Then
        RunWait(@ComSpec & " /c sc start " & $sName, "", @SW_HIDE)
        Return SetError(1, $iCfg, False)
    EndIf
    RunWait(@ComSpec & " /c sc start " & $sName, "", @SW_HIDE)
    Return _ServiceWaitState($sName, "RUNNING", 10000)
EndFunc

; Servisin binPath'ini "sc qc"den okunan ham değere geri yükler (ör. başarısız onarım sonrası).
Func _ServiceRestoreBinPath($sName, $sRawBinPath)
    If $sRawBinPath = "" Then Return False
    RunWait(@ComSpec & " /c sc stop " & $sName, "", @SW_HIDE)
    _ServiceWaitState($sName, "STOPPED", 10000)
    Local $iCfg = RunWait(@ComSpec & " /c sc config " & $sName & ' binPath= "' & StringReplace($sRawBinPath, '"', '\"') & '"', "", @SW_HIDE)
    RunWait(@ComSpec & " /c sc start " & $sName, "", @SW_HIDE)
    Return $iCfg = 0 And _ServiceWaitState($sName, "RUNNING", 10000)
EndFunc

; Servisi durdurup siler (WinDivert sürücü kalıntılarına dokunmaz).
Func _ServiceRemove($sName)
    RunWait(@ComSpec & " /c sc stop " & $sName & " & sc delete " & $sName, "", @SW_HIDE)
EndFunc

; Servisi durdurur (strateji testleri için). Durduysa True.
Func _ServiceStop($sName, $iTimeoutMs = 10000)
    RunWait(@ComSpec & " /c sc stop " & $sName, "", @SW_HIDE)
    Return _ServiceWaitState($sName, "STOPPED", $iTimeoutMs)
EndFunc

Func _ServiceStart($sName, $iTimeoutMs = 10000)
    RunWait(@ComSpec & " /c sc start " & $sName, "", @SW_HIDE)
    Return _ServiceWaitState($sName, "RUNNING", $iTimeoutMs)
EndFunc
