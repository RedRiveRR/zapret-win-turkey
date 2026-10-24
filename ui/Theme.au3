#include-once
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <GDIPlus.au3>
#include <WinAPIGdi.au3>

; =========================================================================
; --- ARAYÜZ TEMASI (Discord benzeri koyu tema) ---
; Kartlar ve butonlar GDI+ ile kenar yumuşatmalı, yuvarlak köşeli görüntü
; olarak çizilir (Picture denetimi); yazı üstte saydam etikettir.
;
; Buton kimliği = üstteki etiket: GUIGetMsg tıklamada onu döndürür,
; GUICtrlSetState/GUICtrlSetData normal çalışır. Üzerine gelme ve devre dışı
; görünümü _UiTick() ile güncellenir (ana döngüde her turda çağrılmalı).
; Sayfa gösterme/gizleme için _UiSetVisible kullanılmalı (alt görüntü de gizlenir).
; =========================================================================

; --- Renkler (RGB) — RedRiveRR Zapret tasarımının koyu teması (ui/web/stil.css "koyu" ile aynı aile) ---
Global Const $UI_BG = 0x14161B
Global Const $UI_SIDEBAR = 0x101216
Global Const $UI_CARD = 0x1D2027
Global Const $UI_TEXT = 0xE7EAF0
Global Const $UI_TEXT2 = 0xB7BECB
Global Const $UI_MUTED = 0x99A2B2
Global Const $UI_ACCENT = 0x6466E0
Global Const $UI_GREEN = 0x2F9E6E
Global Const $UI_RED = 0xD33A45
Global Const $UI_YELLOW = 0xE5A53B
Global Const $UI_DISABLED_BG = 0x2A2E37
Global Const $UI_DISABLED_TX = 0x6F7787

Global Const $UI_FONT = "Segoe UI"
Global Const $UI_FONT_SEMI = "Segoe UI Semibold"
Global Const $UI_ICON_FONT = "Segoe MDL2 Assets"

; Segoe MDL2 Assets ikonları
Global Const $UI_ICON_HOME = 0xE80F
Global Const $UI_ICON_SEARCH = 0xE721
Global Const $UI_ICON_SHIELD = 0xEA18
Global Const $UI_ICON_SHARE = 0xE72D
Global Const $UI_ICON_GLOBE = 0xE774
Global Const $UI_ICON_SETTINGS = 0xE713
Global Const $UI_ICON_HEART = 0xEB51
Global Const $UI_ICON_INFO = 0xE946

; Buton türleri: [normal, üzerinde, yazı]
Global Const $UI_KIND_PRIMARY = 0
Global Const $UI_KIND_SUCCESS = 1
Global Const $UI_KIND_DANGER = 2
Global Const $UI_KIND_SECONDARY = 3
Global Const $UI_KIND_NAV = 4
Global Const $UI_KIND_NAV_ACTIVE = 5
Global $__g_aUiKinds[6][3] = [ _
        [$UI_ACCENT, 0x5153C8, 0xFFFFFF], _
        [$UI_GREEN, 0x268259, 0xFFFFFF], _
        [$UI_RED, 0xB52E38, 0xFFFFFF], _
        [0x2A2E37, 0x363B46, $UI_TEXT], _
        [$UI_SIDEBAR, 0x1D2027, $UI_TEXT2], _
        [0x2A2B4D, 0x2A2B4D, 0xB9BAFA]]

; Kayıtlı butonlar: etiket, görüntü, tür, son görünüm, genişlik, yükseklik, köşe, zemin,
;   x, y, yazı boyutu (-1: devre dışı yazısı çizilmez), bitmap'e çizilen yazı, ortalı mı
Global Const $__UI_BTN_COLS = 13
Global $__g_aUiBtn[0][$__UI_BTN_COLS]
; Aç/kapa anahtarları: [n][4] = etiket, görüntü, açık mı, zemin
Global $__g_aUiToggle[0][4]
; Etiket -> eşlik eden görüntü (_UiSetVisible için)
Global $__g_oUiCompanion = 0
; Çizilmiş görüntü önbelleği: "g|y|köşe|dolgu|zemin" -> HBITMAP
Global $__g_oUiBmp = 0

