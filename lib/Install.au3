#include-once
#include <FileConstants.au3>
#include "Process.au3"
#include "Log.au3"

; =========================================================================
; --- KURULUM KONUMU GÜVENLİĞİ ---
; Servis (winws2, SYSTEM) ve otomatik onarım görevi (yönetici) bu klasördeki
; dosyaları yükseltilmiş yetkiyle çalıştırır. Klasör kullanıcının yazabildiği bir
; yerdeyse (ör. C:\Users\...), kullanıcı hesabıyla çalışan herhangi bir program
; exe'yi değiştirip UAC'siz yönetici/SYSTEM yetkisi kazanabilir. Yalnız klasörün
; izinlerini kısmak yetmez: üst klasör yazılabilirse klasör yeniden adlandırılıp
; yerine sahtesi konabilir. Bu yüzden önerilen konum Program Files'tır.
; =========================================================================

Global Const $INSTALL_DIR_NAME = "Zapret Windows Turkiye"

; $sDir, verilen köklerden birinin altında mı? (saf; birim testli)
Func _InstallIsUnderAny($sDir, $aRoots)
    For $sRoot In $aRoots
        If $sRoot <> "" And _PathIsUnderDir($sDir & "\", $sRoot) Then Return True
    Next
    Return False
EndFunc

; Yalnız yöneticinin yazabildiği standart konumlar.
Func _InstallProtectedRoots()
    Local $a[3] = [@ProgramFilesDir, EnvGet("ProgramFiles(x86)"), @WindowsDir]
    Return $a
EndFunc

Func _InstallIsProtected($sDir)
    Return _InstallIsUnderAny($sDir, _InstallProtectedRoots())
EndFunc

Func _InstallDefaultTarget()
    Return @ProgramFilesDir & "\" & $INSTALL_DIR_NAME
EndFunc

; Kurulumu $sDst'ye kopyalar (config ve loglar dahil). Hedefte exe varsa True.
Func _InstallRelocate($sSrc, $sDst, $sExeName)
    _LogInfo("Kurulum taşınıyor: " & $sSrc & " -> " & $sDst)
    If Not DirCopy($sSrc, $sDst, $FC_OVERWRITE) Then
        _LogError("Kurulum kopyalanamadı: " & $sDst)
        Return False
    EndIf
    Return FileExists($sDst & "\" & $sExeName)
EndFunc

; Servis kurulmadan önce çağrılır. Dönüş:
;   "devam" = burada kur, "taşındı" = yeni konumdan açıldı (çağıran programı kapatmalı), "iptal"
Func _InstallCheckBeforeService($sExeName)
    If _InstallIsProtected(@ScriptDir) Then Return "devam"
    Local $sDst = _InstallDefaultTarget()
    Local $iAns = MsgBox(3 + 48 + 8192, "Kurulum Konumu", _
            "Program şu klasörde: " & @ScriptDir & @CRLF & @CRLF & _
            "Servis ve otomatik onarım bu klasördeki dosyaları yönetici yetkisiyle çalıştırır. Klasör sıradan programların " & _
            "değiştirebileceği bir yerde olduğu için, zararlı bir program bu yolla yönetici yetkisi kazanabilir." & @CRLF & @CRLF & _
            "Program şuraya taşınıp servis oradan kurulsun mu? (önerilen)" & @CRLF & $sDst & @CRLF & @CRLF & _
            "Evet: taşı ve yeni konumdan aç    Hayır: yine de burada kur    İptal: vazgeç")
    If $iAns = 2 Then Return "iptal"
    If $iAns = 7 Then
        _LogWarn("Kullanıcı korumasız konumda servis kurmayı seçti: " & @ScriptDir)
        Return "devam"
    EndIf
    If Not _InstallRelocate(@ScriptDir, $sDst, $sExeName) Then
        MsgBox(16 + 8192, "Kurulum Konumu", "Program taşınamadı. Servis kurulmadı; logs\app.log dosyasına bakın.")
        Return "iptal"
    EndIf
    MsgBox(64 + 8192, "Kurulum Konumu", "Program taşındı:" & @CRLF & $sDst & @CRLF & @CRLF & _
            "Şimdi yeni konumdan açılacak; oradan 'Servis Olarak Yükle'ye tekrar basın." & @CRLF & _
            "Eski klasörü (" & @ScriptDir & ") daha sonra silebilirsiniz.")
    ShellExecute($sDst & "\" & $sExeName, "", $sDst)
    Return "taşındı"
EndFunc
