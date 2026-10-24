#include-once
#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include "Winws.au3"
#include "Process.au3"
#include "Log.au3"

; =========================================================================
; --- AKILLI ANALİZ ---
; Aday stratejileri winws2 ile tek tek çalıştırıp gerçek hedeflere (Discord
; sohbet sunucusu, discord.com, roblox.com...) TCP üzerinden curl bağlantıları
; açarak ölçer, puanlar ve sıralar.
;
; Neden TCP + curl: ISS'in DPI'ı TCP el sıkışmasını (TLS ClientHello) keser,
; QUIC'e bakmaz. Tarayıcı discord.com'u QUIC ile açabildiği için tarayıcıda
; yapılan deneme yanıltıcıdır; Discord uygulamasının sohbet bağlantısı
; (gateway.discord.gg) ise yalnızca TCP kullanır.
;
; Akış:
;   0) Taban ölçüm: zapret olmadan. Engelsiz hedefler puanlamaya girmez.
;   1) Eleme: her aday, her hedef, TLS 1.2 + 1.3, 1 deneme.
;   2) Detay: en iyi $SMART_PHASE2_MAX aday, $SMART_PHASE2_REPS tekrar.
; =========================================================================

Global Const $SMART_TLS12 = "1.2"
Global Const $SMART_TLS13 = "1.3"
; host:ağırlık. gateway.discord.gg Discord uygulamasının sohbet bağlantısıdır (en kritik).
Global Const $SMART_DEFAULT_TARGETS = "gateway.discord.gg:3,discord.com:2,roblox.com:2,cdn.discordapp.com:1"
Global Const $SMART_PHASE2_MAX = 12
; Büyük aday listeleri (blockcheck yüzlerce strateji bulabiliyor) için:
; elemede en fazla bu kadar tarama adayı denenir (kayıtlı/hazır profiller sınırsız)...
Global Const $SMART_PHASE1_MAX = 150
; ...ve bu kadar aday elemede tam başarı aldıysa eleme erken biter.
Global Const $SMART_EARLY_PERFECT = 25
Global Const $SMART_PHASE1_TIMEOUT = 3
Global Const $SMART_PHASE2_TIMEOUT = 4
Global Const $SMART_PHASE2_REPS = 3
Global Const $SMART_STABLE_RATIO = 0.9
Global Const $SMART_TLS13_WEIGHT = 1.5

; Sonuç satırı sütunları
Global Enum $SMART_COL_STRATEGY, $SMART_COL_SCORE, $SMART_COL_SUCCESS, $SMART_COL_TLS13, $SMART_COL_MS, _
        $SMART_COL_STABLE, $SMART_COL_PHASE, $SMART_COL_DETAIL, $SMART_COL_SOURCE, $SMART_COL_COUNT

; ------------------------------------------------------------------------
; Saf yardımcılar (birim testli)
; ------------------------------------------------------------------------

; "host:ağırlık,host2:ağırlık" -> [n][2] (host, ağırlık). Geçersiz host'lar atlanır.
Func _SmartParseTargets($sSpec)
    Local $aOut[0][2]
    Local $aParts = StringSplit(StringStripWS($sSpec, 8), ",", 2)
    For $sPart In $aParts
        If $sPart = "" Then ContinueLoop
        Local $aKV = StringSplit($sPart, ":", 2)
        Local $sHost = StringLower($aKV[0])
        If Not StringRegExp($sHost, "^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$") Then ContinueLoop
        Local $fW = (UBound($aKV) > 1) ? Number($aKV[1]) : 1
        If $fW <= 0 Then $fW = 1
        Local $i = UBound($aOut)
        ReDim $aOut[$i + 1][2]
        $aOut[$i][0] = $sHost
        $aOut[$i][1] = $fW
    Next
    Return $aOut
EndFunc

; Tek bir curl deneme komutu. TCP + IPv4 (winws2 testleri --wf-l3=ipv4 ile çalışır).
Func _SmartProbeCommand($sCurl, $sNull, $sHost, $sTls, $iTimeoutSec)
    Local $sTlsArg = ($sTls = $SMART_TLS12) ? "--tlsv1.2 --tls-max 1.2" : "--tlsv1.3"
    Return '"' & $sCurl & '" -4 -s -o "' & $sNull & '" -m ' & $iTimeoutSec & ' ' & $sTlsArg & _
            ' -w "%{exitcode}|%{http_code}|%{time_total}" https://' & $sHost & '/'
EndFunc