Func _UiInit()
    _GDIPlus_Startup()
    $__g_oUiCompanion = ObjCreate("Scripting.Dictionary")
    $__g_oUiBmp = ObjCreate("Scripting.Dictionary")
    DllCall("uxtheme.dll", "int", 135, "int", 2) ; SetPreferredAppMode(ForceDark): koyu açılır listeler
    DllCall("uxtheme.dll", "none", 136)          ; FlushMenuThemes
EndFunc

; RGB -> COLORREF (BGR)
Func __UiBgr($iRgb)
    Return BitOR(BitShift(BitAND($iRgb, 0xFF), -16), BitAND($iRgb, 0xFF00), BitShift(BitAND($iRgb, 0xFF0000), 16))
EndFunc

; Koyu başlık çubuğu ve başlık rengi (Windows 11'de tam, 10'da koyu başlık).
Func _UiDarkWindow($hWnd, $iCaption = $UI_SIDEBAR)
    DllCall("dwmapi.dll", "long", "DwmSetWindowAttribute", "hwnd", $hWnd, "dword", 20, "int*", 1, "dword", 4)
    DllCall("dwmapi.dll", "long", "DwmSetWindowAttribute", "hwnd", $hWnd, "dword", 35, "dword*", __UiBgr($iCaption), "dword", 4)
    GUISetBkColor($UI_BG, $hWnd)
EndFunc

; Yuvarlak köşeli dolgu görüntüsü (köşe dışı $iBack ile doldurulur). Önbelleklidir.
Func __UiRoundBitmap($w, $h, $r, $iFill, $iBack, $sText = "", $fSize = 10, $iText = 0, $bCenter = True)
    Local $sKey = $w & "|" & $h & "|" & $r & "|" & $iFill & "|" & $iBack & "|" & $sText & "|" & $fSize & "|" & $iText & "|" & $bCenter
    If $__g_oUiBmp.Exists($sKey) Then Return $__g_oUiBmp.Item($sKey)
    Local $hBmp = _GDIPlus_BitmapCreateFromScan0($w, $h)
    Local $hG = _GDIPlus_ImageGetGraphicsContext($hBmp)
    _GDIPlus_GraphicsSetSmoothingMode($hG, $GDIP_SMOOTHINGMODE_ANTIALIAS8X8)
    _GDIPlus_GraphicsClear($hG, BitOR(0xFF000000, $iBack))
    Local $hBrush = _GDIPlus_BrushCreateSolid(BitOR(0xFF000000, $iFill))
    If $r <= 0 Then
        _GDIPlus_GraphicsFillRect($hG, 0, 0, $w, $h, $hBrush)
    Else
        Local $d = $r * 2, $hPath = _GDIPlus_PathCreate()
        _GDIPlus_PathAddArc($hPath, 0, 0, $d, $d, 180, 90)
        _GDIPlus_PathAddArc($hPath, $w - $d - 1, 0, $d, $d, 270, 90)
        _GDIPlus_PathAddArc($hPath, $w - $d - 1, $h - $d - 1, $d, $d, 0, 90)
        _GDIPlus_PathAddArc($hPath, 0, $h - $d - 1, $d, $d, 90, 90)
        _GDIPlus_PathCloseFigure($hPath)
        _GDIPlus_GraphicsFillPath($hG, $hPath, $hBrush)
        _GDIPlus_PathDispose($hPath)
    EndIf
    _GDIPlus_BrushDispose($hBrush)
    If $sText <> "" Then
        _GDIPlus_GraphicsSetTextRenderingHint($hG, 5) ; ClearType
        Local $hFamily = _GDIPlus_FontFamilyCreate($UI_FONT_SEMI)
        Local $hFont = _GDIPlus_FontCreate($hFamily, $fSize)
        Local $hFormat = _GDIPlus_StringFormatCreate()
        _GDIPlus_StringFormatSetAlign($hFormat, $bCenter ? 1 : 0)
        _GDIPlus_StringFormatSetLineAlign($hFormat, 1)
        Local $tRect = _GDIPlus_RectFCreate(0, 0, $w, $h)
        Local $hTextBrush = _GDIPlus_BrushCreateSolid(BitOR(0xFF000000, $iText))
        _GDIPlus_GraphicsDrawStringEx($hG, $sText, $hFont, $tRect, $hFormat, $hTextBrush)
        _GDIPlus_BrushDispose($hTextBrush)
        _GDIPlus_StringFormatDispose($hFormat)
        _GDIPlus_FontDispose($hFont)
        _GDIPlus_FontFamilyDispose($hFamily)
    EndIf
    _GDIPlus_GraphicsDispose($hG)
    Local $hHB = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hBmp)
    _GDIPlus_BitmapDispose($hBmp)
    $__g_oUiBmp.Item($sKey) = $hHB
    Return $hHB
