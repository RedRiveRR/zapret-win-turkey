#include-once
#include "WebMsg.au3"
#include "SmartAnalysis.au3"

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
    If $sFilter <> "" Then $sDetail &= ", " & _WebFilterText($sFilter)
    $s = _WebJsonAdd($s, "stratejiDetay", $sDetail)
    $s = _WebJsonAdd($s, "onarim", $sHealth = "" ? "Servis kurulunca etkinleşir" : $sHealth)
    Return $s
EndFunc

; Strateji ekranı mesajı.
;   $sOptions/$sFilterOptions: "|" ile ayrılmış seçenekler, $sSelected/$sEngine/$sFilter: seçili olanlar
;   $bChoiceOn: strateji/motor kutuları kullanılabilir mi, $bFilterOn: filtre kutusu, $bAnalyzeOn: analiz düğmesi
;   $sSummary + $aRows: _SmartLoadResults çıktısı (sıralı), ilk $iMax satır gönderilir
Func _WebStrategyJson($sOptions, $sSelected, $sEngine, $sFilterOptions, $sFilter, $bChoiceOn, $bFilterOn, $bAnalyzeOn, _
        $sSummary, ByRef $aRows, $iMax = 3)
    Local $s = _WebJsonObj("tip", "strateji", "secili", $sSelected, "motor", $sEngine, "filtre", $sFilter)
    $s = _WebJsonAddRaw($s, "secenekler", _WebJsonList($sOptions))
    $s = _WebJsonAddRaw($s, "motorlar", _WebJsonList("Zapret2 (yeni motor)|Zapret (klasik motor)"))
    $s = _WebJsonAddRaw($s, "filtreler", _WebJsonList($sFilterOptions))
    $s = _WebJsonAdd($s, "secimAcik", $bChoiceOn = True)
    $s = _WebJsonAdd($s, "filtreAcik", $bFilterOn = True)
    $s = _WebJsonAdd($s, "analizAcik", $bAnalyzeOn = True)
    $s = _WebJsonAdd($s, "zaman", _WebSmartTime($sSummary))
    Local $sList = "", $n = UBound($aRows)
    If $n > $iMax Then $n = $iMax
    For $i = 0 To $n - 1
        If $i > 0 Then $sList &= ","
        Local $sRow = _WebJsonObj("puan", _WebScoreText($aRows[$i][$SMART_COL_SCORE]), "ad", _WebStrategyShort($aRows[$i][$SMART_COL_STRATEGY]), _
                "durum", _WebSmartStatus($aRows[$i][$SMART_COL_SCORE], $aRows[$i][$SMART_COL_PHASE], $aRows[$i][$SMART_COL_STABLE]), _
                "tam", $aRows[$i][$SMART_COL_STRATEGY])
        $sRow = _WebJsonAdd($sRow, "calisti", $aRows[$i][$SMART_COL_SCORE] > 0)
        $sList &= $sRow
    Next
    Return _WebJsonAddRaw($s, "sonuclar", "[" & $sList & "]")
EndFunc

; Servis durumu -> [durum, başlık, açıklama]. durum: aktif | hata | uyari | yok
;   $sSvcState: _ServiceGetState çıktısı ("" = kurulu değil, "RUNNING", "STOPPED"...), $sStatus: ana durum metni
Func _WebServiceParts($sSvcState, $sStatus)
    Local $a[4]
    If $sSvcState = "" Then
        __WebSet4($a, "yok", "Servis kurulu değil", "Kurarsan Zapret bilgisayar açılınca kendiliğinden başlar; programı açık tutman gerekmez.", "")
    ElseIf StringInStr($sStatus, "GEÇİCİ") Then
        __WebSet4($a, "uyari", "Servis analiz için durduruldu", "Analiz bitince servis yeniden başlatılır.", "")
    ElseIf $sSvcState = "RUNNING" Then
        __WebSet4($a, "aktif", "Servis çalışıyor", "Bilgisayar açılınca kendiliğinden başlar.", "")
    ElseIf StringInStr($sSvcState, "PENDING") Then
        __WebSet4($a, "uyari", "Servis durumu değişiyor", "Birkaç saniye içinde güncellenir.", "")
    Else
        __WebSet4($a, "hata", "Servis kurulu ama durmuş", "Zapret şu an servis üzerinden çalışmıyor.", "")
    EndIf
    ReDim $a[3]
    Return $a
EndFunc

; Servis ekranı mesajı.
;   $bHealthOn/$bRestartOn: anahtarların durumu, $sHealth: _HealthStatusFormat metni ("" = servis yok)
;   $bInstallOn/$bRemoveOn/$bSettingsOn: ilgili eski düğmeler kullanılabilir mi
Func _WebServiceJson($sSvcState, $sStatus, $bHealthOn, $bRestartOn, $sHealth, $bInstallOn, $bRemoveOn, $bSettingsOn)
    Local $a = _WebServiceParts($sSvcState, $sStatus)
    Local $s = _WebJsonObj("tip", "servis", "durum", $a[0], "baslik", $a[1], "aciklama", $a[2])
    $s = _WebJsonAdd($s, "kurulu", $a[0] <> "yok")
    $s = _WebJsonAdd($s, "onarim", $bHealthOn = True)
    $s = _WebJsonAdd($s, "yenidenBaslat", $bRestartOn = True)
    Local $sNote
    If $a[0] = "yok" Then
        $sNote = "Servis kurulunca etkinleşir."
    ElseIf Not $bHealthOn Then
        $sNote = "Kapalı."
    Else
        $sNote = StringRegExpReplace($sHealth, "^Onarım:\s*", "")
        If $sNote = "" Then $sNote = "Açık."
        $sNote = "Son durum: " & $sNote
    EndIf
    $s = _WebJsonAdd($s, "onarimNot", $sNote)
    $s = _WebJsonAdd($s, "kurAcik", $bInstallOn = True)
    $s = _WebJsonAdd($s, "kaldirAcik", $bRemoveOn = True)
    $s = _WebJsonAdd($s, "ayarAcik", $bSettingsOn = True)
    Return $s
