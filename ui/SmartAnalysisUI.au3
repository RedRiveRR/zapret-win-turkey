#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ProgressConstants.au3>
#include <ListViewConstants.au3>
#include <GuiListView.au3>
#include <FileConstants.au3>
#include <EditConstants.au3>
#include "..\lib\SmartAnalysis.au3"
#include "..\lib\Log.au3"
#include "..\lib\Process.au3"

; =========================================================================
; --- AKILLI ANALİZ ARAYÜZÜ ---
; Seçici, ilerleme ve sonuç pencereleri. Ölçüm mantığı lib/SmartAnalysis.au3'te.
; =========================================================================

Global Const $SMARTUI_CANCEL = 0
Global Const $SMARTUI_FULL = 1
Global Const $SMARTUI_QUICK = 2
Global Const $SMARTUI_PREV_LIST = 3
Global Const $SMARTUI_PREV_SMART = 4

Global $__g_idSmartBar = 0, $__g_idSmartPhase = 0, $__g_idSmartElapsed = 0, $__g_idSmartStop = 0
Global $__g_hSmartTimer = 0, $__g_sSmartLastText = "", $__g_iSmartLastPct = -1, $__g_iSmartLastSec = -1, $__g_bSmartStopping = False

Global Const $SMARTUI_BROWSER_NOTE = "Not: Tarayıcı Discord'u QUIC ile zapret olmadan da açabildiği için tarayıcıda denemek yanıltıcıdır. " & _
        "Discord uygulamasını tepsiden tamamen kapatıp yeniden açarak deneyin."

; Analiz türü seçici. Dönüş: $SMARTUI_* sabiti.
Func _SmartUI_Chooser($bHasPrevList, $bHasPrevSmart, $hParent)
    GUISetState(@SW_DISABLE, $hParent)
    Local $h = GUICreate("ISS Analizi", 440, 330, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hParent)
    GUISetBkColor(0xFFFFFF, $h)
    GUICtrlCreateLabel("Nasıl bir analiz yapılsın?", 20, 14, 400, 24)
    GUICtrlSetFont(-1, 11, 700, 0, "Segoe UI")

    Local $bFull = GUICtrlCreateButton("Tam analiz (önerilen)", 20, 46, 400, 38)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")
    __SmartUI_Hint("ISS'iniz baştan taranır, bulunan stratejiler otomatik sınanıp en uygunu seçilir. (10-15 dk)", 20, 86)

    Local $bQuick = GUICtrlCreateButton("Hızlı akıllı test", 20, 120, 400, 38)
    GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")
    __SmartUI_Hint("Tarama yapılmaz; hazır profiller, kayıtlı ve önceki stratejiler sınanır. (1-3 dk)", 20, 160)

    Local $bPrevSmart = GUICtrlCreateButton("Önceki akıllı analiz sonucu", 20, 200, 195, 34)
    Local $bPrevList = GUICtrlCreateButton("Önceki tarama listesi (elle)", 225, 200, 195, 34)
    If Not $bHasPrevSmart Then GUICtrlSetState($bPrevSmart, $GUI_DISABLE)
    If Not $bHasPrevList Then GUICtrlSetState($bPrevList, $GUI_DISABLE)

    __SmartUI_Hint("Analiz sırasında internet bağlantınızda kısa kesintiler olabilir.", 20, 246)
    Local $bCancel = GUICtrlCreateButton("Vazgeç", 160, 276, 120, 32)
    GUISetState(@SW_SHOW, $h)

    Local $iChoice = $SMARTUI_CANCEL
    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $bCancel
                ExitLoop
            Case $bFull
                $iChoice = $SMARTUI_FULL
                ExitLoop
            Case $bQuick
                $iChoice = $SMARTUI_QUICK
                ExitLoop
            Case $bPrevSmart
                $iChoice = $SMARTUI_PREV_SMART
                ExitLoop
            Case $bPrevList
                $iChoice = $SMARTUI_PREV_LIST
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($h)
    GUISetState(@SW_ENABLE, $hParent)
    Return $iChoice
