#include-once
#include <FileConstants.au3>

; =========================================================================
; --- GÜNLÜK (LOG) ---
; logs\app.log dosyasına zaman damgalı satırlar yazar. Dosya $LOG_MAX_BYTES
; boyutunu aşarsa app.log.1 olarak saklanır ve yeni dosya açılır.
; Log yazılamazsa program çalışmaya devam eder (hata sessizce yutulur).
; =========================================================================

Global Const $LOG_MAX_BYTES = 512 * 1024
Global $__g_sLogPath = ""

; Log dosyasını hazırlar. Klasör yoksa oluşturur, büyükse döndürür.
Func _LogInit($sPath)
    $__g_sLogPath = $sPath
    Local $sDir = StringRegExpReplace($sPath, "\\[^\\]+$", "")
    If $sDir <> $sPath And Not FileExists($sDir) Then DirCreate($sDir)
    _LogRotateIfNeeded($sPath, $LOG_MAX_BYTES)
EndFunc

; Dosya $iMaxBytes'ı aştıysa .1 uzantısıyla yedekler. Döndürüldüyse True.
Func _LogRotateIfNeeded($sPath, $iMaxBytes)
    If Not FileExists($sPath) Then Return False
    If FileGetSize($sPath) <= $iMaxBytes Then Return False
    FileMove($sPath, $sPath & ".1", $FC_OVERWRITE)
    Return True
EndFunc

; Tek bir log satırı oluşturur. Mesajdaki satır sonları " | " ile birleştirilir.
Func _LogFormatLine($sLevel, $sMsg, $sTimestamp)
    $sMsg = StringRegExpReplace(StringStripWS($sMsg, 3), "\R+", " | ")
    Return $sTimestamp & " [" & $sLevel & "] " & $sMsg
EndFunc

Func _LogTimestamp()
    Return @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
EndFunc

Func _Log($sLevel, $sMsg)
    If $__g_sLogPath = "" Then Return
    Local $hFile = FileOpen($__g_sLogPath, $FO_APPEND + $FO_UTF8_NOBOM)
    If $hFile = -1 Then Return
    FileWriteLine($hFile, _LogFormatLine($sLevel, $sMsg, _LogTimestamp()))
    FileClose($hFile)
EndFunc

Func _LogInfo($sMsg)
    _Log("BILGI", $sMsg)
EndFunc

Func _LogWarn($sMsg)
    _Log("UYARI", $sMsg)
EndFunc

Func _LogError($sMsg)
    _Log("HATA", $sMsg)
EndFunc
