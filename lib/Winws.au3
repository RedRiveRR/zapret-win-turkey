#include-once

; =========================================================================
; --- WINWS KOMUT SATIRI ---
; Manuel başlatma, servis kurulumu ve strateji testi aynı argümanları kullanır.
; GUI'ye bağımlı değildir; birim testleri tests/test_winws.au3 içinde.
; =========================================================================

Global Const $WINWS_FILTER_OFF = "off"
Global Const $WINWS_FILTER_AUTO = "auto"
Global Const $WINWS_FILTER_MANUAL = "manual"

; Filtre combo metnini ("Auto (Zapret oluşturur)" vb.) filtre moduna çevirir.
Func _WinwsFilterModeFromText($sText)
    If StringInStr($sText, "Auto") Then Return $WINWS_FILTER_AUTO
    If StringInStr($sText, "Manuel") Then Return $WINWS_FILTER_MANUAL
    Return $WINWS_FILTER_OFF
EndFunc

; OOB stratejileri hostlist filtreleriyle çalışmaz.
Func _WinwsStrategyHasOOB($sStrategy)
    Return StringInStr($sStrategy, "oob") > 0
EndFunc

; Yakalanan giden UDP portları: 67 (DHCP sunucusu) hariç hepsi (H31). Açılışta bilgisayar henüz IPv4
; adresi yokken 0.0.0.0 -> 255.255.255.255:67 DHCP isteği gönderir; winws bunu yakalayıp geri
; gönderemiyor, Ethernet IPv4 adresi alamıyor (yalnız IPv6 kalıyor, Discord açılmıyor).
Global Const $WINWS_UDP_PORTS = "0-66,68-65535"

; Eski sürümlerin kurduğu servis komutunda tüm UDP'yi yakalayan filtreyi DHCP'siz hâline çevirir.
; Başka biçimde verilmiş UDP filtresine dokunulmaz.
Func _WinwsArgsFixDhcp($sCmd)
    $sCmd = StringReplace($sCmd, "--wf-udp-out=0-65535", "--wf-udp-out=" & $WINWS_UDP_PORTS)
    Return StringReplace($sCmd, "--wf-udp=0-65535", "--wf-udp=" & $WINWS_UDP_PORTS)
EndFunc

; winws/winws2 argümanlarını (exe yolu hariç) oluşturur.
;   $sEngine            : "Zapret2" veya "Zapret1"
;   $sWinwsPath         : winws(2).exe tam yolu (Zapret2 lua klasörü buradan bulunur)
;   $sStrategy          : strateji parametreleri
;   $sFilterMode        : $WINWS_FILTER_OFF / AUTO / MANUAL
;   $sExcludePath       : "" ise --hostlist-exclude eklenmez (strateji testi)
;   $sAutoHostlistPath  : AUTO modunda kullanılır
;   $sHostlistPath      : MANUAL modunda kullanılır
Func _BuildWinwsArgs($sEngine, $sWinwsPath, $sStrategy, $sFilterMode, $sExcludePath = "", $sAutoHostlistPath = "", $sHostlistPath = "")
    Local $bOOB = _WinwsStrategyHasOOB($sStrategy)
    Local $sArgs = ""

    If $sEngine = "Zapret2" Then
        $sArgs = "--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=" & $WINWS_UDP_PORTS & " "
    Else
        $sArgs = "--wf-tcp=0-65535 --wf-udp=" & $WINWS_UDP_PORTS & " "
    EndIf

    If Not $bOOB And $sExcludePath <> "" Then $sArgs &= '--hostlist-exclude="' & $sExcludePath & '" '
    $sArgs &= $sStrategy

    If $sEngine = "Zapret2" Then
        Local $sLuaDir = StringRegExpReplace($sWinwsPath, "\\[^\\]+$", "") & "\lua\"
        $sArgs &= ' --lua-init="@' & $sLuaDir & 'zapret-lib.lua"' & _
                ' --lua-init="@' & $sLuaDir & 'zapret-antidpi.lua"' & _
                ' --lua-init="@' & $sLuaDir & 'zapret-auto.lua"'
    EndIf

    ; OOB stratejilerinde hostlist filtreleri uygulanmaz.
    If Not $bOOB Then
        If $sFilterMode = $WINWS_FILTER_AUTO Then
            $sArgs &= ' --hostlist-auto="' & $sAutoHostlistPath & '"'
        ElseIf $sFilterMode = $WINWS_FILTER_MANUAL Then
            $sArgs &= ' --hostlist="' & $sHostlistPath & '"'
        EndIf
    EndIf

    Return $sArgs
EndFunc

; Seçilen filtre modu için gereken hostlist dosyası yoksa varsayılan içerikle oluşturur.
Func _EnsureHostlistFile($sFilterMode, $sStrategy, $sAutoHostlistPath, $sHostlistPath)
    If _WinwsStrategyHasOOB($sStrategy) Then Return
    If $sFilterMode = $WINWS_FILTER_AUTO Then
        If Not FileExists($sAutoHostlistPath) Then FileWrite($sAutoHostlistPath, "")
    ElseIf $sFilterMode = $WINWS_FILTER_MANUAL Then
        If Not FileExists($sHostlistPath) Then FileWrite($sHostlistPath, "discord.com" & @CRLF & "updates.discord.com")
    EndIf
EndFunc