EndFunc

Func __SmartUI_Hint($sText, $iX, $iY)
    GUICtrlCreateLabel($sText, $iX, $iY, 400, 30)
    GUICtrlSetFont(-1, 8.5, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x666666)
EndFunc

; Analizi çalıştırır ve sonuç penceresini gösterir.
;   $sStrategyFile: "Kullan" denince stratejinin yazılacağı dosya ("" ise yazılmaz)
; Dönüş: kullanıcının seçtiği strateji ("" = seçilmedi).
Func _SmartUI_Run(ByRef $aCandidates, $sRoot, $sWinwsPath, $sTargetsSpec, $sResultsPath, $sStrategyFile, $hParent)
    If UBound($aCandidates) = 0 Then
        MsgBox(48 + 8192, "Akıllı Analiz", "Sınanacak strateji bulunamadı.")
        Return ""
    EndIf
    Local $sNull, $sCurl = _SmartFindCurl($sRoot, $sNull)
    If $sCurl = "" Then
        MsgBox(16 + 8192, "Akıllı Analiz", "Bağlantı testi için curl bulunamadı.")
        Return ""
    EndIf

    Local $iMin = _SmartEstimateMinutes(UBound($aCandidates))
    Local $hProg = GUICreate("Akıllı Analiz", 520, 190, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hParent)
    GUISetBkColor(0xFFFFFF, $hProg)
    GUICtrlCreateLabel(UBound($aCandidates) & " strateji sınanıyor (tahmini " & $iMin & " dk)", 18, 14, 484, 24, $SS_CENTER)
    GUICtrlSetFont(-1, 11, 700, 0, "Segoe UI")
    $__g_idSmartPhase = GUICtrlCreateLabel("Hazırlanıyor...", 18, 46, 484, 36, $SS_CENTER)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $__g_idSmartBar = GUICtrlCreateProgress(18, 88, 484, 18)
    $__g_idSmartElapsed = GUICtrlCreateLabel("Geçen süre: 00:00", 18, 112, 484, 20, $SS_CENTER)
    $__g_idSmartStop = GUICtrlCreateButton("Durdur (şimdiye kadarki sonuçları göster)", 110, 140, 300, 32)
    GUISetState(@SW_SHOW, $hProg)
    $__g_hSmartTimer = TimerInit()
    $__g_sSmartLastText = ""
    $__g_iSmartLastPct = -1
    $__g_iSmartLastSec = -1
    $__g_bSmartStopping = False

    Local $sSummary
    Local $aRows = _SmartAnalyze($aCandidates, $sWinwsPath, $sCurl, $sNull, $sTargetsSpec, "__SmartUI_Progress", $sSummary)
    Local $iErr = @error
    Local $iSecs = Int(TimerDiff($__g_hSmartTimer) / 1000)
    GUIDelete($hProg)
    ; Güvenlik: test için açılmış winws2 kalmasın (analiz yalnızca zapret kapalıyken çalışır).
    _KillProcessesUnderDir($sRoot & "\bin\zapret\zapret-winws")

    _LogInfo("Akıllı analiz bitti (" & $iSecs & " sn, hata=" & $iErr & "): " & $sSummary)
    If $iErr = 1 Then
        MsgBox(64 + 8192, "Akıllı Analiz", $sSummary & @CRLF & @CRLF & "DNS ayarınız doğruysa Zapret'e gerek olmayabilir.")
        Return ""
    ElseIf $iErr = 3 Then
        MsgBox(16 + 8192, "Akıllı Analiz", "Analiz başlatılamadı (hedef listesi geçersiz).")
        Return ""
    EndIf
    If UBound($aRows) = 0 Then
        MsgBox(48 + 8192, "Akıllı Analiz", "Hiçbir strateji ölçülemedi." & @CRLF & $sSummary)
        Return ""
    EndIf
    For $i = 0 To 2
        If $i >= UBound($aRows) Then ExitLoop
        _LogInfo("Akıllı analiz #" & ($i + 1) & " puan " & $aRows[$i][$SMART_COL_SCORE] & ", başarı %" & $aRows[$i][$SMART_COL_SUCCESS] & _
                ", " & $aRows[$i][$SMART_COL_MS] & " ms: " & $aRows[$i][$SMART_COL_STRATEGY])
    Next
    _SmartSaveResults($sResultsPath, $aRows, $sSummary)
    Return _SmartUI_ShowResults($aRows, $sSummary, $sStrategyFile, $sWinwsPath, $hParent)
