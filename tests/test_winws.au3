#include-once
#include "Assert.au3"
#include "..\lib\Winws.au3"

; Beklenen çıktılar, refactor öncesi StartWinws / InstallServiceClean /
; _BuildStrategyTestCommand kodunun ürettiği dizgilerle birebir aynıdır.
Func _TestWinws()
    Local $sExe2 = "C:\Z\bin\zapret\zapret-winws\winws2.exe"
    Local $sExe1 = "C:\Z\bin\zapret\zapret-winws\winws.exe"
    Local $sEx = "C:\Z\config\excludelist.txt"
    Local $sAuto = "C:\Z\config\autohostlist.txt"
    Local $sHost = "C:\Z\config\hostlist.txt"
    Local $sLua = ' --lua-init="@C:\Z\bin\zapret\zapret-winws\lua\zapret-lib.lua"' & _
            ' --lua-init="@C:\Z\bin\zapret\zapret-winws\lua\zapret-antidpi.lua"' & _
            ' --lua-init="@C:\Z\bin\zapret\zapret-winws\lua\zapret-auto.lua"'
    Local $sS2 = "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
    Local $sS1 = "--dpi-desync=fake --dpi-desync-ttl=4"

    ; --- _WinwsFilterModeFromText ---
    _AssertEq(_WinwsFilterModeFromText("Auto (Zapret oluşturur)"), $WINWS_FILTER_AUTO, "Auto metni")
    _AssertEq(_WinwsFilterModeFromText("Manuel ('hostlist.txt' İçeriği)"), $WINWS_FILTER_MANUAL, "Manuel metni")
    _AssertEq(_WinwsFilterModeFromText("Kapalı (Tüm trafik)"), $WINWS_FILTER_OFF, "Kapalı metni")
    _AssertEq(_WinwsFilterModeFromText("Filtre Uygulanamaz"), $WINWS_FILTER_OFF, "OOB kilidi metni")

    ; --- _BuildWinwsArgs ---
    _AssertEq(_BuildWinwsArgs("Zapret2", $sExe2, $sS2, $WINWS_FILTER_AUTO, $sEx, $sAuto, $sHost), _
            '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 --hostlist-exclude="' & $sEx & '" ' & $sS2 & $sLua & ' --hostlist-auto="' & $sAuto & '"', _
            "Zapret2 + auto filtre")
    _AssertEq(_BuildWinwsArgs("Zapret2", $sExe2, $sS2, $WINWS_FILTER_OFF, $sEx, $sAuto, $sHost), _
            '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 --hostlist-exclude="' & $sEx & '" ' & $sS2 & $sLua, _
            "Zapret2 + filtre kapalı")
    _AssertEq(_BuildWinwsArgs("Zapret1", $sExe1, $sS1, $WINWS_FILTER_MANUAL, $sEx, $sAuto, $sHost), _
            '--wf-tcp=0-65535 --wf-udp=0-65535 --hostlist-exclude="' & $sEx & '" ' & $sS1 & ' --hostlist="' & $sHost & '"', _
            "Zapret1 + manuel filtre")
    _AssertEq(_BuildWinwsArgs("Zapret2", $sExe2, "--lua-desync=oob", $WINWS_FILTER_AUTO, $sEx, $sAuto, $sHost), _
            '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 --lua-desync=oob' & $sLua, _
            "OOB: exclude ve hostlist eklenmez")
    _AssertEq(_BuildWinwsArgs("Zapret2", $sExe2, $sS2, $WINWS_FILTER_OFF), _
            '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 ' & $sS2 & $sLua, _
            "strateji testi: filtresiz, exclude'suz")

    ; --- _EnsureHostlistFile ---
    Local $sTmpAuto = @TempDir & "\zwt-test-auto.txt", $sTmpHost = @TempDir & "\zwt-test-host.txt"
    FileDelete($sTmpAuto)
    FileDelete($sTmpHost)
    _EnsureHostlistFile($WINWS_FILTER_MANUAL, $sS2, $sTmpAuto, $sTmpHost)
    _AssertEq(FileRead($sTmpHost), "discord.com" & @CRLF & "updates.discord.com", "manuel hostlist varsayılanla oluşturulur")
    _AssertFalse(FileExists($sTmpAuto), "manuel modda auto dosyası oluşturulmaz")
    FileDelete($sTmpHost)
    _EnsureHostlistFile($WINWS_FILTER_MANUAL, "--x=oob", $sTmpAuto, $sTmpHost)
    _AssertFalse(FileExists($sTmpHost), "OOB stratejide dosya oluşturulmaz")
EndFunc