EndFunc

Func __UiSetPicBitmap($idPic, $hHB)
    GUICtrlSendMsg($idPic, 0x0172, 0, $hHB) ; STM_SETIMAGE, IMAGE_BITMAP
EndFunc

; Yuvarlak köşeli kart. Üzerindeki denetimlerden ÖNCE oluşturulmalı; tıklamaları yutmaz.
;   $iBack: kartın oturduğu zemin rengi (köşe dışı).
Func _UiCard($x, $y, $w, $h, $iColor = $UI_CARD, $iRadius = 14, $iBack = $UI_BG)
    Local $id = GUICtrlCreatePic("", $x, $y, $w, $h)
    __UiSetPicBitmap($id, __UiRoundBitmap($w, $h, $iRadius, $iColor, $iBack))
    GUICtrlSetState($id, $GUI_DISABLE)
    Return $id
EndFunc

; Yazı etiketi (saydam zemin).
Func _UiLabel($sText, $x, $y, $w, $h, $fSize = 10, $iColor = $UI_TEXT, $iWeight = 400, $iStyle = 0, $sFont = $UI_FONT)
    Local $id = GUICtrlCreateLabel($sText, $x, $y, $w, $h, $iStyle)
    GUICtrlSetFont($id, $fSize, $iWeight, 0, $sFont)
    GUICtrlSetColor($id, $iColor)
    GUICtrlSetBkColor($id, $GUI_BKCOLOR_TRANSPARENT)
    Return $id
EndFunc

; İkon etiketi (Segoe MDL2 Assets).
Func _UiIcon($iGlyph, $x, $y, $w, $h, $fSize = 14, $iColor = $UI_TEXT2)
    Return _UiLabel(ChrW($iGlyph), $x, $y, $w, $h, $fSize, $iColor, 400, BitOR($SS_CENTER, $SS_CENTERIMAGE), $UI_ICON_FONT)
EndFunc

; Düz, yuvarlak köşeli buton. Dönüş: etiket kimliği (GUIGetMsg ile yakalanır).
;   $iBack: butonun oturduğu zemin (kart üstündeyse $UI_CARD).
Func _UiButton($sText, $x, $y, $w, $h, $iKind = $UI_KIND_PRIMARY, $fSize = 10, $iRadius = 8, $iBack = $UI_CARD, $iStyle = -1)
    Local $idPic = GUICtrlCreatePic("", $x, $y, $w, $h)
    GUICtrlSetState($idPic, $GUI_DISABLE)
    If $iStyle = -1 Then $iStyle = BitOR($SS_CENTER, $SS_CENTERIMAGE)
    Local $id = GUICtrlCreateLabel($sText, $x, $y, $w, $h, BitOR($iStyle, $SS_NOTIFY))
    GUICtrlSetFont($id, $fSize, 600, 0, $UI_FONT_SEMI)
    GUICtrlSetBkColor($id, $GUI_BKCOLOR_TRANSPARENT)
    GUICtrlSetCursor($id, 0)
    Local $n = UBound($__g_aUiBtn)
    ReDim $__g_aUiBtn[$n + 1][$__UI_BTN_COLS]
    $__g_aUiBtn[$n][0] = $id
    $__g_aUiBtn[$n][1] = $idPic
    $__g_aUiBtn[$n][2] = $iKind
    $__g_aUiBtn[$n][3] = -1
    $__g_aUiBtn[$n][4] = $w
    $__g_aUiBtn[$n][5] = $h
    $__g_aUiBtn[$n][6] = $iRadius
    $__g_aUiBtn[$n][7] = $iBack
    $__g_aUiBtn[$n][8] = $x
    $__g_aUiBtn[$n][9] = $y
    $__g_aUiBtn[$n][10] = $fSize
    $__g_aUiBtn[$n][11] = ""
    $__g_aUiBtn[$n][12] = BitAND($iStyle, $SS_CENTER) = $SS_CENTER
    $__g_oUiCompanion.Item(String($id)) = $idPic
    __UiPaint($n, 0)
    Return $id
