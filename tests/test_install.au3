#include-once
#include "Assert.au3"
#include "..\lib\Install.au3"

Func _TestInstall()
    Local $aRoots[3] = ["C:\Program Files", "C:\Program Files (x86)", ""]
    _AssertTrue(_InstallIsUnderAny("C:\Program Files\Zapret Windows Turkiye", $aRoots), "Program Files altı korumalı")
    _AssertTrue(_InstallIsUnderAny("c:\program files (x86)\zapret", $aRoots), "x86, büyük/küçük harf duyarsız")
    _AssertFalse(_InstallIsUnderAny("C:\Users\Ali\zapret-fork", $aRoots), "kullanıcı klasörü korumasız")
    _AssertFalse(_InstallIsUnderAny("C:\Program Files Sahte\zapret", $aRoots), "benzer önekli klasör korumalı sayılmaz")
    _AssertTrue(_InstallIsProtected(@ProgramFilesDir & "\" & $INSTALL_DIR_NAME), "varsayılan hedef korumalı")
    _AssertFalse(_InstallIsProtected(@TempDir & "\zwt"), "geçici klasör korumasız")
    _AssertTrue(StringInStr(_InstallDefaultTarget(), @ProgramFilesDir) = 1, "varsayılan hedef Program Files'ta")

    ; --- Ana exe bulma (eski/yeni ad) ---
    Local $sTmp = @TempDir & "\zwt-exe-test-" & @MSEC
    DirCreate($sTmp)
    _AssertEq(_InstallFindExe($sTmp, "RedRiveRR Zapret.exe"), "", "exe yoksa boş")
    FileWrite($sTmp & "\zapret-win-turkey.exe", "x")
    _AssertEq(_InstallFindExe($sTmp, "RedRiveRR Zapret.exe"), $sTmp & "\zapret-win-turkey.exe", "eski adlı kurulum bulunur")
    FileWrite($sTmp & "\RedRiveRR Zapret.exe", "x")
    _AssertEq(_InstallFindExe($sTmp, "RedRiveRR Zapret.exe"), $sTmp & "\RedRiveRR Zapret.exe", "tercih edilen ad önce")
    DirRemove($sTmp, 1)

    ; --- Varsayılan listeler: yalnız eksikse kopyalanır, kullanıcının dosyası ezilmez ---
    Local $sRoot = @TempDir & "\zwt-cfg-test-" & @MSEC
    DirCreate($sRoot & "\config\varsayilan")
    _AssertEq(_InstallEnsureConfigDefaults($sRoot), 0, "varsayılan klasörü boşsa bir şey yapılmaz")
    FileWrite($sRoot & "\config\varsayilan\hostlist.txt", "discord.com")
    FileWrite($sRoot & "\config\varsayilan\excludelist.txt", "gov.tr")
    FileWrite($sRoot & "\config\varsayilan\autohostlist.txt", "")
    FileWrite($sRoot & "\config\hostlist.txt", "benim-sitem.example")
    _AssertEq(_InstallEnsureConfigDefaults($sRoot), 2, "eksik iki dosya kopyalanır")
    _AssertEq(FileRead($sRoot & "\config\hostlist.txt"), "benim-sitem.example", "kullanıcının listesi korunur")
    _AssertEq(FileRead($sRoot & "\config\excludelist.txt"), "gov.tr", "eksik liste varsayılandan gelir")
    _AssertTrue(FileExists($sRoot & "\config\autohostlist.txt"), "boş varsayılan da kopyalanır")
    _AssertEq(_InstallEnsureConfigDefaults($sRoot), 0, "ikinci çağrıda bir şey değişmez")
    DirRemove($sRoot, 1)
    Local $sBare = @TempDir & "\zwt-cfg-bos-" & @MSEC
    DirCreate($sBare)
    _AssertEq(_InstallEnsureConfigDefaults($sBare), 0, "config klasörü yoksa hata vermez")
    DirRemove($sBare, 1)
EndFunc
