#include-once
#include "Assert.au3"
#include "..\lib\WebMsg.au3"

Func _TestWebMsg()
    ; --- _WebJsonGet ---
    Local $sMsg = '{"tip":"komut","ad":"durdur"}'
    _AssertEq(_WebJsonGet($sMsg, "tip"), "komut", "metin alanı okunur")
    _AssertEq(_WebJsonGet($sMsg, "ad"), "durdur", "ikinci alan okunur")
    Local $sNone = _WebJsonGet($sMsg, "yok")
    Local $iErr = @error
    _AssertEq($sNone, "", "olmayan alan boş döner")
    _AssertEq($iErr, 1, "olmayan alanda @error=1")
    _AssertEq(_WebJsonGet('{ "tip" : "hazir" }', "tip"), "hazir", "boşluklu yazım okunur")
    _AssertEq(_WebJsonGet('{"metin":"a \"b\" c\\d"}', "metin"), 'a "b" c\d', "kaçışlı tırnak ve ters bölü çözülür")
    _AssertEq(_WebJsonGet('{"m":"Ba\u011flant\u0131"}', "m"), "Bağlantı", "\u kaçışı Türkçe harfe çevrilir")
    _AssertEq(_WebJsonGet('{"m":"x\ny"}', "m"), "x" & @LF & "y", "\n satır sonuna çevrilir")
    _AssertEq(_WebJsonGet('{"sira":3,"acik":true}', "sira"), "3", "sayı düz metin döner")
    _AssertEq(_WebJsonGet('{"sira":3,"acik":true}', "acik"), "true", "true düz metin döner")
    _AssertEq(_WebJsonGet('{"a.b":"x","ab":"y"}', "a.b"), "x", "anahtardaki nokta düzenli ifade gibi yorumlanmaz")

    ; --- _WebJsonStr / _WebJsonObj ---
    _AssertEq(_WebJsonStr('a"b\c'), '"a\"b\\c"', "tırnak ve ters bölü kaçışlanır")
    _AssertEq(_WebJsonStr("x" & @CRLF & "y"), '"x\r\ny"', "satır sonları kaçışlanır")
    _AssertEq(_WebJsonStr("Bağlantı"), '"Bağlantı"', "Türkçe harfler olduğu gibi kalır")
    _AssertEq(_WebJsonObj("tip", "durum", "mod", "Servis çalışıyor"), '{"tip":"durum","mod":"Servis çalışıyor"}', "nesne kurulur")
    _AssertEq(_WebJsonObj("ms", 92, "acik", True), '{"ms":92,"acik":true}', "sayı ve Boolean tırnaksız")
    Local $sRound = _WebJsonObj("metin", 'Yol "açık"' & @LF & "C:\x")
    _AssertEq(_WebJsonGet($sRound, "metin"), 'Yol "açık"' & @LF & "C:\x", "kur-oku gidiş dönüşü aynı metni verir")

    ; --- _WebJsonAdd ---
    Local $sObj = _WebJsonAdd("{}", "tip", "durum")
    _AssertEq($sObj, '{"tip":"durum"}', "boş nesneye ilk alan eklenir")
    $sObj = _WebJsonAdd($sObj, "calisiyor", True)
    $sObj = _WebJsonAdd($sObj, "baslik", "Discord'a yol açık")
    _AssertEq($sObj, '{"tip":"durum","calisiyor":true,"baslik":"Discord' & "'" & 'a yol açık"}', "zincirleme alanlar virgülle eklenir")
    _AssertEq(_WebJsonGet($sObj, "baslik"), "Discord'a yol açık", "zincirleme nesne okunabilir")

    ; --- _WebFileUrl ---
    _AssertEq(_WebFileUrl("C:\Program Files\Zapret Windows Turkiye\ui\web\index.html"), _
            "file:///C:/Program%20Files/Zapret%20Windows%20Turkiye/ui/web/index.html", "boşluklar kodlanır")
    _AssertEq(_WebFileUrl("C:\proje\geliştirme\a#b.html"), "file:///C:/proje/geli%C5%9Ftirme/a%23b.html", "ASCII dışı ve # kodlanır")
EndFunc