EndFunc

; Kenar menüsü öğesi (ikon + sola yaslı yazı).
Func _UiNavItem($iGlyph, $sText, $x, $y, $w, $h = 40)
    Local $id = _UiButton("           " & $sText, $x, $y, $w, $h, $UI_KIND_NAV, 10.5, 8, $UI_SIDEBAR, BitOR($SS_LEFT, $SS_CENTERIMAGE))
    $__g_aUiBtn[UBound($__g_aUiBtn) - 1][10] = -1 ; devre dışı yazısı çizilmez (menü öğeleri kapatılmaz)
    GUICtrlSetFont($id, 10.5, 500, 0, $UI_FONT)
    Local $idIcon = _UiIcon($iGlyph, $x + 10, $y, 26, $h, 12, $UI_TEXT2)
    GUICtrlSetState($idIcon, $GUI_DISABLE)
    Return $id
EndFunc

; Butonun türünü (rengini) değiştirir; ör. Başlat (yeşil) <-> Durdur (kırmızı).
Func _UiButtonSetKind($id, $iKind)
    For $i = 0 To UBound($__g_aUiBtn) - 1
        If $__g_aUiBtn[$i][0] = $id Then
            $__g_aUiBtn[$i][2] = $iKind
            $__g_aUiBtn[$i][3] = -1
            __UiPaint($i, BitAND(GUICtrlGetState($id), $GUI_DISABLE) ? 2 : 0)
            Return
        EndIf
    Next
EndFunc

Func __UiPaint($i, $iLook)
    If $__g_aUiBtn[$i][3] = $iLook Then Return
    $__g_aUiBtn[$i][3] = $iLook
    Local $id = $__g_aUiBtn[$i][0], $k = $__g_aUiBtn[$i][2]
    Local $iFill, $iText, $sText = ""
    If $iLook = 2 Then
        $iFill = ($k = $UI_KIND_NAV) ? $UI_SIDEBAR : $UI_DISABLED_BG
        $iText = $UI_DISABLED_TX
        ; Windows devre dışı etiketi kabartmalı çizer; yazıyı bitmap'e çizip etiketi görünmez alana alırız.
        If $__g_aUiBtn[$i][10] > 0 Then $sText = GUICtrlRead($id)
    Else
        $iFill = $__g_aUiKinds[$k][$iLook]
        $iText = $__g_aUiKinds[$k][2]
    EndIf
    $__g_aUiBtn[$i][11] = $sText
    Local $hBmp
    If $sText = "" Then
        $hBmp = __UiRoundBitmap($__g_aUiBtn[$i][4], $__g_aUiBtn[$i][5], $__g_aUiBtn[$i][6], $iFill, $__g_aUiBtn[$i][7])
    Else
        $hBmp = __UiRoundBitmap($__g_aUiBtn[$i][4], $__g_aUiBtn[$i][5], $__g_aUiBtn[$i][6], $iFill, $__g_aUiBtn[$i][7], _
                $sText, $__g_aUiBtn[$i][10], $iText, $__g_aUiBtn[$i][12])
    EndIf
    __UiSetPicBitmap($__g_aUiBtn[$i][1], $hBmp)
    If $sText = "" Then
        GUICtrlSetPos($id, $__g_aUiBtn[$i][8], $__g_aUiBtn[$i][9])
    Else
        GUICtrlSetPos($id, -30000, -30000)
    EndIf
    GUICtrlSetColor($id, $iText)
    ; saydam etiket yeni zemine göre yeniden çizilsin
    DllCall("user32.dll", "bool", "InvalidateRect", "hwnd", GUICtrlGetHandle($id), "ptr", 0, "bool", True)
EndFunc

