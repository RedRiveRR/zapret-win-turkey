#include-once
#include <WinAPISysWin.au3>

; =========================================================================
; --- WEBVIEW2 BAĞLANTISI (yeni arayüz) ---
; Bir AutoIt penceresinin içine WebView2 yerleştirir; sayfa ile JSON mesajlaşır.
; COM arayüzleri WebView2Loader.dll üzerinden elle çağrılır (vtable sıraları
; WebView2.h 1.0.2903.40'tan). Tek örnek: bir programda bir WebView2.
;
; Akış: _WV2_Create (eşzamansız) -> ana döngüde _WV2_State ile hazır/başarısız
; izlenir; sayfadan gelen mesajlar kuyruğa alınır, _WV2_NextMessage ile ana
; döngüde işlenir (geri çağrının içinde ağır iş yapılmaz).
; =========================================================================

Global Const $WV2_STATE_NONE = 0, $WV2_STATE_STARTING = 1, $WV2_STATE_READY = 2, $WV2_STATE_FAILED = 3
Global $__g_WV2_iState = $WV2_STATE_NONE
Global $__g_WV2_hWnd = 0, $__g_WV2_sUrl = "", $__g_WV2_sError = ""
Global $__g_WV2_pEnv = 0, $__g_WV2_pCtrl = 0, $__g_WV2_pView = 0
Global $__g_WV2_aQueue[0], $__g_WV2_aQueueT[0]
Global $__g_WV2_aKeep[0]
Global $__g_WV2_hQI = 0, $__g_WV2_hAddRef = 0, $__g_WV2_hRelease = 0
Global $__g_WV2_pEnvHandler = 0, $__g_WV2_pCtrlHandler = 0, $__g_WV2_pMsgHandler = 0, $__g_WV2_pScriptHandler = 0

; Yüklü WebView2 çalışma zamanının sürümü; yoksa "".
Func _WV2_RuntimeVersion()
    Local Const $sClient = "\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    Local $aKeys[3] = ["HKLM64\SOFTWARE\WOW6432Node" & $sClient, "HKLM64\SOFTWARE" & $sClient, "HKCU\Software" & $sClient]
    For $sKey In $aKeys
        Local $sVer = RegRead($sKey, "pv")
        If $sVer <> "" And $sVer <> "0.0.0.0" Then Return $sVer
    Next
    Return ""
EndFunc

; WebView2'yi $hWnd'nin istemci alanına yerleştirmeye başlar. Başlatılamazsa False.
;   $sDll: WebView2Loader.dll yolu, $sUserData: tarayıcı verisi klasörü (yazılabilir olmalı).
Func _WV2_Create($hWnd, $sDll, $sUserData, $sUrl)
    If Not FileExists($sDll) Then Return __WV2_Fail("WebView2Loader.dll bulunamadı: " & $sDll)
    If _WV2_RuntimeVersion() = "" Then Return __WV2_Fail("WebView2 çalışma zamanı yüklü değil")
    __WV2_InitHandlers()
    $__g_WV2_hWnd = $hWnd
    $__g_WV2_sUrl = $sUrl
    DirCreate($sUserData)
    $__g_WV2_iState = $WV2_STATE_STARTING
    Local $a = DllCall($sDll, "long", "CreateCoreWebView2EnvironmentWithOptions", "ptr", 0, "wstr", $sUserData, "ptr", 0, "ptr", $__g_WV2_pEnvHandler)
    If @error Then Return __WV2_Fail("WebView2Loader.dll çağrılamadı (@error " & @error & ")")
    If $a[0] <> 0 Then Return __WV2_Fail("WebView2 ortamı oluşturulamadı (0x" & Hex($a[0], 8) & ")")
    Return True
EndFunc

Func _WV2_State()
    Return $__g_WV2_iState
EndFunc

Func _WV2_LastError()
    Return $__g_WV2_sError
EndFunc

; Sayfaya JSON mesajı gönderir (sayfada window.chrome.webview 'message' olayı).
Func _WV2_Post($sJson)
    If $__g_WV2_pView = 0 Then Return False
    Local $a = DllCallAddress("long", __WV2_Vt($__g_WV2_pView, 32), "ptr", $__g_WV2_pView, "wstr", $sJson) ; PostWebMessageAsJson
    Return $a[0] = 0
EndFunc

; Sayfada betik çalıştırır (sonuç beklenmez).
Func _WV2_Exec($sScript)
    If $__g_WV2_pView = 0 Then Return False
    Local $a = DllCallAddress("long", __WV2_Vt($__g_WV2_pView, 29), "ptr", $__g_WV2_pView, "wstr", $sScript, "ptr", $__g_WV2_pScriptHandler) ; ExecuteScript
    Return $a[0] = 0
EndFunc

; Kuyruktaki ilk sayfa mesajını (JSON) döndürür; boşsa "".
; @extended: mesajın kuyrukta beklediği süre (ms). Uzun bir iş sürerken (ör. analiz)
; kuyrukta kalmış komutlar bu süreye bakılarak yok sayılabilir.
Func _WV2_NextMessage()
    If UBound($__g_WV2_aQueue) = 0 Then Return ""
    Local $s = $__g_WV2_aQueue[0]
    Local $iAge = Int(TimerDiff($__g_WV2_aQueueT[0]))
    If UBound($__g_WV2_aQueue) = 1 Then
        Local $aEmpty[0], $aEmptyT[0]
        $__g_WV2_aQueue = $aEmpty
        $__g_WV2_aQueueT = $aEmptyT
    Else
        For $i = 1 To UBound($__g_WV2_aQueue) - 1
            $__g_WV2_aQueue[$i - 1] = $__g_WV2_aQueue[$i]
            $__g_WV2_aQueueT[$i - 1] = $__g_WV2_aQueueT[$i]
        Next
        ReDim $__g_WV2_aQueue[UBound($__g_WV2_aQueue) - 1]
        ReDim $__g_WV2_aQueueT[UBound($__g_WV2_aQueueT) - 1]
    EndIf
    Return SetExtended($iAge, $s)
EndFunc

; Pencere boyutu değişince çağrılır (WM_SIZE).
Func _WV2_Resize()
    If $__g_WV2_pCtrl = 0 Then Return
    Local $tRect = _WinAPI_GetClientRect($__g_WV2_hWnd)
    DllCallAddress("long", __WV2_Vt($__g_WV2_pCtrl, 6), "ptr", $__g_WV2_pCtrl, "struct*", $tRect) ; put_Bounds
EndFunc

; Pencere başlık çubuğunu sayfanın temasına uydurur ($iCaptionRgb: başlık rengi, RGB).
Func _WV2_SetCaption($hWnd, $bDark, $iCaptionRgb)
    DllCall("dwmapi.dll", "long", "DwmSetWindowAttribute", "hwnd", $hWnd, "dword", 20, "int*", $bDark ? 1 : 0, "dword", 4)
    Local $iBgr = BitOR(BitShift(BitAND($iCaptionRgb, 0xFF), -16), BitAND($iCaptionRgb, 0xFF00), BitShift(BitAND($iCaptionRgb, 0xFF0000), 16))
    DllCall("dwmapi.dll", "long", "DwmSetWindowAttribute", "hwnd", $hWnd, "dword", 35, "dword*", $iBgr, "dword", 4)
EndFunc

; Pencere gizlenip gösterilirken WebView2'nin görünürlüğü.
Func _WV2_SetVisible($bVisible)
    If $__g_WV2_pCtrl = 0 Then Return
    DllCallAddress("long", __WV2_Vt($__g_WV2_pCtrl, 4), "ptr", $__g_WV2_pCtrl, "bool", $bVisible) ; put_IsVisible
EndFunc

Func _WV2_Close()
    If $__g_WV2_pCtrl <> 0 Then DllCallAddress("long", __WV2_Vt($__g_WV2_pCtrl, 24), "ptr", $__g_WV2_pCtrl) ; Close
    $__g_WV2_pCtrl = 0
    $__g_WV2_pView = 0
    $__g_WV2_iState = $WV2_STATE_NONE
EndFunc

; --- iç işler ---
Func __WV2_Fail($sWhy)
    $__g_WV2_sError = $sWhy
    $__g_WV2_iState = $WV2_STATE_FAILED
    Return False
EndFunc

Func __WV2_Vt($pObj, $iIdx)
    Local $pVt = DllStructGetData(DllStructCreate("ptr", $pObj), 1)
    Return DllStructGetData(DllStructCreate("ptr", $pVt + $iIdx * 8), 1)
EndFunc

Func __WV2_AddRef($pObj)
    DllCallAddress("ulong", __WV2_Vt($pObj, 1), "ptr", $pObj)
EndFunc

Func __WV2_InitHandlers()
    If $__g_WV2_hQI <> 0 Then Return
    $__g_WV2_hQI = DllCallbackRegister("__WV2_QI", "long", "ptr;ptr;ptr")
    $__g_WV2_hAddRef = DllCallbackRegister("__WV2_Ref", "ulong", "ptr")
    $__g_WV2_hRelease = DllCallbackRegister("__WV2_Ref", "ulong", "ptr")
    $__g_WV2_pEnvHandler = __WV2_MakeHandler("__WV2_OnEnvironment", "ptr;long;ptr")
    $__g_WV2_pCtrlHandler = __WV2_MakeHandler("__WV2_OnController", "ptr;long;ptr")
    $__g_WV2_pMsgHandler = __WV2_MakeHandler("__WV2_OnMessage", "ptr;ptr;ptr")
    $__g_WV2_pScriptHandler = __WV2_MakeHandler("__WV2_OnScript", "ptr;long;ptr")
EndFunc

; Tek metotlu (Invoke) COM tamamlama/olay işleyicisi nesnesi kurar.
Func __WV2_MakeHandler($sFunc, $sSig)
    Local $hInvoke = DllCallbackRegister($sFunc, "long", $sSig)
    Local $tVt = DllStructCreate("ptr;ptr;ptr;ptr")
    DllStructSetData($tVt, 1, DllCallbackGetPtr($__g_WV2_hQI))
    DllStructSetData($tVt, 2, DllCallbackGetPtr($__g_WV2_hAddRef))
    DllStructSetData($tVt, 3, DllCallbackGetPtr($__g_WV2_hRelease))
    DllStructSetData($tVt, 4, DllCallbackGetPtr($hInvoke))
    Local $tObj = DllStructCreate("ptr")
    DllStructSetData($tObj, 1, DllStructGetPtr($tVt))
    ; Yapılar program boyunca yaşamalı.
    Local $n = UBound($__g_WV2_aKeep)
    ReDim $__g_WV2_aKeep[$n + 3]
    $__g_WV2_aKeep[$n] = $tVt
    $__g_WV2_aKeep[$n + 1] = $tObj
    $__g_WV2_aKeep[$n + 2] = $hInvoke
    Return DllStructGetPtr($tObj)
EndFunc

Func __WV2_QI($pThis, $pRiid, $ppv)
    #forceref $pRiid
    DllStructSetData(DllStructCreate("ptr", $ppv), 1, $pThis)
    Return 0
EndFunc

; İşleyiciler program boyunca yaşadığı için başvuru sayımı gerekmez.
Func __WV2_Ref($pThis)
    #forceref $pThis
    Return 1
EndFunc

Func __WV2_OnEnvironment($pThis, $hr, $pEnv)
    #forceref $pThis
    If $hr <> 0 Or $pEnv = 0 Then
        __WV2_Fail("WebView2 ortamı başlatılamadı (0x" & Hex($hr, 8) & ")")
        Return 0
    EndIf
    $__g_WV2_pEnv = $pEnv
    __WV2_AddRef($pEnv)
    Local $a = DllCallAddress("long", __WV2_Vt($pEnv, 3), "ptr", $pEnv, "hwnd", $__g_WV2_hWnd, "ptr", $__g_WV2_pCtrlHandler) ; CreateCoreWebView2Controller
    If $a[0] <> 0 Then __WV2_Fail("WebView2 denetleyicisi istenemedi (0x" & Hex($a[0], 8) & ")")
    Return 0
EndFunc

Func __WV2_OnController($pThis, $hr, $pCtrl)
    #forceref $pThis
    If $hr <> 0 Or $pCtrl = 0 Then
        __WV2_Fail("WebView2 denetleyicisi oluşturulamadı (0x" & Hex($hr, 8) & ")")
        Return 0
    EndIf
    $__g_WV2_pCtrl = $pCtrl
    __WV2_AddRef($pCtrl)
    _WV2_Resize()
    Local $a = DllCallAddress("long", __WV2_Vt($pCtrl, 25), "ptr", $pCtrl, "ptr*", 0) ; get_CoreWebView2
    $__g_WV2_pView = $a[2]
    If $__g_WV2_pView = 0 Then
        __WV2_Fail("WebView2 görünümü alınamadı")
        Return 0
    EndIf
    __WV2_AddRef($__g_WV2_pView)
    ; Ayarlar: sağ tık menüsü, yakınlaştırma, durum çubuğu ve geliştirici araçları kapalı.
    Local $aS = DllCallAddress("long", __WV2_Vt($__g_WV2_pView, 3), "ptr", $__g_WV2_pView, "ptr*", 0) ; get_Settings
    Local $pSet = $aS[2]
    If $pSet <> 0 Then
        DllCallAddress("long", __WV2_Vt($pSet, 10), "ptr", $pSet, "bool", False) ; put_IsStatusBarEnabled
        DllCallAddress("long", __WV2_Vt($pSet, 12), "ptr", $pSet, "bool", False) ; put_AreDevToolsEnabled
        DllCallAddress("long", __WV2_Vt($pSet, 14), "ptr", $pSet, "bool", False) ; put_AreDefaultContextMenusEnabled
        DllCallAddress("long", __WV2_Vt($pSet, 18), "ptr", $pSet, "bool", False) ; put_IsZoomControlEnabled
    EndIf
    Local $tToken = DllStructCreate("int64")
    DllCallAddress("long", __WV2_Vt($__g_WV2_pView, 34), "ptr", $__g_WV2_pView, "ptr", $__g_WV2_pMsgHandler, "struct*", $tToken) ; add_WebMessageReceived
    Local $aN = DllCallAddress("long", __WV2_Vt($__g_WV2_pView, 5), "ptr", $__g_WV2_pView, "wstr", $__g_WV2_sUrl) ; Navigate
    If $aN[0] <> 0 Then
        __WV2_Fail("Arayüz sayfası açılamadı (0x" & Hex($aN[0], 8) & ")")
        Return 0
    EndIf
    $__g_WV2_iState = $WV2_STATE_READY
    Return 0
EndFunc

; Sayfadan gelen mesaj: yalnızca kuyruğa alınır.
Func __WV2_OnMessage($pThis, $pSender, $pArgs)
    #forceref $pThis, $pSender
    Local $a = DllCallAddress("long", __WV2_Vt($pArgs, 4), "ptr", $pArgs, "ptr*", 0) ; get_WebMessageAsJson
    If $a[0] <> 0 Or $a[2] = 0 Then Return 0
    Local $aLen = DllCall("kernel32.dll", "int", "lstrlenW", "ptr", $a[2])
    Local $sJson = DllStructGetData(DllStructCreate("wchar[" & ($aLen[0] + 1) & "]", $a[2]), 1)
    DllCall("ole32.dll", "none", "CoTaskMemFree", "ptr", $a[2])
    Local $n = UBound($__g_WV2_aQueue)
    If $n >= 64 Then Return 0 ; aşırı mesaj: yok say
    ReDim $__g_WV2_aQueue[$n + 1]
    ReDim $__g_WV2_aQueueT[$n + 1]
    $__g_WV2_aQueue[$n] = $sJson
    $__g_WV2_aQueueT[$n] = TimerInit()
    Return 0
EndFunc

Func __WV2_OnScript($pThis, $hr, $pResult)
    #forceref $pThis, $hr, $pResult
    Return 0
EndFunc