EndFunc

; Etkin DNS sunucularından seçim: sifreli (yerel DNSCrypt) | cloudflare | saglayici (otomatik/DHCP) | diger
Func _WebDnsMode($sServers)
    $sServers = StringStripWS($sServers, 3)
    If StringInStr($sServers, "127.0.0.1") Then Return "sifreli"
    If StringInStr($sServers, "1.1.1.1") Or StringInStr($sServers, "1.0.0.1") Then Return "cloudflare"
    If $sServers = "" Then Return "saglayici"
    ; Elle girilmiş başka bir DNS mi, modemin adresi mi ayırt edilemez; özel ağ adresleri modem sayılır.
    If StringRegExp($sServers, "^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.|fe80:)") Then Return "saglayici"
    Return "diger"
EndFunc

; Yalnızca IPv4 adresleri, ", " ile (IPv6 adresleri satıra sığmıyor).
Func _WebDnsIPv4($sServers)
    Local $sV4 = ""
    For $sAddr In StringSplit(StringStripWS($sServers, 3), ",", 2)
        $sAddr = StringStripWS($sAddr, 3)
        If $sAddr <> "" And Not StringInStr($sAddr, ":") Then $sV4 &= ($sV4 = "" ? "" : ", ") & $sAddr
    Next
    Return $sV4
EndFunc

; DNS ekranı mesajı. $sServers: _GetActiveAdapterDnsServers çıktısı ("?" = henüz okunmadı),
; $bChangeOn: DNS değiştirilebilir mi (DNSCrypt düğmesi açık ve meşgul değil)
Func _WebDnsJson($sStatus, $sServers, $bChangeOn)
    Local $sDurum, $sBaslik, $sAciklama
    If $sStatus = "DNS ZEHİRLENMESİ SAPTANDI!" Then
        $sDurum = "hata"
        $sBaslik = "Adresler yanlış gösteriliyor"
        $sAciklama = "Sağlayıcının DNS'i Discord'u yanlış adrese yönlendiriyor. Cloudflare'e veya şifreli DNS'e geç."
    ElseIf StringRegExp($sStatus, "DNS|SİSTEM HAZIRLANIYOR") Then
        $sDurum = "bekliyor"
        $sBaslik = "DNS kontrol ediliyor"
        $sAciklama = ""
    Else
        $sDurum = "aktif"
        $sBaslik = "Adresler doğru görünüyor"
        $sAciklama = "Son kontrolde DNS sorunu bulunmadı."
    EndIf
    Local $s = _WebJsonObj("tip", "dns", "durum", $sDurum, "baslik", $sBaslik, "aciklama", $sAciklama)
    $s = _WebJsonAdd($s, "mod", $sServers = "?" ? "" : _WebDnsMode($sServers))
    $s = _WebJsonAdd($s, "sunucular", $sServers = "?" ? "" : _WebDnsIPv4($sServers))
    $s = _WebJsonAdd($s, "degistirAcik", $bChangeOn = True And $sServers <> "?")
    Return $s
EndFunc

; Strateji satırından kısa ad: kullanılan yöntemler "fake + multisplit"; bulunamazsa ilk 40 karakter.
Func _WebStrategyShort($sStrategy)
    Local $a = StringRegExp($sStrategy, "--(?:lua|dpi)-desync=([A-Za-z0-9_,]+)", 3)
    Local $sOut = ""
    If Not @error Then
        For $sPart In $a
            For $sName In StringSplit($sPart, ",", 2)
                If $sName = "" Or StringInStr(" + " & $sOut & " + ", " + " & $sName & " + ", 1) Then ContinueLoop
                $sOut &= ($sOut = "" ? "" : " + ") & $sName
            Next
        Next
    EndIf
    If $sOut <> "" Then Return $sOut
    $sOut = StringStripWS($sStrategy, 7)
    If StringLen($sOut) > 40 Then $sOut = StringLeft($sOut, 39) & "…"
    Return $sOut
EndFunc

; Akıllı analiz satırının durumu (sonuç penceresindekiyle aynı ifadeler).
Func _WebSmartStatus($fScore, $iPhase, $bStable)
    If $fScore <= 0 Then Return "çalışmadı"
    If $iPhase < 2 Then Return "yalnız eleme"
    If $bStable Then Return "kararlı"
    Return "dalgalı"
EndFunc

; Puan: tek ondalık, Türkçe virgül: 99.64 -> "99,6"
Func _WebScoreText($f)
    Return StringReplace(StringFormat("%.1f", Number($f)), ".", ",")
EndFunc

; Sonuç özetinin başındaki zaman: "2026-10-23 11:20:05 | ..." -> "23.10.2026 11:20"; yoksa "".
Func _WebSmartTime($sSummary)
    Local $a = StringRegExp($sSummary, "^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})", 1)
    If @error Then Return ""
    Return $a[2] & "." & $a[1] & "." & $a[0] & " " & $a[3] & ":" & $a[4]
EndFunc

; Filtre seçimi metnini kullanıcı diline çevirir.
Func _WebFilterText($sFilter)
    If StringInStr($sFilter, "Auto") Then Return "otomatik site listesi"
    If StringInStr($sFilter, "Manuel") Then Return "kendi site listen"
    If StringInStr($sFilter, "Kapalı") Then Return "tüm trafik"
    Return _WebLowerFirst(StringRegExpReplace($sFilter, "\s*\(.*$", ""))
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