; curl -w çıktısını yorumlar. Başarılıysa True ve $fMs = toplam süre (ms).
; Eski curl sürümleri %{exitcode} bilmez; o durumda HTTP kodu > 0 başarı sayılır.
Func _SmartParseCurlOutput($sOut, ByRef $fMs)
    $fMs = 0
    Local $a = StringSplit(StringStripWS($sOut, 3), "|", 2)
    If UBound($a) < 3 Then Return False
    Local $bOk
    If StringIsDigit($a[0]) Then
        $bOk = (Number($a[0]) = 0)
    Else
        $bOk = (Number($a[1]) > 0)
    EndIf
    If $bOk Then $fMs = Number($a[2]) * 1000
    Return $bOk
EndFunc

; Stratejinin karmaşıklık cezası (0 = en sade). Sade stratejiler daha az bozulur ve
; ağ değişikliklerine daha dayanıklıdır.
Func _SmartComplexity($sStrategy)
    Local $fP = 0
    StringReplace($sStrategy, "--lua-desync=", "")
    Local $iDesync = @extended
    If $iDesync > 1 Then $fP += ($iDesync - 1) * 1.5
    Local $aRep = StringRegExp($sStrategy, "repeats=(\d+)", 3)
    If Not @error Then
        For $sN In $aRep
            If Number($sN) > 1 Then $fP += (Number($sN) - 1) * 0.5
        Next
    EndIf
    If StringInStr($sStrategy, "fake") Then $fP += 1 ; ek sahte paket gönderir
    If StringRegExp($sStrategy, "(?i)ip6?_ttl|autottl") Then $fP += 0.5 ; hat mesafesine bağımlı
    StringReplace($sStrategy, "-range=", "") ; --in-range / --out-range ek kurallar
    $fP += @extended * 0.5
    Return $fP
EndFunc

; Ağırlıklı başarı oranı (0..1). Yalnızca taban ölçümde engelli çıkan hedefler sayılır.
;   $aM: [hedef][4] = ok12, tot12, ok13, tot13
Func _SmartSuccessRatio(ByRef $aM, ByRef $aTargets, ByRef $aBlocked, $bOnlyTls13 = False)
    Local $fNum = 0, $fDen = 0
    For $t = 0 To UBound($aTargets) - 1
        If Not $aBlocked[$t] Then ContinueLoop
        Local $fW = $aTargets[$t][1]
        If Not $bOnlyTls13 And $aM[$t][1] > 0 Then
            $fNum += $fW * $aM[$t][0] / $aM[$t][1]
            $fDen += $fW
        EndIf
        If $aM[$t][3] > 0 Then
            Local $fW13 = $bOnlyTls13 ? $fW : $fW * $SMART_TLS13_WEIGHT
            $fNum += $fW13 * $aM[$t][2] / $aM[$t][3]
            $fDen += $fW13
        EndIf
    Next
    If $fDen = 0 Then Return 0
    Return $fNum / $fDen
EndFunc

; 0..100 puan: başarı 80, gecikme 15, sadelik 5. OOB stratejiler hostlist ile
; çalışmadığı ve tüm trafiği etkilediği için 30 puan ceza alır.
Func _SmartScore($fSuccess, $fAvgMs, $sStrategy)
    If $fSuccess <= 0 Then Return 0
    Local $fLat = 15 * __SmartClamp(1 - ($fAvgMs - 150) / 1350, 0, 1)
    Local $fSimp = __SmartClamp(5 - _SmartComplexity($sStrategy), 0, 5)
    Local $f = 80 * $fSuccess + $fLat + $fSimp
    If _WinwsStrategyHasOOB($sStrategy) Then $f -= 30
    If $f < 0 Then $f = 0
    Return Round($f, 1)
EndFunc

Func __SmartClamp($f, $fMin, $fMax)
    If $f < $fMin Then Return $fMin
    If $f > $fMax Then Return $fMax
    Return $f
EndFunc

; Hedef bazında okunabilir ayrıntı: "gateway.discord.gg 1.2:3/3 1.3:3/3; ..."
Func _SmartDetail(ByRef $aM, ByRef $aTargets, ByRef $aBlocked)
    Local $s = ""
    For $t = 0 To UBound($aTargets) - 1
        If Not $aBlocked[$t] Then ContinueLoop
        If $s <> "" Then $s &= "; "
        $s &= $aTargets[$t][0] & " 1.2:" & $aM[$t][0] & "/" & $aM[$t][1] & " 1.3:" & $aM[$t][2] & "/" & $aM[$t][3]
    Next
    Return $s
EndFunc

