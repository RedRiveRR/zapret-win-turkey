#include-once
#include "Assert.au3"
#include "..\lib\Process.au3"

Func _TestProcess()
    Local $sDir = "C:\Apps\zapret-win-turkey\bin\zapret"

    _AssertTrue(_PathIsUnderDir("C:\Apps\zapret-win-turkey\bin\zapret\cygwin\bin\bash.exe", $sDir), "alt klasördeki bash eşleşir")
    _AssertTrue(_PathIsUnderDir("c:\apps\ZAPRET-WIN-TURKEY\bin\zapret\winws2.exe", $sDir), "büyük/küçük harf duyarsız")
    _AssertTrue(_PathIsUnderDir("C:/Apps/zapret-win-turkey/bin/zapret/x.exe", $sDir), "ileri eğik çizgi kabul edilir")
    _AssertTrue(_PathIsUnderDir("C:\Apps\zapret-win-turkey\bin\zapret\x.exe", $sDir & "\"), "sondaki ters eğik çizgi önemsiz")
    _AssertFalse(_PathIsUnderDir("C:\Program Files\Git\usr\bin\bash.exe", $sDir), "Git Bash eşleşmez")
    _AssertFalse(_PathIsUnderDir("C:\Apps\zapret-win-turkey\bin\zapret2\bash.exe", $sDir), "benzer önekli kardeş klasör eşleşmez")
    _AssertFalse(_PathIsUnderDir("", $sDir), "boş yol eşleşmez")
    _AssertFalse(_PathIsUnderDir(Null, $sDir), "Null yol (erişilemeyen süreç) eşleşmez")
    _AssertFalse(_PathIsUnderDir("C:\x.exe", ""), "boş klasör hiçbir şeyle eşleşmez")
EndFunc
