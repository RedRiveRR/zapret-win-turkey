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

    ; --- _NetWithAdapter ---
    Local $sScript = _NetWithAdapter("Write-Output x")
    _AssertTrue(StringLeft($sScript, StringLen($NET_PS_SELECT_ADAPTER)) == $NET_PS_SELECT_ADAPTER, "bağdaştırıcı seçimiyle başlar")
    _AssertTrue(StringInStr($sScript, "if ($adapter) { Write-Output x } else { exit " & $NET_EXIT_NO_ADAPTER & " }") > 0, "H4: bağdaştırıcı yoksa ayrı çıkış kodu")
    _AssertFalse(StringInStr($sScript, '"') > 0, "betik çift tırnak içermez (-Command ile güvenli)")
    _AssertFalse(StringInStr($NET_PS_SELECT_ADAPTER, '"') > 0, "bağdaştırıcı seçimi çift tırnak içermez")
EndFunc