; Aday listesine ekler; tırnak ve boşluk farkı yok sayılarak tekrarlar birleştirilir,
; kaynaklar ", " ile toplanır. $aC: [n][2] (strateji, kaynak)
; Tekrar araması sözlükle yapılır (785 adayda doğrusal arama 3,5 sn sürüyordu).
; Sözlük, liste boşken (yeni liste) sıfırlanır; listeler her zaman boştan kurulmalıdır.
Global $__g_oSmartCandKeys = 0
Func _SmartAddCandidate(ByRef $aC, $sStrategy, $sSource)
    $sStrategy = StringStripWS($sStrategy, 7)
    If $sStrategy = "" Then Return
    Local $sKey = StringReplace($sStrategy, '"', "")
    If UBound($aC) = 0 Or Not IsObj($__g_oSmartCandKeys) Then
        $__g_oSmartCandKeys = ObjCreate("Scripting.Dictionary")
        $__g_oSmartCandKeys.CompareMode = 0 ; ikili (büyük/küçük harf duyarlı)
        For $i = 0 To UBound($aC) - 1
            $__g_oSmartCandKeys.Item(StringReplace($aC[$i][0], '"', "")) = $i
        Next
    EndIf
    If $__g_oSmartCandKeys.Exists($sKey) Then
        Local $iIdx = $__g_oSmartCandKeys.Item($sKey)
        If $iIdx < UBound($aC) And StringReplace($aC[$iIdx][0], '"', "") == $sKey Then
            If Not StringInStr(", " & $aC[$iIdx][1] & ",", ", " & $sSource & ",") Then $aC[$iIdx][1] &= ", " & $sSource
            Return
        EndIf
    EndIf
    Local $n = UBound($aC)
    ReDim $aC[$n + 1][2]
    $aC[$n][0] = $sStrategy
    $aC[$n][1] = $sSource
    $__g_oSmartCandKeys.Item($sKey) = $n
EndFunc

; Aday kaynağı öncelikli mi? (Kayıtlı strateji ve hazır profiller her zaman ölçülür.)
Func _SmartIsPriorityCandidate($sSource)
    Return StringInStr($sSource, "Kayıtlı") > 0 Or StringInStr($sSource, "Hazır") > 0
EndFunc

; Adayları ölçüm sırasına koyar: önce öncelikliler (sıra korunur), sonra diğerleri
; sadeden karmaşığa (eşitlikte ilk bulunan önce). Büyük listelerde erken bitirme
; ve üst sınır uygulandığında en sağlam stratejilerin kesin denenmesini sağlar.
Func _SmartOrderCandidates(ByRef $aC)
    Local $n = UBound($aC)
    Local $aOut[$n][2], $iOut = 0
    For $i = 0 To $n - 1
        If Not _SmartIsPriorityCandidate($aC[$i][1]) Then ContinueLoop
        $aOut[$iOut][0] = $aC[$i][0]
        $aOut[$iOut][1] = $aC[$i][1]
        $iOut += 1
    Next
    ; Diğerleri: karmaşıklık bir kez hesaplanır, dizinler kararlı ekleme sıralamasıyla dizilir.
    Local $aIdx[$n], $aCx[$n], $iRest = 0
    For $i = 0 To $n - 1
        If _SmartIsPriorityCandidate($aC[$i][1]) Then ContinueLoop
        ; OOB sade görünse de filtreyle çalışmaz ve puanda ceza alır: en sona.
        Local $fC = _SmartComplexity($aC[$i][0]) + (_WinwsStrategyHasOOB($aC[$i][0]) ? 100 : 0)
        Local $j = $iRest
        While $j > 0 And $aCx[$j - 1] > $fC
            $aIdx[$j] = $aIdx[$j - 1]
            $aCx[$j] = $aCx[$j - 1]
            $j -= 1
        WEnd
        $aIdx[$j] = $i
        $aCx[$j] = $fC
        $iRest += 1
    Next
    For $k = 0 To $iRest - 1
        $aOut[$iOut][0] = $aC[$aIdx[$k]][0]
        $aOut[$iOut][1] = $aC[$aIdx[$k]][1]
        $iOut += 1
    Next
    Return $aOut
EndFunc

; Sonuçları sıralar: önce detaylı ölçülenler (faz 2), sonra puan (yüksek), sonra gecikme (düşük).
Func _SmartRank(ByRef $aRows)
    Local $n = UBound($aRows)
    For $i = 1 To $n - 1
        For $j = $i To 1 Step -1
            If Not __SmartRowBefore($aRows, $j, $j - 1) Then ExitLoop
            For $c = 0 To $SMART_COL_COUNT - 1
                Local $vTmp = $aRows[$j][$c]
                $aRows[$j][$c] = $aRows[$j - 1][$c]
                $aRows[$j - 1][$c] = $vTmp
            Next
        Next
    Next
