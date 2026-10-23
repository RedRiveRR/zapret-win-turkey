#include-once
#include "WebMsg.au3"

; =========================================================================
; Eski arayüzün durum metinlerini yeni arayüzün "durum" mesajına çevirir.
; Program mantığı eski denetimlere yazmaya devam eder; yeni arayüz bu
; çeviriyle aynı durumu gösterir. GUI'ye bağlı değildir (tests/test_webstate.au3).
; =========================================================================

; Durum metni -> [durum, rozet, başlık, açıklama]
Func _WebStatusParts($sStatus)
    Local $a[4]
    Switch $sStatus
        Case "SERVİS MODU AKTİF"
            __WebSet4($a, "aktif", "Servis çalışıyor", "Discord'a yol açık", "Bilgisayar açılınca kendiliğinden başlar.")
        Case "MANUEL MOD AKTİF"
            __WebSet4($a, "aktif", "Zapret çalışıyor", "Discord'a yol açık", "Program kapanınca Zapret de durur. Kalıcı kullanım için servisi kurun.")
        Case "ÇALIŞMAYA HAZIR"
            __WebSet4($a, "hazir", "Çalışmaya hazır", "Zapret kapalı", "Başlatmak için düğmeye basın.")
        Case "DNS ZEHİRLENMESİ SAPTANDI!"
            __WebSet4($a, "hata", "DNS sorunu", "Adresler yanlış gösteriliyor", "Sağlayıcının DNS'i Discord'u yanlış adrese yönlendiriyor. DNS'i değiştirmeniz gerekiyor.")
        Case "SERVİS YÜKLÜ - DURDU"
            __WebSet4($a, "hata", "Servis durdu", "Discord'a yol kapalı", "Servis durmuş. Bir program (ör. oyun hile koruması) kapatmış olabilir.")
        Case Else
            If StringInStr($sStatus, "GEÇİCİ") Then
                __WebSet4($a, "uyari", "Servis geçici olarak durduruldu", "Analiz sürüyor", "Analiz bitince servis eski haline döner.")
            Else
                __WebSet4($a, "bekliyor", "Lütfen bekleyin", _WebSentenceCase(StringRegExpReplace($sStatus, "[.!…]+$", "")), "")
            EndIf
    EndSwitch
    Return $a
EndFunc

; Yeni arayüze gönderilecek tam durum mesajı.
;   $sRunText: Başlat/Durdur düğmesinin metni, $bRunEnabled: düğme kullanılabilir mi
;   $sEngine: motor seçimi metni, $sFilter: filtre seçimi metni, $sHealth: onarım durumu ("" = servis yok)
Func _WebStateJson($sStatus, $sRunText, $bRunEnabled, $sStrategy, $sEngine, $sFilter, $sHealth)
    Local $a = _WebStatusParts($sStatus)
    Local $s = _WebJsonObj("tip", "durum", "durum", $a[0], "rozet", $a[1], "baslik", $a[2], "aciklama", $a[3])
    $s = _WebJsonAdd($s, "calisiyor", StringInStr($sRunText, "Durdur") > 0)
    $s = _WebJsonAdd($s, "dugme", $bRunEnabled = True)
    $s = _WebJsonAdd($s, "strateji", $sStrategy)
    Local $sDetail = (StringInStr($sEngine, "Zapret2") ? "Zapret2 motoru" : "Klasik motor")
    If $sFilter <> "" Then $sDetail &= ", " & _WebLowerFirst(StringRegExpReplace($sFilter, "\s*\(.*$", "")) & " filtre"
    $s = _WebJsonAdd($s, "stratejiDetay", $sDetail)
    $s = _WebJsonAdd($s, "onarim", $sHealth = "" ? "Servis kurulunca etkinleşir" : $sHealth)
    Return $s
EndFunc

; Türkçe kurallarıyla küçük harf (İ->i, I->ı).
Func _WebTrLower($s)
    $s = StringReplace($s, "İ", "i", 0, 1)
    $s = StringReplace($s, "I", "ı", 0, 1)
    Return StringLower($s)
EndFunc

; Yalnızca ilk harf büyük, gerisi Türkçe küçük harf: "DNS KONTROL EDİLİYOR" -> "Dns kontrol ediliyor"
Func _WebSentenceCase($s)
    $s = _WebTrLower($s)
    If $s = "" Then Return ""
    Local $c = StringLeft($s, 1)
    If $c == "i" Then
        $c = "İ"
    ElseIf $c == "ı" Then
        $c = "I"
    Else
        $c = StringUpper($c)
    EndIf
    ; Bilinen kısaltmalar büyük kalır.
    Local $sOut = $c & StringTrimLeft($s, 1)
    $sOut = StringRegExpReplace($sOut, "(?i)\bdns\b", "DNS")
    $sOut = StringRegExpReplace($sOut, "(?i)\biss\b", "İSS")
    Return $sOut
EndFunc

Func _WebLowerFirst($s)
    If $s = "" Then Return ""
    Return _WebTrLower(StringLeft($s, 1)) & StringTrimLeft($s, 1)
EndFunc

Func __WebSet4(ByRef $a, $s0, $s1, $s2, $s3)
    $a[0] = $s0
    $a[1] = $s1
    $a[2] = $s2
    $a[3] = $s3
EndFunc