; Üzerine gelme ve devre dışı görünümünü günceller. Ana döngüde her turda çağrılır.
; Uzun işlem/alt pencere döngülerinde çağrılacak işlev adı (ör. yeni arayüzü canlı tutmak için).
; İşlev tek parametre alır: döngüdeki pencerenin tanıtıcısı.
Global $g_sUiYieldHook = ""

Func _UiTick($hWnd)
    If $g_sUiYieldHook <> "" Then Call($g_sUiYieldHook, $hWnd)
    Local $iHover = 0
    Local $a = GUIGetCursorInfo($hWnd)
    If IsArray($a) Then $iHover = $a[4]
    For $i = 0 To UBound($__g_aUiBtn) - 1
        Local $id = $__g_aUiBtn[$i][0]
        Local $iLook = 0
        If BitAND(GUICtrlGetState($id), $GUI_DISABLE) Then
            $iLook = 2
            If $__g_aUiBtn[$i][10] > 0 And GUICtrlRead($id) <> $__g_aUiBtn[$i][11] Then $__g_aUiBtn[$i][3] = -1
        ElseIf $id = $iHover Then
            $iLook = 1
        EndIf
        __UiPaint($i, $iLook)
    Next
EndFunc

; Denetimi (butonsa alt görüntüsüyle birlikte) gösterir/gizler.
Func _UiSetVisible($id, $bShow)
    Local $iState = $bShow ? $GUI_SHOW : $GUI_HIDE
    If IsObj($__g_oUiCompanion) And $__g_oUiCompanion.Exists(String($id)) Then GUICtrlSetState($__g_oUiCompanion.Item(String($id)), $iState)
    GUICtrlSetState($id, $iState)
EndFunc

; Diyalog açılmadan önce alınır; diyalog GUIDelete ile kapatıldıktan sonra _UiRelease ile
; o diyaloğun buton/anahtar kayıtları silinir (AutoIt denetim kimliklerini yeniden kullanır,
; eski kayıtlar yeni pencerelerdeki başka denetimleri boyayabilirdi).
Func _UiMark()
    Local $a[2] = [UBound($__g_aUiBtn), UBound($__g_aUiToggle)]
    Return $a
EndFunc

Func _UiRelease($aMark)
    For $i = $aMark[0] To UBound($__g_aUiBtn) - 1
        If IsObj($__g_oUiCompanion) Then $__g_oUiCompanion.Remove(String($__g_aUiBtn[$i][0]))
    Next
    If UBound($__g_aUiBtn) > $aMark[0] Then ReDim $__g_aUiBtn[$aMark[0]][$__UI_BTN_COLS]
    If UBound($__g_aUiToggle) > $aMark[1] Then ReDim $__g_aUiToggle[$aMark[1]][4]
EndFunc

; Koyu temalı alt pencere (diyalog) oluşturur.
Func _UiWindow($sTitle, $w, $h, $hParent = 0)
    Local $hWnd = GUICreate($sTitle, $w, $h, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), 0, $hParent)
    _UiDarkWindow($hWnd)
    Return $hWnd
EndFunc

; İlerleme çubuğunu düz, vurgu renkli hale getirir (Windows görsel stili kaldırılır).
Func _UiProgressStyle($id, $iBack = $UI_CARD)
    DllCall("uxtheme.dll", "long", "SetWindowTheme", "hwnd", GUICtrlGetHandle($id), "wstr", "", "wstr", "")
    GUICtrlSetColor($id, $UI_ACCENT)
    GUICtrlSetBkColor($id, $iBack)
EndFunc

; --- Aç/kapa anahtarı (Discord tarzı) ---