EndFunc

; a satırı b'den önce mi gelmeli?
Func __SmartRowBefore(ByRef $aRows, $a, $b)
    If $aRows[$a][$SMART_COL_PHASE] <> $aRows[$b][$SMART_COL_PHASE] Then Return $aRows[$a][$SMART_COL_PHASE] > $aRows[$b][$SMART_COL_PHASE]
    If $aRows[$a][$SMART_COL_SCORE] <> $aRows[$b][$SMART_COL_SCORE] Then Return $aRows[$a][$SMART_COL_SCORE] > $aRows[$b][$SMART_COL_SCORE]
    Local $fA = ($aRows[$a][$SMART_COL_MS] > 0) ? $aRows[$a][$SMART_COL_MS] : 1e9
    Local $fB = ($aRows[$b][$SMART_COL_MS] > 0) ? $aRows[$b][$SMART_COL_MS] : 1e9
    Return $fA < $fB
EndFunc

; Tahmini en uzun süre (dakika): eleme ~3 sn/aday (üst sınırla), detay ~7 sn/aday, taban ~10 sn.
; Erken bitirme çoğu zaman bunu kısaltır.
Func _SmartEstimateMinutes($iCandidates)
    Local $iP1 = ($iCandidates < $SMART_PHASE1_MAX) ? $iCandidates : $SMART_PHASE1_MAX
    Local $iP2 = ($iCandidates < $SMART_PHASE2_MAX) ? $iCandidates : $SMART_PHASE2_MAX
    Return Ceiling(($iP1 * 3 + $iP2 * 7 + 10) / 60)
EndFunc

; ------------------------------------------------------------------------
; Sonuç dosyası (TSV)
; ------------------------------------------------------------------------

Func _SmartSaveResults($sPath, ByRef $aRows, $sSummary)
    Local $h = FileOpen($sPath, $FO_OVERWRITE + $FO_UTF8_NOBOM)
    If $h = -1 Then Return False
    FileWriteLine($h, "# " & _LogTimestamp() & " | " & StringRegExpReplace($sSummary, "\R+", " "))
    For $i = 0 To UBound($aRows) - 1
        Local $sLine = ""
        For $c = 0 To $SMART_COL_COUNT - 1
            If $c > 0 Then $sLine &= @TAB
            $sLine &= StringReplace(String($aRows[$i][$c]), @TAB, " ")
        Next
        FileWriteLine($h, $sLine)
    Next
    FileClose($h)
    Return True
EndFunc

Func _SmartLoadResults($sPath, ByRef $sSummary)
    Local $aRows[0][$SMART_COL_COUNT]
    $sSummary = ""
    If Not FileExists($sPath) Then Return $aRows
    Local $aLines = StringSplit(StringStripCR(FileRead($sPath)), @LF, 2)
    For $sLine In $aLines
        If $sLine = "" Then ContinueLoop
        If StringLeft($sLine, 2) = "# " Then
            $sSummary = StringTrimLeft($sLine, 2)
            ContinueLoop
        EndIf
        Local $aF = StringSplit($sLine, @TAB, 2)
        If UBound($aF) <> $SMART_COL_COUNT Then ContinueLoop
        Local $n = UBound($aRows)
        ReDim $aRows[$n + 1][$SMART_COL_COUNT]
        For $c = 0 To $SMART_COL_COUNT - 1
            $aRows[$n][$c] = $aF[$c]
        Next
        ; sayısal sütunlar
        $aRows[$n][$SMART_COL_SCORE] = Number($aF[$SMART_COL_SCORE])
        $aRows[$n][$SMART_COL_SUCCESS] = Number($aF[$SMART_COL_SUCCESS])
        $aRows[$n][$SMART_COL_TLS13] = Number($aF[$SMART_COL_TLS13])
        $aRows[$n][$SMART_COL_MS] = Number($aF[$SMART_COL_MS])
        $aRows[$n][$SMART_COL_STABLE] = ($aF[$SMART_COL_STABLE] = "True")
        $aRows[$n][$SMART_COL_PHASE] = Number($aF[$SMART_COL_PHASE])
    Next
    Return $aRows
EndFunc

; ------------------------------------------------------------------------
; Ölçüm motoru (süreç başlatır; birim testlerde yalnızca taban ölçüm kullanılır)
; ------------------------------------------------------------------------

