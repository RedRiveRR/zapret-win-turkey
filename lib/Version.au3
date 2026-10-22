#include-once

; =========================================================================
; --- SÜRÜM BİLGİSİ ---
; Uygulama ve motor sürümleri tek yerde tutulur.
; NOT: Ana betiklerdeki #AutoIt3Wrapper_Res_Fileversion / ProductVersion
; yönergeleri derleyici tarafından okunduğu için sabit kullanamaz;
; sürüm değiştiğinde onları da güncelleyin (scripts/check.ps1 uyumsuzluğu yakalar).
; =========================================================================

Global Const $APP_VERSION = "4.5"
Global Const $APP_NAME = "Zapret Windows Türkiye"
Global Const $ENGINE_ZAPRET2_VERSION = "1.0.5.2"
Global Const $ENGINE_ZAPRET1_VERSION = "72.12"

; Güncelleme kontrolünde sorgulanan GitHub deposu ve kullanıcıya gösterilen sürümler sayfası.
; Fork kendi sürümlerine bakar: upstream (alimali54) sürümleri bu fork'taki geliştirmeleri
; içermez; oraya yönlendirmek kullanıcının bu özellikleri kaybetmesine yol açar.
Global Const $APP_UPDATE_REPO = "RedRiveRR/zapret-win-turkey"
Global Const $APP_RELEASES_URL = "https://github.com/" & $APP_UPDATE_REPO & "/releases"
