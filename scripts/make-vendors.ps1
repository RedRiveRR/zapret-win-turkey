<#
.SYNOPSIS
    Ağ paylaşımındaki "Bağlı cihazlar" için üretici tablosunu (veri\cihaz-ureticileri.txt) üretir.

.DESCRIPTION
    Wireshark'ın üretici veritabanından (manuf; IEEE OUI kayıtlarından derlenir) yalnızca paylaşımda
    beklenen cihazların (konsol, TV, medya oynatıcı) üreticileri alınır. Satır biçimi: "AABBCC<TAB>Etiket".
    Program cihazın MAC adresinin ilk üç baytını bu tabloda arar; MAC adresinin kendisi saklanmaz.

.PARAMETER Manuf
    Yerel manuf dosyası. Verilmezse https://www.wireshark.org/download/automated/data/manuf indirilir.
#>
param([string]$Manuf = "")

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo 'veri\cihaz-ureticileri.txt'

if (-not $Manuf) {
    $Manuf = Join-Path ([IO.Path]::GetTempPath()) 'zwt-manuf.txt'
    Invoke-WebRequest 'https://www.wireshark.org/download/automated/data/manuf' -OutFile $Manuf -TimeoutSec 120
}

# Üretici adı (manuf'taki uzun ad) -> ekranda görünecek etiket. Sıra önemli: ilk eşleşen kazanır.
$map = [ordered]@{
    '^Sony Interactive Entertainment'             = 'PlayStation'
    '^Nintendo'                                   = 'Nintendo'
    '^Microsoft'                                  = 'Microsoft (Xbox)'
    '^Valve Corporation'                          = 'Valve (Steam Deck)'
    '^Sony (Corporation|Visual|Home|Network)'     = 'Sony'
    '^Samsung Electronics'                        = 'Samsung'
    '^LG Electronics'                             = 'LG'
    '^Vestel'                                     = 'Vestel'
    '^Arcelik'                                    = 'Arçelik / Beko'
    '^TP Vision'                                  = 'Philips TV'
    '^(TCL|Shenzhen TCL)'                         = 'TCL'
    '^Hisense'                                    = 'Hisense'
    '^Roku'                                       = 'Roku'
    '^Amazon Technologies'                        = 'Amazon (Fire TV)'
    '^Google, Inc'                                = 'Google (Chromecast)'
    '^Apple, Inc'                                 = 'Apple'
    '^(Xiaomi|Beijing Xiaomi)'                    = 'Xiaomi'
}

$rows = New-Object System.Collections.Generic.List[string]
foreach ($line in [IO.File]::ReadLines($Manuf)) {
    # Yalnız 24 bit OUI satırları: "00:04:1F<boşluk><TAB>Kısa<TAB>Uzun ad"
    if ($line -notmatch '^([0-9A-F]{2}):([0-9A-F]{2}):([0-9A-F]{2})\s*\t[^\t]*\t(.+)$') { continue }
    $oui = $Matches[1] + $Matches[2] + $Matches[3]
    $name = $Matches[4].Trim()
    foreach ($k in $map.Keys) {
        if ($name -match $k) { $rows.Add("$oui`t$($map[$k])"); break }
    }
}
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
$header = "# Bağlı cihazlar için üretici tablosu (scripts\make-vendors.ps1 ile üretilir; elle düzenlemeyin)." + "`n" +
        "# Kaynak: Wireshark manuf (IEEE OUI). Biçim: OUI<TAB>Etiket"
[IO.File]::WriteAllText($out, $header + "`n" + (($rows | Sort-Object -Unique) -join "`n") + "`n", [Text.UTF8Encoding]::new($true))
$rows | ForEach-Object { ($_ -split "`t")[1] } | Group-Object | Sort-Object Count -Descending | ForEach-Object { "{0,5}  {1}" -f $_.Count, $_.Name }
Write-Host ("{0} kayıt -> {1} ({2:N0} bayt)" -f $rows.Count, $out, (Get-Item $out).Length)
