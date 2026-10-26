; =========================================================================
; Birim testleri — GUI ve yönetici yetkisi gerektirmez.
; Çalıştırma: AutoIt3_x64.exe /ErrorStdOut tests\run_tests.au3
; Çıkış kodu: 0 = tüm testler geçti, 1 = en az bir test başarısız.
; =========================================================================
#include "Assert.au3"
#include "test_process.au3"
#include "test_blockcheck.au3"
#include "test_network.au3"
#include "test_winws.au3"
#include "test_strategies.au3"
#include "test_log.au3"
#include "test_conflicts.au3"
#include "test_update.au3"
#include "test_diag.au3"
#include "test_smart.au3"
#include "test_service.au3"
#include "test_health.au3"
#include "test_install.au3"
#include "test_webmsg.au3"
#include "test_webstate.au3"
#include "test_appstate.au3"
#include "test_lanshare.au3"

_TestProcess()
_TestBlockcheck()
_TestNetwork()
_TestWinws()
_TestStrategies()
_TestLog()
_TestConflicts()
_TestUpdate()
_TestDiag()
_TestSmart()
_TestService()
_TestHealth()
_TestInstall()
_TestWebMsg()
_TestWebState()
_TestAppState()
_TestLanShare()

Exit _AssertSummary()
