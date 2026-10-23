#include-once
#include "Assert.au3"
#include "..\lib\Install.au3"

Func _TestInstall()
    Local $aRoots[3] = ["C:\Program Files", "C:\Program Files (x86)", ""]
    _AssertTrue(_InstallIsUnderAny("C:\Program Files\Zapret Windows Turkiye", $aRoots), "Program Files altı korumalı")
    _AssertTrue(_InstallIsUnderAny("c:\program files (x86)\zapret", $aRoots), "x86, büyük/küçük harf duyarsız")
    _AssertFalse(_InstallIsUnderAny("C:\Users\adaki\zapret-fork", $aRoots), "kullanıcı klasörü korumasız")
    _AssertFalse(_InstallIsUnderAny("C:\Program Files Sahte\zapret", $aRoots), "benzer önekli klasör korumalı sayılmaz")
    _AssertTrue(_InstallIsProtected(@ProgramFilesDir & "\" & $INSTALL_DIR_NAME), "varsayılan hedef korumalı")
    _AssertFalse(_InstallIsProtected(@TempDir & "\zwt"), "geçici klasör korumasız")
    _AssertTrue(StringInStr(_InstallDefaultTarget(), @ProgramFilesDir) = 1, "varsayılan hedef Program Files'ta")
EndFunc
