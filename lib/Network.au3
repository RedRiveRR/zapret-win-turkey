#include-once
#include <AutoItConstants.au3>
#include "Log.au3"

; =========================================================================
; --- AĞ / DNS YARDIMCILARI ---
; GUI'ye bağımlı değildir; ana ve lite sürüm tarafından ortak kullanılır.
; =========================================================================

; Fiziksel, açık durumdaki ilk ağ bağdaştırıcısını $adapter değişkenine atayan PowerShell parçası.
; Sanal (Hyper-V, WSL, VPN, TAP/TUN) bağdaştırıcılar atlanır.
Global Const $NET_PS_SELECT_ADAPTER = "$adapter = Get-NetAdapter | Where-Object {$_.Status -eq 'Up' -and $_.InterfaceDescription -notlike '*Virtual*' -and $_.InterfaceDescription -notlike '*Hyper-V*' -and $_.InterfaceDescription -notlike '*WSL*' -and $_.Name -notlike '*vEthernet*' -and $_.InterfaceDescription -notlike '*TAP*' -and $_.InterfaceDescription -notlike '*TUN*' -and $_.InterfaceDescription -notlike '*VPN*'} | Select-Object -First 1; "

; Uygun bağdaştırıcı bulunamadığında PowerShell betiklerinin döndürdüğü çıkış kodu.
Global Const $NET_EXIT_NO_ADAPTER = 3
Global Const $NET_MSG_NO_ADAPTER = "Etkin fiziksel ağ bağdaştırıcısı bulunamadı; DNS ayarı değiştirilemedi." & @CRLF & @CRLF & _
        "VPN veya sanal ağ bağdaştırıcısı kullanıyorsanız kapatıp tekrar deneyin, ya da DNS'i Windows ağ ayarlarından elle değiştirin."

; Cloudflare yanıt öneki ve Türk Telekom'un zehirli yanıt IP'si (discord.com sorgusu için).
Global Const $NET_DNS_SAFE_PREFIX = "162.159"
Global Const $NET_DNS_TT_POISON_IP = "195.175.254.2"

; PowerShell betiğini gizli pencerede çalıştırır ve çıkış kodunu döndürür.
; Betik içinde çift tırnak kullanılmamalıdır.
Func _NetRunPowerShell($sScript)
    Return RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' & $sScript & '"', "", @SW_HIDE)
EndFunc

; PowerShell betiğini çalıştırır ve standart çıktısını döndürür.
Func _NetReadPowerShell($sScript)
    Local $iPid = Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' & $sScript & '"', "", @SW_HIDE, $STDOUT_CHILD)
    If $iPid = 0 Then Return ""
    ProcessWaitClose($iPid)
    Return StdoutRead($iPid)
EndFunc

; Bağdaştırıcı gerektiren bir DNS işlemini çalıştırır, sonucu loglar.
Func __NetRunAdapterAction($sAction, $sBody)
    Local $bOk = _NetRunPowerShell(_NetWithAdapter($sBody)) <> $NET_EXIT_NO_ADAPTER
    If $bOk Then
        _LogInfo("DNS: " & $sAction)
    Else
        _LogWarn("DNS: " & $sAction & " yapılamadı, uygun ağ bağdaştırıcısı yok")
    EndIf
    Return $bOk
EndFunc

; Betiği yalnızca uygun bağdaştırıcı bulunduğunda çalışacak şekilde sarar.
Func _NetWithAdapter($sBody)
    Return $NET_PS_SELECT_ADAPTER & "if ($adapter) { " & $sBody & " } else { exit " & $NET_EXIT_NO_ADAPTER & " }"
EndFunc

; Sistem DNS'ini Cloudflare (IPv4 + IPv6) yapar; Windows 11'de DoH şablonu da ekler.
; Bağdaştırıcı bulunamazsa False döner.
Func _SetSystemDNS()
    Local $sBody = "$ErrorActionPreference = 'SilentlyContinue'; " & _
            "Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses @('1.1.1.1','1.0.0.1','2606:4700:4700::1111','2606:4700:4700::1001'); " & _
            "if ([Environment]::OSVersion.Version.Build -ge 22000) { " & _
            "$doh = Get-DnsClientDohServerAddress; " & _
            "foreach ($ip in @('1.1.1.1','1.0.0.1','2606:4700:4700::1111','2606:4700:4700::1001')) { " & _
            "if ($doh.ServerAddress -contains $ip) { " & _
            "Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate 'https://cloudflare-dns.com/dns-query' -AutoUpgrade $true -AllowFallbackToUdp $false " & _
            "} else { " & _
            "Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate 'https://cloudflare-dns.com/dns-query' -AutoUpgrade $true -AllowFallbackToUdp $false " & _
            "} " & _
            "} " & _
            "}; " & _
            "ipconfig /flushdns"
    Return __NetRunAdapterAction("Cloudflare (1.1.1.1) olarak ayarlandı", $sBody)
EndFunc

; DNS'i otomatiğe (DHCP) alır ve önbelleği temizler. Bağdaştırıcı bulunamazsa False döner.
Func _ResetSystemDNS()
    Return __NetRunAdapterAction("otomatiğe (DHCP) alındı", "Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses; ipconfig /flushdns")
EndFunc

; DNS'i yerel dnscrypt-proxy'ye (127.0.0.1 / ::1) yönlendirir. Bağdaştırıcı bulunamazsa False döner.
Func _SetDNS_Localhost()
    Return __NetRunAdapterAction("yerel dnscrypt-proxy'ye (127.0.0.1) yönlendirildi", "Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses '127.0.0.1', '::1'; ipconfig /flushdns")
