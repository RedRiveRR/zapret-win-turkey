#include-once
#include "Assert.au3"
#include "..\lib\Blockcheck.au3"

Func _TestBlockcheck()
    ; --- _FormatStrategyQuotes ---
    _AssertEq(_FormatStrategyQuotes("--dpi-desync=fake --dpi-desync-ttl=4"), '--dpi-desync="fake" --dpi-desync-ttl="4"', "değerler tırnaklanır")
    _AssertEq(_FormatStrategyQuotes("--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"), _
            '--payload="tls_client_hello" --lua-desync="multidisorder:pos=2:seqovl=1"', "yalnızca ilk = bölünür")
    _AssertEq(_FormatStrategyQuotes("--nodrop"), "--nodrop", "değersiz parametre aynen kalır")
    _AssertEq(_FormatStrategyQuotes("  --a=1  "), '--a="1"', "baştaki/sondaki boşluk atılır")

    ; --- _CollectStrategiesFromText ---
    Local $sLog = "- curl_test_https_tls12 ipv4 discord.com : winws2 --wf-l3=ipv4 --wf-tcp-out=443 --lua-desync=fake:blob=0x00" & @CRLF & _
            "!!!!! AVAILABLE !!!!!" & @CRLF & _
            "- curl_test_https_tls12 ipv4 iana.org : winws2 --wf-tcp-out=443 --lua-desync=iana" & @CRLF & _
            "!!!!! AVAILABLE !!!!!" & @CRLF & _
            "- curl_test_https_tls12 ipv4 discord.com : winws2 --wf-l3=ipv4 --wf-tcp-out=443 --lua-desync=fake:blob=0x00" & @CRLF & _
            "!!!!! AVAILABLE !!!!!" & @CRLF & _
            "- curl_test_https_tls12 ipv4 discord.com : winws2 --wf-l3=ipv4 --wf-tcp-out=443 --lua-desync=multisplit:pos=2" & @CRLF & _
            "!!!!! AVAILABLE !!!!!" & @CRLF & _
            "- başarısız deneme --wf-tcp-out=443 --lua-desync=oob" & @CRLF & _
            "UNAVAILABLE"
    Local $aFound[1] = [0]
    _CollectStrategiesFromText($sLog, $aFound)
    _AssertEq($aFound[0], 2, "iana.org ve tekrarlar atlanır, 2 strateji bulunur")
    If $aFound[0] = 2 Then
        _AssertEq($aFound[1], '--lua-desync="fake:blob=0x00"', "ilk strateji")
        _AssertEq($aFound[2], '--lua-desync="multisplit:pos=2"', "ikinci strateji")
    EndIf

    ; Aynı diziye ikinci kez toplanınca tekrar eklenmez (analiz sırasında log her saniye yeniden okunur).
    _CollectStrategiesFromText($sLog, $aFound)
    _AssertEq($aFound[0], 2, "tekrar okumada strateji sayısı değişmez")

    Local $aEmpty[1] = [0]
    _CollectStrategiesFromText("!!!!! AVAILABLE !!!!!", $aEmpty)
    _AssertEq($aEmpty[0], 0, "tek satırlık log çökmez")

    ; --- _ParseSummaryStrategy (Zapret1) ---
    Local $sSummary = "test satırı" & @CRLF & "* SUMMARY" & @CRLF & _
            "ipv4 discord.com curl_test_https_tls12 : winws --wf-tcp=443 --dpi-desync=fake --dpi-desync-ttl=4 " & @CRLF & "son"
    _AssertEq(_ParseSummaryStrategy($sSummary), "--dpi-desync=fake --dpi-desync-ttl=4", "SUMMARY sonrası strateji alınır")
    _AssertEq(_ParseSummaryStrategy("a" & @LF & "* SUMMARY"), "", "H3: SUMMARY son satırdaysa çökmez, boş döner")
    _AssertEq(_ParseSummaryStrategy("* SUMMARY" & @LF & "--dpi-desync=eski" & @LF & "* SUMMARY" & @LF & "strateji yok"), _
            "--dpi-desync=eski", "son SUMMARY'de strateji yoksa öncekine bakılır")
    _AssertEq(_ParseSummaryStrategy(""), "", "boş log")
EndFunc