EndFunc

; Motor bu fonksiyonu ~25 ms'de bir çağırır: yalnızca değişen denetimler güncellenir
; (her çağrıda yazmak pencereyi titretir ve tıklamaları geciktirir).
Func __SmartUI_Progress($iDone, $iTotal, $sText)
    If $__g_bSmartStopping Then Return False
    Local $iPct = ($iTotal > 0) ? Int($iDone * 100 / $iTotal) : 0
    If $iPct <> $__g_iSmartLastPct Then
        GUICtrlSetData($__g_idSmartBar, $iPct)
        $__g_iSmartLastPct = $iPct
    EndIf
    If $sText <> $__g_sSmartLastText Then
        GUICtrlSetData($__g_idSmartPhase, $sText)
        $__g_sSmartLastText = $sText
    EndIf
    Local $iSecs = Int(TimerDiff($__g_hSmartTimer) / 1000)
    If $iSecs <> $__g_iSmartLastSec Then
        GUICtrlSetData($__g_idSmartElapsed, "Geçen süre: " & StringFormat("%02d:%02d", Int($iSecs / 60), Mod($iSecs, 60)) & "   |   %" & $iPct)
        $__g_iSmartLastSec = $iSecs
    EndIf
    Local $nMsg = GUIGetMsg()
    If $nMsg = $__g_idSmartStop Or $nMsg = $GUI_EVENT_CLOSE Then
        ; Anında geri bildirim: çalışan ölçüm birkaç yüz ms içinde kapanır.
        $__g_bSmartStopping = True
        GUICtrlSetState($__g_idSmartStop, $GUI_DISABLE)
        GUICtrlSetData($__g_idSmartStop, "Durduruluyor...")
        GUICtrlSetData($__g_idSmartPhase, "Durduruluyor, şimdiye kadarki sonuçlar hazırlanıyor...")
        Return False
    EndIf
    Return True
EndFunc

; Önceki sonuç dosyasını açar.
Func _SmartUI_ShowSaved($sResultsPath, $sStrategyFile, $sWinwsPath, $hParent)
    Local $sSummary
    Local $aRows = _SmartLoadResults($sResultsPath, $sSummary)
    If UBound($aRows) = 0 Then
        MsgBox(48 + 8192, "Akıllı Analiz", "Kayıtlı akıllı analiz sonucu bulunamadı.")
        Return ""
    EndIf
    Return _SmartUI_ShowResults($aRows, $sSummary, $sStrategyFile, $sWinwsPath, $hParent)
EndFunc

; Durum metni
Func _SmartUI_StatusText(ByRef $aRows, $i)
    If $aRows[$i][$SMART_COL_SCORE] <= 0 Then Return "çalışmadı"
    If $aRows[$i][$SMART_COL_PHASE] < 2 Then Return "yalnız eleme"
    If $aRows[$i][$SMART_COL_STABLE] Then Return "kararlı"
    Return "dalgalı"
EndFunc

