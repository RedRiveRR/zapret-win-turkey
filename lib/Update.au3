#include-once
#include <AutoItConstants.au3>
#include "Log.au3"

; =========================================================================
; --- GÜNCELLEME KONTROLÜ ---
; GitHub'daki son sürümü arka planda sorgular; arayüzü bekletmez. Yeni sürüm bulunursa tepside
; kurma seçeneği çıkar; kurma kullanıcı onayıyla (lib/SelfUpdate.au3, yalnız ana sürüm).
; =========================================================================

Global $__g_iUpdatePid = 0
Global $__g_sUpdateOut = ""
Global $__g_sUpdateUrl = ""
Global $__g_sUpdateTag = "" ; bulunan yeni sürüm (kendini güncelleme)

; Sürüm karşılaştırır: $a > $b ise 1, eşitse 0, küçükse -1.
; Baştaki "v" yok sayılır; eksik bölümler 0 kabul edilir ("4.5" = "4.5.0").
Func _VersionCompare($a, $b)
    Local $aA = __VersionParts($a), $aB = __VersionParts($b)
    Local $iLen = (UBound($aA) > UBound($aB)) ? UBound($aA) : UBound($aB)
    For $i = 0 To $iLen - 1
        Local $x = ($i < UBound($aA)) ? $aA[$i] : 0
        Local $y = ($i < UBound($aB)) ? $aB[$i] : 0
        If $x > $y Then Return 1
        If $x < $y Then Return -1
    Next
    Return 0
EndFunc

Func __VersionParts($s)
    $s = StringRegExpReplace(StringStripWS($s, 3), "^[vV]", "")
    Local $aRaw = StringSplit($s, ".", 2)
    Local $aOut[UBound($aRaw)]
    For $i = 0 To UBound($aRaw) - 1
        ; "6-beta" gibi bölümlerde baştaki sayı alınır.
        $aOut[$i] = Number(StringRegExpReplace($aRaw[$i], "^(\d*).*$", "$1"))
    Next
    Return $aOut
EndFunc

; Sürüm etiketi makul mü? (v4.6, 4.5.1 gibi)
Func _IsVersionTag($s)
    Return StringRegExp(StringStripWS($s, 3), "^[vV]?\d+(\.\d+){0,3}([-+][0-9A-Za-z.]+)?$") = 1
EndFunc

; Arka planda son sürüm sorgusunu başlatır.
Func _UpdateStartCheck($sRepo)
    $__g_sUpdateOut = ""
    Local $sPs = "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " & _
            "(Invoke-RestMethod -Uri 'https://api.github.com/repos/" & $sRepo & "/releases/latest' -TimeoutSec 8).tag_name } " & _
            "catch { 'HATA ' + [int]$_.Exception.Response.StatusCode }"
    $__g_iUpdatePid = Run('powershell.exe -NoProfile -NonInteractive -Command "' & $sPs & '"', "", @SW_HIDE, $STDOUT_CHILD)
EndFunc

; Sorgu bittiyse ve daha yeni sürüm varsa etiketi döndürür (yalnızca bir kez); aksi halde "".
Func _UpdatePoll($sCurrent)
    If $__g_iUpdatePid = 0 Then Return ""
    $__g_sUpdateOut &= StdoutRead($__g_iUpdatePid)
    If ProcessExists($__g_iUpdatePid) Then Return ""
    $__g_sUpdateOut &= StdoutRead($__g_iUpdatePid)
    $__g_iUpdatePid = 0

    Local $sTag = StringStripWS($__g_sUpdateOut, 3)
    If Not _IsVersionTag($sTag) Then
        _LogInfo("Güncelleme kontrolü: " & _UpdateFailText($sTag))
        Return ""
    EndIf
    If _VersionCompare($sTag, $sCurrent) > 0 Then
        _LogInfo("Güncelleme kontrolü: yeni sürüm " & $sTag & " (mevcut " & $sCurrent & ")")
        Return $sTag
    EndIf
    _LogInfo("Güncelleme kontrolü: güncel (" & $sTag & ")")
    Return ""
EndFunc

; Ana döngüden çağrılır: yeni sürüm bulunduysa tepsi bildirimi gösterir ve tepsi menüsünün başına
; öğe ekler. $sInstallFunc verilirse öğe "Yeni sürümü kur" olur ve o fonksiyonu çağırır; verilmezse
; release sayfasını açar (lite). TrayOnEventMode açık olmalıdır. Dönüş: bulunan etiket ya da "".
Func _UpdatePollAndNotify($sCurrent, $sReleasesUrl, $sInstallFunc = "")
    Local $sTag = _UpdatePoll($sCurrent)
    If $sTag = "" Then Return ""
    $__g_sUpdateUrl = $sReleasesUrl
    $__g_sUpdateTag = $sTag
    If $sInstallFunc <> "" Then
        TrayCreateItem("Yeni sürümü kur (" & $sTag & ")", -1, 0)
        TrayItemSetOnEvent(-1, $sInstallFunc)
        TrayTip("Yeni sürüm: " & $sTag, "Kurmak için tepsi simgesine sağ tıklayın ya da Diğer sayfasındaki Güncelle düğmesine basın.", 10, 1)
    Else
        TrayCreateItem("Yeni sürümü indir (" & $sTag & ")", -1, 0)
        TrayItemSetOnEvent(-1, "__UpdateOpenReleases")
        TrayTip("Yeni sürüm: " & $sTag, "Yeni bir sürüm yayınlandı. İndirmek için tepsi simgesine sağ tıklayın.", 10, 1)
    EndIf
    Return $sTag
EndFunc

; Sorgu sürüm etiketi döndürmediğinde log metni. "HATA 404": depoda yayınlanmış (taslak olmayan) sürüm yok.
Func _UpdateFailText($sOut)
    If $sOut = "HATA 404" Then Return "henüz yayınlanmış sürüm yok"
    If StringLeft($sOut, 5) = "HATA " Then Return "GitHub'a ulaşılamadı (" & ($sOut = "HATA 0" ? "bağlantı yok" : "HTTP " & StringTrimLeft($sOut, 5)) & ")"
    Return "sürüm bilgisi alınamadı"
EndFunc

Func __UpdateOpenReleases()
    If $__g_sUpdateUrl <> "" Then ShellExecute($__g_sUpdateUrl)
EndFunc

; Yeni sürüm bulunduysa etiketi ("v5.2.0"), yoksa "". Kurma: lib/SelfUpdate.au3 (yalnız ana sürüm).
Func _UpdateAvailableTag()
    Return $__g_sUpdateTag
EndFunc
