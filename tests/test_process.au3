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

    ; --- _CloseProcessesByName ---
    Local $aNone[1] = ["zwt-olmayan-surec-12345.exe"]
    Local $hTimer = TimerInit()
    _AssertTrue(_CloseProcessesByName($aNone, 2000), "çalışmayan süreç için hemen True")
    _AssertTrue(TimerDiff($hTimer) < 1000, "çalışmayan süreçte zaman aşımı beklenmez")

    ; Gerçek bir süreci kapat: PING.EXE benzersiz adla kopyalanır, böylece başka süreçlere dokunulmaz.
    Local $sCopy = @TempDir & "\zwt-test-sleeper.exe"
    FileCopy(@SystemDir & "\PING.EXE", $sCopy, 1)
    Local $iPid = Run('"' & $sCopy & '" -n 30 127.0.0.1', "", @SW_HIDE)
    _AssertTrue($iPid > 0 And ProcessExists($iPid) > 0, "test süreci başladı")
    Local $aSleeper[1] = ["zwt-test-sleeper.exe"]
    _AssertTrue(_CloseProcessesByName($aSleeper, 3000), "H5: çalışan süreç kapatılır")
    _AssertFalse(ProcessExists($iPid) > 0, "süreç gerçekten kapandı")
    FileDelete($sCopy)
EndFunc
