#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include "Log.au3"
#include "Network.au3"
#include "Process.au3"

; =========================================================================
; --- AĞ PAYLAŞIMI (go-pcap2socks) ---
; Konsol / akıllı TV gibi cihazlar bilgisayardaki zapret üzerinden çıksın diye
; go-pcap2socks yerel ağda sahte bir ağ geçidi olur (Npcap ile). Trafik bilgisayarın
; kendi bağlantılarıyla çıktığı için winws'in --wf-tcp-out filtresine takılır.
; go-pcap2socks'ta DHCP sunucusu yok: cihaza IP elle girilir (bkz. _LanPlan).
; GUI'ye bağlı değildir; saf fonksiyonlar tests/test_lanshare.au3 ile sınanır.
; =========================================================================

Global Const $LAN_EXE_REL = "\bin\go-pcap2socks\go-pcap2socks.exe"
Global Const $LAN_LOG_REL = "\logs\paylasim.log"
; Paylaşım ağı için aday /16 önekleri (ev ağıyla çakışmayan ilki seçilir).
Global Const $LAN_PREFIXES = "172.24|10.77|172.29|10.123"

; Npcap durumu: "var" | "uyumsuz" (kurulu ama "WinPcap API-compatible Mode" kapalı; go-pcap2socks
; belgesi bu modu şart koşar) | "yok".
Func _LanNpcapState($bCompatDll, $bNpcapDirDll, $sDriverState)
    If $bCompatDll Then Return "var"
    If $bNpcapDirDll Or $sDriverState <> "" Then Return "uyumsuz"
    Return "yok"
EndFunc

