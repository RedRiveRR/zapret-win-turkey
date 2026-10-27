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

; Ağ paylaşımı açık mı (Aşama 2.8; önceden "[ ✓ ] Paylaşım Aktif / Durdur" düğme metninden okunuyordu).
Global $g_bStateLanOn = False

Func _StateSetLanOn($bOn)
    $g_bStateLanOn = IsBool($bOn) ? $bOn : (Number($bOn) <> 0)
EndFunc

Func _StateLanOn()
    Return $g_bStateLanOn
EndFunc