Func __UiToggleBitmap($bOn, $iBack)
    Local $sKey = "toggle|" & $bOn & "|" & $iBack
    If $__g_oUiBmp.Exists($sKey) Then Return $__g_oUiBmp.Item($sKey)
    Local $w = 40, $h = 24
    Local $hBmp = _GDIPlus_BitmapCreateFromScan0($w, $h)
    Local $hG = _GDIPlus_ImageGetGraphicsContext($hBmp)
    _GDIPlus_GraphicsSetSmoothingMode($hG, $GDIP_SMOOTHINGMODE_ANTIALIAS8X8)
    _GDIPlus_GraphicsClear($hG, BitOR(0xFF000000, $iBack))
    Local $hTrack = _GDIPlus_BrushCreateSolid(BitOR(0xFF000000, $bOn ? $UI_ACCENT : 0x3A3F4A))
    Local $hPath = _GDIPlus_PathCreate()
    _GDIPlus_PathAddArc($hPath, 0, 0, $h - 1, $h - 1, 90, 180)
    _GDIPlus_PathAddArc($hPath, $w - $h, 0, $h - 1, $h - 1, 270, 180)
    _GDIPlus_PathCloseFigure($hPath)
    _GDIPlus_GraphicsFillPath($hG, $hPath, $hTrack)
    Local $hKnob = _GDIPlus_BrushCreateSolid(0xFFFFFFFF)
    _GDIPlus_GraphicsFillEllipse($hG, $bOn ? $w - $h + 3 : 3, 3, $h - 7, $h - 7, $hKnob)
    _GDIPlus_PathDispose($hPath)
    _GDIPlus_BrushDispose($hTrack)
    _GDIPlus_BrushDispose($hKnob)
    _GDIPlus_GraphicsDispose($hG)
    Local $hHB = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hBmp)
    _GDIPlus_BitmapDispose($hBmp)
    $__g_oUiBmp.Item($sKey) = $hHB
    Return $hHB
EndFunc

; Anahtar + yazı. Dönüş: yazı etiketi kimliği (tıklama hem yazıda hem anahtarda çalışır).
Func _UiToggle($sText, $x, $y, $w, $bOn, $iBack = $UI_CARD)
    Local $idPic = GUICtrlCreatePic("", $x, $y, 40, 24)
    __UiSetPicBitmap($idPic, __UiToggleBitmap($bOn, $iBack))
    Local $id = GUICtrlCreateLabel($sText, $x + 52, $y, $w - 52, 24, BitOR($SS_LEFT, $SS_CENTERIMAGE, $SS_NOTIFY))
    GUICtrlSetFont($id, 10, 400, 0, $UI_FONT)
    GUICtrlSetColor($id, $UI_TEXT)
    GUICtrlSetBkColor($id, $GUI_BKCOLOR_TRANSPARENT)
    GUICtrlSetCursor($id, 0)
    GUICtrlSetCursor($idPic, 0)
    Local $n = UBound($__g_aUiToggle)
    ReDim $__g_aUiToggle[$n + 1][4]
    $__g_aUiToggle[$n][0] = $id
    $__g_aUiToggle[$n][1] = $idPic
    $__g_aUiToggle[$n][2] = $bOn
    $__g_aUiToggle[$n][3] = $iBack
    Return $id
EndFunc

; GUIGetMsg sonucu bir anahtara aitse durumunu çevirir ve True döner.
Func _UiToggleHandle($nMsg)
    If $nMsg <= 0 Then Return False
    For $i = 0 To UBound($__g_aUiToggle) - 1
        If $nMsg = $__g_aUiToggle[$i][0] Or $nMsg = $__g_aUiToggle[$i][1] Then
            _UiToggleSet($__g_aUiToggle[$i][0], Not $__g_aUiToggle[$i][2])
            Return True
        EndIf
    Next
    Return False
EndFunc

Func _UiToggleSet($id, $bOn)
    For $i = 0 To UBound($__g_aUiToggle) - 1
        If $__g_aUiToggle[$i][0] = $id Then
            $__g_aUiToggle[$i][2] = $bOn
            __UiSetPicBitmap($__g_aUiToggle[$i][1], __UiToggleBitmap($bOn, $__g_aUiToggle[$i][3]))
            Return
        EndIf
    Next
EndFunc

Func _UiToggleGet($id)
    For $i = 0 To UBound($__g_aUiToggle) - 1
        If $__g_aUiToggle[$i][0] = $id Then Return $__g_aUiToggle[$i][2]
    Next
    Return False
EndFunc

; Yerel denetimi koyu temaya alır (combobox: "DarkMode_CFD", liste/edit: "DarkMode_Explorer").
Func _UiDarkControl($id, $sTheme = "DarkMode_CFD")
    DllCall("uxtheme.dll", "long", "SetWindowTheme", "hwnd", GUICtrlGetHandle($id), "wstr", $sTheme, "ptr", 0)
EndFunc
