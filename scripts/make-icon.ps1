<#
.SYNOPSIS
    Kilit logosundan (docs/tasarim/logo/kilit.svg) çok boyutlu Windows simgesi üretir.
.DESCRIPTION
    Çıktı: ui\simge\kilit.ico (16, 24, 32, 48, 64, 256 px). 48 px ve altında kalın çizgili
    "küçük" çizim (kilit-kucuk.svg) kullanılır. 256 px PNG, diğerleri 32 bit DIB olarak saklanır.
    Çizim GDI+ ile SVG'deki ölçülerle (64x64 tuval) yapılır; logo değişirse bu betik de güncellenmeli.
#>
param([string]$Out = "")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repo = Split-Path $PSScriptRoot -Parent
if (-not $Out) { $Out = Join-Path $repo 'ui\simge\kilit.ico' }
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null

$accent = [Drawing.Color]::FromArgb(255, 0x5B, 0x5B, 0xD6)
$white = [Drawing.Color]::White

function New-RoundRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}

function Draw-Lock([int]$size) {
    $small = $size -le 48
    $bmp = New-Object Drawing.Bitmap $size, $size, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([Drawing.Color]::Transparent)
    $s = $size / 64.0
    $g.ScaleTransform($s, $s)
    $g.FillPath((New-Object Drawing.SolidBrush $accent), (New-RoundRect 0 0 64 64 16))
    # Açık kilit halkası: (40,30) -> (40,21), yarıçap 8 yay (merkez 32,21) üstten, -> (24,21) -> (24,18)
    $pen = New-Object Drawing.Pen $white, ($(if ($small) { 7.5 } else { 5.5 }))
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $ring = New-Object Drawing.Drawing2D.GraphicsPath
    $ring.AddLine(40, 30, 40, 21); $ring.AddArc(24, 13, 16, 16, 0, -180); $ring.AddLine(24, 21, 24, 18)
    $g.DrawPath($pen, $ring)
    $g.FillPath((New-Object Drawing.SolidBrush $white), (New-RoundRect 17 30 30 22 6))
    $pen2 = New-Object Drawing.Pen $accent, ($(if ($small) { 6 } else { 4.5 }))
    $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'; $pen2.LineJoin = 'Round'
    $g.DrawLines($pen2, [Drawing.PointF[]]@((New-Object Drawing.PointF 26, 41), (New-Object Drawing.PointF 30, 45), (New-Object Drawing.PointF 38, 37)))
    $g.Dispose()
    return $bmp
}

# 32 bit DIB (BITMAPINFOHEADER + alttan üste BGRA + AND maskesi)
function Get-DibBytes([Drawing.Bitmap]$bmp) {
    $n = $bmp.Width
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $ms
    $bw.Write([int]40); $bw.Write([int]$n); $bw.Write([int]($n * 2)); $bw.Write([int16]1); $bw.Write([int16]32)
    $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $n - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $n; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([byte]$c.B); $bw.Write([byte]$c.G); $bw.Write([byte]$c.R); $bw.Write([byte]$c.A)
        }
    }
    $maskRow = [Math]::Ceiling($n / 32.0) * 4
    $bw.Write((New-Object byte[] ($maskRow * $n)))
    $bw.Flush(); return ,[byte[]]$ms.ToArray()
}

$sizes = 16, 24, 32, 48, 64, 256
$images = foreach ($sz in $sizes) {
    $b = Draw-Lock $sz
    if ($sz -eq 256) {
        $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); [byte[]]$bytes = $ms.ToArray()
    } else { [byte[]]$bytes = Get-DibBytes $b }
    $b.Dispose()
    [pscustomobject]@{ Size = $sz; Bytes = $bytes }
}

$fs = [IO.File]::Create($Out)
$w = New-Object IO.BinaryWriter $fs
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($im in $images) {
    $dim = if ($im.Size -ge 256) { 0 } else { $im.Size }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$im.Bytes.Length); $w.Write([int]$offset)
    $offset += $im.Bytes.Length
}
foreach ($im in $images) { $w.Write([byte[]]$im.Bytes) }
$w.Close()
"Simge yazıldı: $Out ($((Get-Item $Out).Length) bayt, boyutlar: $($sizes -join ', '))"
