#include-once
#include <AutoItConstants.au3>

; =========================================================================
; --- GÖREV ZAMANLAYICI (yalnız eski görevin kaldırılması) ---
; v5.2.2'ye kadar sağlık kontrolü oturum açılışında, 30 dk'da bir ve ağ olayıyla çalışan,
; "en yüksek ayrıcalıklarla" bir zamanlanmış görevdi. Defender bunu kendini kalıcı kılma
; davranışı saydı ve exe'yi karantinaya aldı (H32). Program artık görev oluşturmaz; bu modül
; yalnız eski kurulumlardan kalan görevi bulup siler. Kontrol program içinde (lib/Health.au3).
; =========================================================================

Func _ScheduleRemove($sTaskName)
    Return RunWait(@ComSpec & ' /c schtasks /Delete /TN "' & $sTaskName & '" /F', "", @SW_HIDE)
EndFunc

Func _ScheduleExists($sTaskName)
    Return RunWait(@ComSpec & ' /c schtasks /Query /TN "' & $sTaskName & '"', "", @SW_HIDE) = 0
EndFunc
