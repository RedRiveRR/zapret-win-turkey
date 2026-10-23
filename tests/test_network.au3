#include-once
#include "Assert.au3"
#include "..\lib\Network.au3"

Func _TestNetwork()
    ; --- _IsDnsAnswerSafe ---
    _AssertTrue(_IsDnsAnswerSafe("162.159.135.232"), "Cloudflare yanıtı güvenli")
    _AssertTrue(_IsDnsAnswerSafe(@CRLF & " 162.159.128.233 " & @CRLF), "boşluklu yanıt kırpılır")
    _AssertFalse(_IsDnsAnswerSafe("195.175.254.2"), "TT zehirli IP")
    _AssertFalse(_IsDnsAnswerSafe(""), "boş yanıt (sorgu başarısız) güvenli değil")
    _AssertFalse(_IsDnsAnswerSafe("Exception calling GetHostAddresses"), "hata metni güvenli değil")
    _AssertFalse(_IsDnsAnswerSafe("10.0.0.1"), "bilinmeyen IP güvenli değil (mevcut davranış)")
    ; Sahadan (2026-10-22): ISS'nin discord.com için döndürdüğü zehirli IPv6 yanıtı.
    _AssertFalse(_IsDnsAnswerSafe("2a01:358:4014:a00::3"), "sahada görülen zehirli IPv6 yanıtı")
    _AssertFalse(_DnsAnswerNeedsRetry("2a01:358:4014:a00::3"), "zehirli IPv6 kesin yanıttır, yeniden denenmez")

    ; --- _DnsAnswerNeedsRetry (H7) ---
    _AssertTrue(_DnsAnswerNeedsRetry(""), "boş yanıt yeniden denenir")
    _AssertTrue(_DnsAnswerNeedsRetry("  " & @CRLF), "yalnızca boşluk yeniden denenir")
    _AssertTrue(_DnsAnswerNeedsRetry('Exception calling "GetHostAddresses" with "1" argument(s): "No such host is known"'), "PowerShell hata metni yeniden denenir")
    _AssertFalse(_DnsAnswerNeedsRetry("195.175.254.2"), "zehirli IP kesin yanıttır, yeniden denenmez")
    _AssertFalse(_DnsAnswerNeedsRetry("162.159.135.232" & @CRLF), "Cloudflare IP yeniden denenmez")
    _AssertFalse(_DnsAnswerNeedsRetry("2606:4700::6810:84e5"), "IPv6 yanıt yeniden denenmez")

    ; --- _DnsIsPoisonVerdict (H17): yanıtsız DNS + internet yok = zehirlenme değil ---
    Local $sNoHost = 'Exception calling "GetHostAddresses" with "1" argument(s): "No such host is known"'
    _AssertFalse(_DnsIsPoisonVerdict($sNoHost, False), "H17: internet yokken yanıtsız DNS zehirli sayılmaz")
    _AssertFalse(_DnsIsPoisonVerdict("", False), "H17: internet yokken boş yanıt zehirli sayılmaz")
    _AssertTrue(_DnsIsPoisonVerdict($sNoHost, True), "internet varken DNS hiç çözmüyorsa sorunlu sayılır")
    _AssertTrue(_DnsIsPoisonVerdict("195.175.254.2", False), "kesin zehirli yanıt internetten bağımsız zehirli")
    _AssertFalse(_DnsIsPoisonVerdict("162.159.135.232", True), "Cloudflare yanıtı temiz")

    ; --- _NetWithAdapter ---
    Local $sScript = _NetWithAdapter("Write-Output x")
    _AssertTrue(StringLeft($sScript, StringLen($NET_PS_SELECT_ADAPTER)) == $NET_PS_SELECT_ADAPTER, "bağdaştırıcı seçimiyle başlar")
    _AssertTrue(StringInStr($sScript, "if ($adapter) { Write-Output x } else { exit " & $NET_EXIT_NO_ADAPTER & " }") > 0, "H4: bağdaştırıcı yoksa ayrı çıkış kodu")
    _AssertFalse(StringInStr($sScript, '"') > 0, "betik çift tırnak içermez (-Command ile güvenli)")
    _AssertFalse(StringInStr($NET_PS_SELECT_ADAPTER, '"') > 0, "bağdaştırıcı seçimi çift tırnak içermez")
EndFunc