; Kullanılacak curl'ü bulur: paketteki cygwin curl, yoksa Windows curl.
; $sNull: çıktının atılacağı yol. Bulunamazsa "".
Func _SmartFindCurl($sRoot, ByRef $sNull)
    Local $sCyg = $sRoot & "\bin\zapret\cygwin\usr\local\bin\curl.exe"
    If FileExists($sCyg) Then
        $sNull = "/dev/null"
        Local $sCygBin = $sRoot & "\bin\zapret\cygwin\bin"
        ; cygwin1.dll bulunabilsin
        If Not StringInStr(";" & EnvGet("PATH") & ";", ";" & $sCygBin & ";") Then EnvSet("PATH", $sCygBin & ";" & EnvGet("PATH"))
        Return $sCyg
    EndIf
    If FileExists(@SystemDir & "\curl.exe") Then
        $sNull = "NUL"
        Return @SystemDir & "\curl.exe"
    EndIf
    $sNull = ""
    Return ""
EndFunc

; İlerleme geri çağrısı: Func f($iDone, $iTotal, $sText) -> True (devam) / False (durdur)
Func __SmartProgress($sFunc, $iDone, $iTotal, $sText)
    If $sFunc = "" Then Return True
    Local $vRet = Call($sFunc, $iDone, $iTotal, $sText)
    If @error = 0xDEAD And @extended = 0xBEEF Then Return True
    Return $vRet <> False
EndFunc

; Deneme grubunu paralel çalıştırır. $aP: [n][5] = host, tls, hedef no, başarı, ms
; Kullanıcı durdurursa False döner.
Func __SmartRunBatch(ByRef $aP, $sCurl, $sNull, $iTimeout, $sProgressFunc, $iDone, $iTotal, $sText)
    Local $n = UBound($aP)
    Local $aPid[$n], $aOut[$n], $aDone[$n]
    For $i = 0 To $n - 1
        $aPid[$i] = Run(_SmartProbeCommand($sCurl, $sNull, $aP[$i][0], $aP[$i][1], $iTimeout), "", @SW_HIDE, $STDOUT_CHILD)
        $aOut[$i] = ""
        $aDone[$i] = ($aPid[$i] = 0)
    Next

    Local $hT = TimerInit()
    While 1
        Local $bPending = False
        For $i = 0 To $n - 1
            If $aDone[$i] Then ContinueLoop
            $aOut[$i] &= StdoutRead($aPid[$i])
            If ProcessExists($aPid[$i]) Then
                $bPending = True
            Else
                While 1
                    Local $sMore = StdoutRead($aPid[$i])
                    If @error Or $sMore = "" Then ExitLoop
                    $aOut[$i] &= $sMore
                WEnd
                $aDone[$i] = True
            EndIf
        Next
        If Not $bPending Then ExitLoop
        If TimerDiff($hT) > ($iTimeout + 3) * 1000 Then ExitLoop
        If Not __SmartProgress($sProgressFunc, $iDone, $iTotal, $sText) Then
            For $i = 0 To $n - 1
                If Not $aDone[$i] Then ProcessClose($aPid[$i])
            Next
            Return False
        EndIf
        Sleep(25)
    WEnd

    For $i = 0 To $n - 1
        If Not $aDone[$i] And $aPid[$i] > 0 Then ProcessClose($aPid[$i])
        Local $fMs = 0
        $aP[$i][3] = $aDone[$i] And _SmartParseCurlOutput($aOut[$i], $fMs)
        $aP[$i][4] = $fMs
    Next
    Return True
EndFunc

; Bekler; bu sırada ilerleme geri çağrısını çalıştırır ki pencere tepkisiz kalmasın.
; Kullanıcı durdurursa False.
Func __SmartWait($iMs, $sProgressFunc, $iDone, $iTotal, $sText, $iWatchPid = 0)
    Local $hT = TimerInit()
    While TimerDiff($hT) < $iMs
        If Not __SmartProgress($sProgressFunc, $iDone, $iTotal, $sText) Then Return False
        If $iWatchPid > 0 And Not ProcessExists($iWatchPid) Then Return True
        Sleep(25)
    WEnd
    Return True
EndFunc

; winws2'yi strateji ile başlatır. Dönüş: PID, 0 = başlatılamadı/hemen kapandı, -1 = kullanıcı durdurdu.
Func __SmartStartWinws($sWinwsPath, $sStrategy, $sProgressFunc = "", $iDone = 0, $iTotal = 0, $sText = "")
    Local $sDir = StringRegExpReplace($sWinwsPath, "\\[^\\]+$", "")
    Local $iPid = Run('"' & $sWinwsPath & '" ' & _BuildWinwsArgs("Zapret2", $sWinwsPath, $sStrategy, $WINWS_FILTER_OFF), $sDir, @SW_HIDE)
    If $iPid = 0 Then Return 0
    ; WinDivert filtresinin oturması için bekle (süreç erken kapanırsa beklemeyi kes).
    If Not __SmartWait(700, $sProgressFunc, $iDone, $iTotal, $sText, $iPid) Then
        __SmartStopWinws($iPid)
        Return -1
    EndIf
    If Not ProcessExists($iPid) Then Return 0
    Return $iPid
