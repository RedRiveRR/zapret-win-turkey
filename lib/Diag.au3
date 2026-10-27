#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include "Network.au3"
#include "Version.au3"
#include "Log.au3"

; =========================================================================
; --- TANILAMA PAKETİ ---
; Destek için log, ayar ve servis durumunu tek ZIP dosyasında toplar.
; Gizlilik: autohostlist.txt (ziyaret edilen siteler) ve paylaşım kaydı pakete EKLENMEZ; eklenen
; metinlerde ev ağı IP'leri, IPv6 ve MAC adresleri ile Windows kullanıcı adı maskelenir (_DiagRedact).
; =========================================================================

; Pakete eklenmeye aday dosyalar (programın köküne göre).
Global Const $DIAG_FILES = "logs\app.log|logs\app.log.1|config\config.ini|config\strategy.txt|config\strategy2.txt|" & _
        "config\blockcheck2_strategies.txt|config\hostlist.txt|config\excludelist.txt|config\strategies.ini|" & _
        "bin\zapret\blockcheck\blockcheck.log|bin\zapret\blockcheck\blockcheck2.log"

; Kökte mevcut olan aday dosyaların göreli yollarını döndürür.
Func _DiagCandidateFiles($sRoot)
    Local $aAll = StringSplit($DIAG_FILES, "|", 2)
    Local $aOut[0]
    For $sRel In $aAll
        If FileExists($sRoot & "\" & $sRel) Then
            ReDim $aOut[UBound($aOut) + 1]
            $aOut[UBound($aOut) - 1] = $sRel
        EndIf
    Next
    Return $aOut
EndFunc

; Pakete giren metindeki kişisel bilgileri maskeler (saf):
;   ev ağı IPv4 (10/8, 172.16/12, 192.168/16) -> ilk iki bölüm kalır: 192.168.x.x
;   IPv6 -> <ipv6>, MAC -> xx:xx:xx:xx:xx:xx, "\Users\<ad>\" -> "\Users\<kullanıcı>\"
; Genel adresler (1.1.1.1, Discord'un adresleri) hata ayıklamaya yaradığı için kalır.
Func _DiagRedact($sText, $sUserName = @UserName)
    Local $s = StringRegExpReplace($sText, "(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b", "xx:xx:xx:xx:xx:xx")
    ; IPv6: "::" ile kısaltılmış (fe80::1) ya da en az üç ':' içeren (saat "14:58:54" iki ':' içerir, korunur)
    $s = StringRegExpReplace($s, "(?i)(?<![0-9a-z:.])[0-9a-f]{0,4}(?::[0-9a-f]{1,4})*::[0-9a-f:]*(?:%\w+)?(?![0-9a-z:.])", "<ipv6>")
    $s = StringRegExpReplace($s, "(?i)(?<![0-9a-z:.])(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}(?:%\w+)?(?![0-9a-z:.])", "<ipv6>")
    $s = StringRegExpReplace($s, "\b(10)\.\d{1,3}\.\d{1,3}\.\d{1,3}\b", "$1.x.x.x")
    $s = StringRegExpReplace($s, "\b(192\.168)\.\d{1,3}\.\d{1,3}\b", "$1.x.x")
    $s = StringRegExpReplace($s, "\b(172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b", "$1.x.x")
    If $sUserName <> "" Then
        $s = StringRegExpReplace($s, "(?i)(\\Users\\)\Q" & $sUserName & "\E(?=\\|$|[\s""'])", "$1<kullanıcı>")
    EndIf
    Return $s
EndFunc

; PowerShell için tek tırnaklı, kaçışlı dizgi üretir.
Func _PsQuote($s)
    Return "'" & StringReplace($s, "'", "''") & "'"
EndFunc

; PowerShell betiğini çalıştırıp çıktısını UTF-8 olarak döndürür.
; (sc.exe / tasklist OEM kod sayfasıyla yazdığı için Türkçe karakterler bozuluyordu.)
Func __DiagReadPs($sScript)
    Local $sPs = "[Console]::OutputEncoding = [Text.Encoding]::UTF8; " & $sScript
    Local $iPid = Run('powershell.exe -NoProfile -NonInteractive -Command "' & $sPs & '"', "", @SW_HIDE, $STDOUT_CHILD + $STDERR_MERGED)
    If $iPid = 0 Then Return "(çalıştırılamadı)"
    ProcessWaitClose($iPid, 15)
    Return StringStripWS(BinaryToString(StdoutRead($iPid, False, True), 4), 3)
EndFunc

; Sistem ve servis durumunu metin olarak toplar (IP/MAC içermez).
Func _DiagSystemInfo()
    Local $s = $APP_NAME & " v" & $APP_VERSION & @CRLF
    $s &= "Oluşturma: " & _LogTimestamp() & @CRLF
    $s &= "Windows: " & @OSVersion & " " & @OSBuild & " " & @OSArch & " | Dil: " & @OSLang & @CRLF
    $s &= "Program klasörü ASCII mi: " & (StringRegExp(@ScriptDir, "[^\x00-\x7F]") ? "hayır" : "evet") & @CRLF
    $s &= "Npcap (Packet.dll): " & (FileExists(@SystemDir & "\Packet.dll") ? "var" : "yok") & @CRLF
    $s &= "Etkin bağdaştırıcı DNS: " & StringStripWS(_GetActiveAdapterDnsServers(), 3) & @CRLF
    $s &= @CRLF & "=== İlgili servisler (listede olmayan kurulu değildir) ===" & @CRLF
    $s &= __DiagReadPs("Get-CimInstance Win32_Service | Where-Object { @('ZapretService','WinDivert','WinDivert14','monkey','dnscrypt-proxy','GoodbyeDPI') -contains $_.Name } | " & _
            "Format-List Name, State, StartMode, PathName | Out-String -Width 4096") & @CRLF
    $s &= @CRLF & "=== Çalışan ilgili süreçler ===" & @CRLF
    $s &= __DiagReadPs("Get-Process -Name winws, winws2, go-pcap2socks, dnscrypt-proxy, goodbyedpi, ciadpi -ErrorAction SilentlyContinue | " & _
            "Format-Table Id, Name, Path -AutoSize | Out-String -Width 4096") & @CRLF
    Return $s
EndFunc

; Tanılama paketini $sOutZip olarak oluşturur. Başarılıysa True.
Func _DiagCreateBundle($sRoot, $sOutZip)
    Local $sWork = @TempDir & "\zwt-diag-" & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC
    DirRemove($sWork, 1)
    DirCreate($sWork)

    Local $aFiles = _DiagCandidateFiles($sRoot)
    For $sRel In $aFiles
        ; Hepsi metin dosyası: maskelenmiş kopya yazılır.
        Local $h = FileOpen($sWork & "\" & $sRel, $FO_OVERWRITE + $FO_CREATEPATH + $FO_UTF8)
        If $h = -1 Then ContinueLoop
        FileWrite($h, _DiagRedact(FileRead($sRoot & "\" & $sRel)))
        FileClose($h)
    Next

    Local $hInfo = FileOpen($sWork & "\sistem-bilgisi.txt", $FO_OVERWRITE + $FO_UTF8)
    If $hInfo <> -1 Then
        FileWrite($hInfo, _DiagRedact(_DiagSystemInfo()))
        FileClose($hInfo)
    EndIf

    FileDelete($sOutZip)
    Local $sPs = "Compress-Archive -Path " & _PsQuote($sWork & "\*") & " -DestinationPath " & _PsQuote($sOutZip) & " -Force"
    RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' & $sPs & '"', "", @SW_HIDE)
    DirRemove($sWork, 1)

    Local $bOk = FileExists($sOutZip)
    If $bOk Then
        _LogInfo("Tanılama paketi oluşturuldu: " & $sOutZip & " (" & UBound($aFiles) & " dosya)")
    Else
        _LogError("Tanılama paketi oluşturulamadı: " & $sOutZip)
    EndIf
    Return $bOk
EndFunc

; Tepsi menüsünden çağrılır: paketi masaüstüne oluşturur ve kullanıcıyı bilgilendirir.
Func _DiagCreateFromTray()
    Local $sZip = @DesktopDir & "\zapret-tanilama-" & @YEAR & @MON & @MDAY & "-" & @HOUR & @MIN & @SEC & ".zip"
    If _DiagCreateBundle(@ScriptDir, $sZip) Then
        MsgBox(64 + 8192, "Tanılama Paketi", "Tanılama paketi masaüstüne kaydedildi:" & @CRLF & $sZip & @CRLF & @CRLF & _
                "Paylaşmadan önce içeriğini kontrol edebilirsiniz. Ziyaret ettiğiniz siteler (autohostlist) pakete eklenmez; " & _
                "ev ağı IP'leri, MAC adresleri ve Windows kullanıcı adınız maskelenir.")
        ShellExecute(@DesktopDir)
    Else
        MsgBox(16 + 8192, "Tanılama Paketi", "Tanılama paketi oluşturulamadı.")
    EndIf
EndFunc
