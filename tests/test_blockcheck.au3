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

    ; --- _BlockcheckLooksUnparsed ---
    _AssertFalse(_BlockcheckLooksUnparsed($sLog, 2), "strateji bulunduysa sorun yok")
    _AssertFalse(_BlockcheckLooksUnparsed("- iana.org test" & @LF & "!!!!! AVAILABLE !!!!!", 0), "yalnız iana.org AVAILABLE sorun değil")
    _AssertFalse(_BlockcheckLooksUnparsed("UNAVAILABLE code=35", 0), "hiç AVAILABLE yoksa sorun değil (gerçekten bulunamadı)")
    _AssertTrue(_BlockcheckLooksUnparsed("- curl roblox.com : winws2 --yeni-bicim-443 --lua-desync=fake" & @LF & "!!!!! AVAILABLE !!!!!", 0), _
            "AVAILABLE var ama --wf-tcp-out=443 biçimi yoksa okunamadı")

    ; --- _ParseSummaryStrategy (Zapret1) ---
    Local $sSummary = "test satırı" & @CRLF & "* SUMMARY" & @CRLF & _
            "ipv4 discord.com curl_test_https_tls12 : winws --wf-tcp=443 --dpi-desync=fake --dpi-desync-ttl=4 " & @CRLF & "son"
    _AssertEq(_ParseSummaryStrategy($sSummary), "--dpi-desync=fake --dpi-desync-ttl=4", "SUMMARY sonrası strateji alınır")
    _AssertEq(_ParseSummaryStrategy("a" & @LF & "* SUMMARY"), "", "H3: SUMMARY son satırdaysa çökmez, boş döner")
    _AssertEq(_ParseSummaryStrategy("* SUMMARY" & @LF & "--dpi-desync=eski" & @LF & "* SUMMARY" & @LF & "strateji yok"), _
            "--dpi-desync=eski", "son SUMMARY'de strateji yoksa öncekine bakılır")
    _AssertEq(_ParseSummaryStrategy(""), "", "boş log")

    ; --- H38: analiz yalnız roblox.com'u deniyordu; Roblox açık, Discord engelli hatlarda "engel yok" deyip bitiyordu ---
    _AssertEq(StringLeft($BLOCKCHECK_DOMAINS, 12), "discord.com ", "H38: önce discord.com denenir")
    _AssertTrue(StringInStr(" " & $BLOCKCHECK_DOMAINS & " ", " roblox.com ") > 0, "H38: roblox.com da denenir")
    Local $sFreeLog2 = "* SUMMARY" & @LF & "curl_test_https_tls12 ipv4 roblox.com : working without bypass" & @LF
    _AssertFalse(_BlockcheckNoBypassNeeded($sFreeLog2, "discord.com roblox.com"), "H38: yalnız roblox engelsizse engel yok denmez")
    _AssertTrue(_BlockcheckNoBypassNeeded($sFreeLog2, "roblox.com"), "tek hedef engelsizse engel yok")
    _AssertTrue(_BlockcheckNoBypassNeeded("curl_test_https_tls12 ipv4 discord.com : working without bypass" & @LF & $sFreeLog2, "discord.com roblox.com"), _
            "iki hedef de engelsizse engel yok (Zapret2 biçimi)")
    _AssertTrue(_BlockcheckNoBypassNeeded("ipv4 discord.com curl_test_https_tls12 : working without bypass" & @CRLF & _
            "ipv4 roblox.com curl_test_https_tls12 : working without bypass" & @CRLF, "discord.com roblox.com"), "Zapret1 biçimi")
    _AssertFalse(_BlockcheckNoBypassNeeded("ipv4 cdn.discord.com.tr x : working without bypass", "discord.com"), "alan adı tam eşleşir")
    _AssertFalse(_BlockcheckNoBypassNeeded("", "discord.com"), "boş log engel yok sayılmaz")
    ; Engelsiz hedefin "- checking without DPI bypass" ardından gelen AVAILABLE'ı okunamayan sonuç değildir.
    _AssertFalse(_BlockcheckLooksUnparsed("* curl_test_https_tls12 ipv4 roblox.com" & @LF & "- checking without DPI bypass" & @LF & "!!!!! AVAILABLE !!!!!", 0), _
            "H38: engelsiz hedefin AVAILABLE satırı 'okunamadı' sayılmaz")
    ; Zapret1: iki hedefte SUMMARY'nin ilk satırı engelsiz hedef olabilir; bloktaki strateji alınır.
    _AssertEq(_ParseSummaryStrategy("* SUMMARY" & @LF & "ipv4 roblox.com curl_test_https_tls12 : working without bypass" & @LF & _
            "ipv4 discord.com curl_test_https_tls12 : winws --wf-tcp=443 --dpi-desync=fake --dpi-desync-ttl=4" & @LF & @LF & "Please note"), _
            "--dpi-desync=fake --dpi-desync-ttl=4", "H38: SUMMARY bloğunun ikinci satırındaki strateji alınır")
EndFunc