EndFunc

Func __SmartStopWinws($iPid)
    If $iPid <= 0 Then Return
    ProcessClose($iPid)
    If Not ProcessWaitClose($iPid, 3) Then _KillProcessTree($iPid)
    Sleep(50)
EndFunc

; Bir stratejiyi (ya da $sStrategy = "" ise bypass'sız durumu) ölçer.
; $aMetrics: [hedef][4] = ok12, tot12, ok13, tot13. Dönüş: 1 tamam, 0 winws başlatılamadı, -1 durduruldu.
Func _SmartMeasure($sWinwsPath, $sStrategy, ByRef $aTargets, $iReps, $iTimeout, $sCurl, $sNull, _
        $sProgressFunc, $iDone, $iTotal, $sText, ByRef $aMetrics, ByRef $fAvgMs)
    Local $nT = UBound($aTargets)
    Local $aM[$nT][4]
    For $t = 0 To $nT - 1
        For $c = 0 To 3
            $aM[$t][$c] = 0
        Next
    Next
    $aMetrics = $aM
    $fAvgMs = 0

    Local $iPid = 0
    If $sStrategy <> "" Then
        $iPid = __SmartStartWinws($sWinwsPath, $sStrategy, $sProgressFunc, $iDone, $iTotal, $sText)
        If $iPid = -1 Then Return -1
        If $iPid = 0 Then Return 0
    EndIf

    Local $fSum = 0, $iOk = 0, $iRet = 1
    For $r = 1 To $iReps
        Local $aP[$nT * 2][5]
        For $t = 0 To $nT - 1
            $aP[$t * 2][0] = $aTargets[$t][0]
            $aP[$t * 2][1] = $SMART_TLS12
            $aP[$t * 2][2] = $t
            $aP[$t * 2 + 1][0] = $aTargets[$t][0]
            $aP[$t * 2 + 1][1] = $SMART_TLS13
            $aP[$t * 2 + 1][2] = $t
        Next
        If Not __SmartRunBatch($aP, $sCurl, $sNull, $iTimeout, $sProgressFunc, $iDone, $iTotal, $sText) Then
            $iRet = -1
            ExitLoop
        EndIf
        For $i = 0 To UBound($aP) - 1
            Local $iCol = ($aP[$i][1] = $SMART_TLS12) ? 0 : 2
            $aM[$aP[$i][2]][$iCol + 1] += 1
            If $aP[$i][3] Then
                $aM[$aP[$i][2]][$iCol] += 1
                $fSum += $aP[$i][4]
                $iOk += 1
            EndIf
        Next
    Next

    __SmartStopWinws($iPid)
    If $iOk > 0 Then $fAvgMs = $fSum / $iOk
    $aMetrics = $aM
    Return $iRet
EndFunc

; Tam analiz. $aCandidates: [n][2] (strateji, kaynak).
; Dönüş: sıralı sonuçlar [n][$SMART_COL_COUNT]. $sSummary'ye özet yazılır.
; @error: 1 = hiçbir hedefte engel yok, 2 = kullanıcı durdurdu (kısmi sonuç), 3 = geçersiz girdi,
;         4 = zapret motoru hiçbir adayla başlatılamadı (sürücü yüklenemiyor; H20)
Func _SmartAnalyze(ByRef $aCandidatesIn, $sWinwsPath, $sCurl, $sNull, $sTargetsSpec, $sProgressFunc, ByRef $sSummary)
    Local $aEmpty[0][$SMART_COL_COUNT]
    $sSummary = ""
    Local $aTargets = _SmartParseTargets($sTargetsSpec)
    Local $nT = UBound($aTargets), $nC = UBound($aCandidatesIn)
    If $nT = 0 Or $sCurl = "" Then Return SetError(3, 0, $aEmpty)

    ; Öncelikliler önce, sonra sadeden karmaşığa.
    Local $aCandidates = _SmartOrderCandidates($aCandidatesIn)
    Local $nPrio = 0
    For $i = 0 To $nC - 1
        If _SmartIsPriorityCandidate($aCandidates[$i][1]) Then $nPrio += 1
    Next
    Local $nRest = $nC - $nPrio
    Local $iP1 = $nPrio + (($nRest < $SMART_PHASE1_MAX) ? $nRest : $SMART_PHASE1_MAX)
    Local $iP2 = ($iP1 < $SMART_PHASE2_MAX) ? $iP1 : $SMART_PHASE2_MAX
    Local $iTotal = 1 + $iP1 + $iP2, $iDone = 0
    Local $aM, $fMs

    ; --- 0) Taban ölçüm ---
    Local $iR = _SmartMeasure($sWinwsPath, "", $aTargets, 1, $SMART_PHASE1_TIMEOUT, $sCurl, $sNull, _
            $sProgressFunc, $iDone, $iTotal, "Taban ölçüm: zapret olmadan hedefler deneniyor...", $aM, $fMs)
    If $iR = -1 Then Return SetError(2, 0, $aEmpty)
    Local $aBlocked[$nT], $sBlocked = "", $sFree = "", $iBlocked = 0
    For $t = 0 To $nT - 1
        $aBlocked[$t] = ($aM[$t][0] < $aM[$t][1]) Or ($aM[$t][2] < $aM[$t][3])
        If $aBlocked[$t] Then
            $iBlocked += 1
            $sBlocked &= ($sBlocked = "" ? "" : ", ") & $aTargets[$t][0]
        Else
            $sFree &= ($sFree = "" ? "" : ", ") & $aTargets[$t][0]
        EndIf
    Next
    $iDone += 1
    _LogInfo("Akıllı analiz: engelli hedefler [" & $sBlocked & "], engelsiz [" & $sFree & "], " & $nC & " aday (" & $nPrio & " öncelikli)")
    If $iBlocked = 0 Then
        $sSummary = "Hedeflerin hiçbirinde engel saptanmadı (" & $sFree & ")."
        Return SetError(1, 0, $aEmpty)
    EndIf

    ; --- 1) Eleme ---
    Local $aRows[$nC][$SMART_COL_COUNT]
    Local $bAborted = False, $iMeasured = 0, $iRestMeasured = 0, $iPerfect = 0, $iSkipped = 0, $sSkipReason = "", $iStartFail = 0
    For $i = 0 To $nC - 1
        __SmartFillRow($aRows, $i, $aCandidates[$i][0], $aCandidates[$i][1])
        If $bAborted Then ContinueLoop
        Local $bPrio = _SmartIsPriorityCandidate($aCandidates[$i][1])
        If Not $bPrio Then
            If $iPerfect >= $SMART_EARLY_PERFECT Then
                $iSkipped += 1
                $sSkipReason = $SMART_EARLY_PERFECT & " aday tam başarı aldı"
                ContinueLoop
            EndIf
            If $iRestMeasured >= $SMART_PHASE1_MAX Then
                $iSkipped += 1
                If $sSkipReason = "" Then $sSkipReason = "üst sınır " & $SMART_PHASE1_MAX
                ContinueLoop
            EndIf
        EndIf
        $iR = _SmartMeasure($sWinwsPath, $aCandidates[$i][0], $aTargets, 1, $SMART_PHASE1_TIMEOUT, $sCurl, $sNull, _
                $sProgressFunc, $iDone, $iTotal, "Eleme " & ($iMeasured + 1) & "/" & $iP1 & " (tam başarılı: " & $iPerfect & "): " & _
                StringLeft($aCandidates[$i][0], 80), $aM, $fMs)
        If $iR = -1 Then
            $bAborted = True
            ContinueLoop
        EndIf
        __SmartScoreRow($aRows, $i, $iR, $aM, $fMs, $aTargets, $aBlocked, 1)
        If $aRows[$i][$SMART_COL_SUCCESS] >= 100 Then $iPerfect += 1
        $iMeasured += 1
        If $iR = 0 Then $iStartFail += 1
        If _SmartEngineFailed($iMeasured, $iStartFail) Then
            $sSummary = "Zapret motoru (winws2) hiçbir stratejiyle başlatılamadı; sürücüsü yüklenemiyor olabilir. Sonuçlar kaydedilmedi."
            _LogError("Akıllı analiz durduruldu: ilk " & $iMeasured & " adayda winws2 başlatılamadı")
            Return SetError(4, 0, $aEmpty)
        EndIf
        If Not $bPrio Then $iRestMeasured += 1
        $iDone += 1
    Next
    ; Erken bitince ilerleme çubuğu eleme sonuna atlasın.
    $iDone = 1 + $iP1
    _SmartRank($aRows)

    ; --- 2) Detaylı ölçüm ---
    If Not $bAborted Then
        Local $iCount = 0
        For $i = 0 To $nC - 1
            If $iCount >= $SMART_PHASE2_MAX Then ExitLoop
            If $aRows[$i][$SMART_COL_SCORE] <= 0 Then ExitLoop
            $iCount += 1
            $iR = _SmartMeasure($sWinwsPath, $aRows[$i][$SMART_COL_STRATEGY], $aTargets, $SMART_PHASE2_REPS, $SMART_PHASE2_TIMEOUT, $sCurl, $sNull, _
                    $sProgressFunc, $iDone, $iTotal, "Detaylı ölçüm " & $iCount & "/" & $iP2 & ": " & StringLeft($aRows[$i][$SMART_COL_STRATEGY], 90), $aM, $fMs)
            If $iR = -1 Then
                $bAborted = True
                ExitLoop
            EndIf
            __SmartScoreRow($aRows, $i, $iR, $aM, $fMs, $aTargets, $aBlocked, 2)
            $iDone += 1
        Next
        _SmartRank($aRows)
    EndIf

    ; Ölçülmeyen (atlanan / durdurma sonrası) satırları at
    Local $aOut[0][$SMART_COL_COUNT], $iWorking = 0
    For $i = 0 To $nC - 1
        If $aRows[$i][$SMART_COL_PHASE] = 0 Then ContinueLoop
        Local $n = UBound($aOut)
        ReDim $aOut[$n + 1][$SMART_COL_COUNT]
        For $c = 0 To $SMART_COL_COUNT - 1
            $aOut[$n][$c] = $aRows[$i][$c]
        Next
        If $aRows[$i][$SMART_COL_SCORE] > 0 Then $iWorking += 1
    Next

    $sSummary = "Engelli hedefler: " & $sBlocked & ($sFree = "" ? "" : " | Engelsiz: " & $sFree) & " | " & _
            $iWorking & "/" & $iMeasured & " strateji çalıştı"
    If $iSkipped > 0 Then $sSummary &= " | " & $iSkipped & " karmaşık aday atlandı (" & $sSkipReason & ")"
    If UBound($aOut) > 0 And $aOut[0][$SMART_COL_SCORE] > 0 Then $sSummary &= " | Önerilen puan: " & $aOut[0][$SMART_COL_SCORE]
    If $bAborted Then
        $sSummary &= " | Kullanıcı durdurdu"
        Return SetError(2, 0, $aOut)
    EndIf
    Return $aOut
