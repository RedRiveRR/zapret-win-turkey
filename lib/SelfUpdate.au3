#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <InetConstants.au3>
#include <Crypt.au3>
#include "Log.au3"
#include "Update.au3"

; =========================================================================
; --- KENDİNİ GÜNCELLEME (yalnız ana sürüm) ---
; Yeni sürüm bu deponun GitHub release'inden indirilir (zip + SHA256SUMS.txt; InetGet), özeti
; doğrulanır (AutoIt Crypt), Windows'un tar.exe'siyle geçici klasöre açılır. Program kapanınca
; İNDİRİLEN yeni exe "/guncelle-uygula" kipinde dosyaları kurulum klasörüne kopyalar (robocopy) ve
; yeni sürümü açar. config\ (yalnız strategies.ini ve varsayilan\ yenilenir) ve logs\ korunur;
; robocopy değişmeyen dosyaları atladığı için servisin kullandığı motor dosyalarına dokunulmaz.
;
; Neden PowerShell betiği yok: indir + "-ExecutionPolicy Bypass -File" ile betik çalıştır kalıbı
; Windows Defender'ın makine öğrenmesi tespitine takıldı (Program:Win32/Contebrew.A!ml, 2026-10-27).
; =========================================================================
Global Const $UPDATE_APPLY_ARG = "/guncelle-uygula"

; Release'teki paket adı: RedRiveRR-Zapret-v5.2.0.zip / RedRiveRR-Zapret-Lite-v5.2.0.zip
Func _UpdateAssetName($sTag, $bLite = False)
    Return "RedRiveRR-Zapret-" & ($bLite ? "Lite-" : "") & $sTag & ".zip"
EndFunc

; Güncellemenin indirildiği geçici klasör (yeni sürüm açılınca bu adla bulup siler).
Func _UpdateTempDir($sTag)
    Return @TempDir & "\zwt-guncelleme-" & StringRegExpReplace($sTag, "[^\w.-]", "")
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

; GitHub API cevabından (release JSON) bir dosyanın indirme adresi; yoksa "".
Func _UpdateAssetUrl($sJson, $sName)
    Local $a = StringRegExp($sJson, '"browser_download_url"\s*:\s*"([^"]*/\Q' & $sName & '\E)"', 1)
    If @error Then Return ""
    Return $a[0]
EndFunc

; Dosyanın SHA256 özeti (küçük harf onaltılık).
Func _UpdateFileSha256($sPath)
    Local $bHash = _Crypt_HashFile($sPath, $CALG_SHA_256)
    If @error Then Return ""
    Return StringLower(StringTrimLeft(String($bHash), 2))
EndFunc

; Sürümü indirir, doğrular, $sDir\paket içine açar. Dönüş: paket klasörü ya da "" ($sErr nedeni taşır).
Func _UpdateDownload($sRepo, $sTag, $bLite, $sDir, ByRef $sErr)
    $sErr = ""
    Local $sAsset = _UpdateAssetName($sTag, $bLite)
    DirRemove($sDir, 1)
    DirCreate($sDir)
    ; 1) Release bilgisi
    Local $bJson = InetRead("https://api.github.com/repos/" & $sRepo & "/releases/tags/" & $sTag, $INET_FORCERELOAD)
    If @error Or BinaryLen($bJson) = 0 Then
        $sErr = "GitHub'a ulaşılamadı (sürüm bilgisi alınamadı)."
        Return ""
    EndIf
    Local $sJson = BinaryToString($bJson, $SB_UTF8)
    Local $sZipUrl = _UpdateAssetUrl($sJson, $sAsset), $sSumUrl = _UpdateAssetUrl($sJson, "SHA256SUMS.txt")
    If $sZipUrl = "" Or $sSumUrl = "" Then
        $sErr = "Bu sürümde " & $sAsset & " bulunamadı."
        Return ""
    EndIf
    If Not _UpdateUrlAllowed($sZipUrl, $sRepo) Or Not _UpdateUrlAllowed($sSumUrl, $sRepo) Then
        $sErr = "Beklenmeyen indirme adresi: " & $sZipUrl
        Return ""
    EndIf
    ; 2) İndirme
    Local $sZip = $sDir & "\" & $sAsset, $sSums = $sDir & "\SHA256SUMS.txt"
    InetGet($sSumUrl, $sSums, $INET_FORCERELOAD, $INET_DOWNLOADWAIT)
    InetGet($sZipUrl, $sZip, $INET_FORCERELOAD, $INET_DOWNLOADWAIT)
    If Not FileExists($sZip) Or Not FileExists($sSums) Then
        $sErr = "İndirme tamamlanamadı."
        Return ""
    EndIf
    ; 3) Özet doğrulama
    Local $sWant = _UpdateSumFor(FileRead($sSums), $sAsset)
    If $sWant = "" Then
        $sErr = "SHA256SUMS.txt içinde " & $sAsset & " yok."
        Return ""
    EndIf
    Local $sGot = _UpdateFileSha256($sZip)
    If $sGot <> $sWant Then
        $sErr = "İndirilen dosyanın özeti tutmuyor (bozuk ya da değiştirilmiş)."
        Return ""
    EndIf
    ; 4) Açma: Windows'un tar.exe'si (Windows 10 1803+)
    Local $sPkg = $sDir & "\paket"
    DirCreate($sPkg)
    RunWait('"' & @SystemDir & '\tar.exe" -xf "' & $sZip & '" -C "' & $sPkg & '"', $sDir, @SW_HIDE)
    If Not FileExists($sPkg & "\RedRiveRR Zapret" & ($bLite ? " Lite" : "") & ".exe") Then
        $sErr = "Paket açılamadı ya da içinde program yok."
        Return ""
    EndIf
    _LogInfo("Güncelleme: " & $sTag & " indirildi ve doğrulandı (" & $sGot & ")")
    Return $sPkg