EndFunc

; Etkin bağdaştırıcının DNS sunucularını virgülle ayrılmış olarak döndürür.
Func _GetActiveAdapterDnsServers()
    Return _NetReadPowerShell(_NetWithAdapter("(Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue).ServerAddresses -join ','"))
EndFunc

; discord.com için dönen IP güvenli mi? Yalnızca Cloudflare öneki güvenli kabul edilir.
Func _IsDnsAnswerSafe($sIP)
    $sIP = StringStripWS($sIP, 3)
    If $sIP = "" Then Return False
    If StringInStr($sIP, $NET_DNS_TT_POISON_IP) Then Return False
    Return StringInStr($sIP, $NET_DNS_SAFE_PREFIX) > 0
EndFunc

; discord.com sorgusuyla DNS zehirlenmesini sessizce kontrol eder. Zehirliyse veya
; internet varken iki denemede de geçerli yanıt alınamazsa True döner.
; İnternet tamamen kesikse (DNS'ten bağımsız bağlantı da yok) False: DNS değiştirmek işe yaramaz (H17).
Func CheckDnsPoisoningSilent()
    Local $sIP = __NetQueryDiscord()
    ; Boş yanıt, zaman aşımı veya hata metni geçici bir ağ sorunu olabilir; bir kez daha dene.
    ; Kesin bir IP (zehirli dahil) döndüyse yeniden denenmez.
    If _DnsAnswerNeedsRetry($sIP) Then
        _LogWarn("DNS kontrolü: geçerli yanıt alınamadı (" & StringLeft(StringStripWS($sIP, 3), 80) & "), 1 sn sonra yeniden deneniyor")
        Sleep(1000)
        $sIP = __NetQueryDiscord()
    EndIf

    Local $bInternet = True
    If _DnsAnswerNeedsRetry($sIP) Then
        $bInternet = __NetInternetReachable()
        If Not $bInternet Then _LogWarn("DNS kontrolü: internet bağlantısı yok (1.1.1.1/8.8.8.8 erişilemiyor); DNS zehirli sayılmadı")
    EndIf
    Local $bPoison = _DnsIsPoisonVerdict($sIP, $bInternet)
    _LogInfo("DNS kontrolü: discord.com -> " & StringLeft(StringStripWS($sIP, 3), 80) & " => " & _
            ($bPoison ? "zehirli" : ($bInternet ? "temiz" : "bilinmiyor (internet yok)")))
    Return $bPoison
EndFunc

; DNS yanıtı ve internet durumundan karar: True = DNS zehirli/sorunlu (düzeltme önerilir).
; Yanıt bir IP değilse ve internet de yoksa sorun DNS'te değildir.
Func _DnsIsPoisonVerdict($sIP, $bInternetUp)
    If _DnsAnswerNeedsRetry($sIP) And Not $bInternetUp Then Return False
    Return Not _IsDnsAnswerSafe($sIP)
EndFunc

; DNS kullanmadan internete çıkılabiliyor mu (1.1.1.1 / 8.8.8.8, TCP 443, en fazla ~2 sn).
Func __NetInternetReachable()
    Local $sPs = "foreach ($h in '1.1.1.1','8.8.8.8') { $c = New-Object Net.Sockets.TcpClient; " & _
            "try { if ($c.ConnectAsync($h, 443).Wait(2000)) { exit 0 } } catch {} finally { $c.Close() } }; exit 1"
    Local $iRc = RunWait('powershell.exe -NoProfile -NonInteractive -Command "' & $sPs & '"', "", @SW_HIDE)
    Return $iRc = 0
EndFunc

; Yanıt bir IPv4/IPv6 adresi değilse (boş, zaman aşımı, PowerShell hata metni) True.
Func _DnsAnswerNeedsRetry($sIP)
    $sIP = StringStripWS($sIP, 3)
    If $sIP = "" Then Return True
    If StringRegExp($sIP, "^\d{1,3}(\.\d{1,3}){3}$") Then Return False
    If StringRegExp($sIP, "^[0-9a-fA-F:]+$") And StringInStr($sIP, ":") Then Return False
    Return True
EndFunc

; DNS önbelleğini temizleyip discord.com'u çözer; ilk IP'yi döndürür. 5 sn içinde yanıt yoksa "".
Func __NetQueryDiscord()
    RunWait(@ComSpec & " /c ipconfig /flushdns", "", @SW_HIDE)

    Local $iPID = Run( _
            'powershell.exe -NoProfile -NonInteractive -Command "[Console]::OutputEncoding = [Text.Encoding]::UTF8; [System.Net.Dns]::GetHostAddresses(' & "'" & "discord.com" & "'" & ') | Select-Object -ExpandProperty IPAddressToString | Select-Object -First 1"', _
            "", @SW_HIDE, $STDOUT_CHILD + $STDERR_MERGED)
    If $iPID = 0 Then Return ""

    Local $hTimer = TimerInit()

    ; En fazla 5 saniye bekle. Çıktı kısa olduğu için süreç bitince bir kerede, UTF-8 olarak okunur
    ; (Windows hata metinleri OEM kod sayfasında bozuk görünüyordu: "˜stenen ad ge‡erli").
    While ProcessExists($iPID)
        If TimerDiff($hTimer) > 5000 Then
            ProcessClose($iPID)
            _LogWarn("DNS kontrolü: discord.com sorgusu 5 sn içinde yanıt vermedi")
            Return ""
        EndIf

        Sleep(50)
    WEnd

    Return StringStripWS(BinaryToString(StdoutRead($iPID, False, True), 4), 3)
EndFunc
