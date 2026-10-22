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

_TestProcess()
_TestBlockcheck()
_TestNetwork()
_TestWinws()
_TestStrategies()
_TestLog()
_TestConflicts()

Exit _AssertSummary()