; Sonuç tablosu. Dönüş: kullanılmak üzere seçilen strateji ya da "".
Func _SmartUI_ShowResults(ByRef $aRows, $sSummary, $sStrategyFile, $sWinwsPath, $hParent)
    GUISetState(@SW_DISABLE, $hParent)
    Local $h = GUICreate("Akıllı Analiz Sonuçları", 820, 540, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hParent)
    GUISetBkColor(0xFFFFFF, $h)

    Local $bHasBest = $aRows[0][$SMART_COL_SCORE] > 0
    GUICtrlCreateLabel($bHasBest ? "★ Önerilen strateji listenin en üstünde." : "Çalışan strateji bulunamadı.", 15, 10, 790, 22)
    GUICtrlSetFont(-1, 11, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, $bHasBest ? 0x1B5E20 : 0xB71C1C)
    GUICtrlCreateLabel($sSummary, 15, 34, 790, 32)
    GUICtrlSetFont(-1, 8.5, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x555555)

    Local $idLV = GUICtrlCreateListView("#|Puan|Başarı %|TLS1.3 %|Gecikme ms|Durum|Kaynak|Strateji", 15, 70, 790, 280, _
            BitOR($LVS_SHOWSELALWAYS, $LVS_SINGLESEL, $LVS_REPORT), BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES))
    Local $n = UBound($aRows)
    Local $aItems[$n]
    For $i = 0 To $n - 1
        Local $sRank = ($i = 0 And $bHasBest) ? "★ 1" : String($i + 1)
        $aItems[$i] = GUICtrlCreateListViewItem($sRank & "|" & $aRows[$i][$SMART_COL_SCORE] & "|" & $aRows[$i][$SMART_COL_SUCCESS] & "|" & _
                $aRows[$i][$SMART_COL_TLS13] & "|" & $aRows[$i][$SMART_COL_MS] & "|" & _SmartUI_StatusText($aRows, $i) & "|" & _
                $aRows[$i][$SMART_COL_SOURCE] & "|" & $aRows[$i][$SMART_COL_STRATEGY], $idLV)
    Next
    Local $aWidths[8] = [40, 50, 65, 65, 80, 85, 140, 900]
    For $c = 0 To 7
        _GUICtrlListView_SetColumnWidth($idLV, $c, $aWidths[$c])
    Next

    GUICtrlCreateLabel("Seçili strateji ayrıntısı:", 15, 358, 790, 18)
    GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
    Local $idDetail = GUICtrlCreateEdit("", 15, 378, 790, 58, BitOR($ES_READONLY, $ES_AUTOVSCROLL, $WS_VSCROLL))
    Local $idNote = GUICtrlCreateLabel($SMARTUI_BROWSER_NOTE, 15, 440, 790, 30)
    GUICtrlSetFont($idNote, 8.5, 400, 0, "Segoe UI")
    GUICtrlSetColor($idNote, 0x8A4B08)

    Local $bUseBest = GUICtrlCreateButton("★ Önerileni Kullan", 15, 482, 190, 36)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")
    Local $bUseSel = GUICtrlCreateButton("Seçileni Kullan", 215, 482, 160, 36)
    Local $bTry = GUICtrlCreateButton("Seçileni Dene", 385, 482, 160, 36)
    Local $bClose = GUICtrlCreateButton("Kapat", 685, 482, 120, 36)
    If Not $bHasBest Then GUICtrlSetState($bUseBest, $GUI_DISABLE)
    GUISetState(@SW_SHOW, $h)

    Local $iSel = 0, $iTryPid = 0, $sChosen = ""
    _GUICtrlListView_SetItemSelected($idLV, 0)
    __SmartUI_ShowDetail($aRows, 0, $idDetail)

    While 1
        Local $nMsg = GUIGetMsg()
        Switch $nMsg
            Case $GUI_EVENT_CLOSE, $bClose
                ExitLoop
            Case $bUseBest
                $sChosen = $aRows[0][$SMART_COL_STRATEGY]
                ExitLoop
            Case $bUseSel
                $iSel = __SmartUI_Selected($idLV)
                If $iSel < 0 Then ContinueLoop
                If $aRows[$iSel][$SMART_COL_SCORE] <= 0 Then
                    If MsgBox(36 + 8192, "Akıllı Analiz", "Bu strateji testlerde çalışmadı. Yine de kullanılsın mı?") <> 6 Then ContinueLoop
                EndIf
                $sChosen = $aRows[$iSel][$SMART_COL_STRATEGY]
                ExitLoop
            Case $bTry
                If $iTryPid > 0 Then
                    __SmartStopWinws($iTryPid)
                    $iTryPid = 0
                    GUICtrlSetData($bTry, "Seçileni Dene")
                    GUICtrlSetData($idNote, $SMARTUI_BROWSER_NOTE)
                Else
                    $iSel = __SmartUI_Selected($idLV)
                    If $iSel < 0 Then ContinueLoop
                    GUICtrlSetState($bTry, $GUI_DISABLE)
                    GUICtrlSetData($bTry, "Başlatılıyor...")
                    $iTryPid = __SmartStartWinws($sWinwsPath, $aRows[$iSel][$SMART_COL_STRATEGY])
                    GUICtrlSetState($bTry, $GUI_ENABLE)
                    GUICtrlSetData($bTry, "Seçileni Dene")
                    If $iTryPid > 0 Then
                        GUICtrlSetData($bTry, "Denemeyi Durdur")
                        GUICtrlSetData($idNote, "DENEME ÇALIŞIYOR (#" & ($iSel + 1) & ") — Discord uygulamasını tamamen kapatıp açın; bağlanıyorsa strateji çalışıyor.")
                    Else
                        MsgBox(16 + 8192, "Akıllı Analiz", "winws2 başlatılamadı.")
                    EndIf
                EndIf
            Case Else
                ; Satır öğelerinin denetim kimlikleri ardışıktır: döngü yerine doğrudan hesapla
                ; (yüzlerce satırda her olayda dizi taramak tepkiyi yavaşlatıyordu).
                If $nMsg > 0 And $n > 0 And $nMsg >= $aItems[0] And $nMsg <= $aItems[$n - 1] Then
                    Local $iIdx = $nMsg - $aItems[0]
                    If $aItems[$iIdx] = $nMsg Then __SmartUI_ShowDetail($aRows, $iIdx, $idDetail)
                EndIf
        EndSwitch
        ; Deneme süreci dışarıdan kapanırsa düğmeyi düzelt
        If $iTryPid > 0 And Not ProcessExists($iTryPid) Then
            $iTryPid = 0
            GUICtrlSetData($bTry, "Seçileni Dene")
            GUICtrlSetData($idNote, "Deneme süreci kapandı.")
        EndIf
    WEnd

    If $iTryPid > 0 Then __SmartStopWinws($iTryPid)
    GUIDelete($h)
    GUISetState(@SW_ENABLE, $hParent)

    If $sChosen <> "" And $sStrategyFile <> "" Then
        Local $hF = FileOpen($sStrategyFile, $FO_OVERWRITE)
        If $hF = -1 Then
            MsgBox(16 + 8192, "Kayıt Hatası", "Strateji dosyasına yazılamadı:" & @CRLF & $sStrategyFile)
            Return ""
        EndIf
        FileWrite($hF, $sChosen)
        FileClose($hF)
    EndIf
    If $sChosen <> "" Then
        _LogInfo("Akıllı analiz: strateji seçildi: " & $sChosen)
        MsgBox(64 + 8192, "Strateji Kaydedildi", "Strateji kaydedildi. Zapret'i başlatıp Discord uygulamasını yeniden açarak deneyebilirsiniz.")
    EndIf
    Return $sChosen
EndFunc

Func __SmartUI_Selected($idLV)
    Local $aSel = _GUICtrlListView_GetSelectedIndices($idLV, True)
    If Not IsArray($aSel) Or $aSel[0] = 0 Then Return -1
    Return $aSel[1]
EndFunc

Func __SmartUI_ShowDetail(ByRef $aRows, $i, $idDetail)
    GUICtrlSetData($idDetail, "#" & ($i + 1) & " | " & _SmartUI_StatusText($aRows, $i) & " | Puan " & $aRows[$i][$SMART_COL_SCORE] & _
            " | Kaynak: " & $aRows[$i][$SMART_COL_SOURCE] & @CRLF & "Hedefler: " & $aRows[$i][$SMART_COL_DETAIL] & @CRLF & $aRows[$i][$SMART_COL_STRATEGY])
EndFunc