EndFunc

Func __SmartFillRow(ByRef $aRows, $i, $sStrategy, $sSource)
    $aRows[$i][$SMART_COL_STRATEGY] = $sStrategy
    $aRows[$i][$SMART_COL_SCORE] = 0
    $aRows[$i][$SMART_COL_SUCCESS] = 0
    $aRows[$i][$SMART_COL_TLS13] = 0
    $aRows[$i][$SMART_COL_MS] = 0
    $aRows[$i][$SMART_COL_STABLE] = False
    $aRows[$i][$SMART_COL_PHASE] = 0
    $aRows[$i][$SMART_COL_DETAIL] = ""
    $aRows[$i][$SMART_COL_SOURCE] = $sSource
EndFunc

Func __SmartScoreRow(ByRef $aRows, $i, $iMeasureResult, ByRef $aM, $fMs, ByRef $aTargets, ByRef $aBlocked, $iPhase)
    $aRows[$i][$SMART_COL_PHASE] = $iPhase
    If $iMeasureResult = 0 Then
        $aRows[$i][$SMART_COL_DETAIL] = "winws2 başlatılamadı (geçersiz parametre olabilir)"
        $aRows[$i][$SMART_COL_SCORE] = 0
        Return
    EndIf
    Local $fSucc = _SmartSuccessRatio($aM, $aTargets, $aBlocked)
    $aRows[$i][$SMART_COL_SUCCESS] = Round($fSucc * 100)
    $aRows[$i][$SMART_COL_TLS13] = Round(_SmartSuccessRatio($aM, $aTargets, $aBlocked, True) * 100)
    $aRows[$i][$SMART_COL_MS] = Round($fMs)
    $aRows[$i][$SMART_COL_SCORE] = _SmartScore($fSucc, $fMs, $aRows[$i][$SMART_COL_STRATEGY])
    $aRows[$i][$SMART_COL_STABLE] = ($iPhase = 2 And $fSucc >= $SMART_STABLE_RATIO)
    $aRows[$i][$SMART_COL_DETAIL] = _SmartDetail($aM, $aTargets, $aBlocked)
EndFunc

; İlk adayların hepsinde winws2 başlatılamadıysa sorun stratejide değil motorda/sürücüdedir:
; analizi sürdürmek yanıltıcı 0.0 puanlar üretir (2026-10-24, H20).
Func _SmartEngineFailed($iMeasured, $iStartFail)
    Return $iMeasured >= 5 And $iStartFail = $iMeasured
EndFunc
