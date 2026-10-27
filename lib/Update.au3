#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <Crypt.au3>
#include "Log.au3"

; =========================================================================
; --- GÜNCELLEME KONTROLÜ ---
; GitHub'daki son sürümü arka planda sorgular; arayüzü bekletmez. Yeni sürüm bulunursa tepside
; kurma seçeneği çıkar; kurma kullanıcı onayıyla (aşağıda "KENDİNİ GÜNCELLEME").
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

; =========================================================================
; --- KENDİNİ GÜNCELLEME ---
; Yeni sürüm bu deponun GitHub release'inden indirilir (zip + SHA256SUMS.txt), özeti doğrulanır,
; geçici klasöre açılır. Program kapanınca _UpdateApplyScript'in ürettiği PowerShell adımı dosyaları
; kurulum klasörüne kopyalar ve yeni sürümü başlatır. config\ (yalnız strategies.ini ve varsayilan\
; yenilenir) ve logs\ korunur; robocopy değişmeyen dosyaları atladığı için servisin kullandığı motor
; dosyalarına dokunulmaz. İndirme PowerShell ile yapıldığından dosyalarda internet işareti olmaz.
; =========================================================================
; Yeni sürüm bulunduysa etiketi ("v5.2.0"), yoksa "".
Func _UpdateAvailableTag()
    Return $__g_sUpdateTag
EndFunc

; Release'teki paket adı: RedRiveRR-Zapret-v5.2.0.zip / RedRiveRR-Zapret-Lite-v5.2.0.zip
Func _UpdateAssetName($sTag, $bLite = False)
    Return "RedRiveRR-Zapret-" & ($bLite ? "Lite-" : "") & $sTag & ".zip"
EndFunc

; SHA256SUMS.txt içinde dosyanın özeti (küçük harf); yoksa "".
Func _UpdateSumFor($sSums, $sName)
    For $sLine In StringSplit(StringStripCR($sSums), @LF, 2)
        Local $a = StringRegExp($sLine, "^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$", 1)
        If Not @error And $a[1] == $sName Then Return StringLower($a[0])
    Next
    Return ""
EndFunc

; İndirme adresi yalnız bu deponun release dosyası olabilir (başka depo/alan adı reddedilir).
Func _UpdateUrlAllowed($sUrl, $sRepo)
    Return StringRegExp($sUrl, "(?i)^https://github\.com/\Q" & $sRepo & "\E/releases/download/[^/\s?#]+/[^/\s?#]+$") = 1
EndFunc

; Dosyanın SHA256 özeti (küçük harf onaltılık). PowerShell'e bağlı değil: Get-FileHash, PowerShell 7'den
; başlatılan Windows PowerShell'de modül yolu karıştığı için bulunamayabiliyor (denendi).
Func _UpdateFileSha256($sPath)
    Local $bHash = _Crypt_HashFile($sPath, $CALG_SHA_256)
    If @error Then Return ""
    Return StringLower(StringTrimLeft(String($bHash), 2))
EndFunc

Func _PsQuoteU($s)
    Return "'" & StringReplace($s, "'", "''") & "'"
EndFunc