EndFunc

; İndirilen yeni exe'yi kurulum kipinde başlatır: eski süreç ($iPid) kapanınca kopyalayıp yeni sürümü açar.
; $sArgs yeni sürüme verilir (ör. "/guncellendi v5.2.0 /devam-manuel").
Func _UpdateLaunchApply($iPid, $sPkg, $sDst, $sExe, $sArgs)
    Local $sNewExe = $sPkg & "\" & $sExe
    If Not FileExists($sNewExe) Then Return False
    Local $sCmd = '"' & $sNewExe & '" ' & $UPDATE_APPLY_ARG & ' ' & Int($iPid) & ' "' & $sPkg & '" "' & $sDst & '" "' & $sExe & '" ' & $sArgs
    Return Run($sCmd, $sPkg, @SW_HIDE) <> 0
EndFunc

; Kurulum kipi (yeni sürümün exe'sinde, geçici klasörden çalışır). Dönüş: çıkış kodu (0 = tamam).
;   $iPid: beklenecek eski süreç, $sPkg: açılmış paket, $sDst: kurulum klasörü, $sExe: açılacak exe adı,
;   $sArgs: yeni sürüme verilecek argümanlar. Kopyalama sonucu kurulumun logs\guncelleme.log dosyasına.
Func _UpdateApply($iPid, $sPkg, $sDst, $sExe, $sArgs)
    If $iPid > 0 Then ProcessWaitClose($iPid, 60)
    Sleep(700)
    DirCreate($sDst & "\logs")
    Local $sLog = $sDst & "\logs\guncelleme.log"
    Local $sOpt = ' /R:3 /W:1 /NP /NJH /NJS /NDL /LOG+:"' & $sLog & '"'
    Local $rc1 = RunWait('robocopy "' & $sPkg & '" "' & $sDst & '" /E /XD "' & $sPkg & '\config" "' & $sPkg & '\logs"' & $sOpt, "", @SW_HIDE)
    Local $rc2 = RunWait('robocopy "' & $sPkg & '\config" "' & $sDst & '\config" strategies.ini' & $sOpt, "", @SW_HIDE)
    Local $rc3 = RunWait('robocopy "' & $sPkg & '\config\varsayilan" "' & $sDst & '\config\varsayilan" /E' & $sOpt, "", @SW_HIDE)
    Local $bFail = ($rc1 >= 8 Or $rc2 >= 8 Or $rc3 >= 8)
    FileWriteLine($sLog, @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & " robocopy " & $rc1 & "/" & $rc2 & "/" & $rc3)
    Run('"' & $sDst & '\' & $sExe & '" ' & $sArgs & ($bFail ? " /guncelleme-hatasi" : ""), $sDst)
    Return $bFail ? 1 : 0
EndFunc
