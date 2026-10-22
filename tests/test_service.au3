#include-once
#include "Assert.au3"
#include "..\lib\Service.au3"

Func _TestService()
    ; --- _ServiceBuildBinPath (eski InstallServiceClean ile aynı kaçışlama) ---
    _AssertEq(_ServiceBuildBinPath("C:\Z\winws2.exe", '--a="x y" --b=1'), '\"C:\Z\winws2.exe\" --a=\"x y\" --b=1', "iç tırnaklar kaçışlanır")

    ; --- _ServiceParseState ---
    Local $sRunning = "SERVICE_NAME: ZapretService" & @CRLF & "        TYPE               : 10  WIN32_OWN_PROCESS" & @CRLF & _
            "        STATE              : 4  RUNNING" & @CRLF & "                                (STOPPABLE, NOT_PAUSABLE, IGNORES_SHUTDOWN)"
    _AssertEq(_ServiceParseState($sRunning), "RUNNING", "çalışıyor")
    _AssertEq(_ServiceParseState(StringReplace($sRunning, "4  RUNNING", "1  STOPPED")), "STOPPED", "durmuş")
    _AssertEq(_ServiceParseState("[SC] EnumQueryServicesStatus:OpenService FAILED 1060:" & @CRLF & "Belirtilen hizmet yok."), "", "kurulu değil")
    _AssertEq(_ServiceParseState("SERVICE_NAME: X" & @CRLF & "garip çıktı"), "UNKNOWN", "STATE satırı yoksa UNKNOWN")

    ; --- _ServiceParseStartType / _ServiceParseBinPath ---
    Local $sQc = "[SC] QueryServiceConfig SUCCESS" & @CRLF & @CRLF & "SERVICE_NAME: ZapretService" & @CRLF & _
            "        TYPE               : 10  WIN32_OWN_PROCESS" & @CRLF & _
            "        START_TYPE         : 2   AUTO_START  (DELAYED)" & @CRLF & _
            "        ERROR_CONTROL      : 1   NORMAL" & @CRLF & _
            '        BINARY_PATH_NAME   : "C:\Z\winws2.exe" --wf-l3=ipv4 --payload="tls_client_hello"  ' & @CRLF & _
            "        DISPLAY_NAME       : ZapretService"
    _AssertEq(_ServiceParseStartType($sQc), "AUTO_START (DELAYED)", "gecikmeli otomatik")
    _AssertEq(_ServiceParseStartType(StringReplace($sQc, "  (DELAYED)", "")), "AUTO_START", "otomatik")
    _AssertEq(_ServiceParseBinPath($sQc), '"C:\Z\winws2.exe" --wf-l3=ipv4 --payload="tls_client_hello"', "binPath okunur, sondaki boşluk atılır")
    _AssertEq(_ServiceParseBinPath("yok"), "", "binPath yoksa boş")

    ; --- Gerçek sorgu: var olmayan servis (yetki gerektirmez, hiçbir şeyi değiştirmez) ---
    _AssertEq(_ServiceGetState("zwt-olmayan-servis-123"), "", "olmayan servis kurulu değil")
    _AssertFalse(_ServiceIsInstalled("zwt-olmayan-servis-123"), "olmayan servis kurulu sayılmaz")
EndFunc