; Sürümü indirir, doğrular, $sDir\paket içine açar. Dönüş: paket klasörü ya da "" ($sErr nedeni taşır).
Func _UpdateDownload($sRepo, $sTag, $bLite, $sDir, ByRef $sErr)
    $sErr = ""
    Local $sAsset = _UpdateAssetName($sTag, $bLite)
    DirRemove($sDir, 1)
    DirCreate($sDir)
    ; 1) Release bilgisi ve indirme (PowerShell: TLS 1.2, zaman aşımı; çıktı satırları URL/TAMAM/HATA)
    Local $sPs = "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; " & _
            "try { $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/" & $sRepo & "/releases/tags/" & $sTag & "' -TimeoutSec 15; " & _
            "$z = $r.assets | Where-Object { $_.name -eq '" & $sAsset & "' }; $s = $r.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' }; " & _
            "if (-not $z -or -not $s) { 'HATA dosya-yok'; exit }; 'URL ' + $z.browser_download_url; 'URL ' + $s.browser_download_url; " & _
            "Invoke-WebRequest -Uri $s.browser_download_url -OutFile " & _PsQuoteU($sDir & "\SHA256SUMS.txt") & " -UseBasicParsing -TimeoutSec 30; " & _
            "Invoke-WebRequest -Uri $z.browser_download_url -OutFile " & _PsQuoteU($sDir & "\" & $sAsset) & " -UseBasicParsing -TimeoutSec 600; 'TAMAM' } " & _
            "catch { 'HATA ' + $_.Exception.Message }"
    Local $iPid = Run('powershell.exe -NoProfile -NonInteractive -Command "' & StringReplace($sPs, '"', '\"') & '"', "", @SW_HIDE, $STDOUT_CHILD + $STDERR_MERGED)
    If $iPid = 0 Then
        $sErr = "PowerShell başlatılamadı."
        Return ""
    EndIf
    ProcessWaitClose($iPid, 900)
    Local $sOut = BinaryToString(StdoutRead($iPid, False, True), 4)
    For $sLine In StringSplit(StringStripCR($sOut), @LF, 2)
        If StringLeft($sLine, 4) = "URL " And Not _UpdateUrlAllowed(StringTrimLeft($sLine, 4), $sRepo) Then
            $sErr = "Beklenmeyen indirme adresi: " & StringTrimLeft($sLine, 4)
            Return ""
        EndIf
    Next
    If Not StringInStr($sOut, "TAMAM") Then
        Local $m = StringRegExp($sOut, "HATA ([^\r\n]*)", 1)
        $sErr = @error ? "İndirme tamamlanamadı." : ($m[0] = "dosya-yok" ? "Bu sürümde " & $sAsset & " bulunamadı." : "İndirme hatası: " & $m[0])
        Return ""
    EndIf
    ; 2) Özet doğrulama
    Local $sWant = _UpdateSumFor(FileRead($sDir & "\SHA256SUMS.txt"), $sAsset)
    If $sWant = "" Then
        $sErr = "SHA256SUMS.txt içinde " & $sAsset & " yok."
        Return ""
    EndIf
    Local $sGot = _UpdateFileSha256($sDir & "\" & $sAsset)
    If $sGot <> $sWant Then
        $sErr = "İndirilen dosyanın özeti tutmuyor (bozuk ya da değiştirilmiş)."
        Return ""
    EndIf
    ; 3) Açma
    Local $sPkg = $sDir & "\paket"
    ; .NET ZipFile (Expand-Archive modülüne bağlı değil; yukarıdaki not).
    RunWait('powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; ' & _
            '[IO.Compression.ZipFile]::ExtractToDirectory(' & _PsQuoteU($sDir & "\" & $sAsset) & ', ' & _PsQuoteU($sPkg) & ')"', "", @SW_HIDE)
    If Not FileExists($sPkg & "\RedRiveRR Zapret" & ($bLite ? " Lite" : "") & ".exe") Then
        $sErr = "Paket açılamadı ya da içinde program yok."
        Return ""
    EndIf
    _LogInfo("Güncelleme: " & $sTag & " indirildi ve doğrulandı (" & $sGot & ")")
    Return $sPkg
EndFunc

; Program kapandıktan sonra çalışacak kurulum adımı (PowerShell betiği metni; saf).
;   $iPid: beklenecek süreç, $sPkg: açılmış paket, $sDst: kurulum klasörü, $sExe: başlatılacak exe adı,
;   $sArgs: yeni sürüme verilecek argümanlar, $sTempDir: sonra silinecek geçici klasör
Func _UpdateApplyScript($iPid, $sPkg, $sDst, $sExe, $sArgs, $sTempDir)
    Local $s = "$ErrorActionPreference = 'Continue'" & @CRLF
    $s &= "$p = Get-Process -Id " & Int($iPid) & " -ErrorAction SilentlyContinue; if ($p) { [void]$p.WaitForExit(60000) }" & @CRLF
    $s &= "Start-Sleep -Milliseconds 700" & @CRLF
    $s &= "$src = " & _PsQuoteU($sPkg) & "; $dst = " & _PsQuoteU($sDst) & @CRLF
    $s &= "New-Item -ItemType Directory -Force -Path (Join-Path $dst 'logs') | Out-Null" & @CRLF
    $s &= "$log = Join-Path $dst 'logs\guncelleme.log'" & @CRLF
    ; config\ ve logs\ korunur; değişmeyen dosyalar (kullanımdaki motor dosyaları dahil) atlanır.
    $s &= "robocopy $src $dst /E /XD (Join-Path $src 'config') (Join-Path $src 'logs') /R:3 /W:1 /NP /NJH /NJS /NDL | Out-File -Append -Encoding utf8 $log; $rc = $LASTEXITCODE" & @CRLF
    $s &= "robocopy (Join-Path $src 'config') (Join-Path $dst 'config') strategies.ini /R:3 /W:1 /NP /NJH /NJS /NDL | Out-File -Append -Encoding utf8 $log; $rc2 = $LASTEXITCODE" & @CRLF
    $s &= "robocopy (Join-Path $src 'config\varsayilan') (Join-Path $dst 'config\varsayilan') /E /R:3 /W:1 /NP /NJH /NJS /NDL | Out-File -Append -Encoding utf8 $log; $rc3 = $LASTEXITCODE" & @CRLF
    $s &= "Add-Content -Encoding utf8 $log ((Get-Date -Format s) + ' robocopy ' + $rc + '/' + $rc2 + '/' + $rc3)" & @CRLF
    $s &= "$a = " & _PsQuoteU($sArgs) & "; if ($rc -ge 8 -or $rc2 -ge 8 -or $rc3 -ge 8) { $a = $a + ' /guncelleme-hatasi' }" & @CRLF
    $s &= "Start-Process -FilePath (Join-Path $dst " & _PsQuoteU($sExe) & ") -ArgumentList $a -WorkingDirectory $dst" & @CRLF
    $s &= "Start-Sleep -Seconds 2; Remove-Item -LiteralPath " & _PsQuoteU($sTempDir) & " -Recurse -Force -ErrorAction SilentlyContinue" & @CRLF
    Return $s
EndFunc

; Kurulum adımını gizli PowerShell olarak başlatır (betik geçici klasörde, UTF-8 BOM: Türkçe yollar için).
Func _UpdateLaunchApply($sScript, $sTempDir)
    Local $sFile = $sTempDir & "\kur.ps1"
    Local $h = FileOpen($sFile, $FO_OVERWRITE + $FO_UTF8)
    If $h = -1 Then Return False
    FileWrite($h, $sScript)
    FileClose($h)
    Return Run('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' & $sFile & '"', @TempDir, @SW_HIDE) <> 0 ; çalışma klasörü geçici klasör olmasın (sonunda siliniyor)
EndFunc