Func _LanNpcapStatus()
    Local $iPid = Run(@ComSpec & " /c sc query npcap", "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPid, 5)
    Local $sOut = StdoutRead($iPid)
    Return _LanNpcapState(FileExists(@SystemDir & "\wpcap.dll") = 1, FileExists(@SystemDir & "\Npcap\wpcap.dll") = 1, _
            StringInStr($sOut, "SERVICE_NAME") ? "var" : "")
EndFunc

; Bilgisayarın IPv4 adreslerinden ("a,b,c") çakışmayan /16 önekini seçer: "172.24" gibi.
Func _LanPickPrefix($sLocalIPs)
    Local $aPref = StringSplit($LAN_PREFIXES, "|", 2)
    For $sPref In $aPref
        Local $bClash = False
        For $sIP In StringSplit($sLocalIPs, ",", 2)
            $sIP = StringStripWS($sIP, 3)
            If $sIP <> "" And StringLeft($sIP, StringLen($sPref) + 1) = $sPref & "." Then
                $bClash = True
                ExitLoop
            EndIf
        Next
        If Not $bClash Then Return $sPref
    Next
    Return $aPref[0]
EndFunc

; Önekten cihaz ayarları: [ağ (CIDR), ağ geçidi, maske, ilk önerilen cihaz IP'si, son kullanılabilir IP]
Func _LanPlan($sPrefix)
    Local $a[5] = [$sPrefix & ".0.0/16", $sPrefix & ".2.1", "255.255.0.0", $sPrefix & ".2.50", $sPrefix & ".2.254"]
    Return $a
EndFunc

; n'inci cihaz için önerilen IP (1 tabanlı): .2.50, .2.51 ...
Func _LanDeviceIP($sPrefix, $iN)
    If $iN < 1 Then $iN = 1
    If $iN > 200 Then $iN = 200
    Return $sPrefix & ".2." & (49 + $iN)
EndFunc

; go-pcap2socks yapılandırması (config.json, exe'nin yanında).
; $sIfaceIP: dinlenecek kartın BU BİLGİSAYARDAKİ IPv4 adresi (go-pcap2socks belgesi: "interfaceGateway =
; IPv4 address of the physical network interface to capture on"; modemin adresi değil). "" = varsayılan
; rota kartını kendisi seçer.
; Tüm DNS sorguları (53) bilgisayarın çözücüsüne gider: cihaz DNS olarak ağ geçidini kullanabilir.
Func _LanBuildConfig($sNetwork, $sLocalIP, $sIfaceIP)
    Local $sPcap = '"network": "' & $sNetwork & '", "localIP": "' & $sLocalIP & '"'
    If $sIfaceIP <> "" Then $sPcap &= ', "interfaceGateway": "' & $sIfaceIP & '"'
    Return '{' & @CRLF & _
            '  "pcap": { ' & $sPcap & ' },' & @CRLF & _
            '  "dns": { "servers": [ { "address": "local" } ] },' & @CRLF & _
            '  "routing": { "rules": [ { "dstPort": "53", "outboundTag": "dns-out" } ] },' & @CRLF & _
            '  "outbounds": [ { "tag": "", "direct": {} }, { "tag": "dns-out", "dns": {} } ],' & @CRLF & _
            '  "capture": { "enabled": false }' & @CRLF & _
            '}' & @CRLF
EndFunc

; PowerShell çıktısı "ad|açıklama|ev ağı geçidi|tüm IPv4'ler|ortam|kartın IPv4'ü"
; -> [ad, ev ağı geçidi, tüm IPv4'ler (çakışma denetimi için), Wi-Fi mi, kartın kendi IPv4'ü]
Func _LanParseAdapter($sOut)
    Local $a[5] = ["", "", "", False, ""]
    Local $aF = StringSplit(StringStripWS($sOut, 3), "|", 2)
    If UBound($aF) < 6 Then Return $a
    $a[0] = $aF[0]
    $a[1] = StringStripWS($aF[2], 3)
    $a[2] = StringStripWS($aF[3], 3)
    $a[3] = StringRegExp($aF[1] & " " & $aF[4], "(?i)wi-?fi|wireless|802\.11|wlan") = 1
    ; Kartta birden fazla IPv4 olabilir: ilki
    Local $aOwn = StringSplit(StringStripWS($aF[5], 3), ",", 2)
    $a[4] = StringStripWS($aOwn[0], 3)
    Return $a
EndFunc

; Etkin fiziksel kart bilgisi (bkz. _LanParseAdapter). Kart yoksa ad "".
Func _LanReadAdapter()
    Local $sBody = "$c = Get-NetIPConfiguration -InterfaceAlias $adapter.Name; " & _
            "$g = ($c.IPv4DefaultGateway | Select-Object -First 1).NextHop; " & _
            "$ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) -join ','; " & _
            "$own = (Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | ForEach-Object { $_.IPAddress }) -join ','; " & _
            "$adapter.Name + '|' + $adapter.InterfaceDescription + '|' + $g + '|' + $ips + '|' + $adapter.PhysicalMediaType + '|' + $own"
    Return _LanParseAdapter(_NetReadPowerShell(_NetWithAdapter($sBody)))
EndFunc

; Log'un son satırlarından kullanıcıya gösterilecek kısa hata nedeni ("" = bilinmiyor).
Func _LanErrorReason($sLogTail)
    ; Yalnızca hata satırları: normal açılış satırları ("Using ethernet interface"...) yanlış neden üretmesin.
    Local $sErrLines = ""
    For $sLine In StringSplit(StringStripCR($sLogTail), @LF, 2)
        If StringRegExp($sLine, "(?i)level=(error|warn)|error|fatal|panic|couldn't|failed") Then $sErrLines &= $sLine & @LF
    Next
    $sLogTail = $sErrLines
    If StringRegExp($sLogTail, "(?i)wpcap\.dll|couldn't load") Then Return "Npcap yüklenemedi (Npcap'i yeniden kurun)."
    If StringRegExp($sLogTail, "(?i)setup PCAP capture|no such device|interface") Then Return "Ağ kartı dinlenemedi (VPN veya sanal ağ kartı açıksa kapatın)."
    If StringRegExp($sLogTail, "(?i)address already in use|bind") Then Return "Gereken ağ portu başka bir programda."
    If StringRegExp($sLogTail, "(?i)config|json|unmarshal") Then Return "Yapılandırma okunamadı."
    Return ""
EndFunc

; Dosyanın son $iLines satırı.
Func _LanLogTail($sPath, $iLines = 15)
    If Not FileExists($sPath) Then Return ""
    Local $a = StringSplit(StringStripCR(FileRead($sPath)), @LF, 2)
    Local $s = "", $iStart = UBound($a) - $iLines
    If $iStart < 0 Then $iStart = 0
    For $i = $iStart To UBound($a) - 1
        If $a[$i] <> "" Then $s &= $a[$i] & @CRLF
    Next
    Return $s
EndFunc

; Paylaşımı başlatır. Dönüş: süreç PID'i (0 = başlamadı; $sErr nedeni taşır).
; $aPlan/$aAdapter çıkış: kullanılan ayarlar ve kart (arayüzde gösterilir).
Func _LanStart($sRoot, ByRef $aPlan, ByRef $aAdapter, ByRef $sErr)
    $sErr = ""
    Local $sExe = $sRoot & $LAN_EXE_REL
    If Not FileExists($sExe) Then
        $sErr = "go-pcap2socks bulunamadı (" & $sExe & ")."
        Return 0
    EndIf
    Local $sNpcap = _LanNpcapStatus()
    If $sNpcap <> "var" Then
        $sErr = _LanNpcapMessage($sNpcap)
        Return 0
    EndIf
    $aAdapter = _LanReadAdapter()
    If $aAdapter[0] = "" Then
        $sErr = "Etkin fiziksel ağ kartı bulunamadı (VPN veya sanal ağ kartı açıksa kapatın)."
        Return 0
    EndIf
    Local $sPrefix = _LanPickPrefix($aAdapter[2])
    $aPlan = _LanPlan($sPrefix)
    Local $sDir = StringRegExpReplace($sExe, "\\[^\\]+$", "")
    Local $h = FileOpen($sDir & "\config.json", $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $h = -1 Then
        $sErr = "Yapılandırma yazılamadı (" & $sDir & ")."
        Return 0
    EndIf
    FileWrite($h, _LanBuildConfig($aPlan[0], $aPlan[1], $aAdapter[4]))
    FileClose($h)
    _LanEnsureFirewall($sExe)

    Local $sLog = $sRoot & $LAN_LOG_REL
    DirCreate($sRoot & "\logs")
    FileDelete($sLog)
    ; Çıktı dosyaya: süreç gizli çalışır, hata nedeni loga ve kullanıcıya ulaşır.
    Local $iPid = Run(@ComSpec & ' /c ""' & $sExe & '" > "' & $sLog & '" 2>&1"', $sDir, @SW_HIDE)
    If $iPid = 0 Then
        $sErr = "go-pcap2socks başlatılamadı."
        Return 0
    EndIf
    ; Erken çökme (Npcap/kart sorunu) genelde ilk saniyede olur.
    Local $hT = TimerInit()
    While TimerDiff($hT) < 2000
        If Not ProcessExists($iPid) Then ExitLoop
        Sleep(100)
    WEnd
    If Not ProcessExists($iPid) Then
        Local $sTail = _LanLogTail($sLog)
        $sErr = _LanErrorReason($sTail)
        If $sErr = "" Then $sErr = "go-pcap2socks hemen kapandı. Ayrıntı: logs\paylasim.log"
        _LogWarn("Ağ paylaşımı başlamadı: " & StringReplace(StringStripWS($sTail, 3), @CRLF, " | "))
        Return 0
    EndIf
    _LogInfo("Ağ paylaşımı başladı (PID " & $iPid & ", kart " & $aAdapter[0] & ($aAdapter[3] ? " [Wi-Fi]" : "") & _
            ", ağ " & $aPlan[0] & ", geçit " & $aPlan[1] & ", kart IP " & $aAdapter[4] & ", ev ağı geçidi " & $aAdapter[1] & ")")
    Return $iPid
EndFunc

; Paylaşımı durdurur (cmd + go-pcap2socks süreç ağacı).
Func _LanStop($iPid, $sRoot)
    If $iPid > 0 And ProcessExists($iPid) Then _KillProcessTree($iPid)
    ; Önceki oturumdan kalmış olabilir: yalnızca bu paketteki kopya hedeflenir.
    _KillProcessesUnderDir($sRoot & "\bin\go-pcap2socks")
    _LogInfo("Ağ paylaşımı durduruldu")
EndFunc

; Paylaşım çalışıyor mu? (cmd sarmalayıcısı go-pcap2socks kapanınca o da kapanır)
Func _LanIsRunning($iPid)
    Return $iPid > 0 And ProcessExists($iPid) <> 0
EndFunc

; Güvenlik duvarında izin kuralı yoksa sessizce ekler (program yönetici çalışır; Windows uyarısı beklenmez).
Func _LanEnsureFirewall($sExe)
    Local $sName = "RedRiveRR Zapret - ağ paylaşımı"
    Local $iPid = Run(@ComSpec & ' /c netsh advfirewall firewall show rule name="' & $sName & '"', "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPid, 10)
    If StringInStr(StdoutRead($iPid), $sExe) Then Return
    RunWait(@ComSpec & ' /c netsh advfirewall firewall add rule name="' & $sName & '" dir=in action=allow program="' & $sExe & '" enable=yes profile=any', "", @SW_HIDE)
    RunWait(@ComSpec & ' /c netsh advfirewall firewall add rule name="' & $sName & '" dir=out action=allow program="' & $sExe & '" enable=yes profile=any', "", @SW_HIDE)
    _LogInfo("Ağ paylaşımı: güvenlik duvarı izni eklendi")
EndFunc

Func _LanNpcapMessage($sState)
    If $sState = "uyumsuz" Then Return "Npcap kurulu ama 'WinPcap API-compatible Mode' kapalı. Npcap'i bu seçenek işaretli olarak yeniden kurun."
    If $sState = "yok" Then Return "Npcap kurulu değil. npcap.com adresinden indirip kurun ('WinPcap API-compatible Mode' işaretli olsun)."
    Return ""
EndFunc

; go-pcap2socks açılışta cihazda girilecek MTU'yu yazar (PS5 ve Switch'te elle girilmesi gerekir).
; Log'dan sayıyı çıkarır; bulunamazsa "".
Func _LanParseMtu($sLog)
    Local $a = StringRegExp($sLog, "(?i)\bmtu\b\D{0,30}(\d{3,5})", 1)
    If @error Then Return ""
    Local $n = Number($a[0])
    If $n < 576 Or $n > 9000 Then Return ""
    Return String($n)
EndFunc
