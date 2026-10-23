#include-once

; =========================================================================
; Programın durumu (arayüzden bağımsız). Eski arayüzde bu bilgi denetimlerin
; metninde duruyordu; yeni arayüze tam geçiş için tek kaynak burasıdır
; (bkz. vault "Geçiş Planı - Yeni Arayüz", Aşama 2). GUI'ye bağlı değildir.
; =========================================================================

; Ana durum metni ("ÇALIŞMAYA HAZIR", "SERVİS MODU AKTİF", "DNS ZEHİRLENMESİ SAPTANDI!" ...)
Global $g_sStateStatus = "SİSTEM HAZIRLANIYOR..."

Func _StateSetStatus($sStatus)
    $g_sStateStatus = String($sStatus)
EndFunc

Func _StateStatus()
    Return $g_sStateStatus
EndFunc
