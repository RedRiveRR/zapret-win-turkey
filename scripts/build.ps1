<#
.SYNOPSIS
    Ana ve Lite sürüm için dağıtım ZIP'lerini üretir.

.DESCRIPTION
    Repoda olmayan ikililer (zapret-winws, cygwin, blockcheck yardımcıları) upstream'in
    v4.5 release ZIP'inden alınır. ZIP'in SHA256 özeti sabitlenmiştir; değişirse derleme durur.
    Üzerine bu repodaki kaynaklar, config dosyaları ve Aut2Exe ile derlenen exe konur.
    Upstream ZIP'indeki geliştiriciye ait config.ini ve blockcheck logları pakete alınmaz.

    Çıktı: dist\zapret-win-turkey-<sürüm>-<commit>.zip, dist\zapret-win-turkey-lite-<sürüm>-<commit>.zip,
    dist\SHA256SUMS.txt

.PARAMETER AutoItDir
    Aut2Exe klasörünü içeren AutoIt kökü. Varsayılan: $env:AUTOIT_DIR, ~\tools\autoit-portable.

.PARAMETER BaseZip
    Upstream release ZIP'inin yerel kopyası. Verilmezse indirilir.
#>
param(
    [string]$AutoItDir = $env:AUTOIT_DIR,
    [string]$BaseZip = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }

$BaseUrl = 'https://github.com/alimali54/zapret-win-turkey/releases/download/v4.5/zapret-win-turkey.zip'
$BaseSha256 = '7aee242c47a00c62156461ad9beff6096f5df3283185ccd70c0bf144edf345b3'

if (-not $AutoItDir) {
    $AutoItDir = @((Join-Path $env:USERPROFILE 'tools\autoit-portable'), (Join-Path ${env:ProgramFiles(x86)} 'AutoIt3')) |
        Where-Object { Test-Path (Join-Path $_ 'Aut2Exe\Aut2exe_x64.exe') } | Select-Object -First 1
}
$aut2exe = Join-Path $AutoItDir 'Aut2Exe\Aut2exe_x64.exe'
if (-not (Test-Path $aut2exe)) { throw "Aut2exe_x64.exe bulunamadı (AutoItDir: $AutoItDir)" }

$version = [regex]::Match((Get-Content (Join-Path $repo 'lib\Version.au3') -Raw), 'APP_VERSION\s*=\s*"([^"]+)"').Groups[1].Value
$commit = (git -C $repo rev-parse --short HEAD).Trim()
$suffix = "$version-$commit"

# Aut2Exe ve Au3Check Türkçe karakterli yollarda sorun çıkardığı için ASCII geçici klasör.
$work = Join-Path ([IO.Path]::GetTempPath()) ("zwt-build-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
if ($work -match '[^\x00-\x7F]') { $work = Join-Path $env:SystemDrive ("zwt-build-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Path $work | Out-Null

try {
    # --- Temel ZIP ---
    if (-not $BaseZip) {
        $BaseZip = Join-Path $work 'base.zip'
        Write-Host "Temel paket indiriliyor: $BaseUrl"
        Invoke-WebRequest -Uri $BaseUrl -OutFile $BaseZip
    }
    $hash = (Get-FileHash $BaseZip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $BaseSha256) { throw "Temel paketin SHA256 özeti uyuşmuyor: $hash (beklenen $BaseSha256)" }
    $base = Join-Path $work 'base'
    Expand-Archive $BaseZip -DestinationPath $base

    # --- Kaynakları ASCII klasöre kopyala ve derle ---
    $src = Join-Path $work 'src'
    New-Item -ItemType Directory -Path $src | Out-Null
    Copy-Item (Join-Path $repo '*.au3') $src
    Copy-Item (Join-Path $repo 'lib') (Join-Path $src 'lib') -Recurse
    $icon = Join-Path $base 'bin\zapret\zapret-winws\winws2.ico'

    function Invoke-Compile([string]$name) {
        $in = Join-Path $src "$name.au3"
        $out = Join-Path $src "$name.exe"
        # /nopack: UPX ile sıkıştırılmış exe'ler antivirüslerde daha sık yanlış alarm veriyor.
        $p = Start-Process -FilePath $aut2exe -ArgumentList '/in', "`"$in`"", '/out', "`"$out`"", '/icon', "`"$icon`"", '/x64', '/nopack' -Wait -PassThru -NoNewWindow
        if (-not (Test-Path $out)) { throw "$name derlenemedi (Aut2Exe çıkış kodu $($p.ExitCode))" }
        Write-Host ("derlendi {0}.exe ({1:N0} bayt)" -f $name, (Get-Item $out).Length)
        return $out
    }
    $mainExe = Invoke-Compile 'zapret-win-turkey'
    $liteExe = Invoke-Compile 'zapret-win-turkey-lite'

    # Ortak: repo config dosyaları ve dokümanlar
    function Copy-Common([string]$dest, [string]$scriptName) {
        New-Item -ItemType Directory -Force -Path (Join-Path $dest 'config') | Out-Null
        foreach ($f in 'autohostlist.txt', 'excludelist.txt', 'hostlist.txt', 'strategies.ini') {
            Copy-Item (Join-Path $repo "config\$f") (Join-Path $dest 'config')
        }
        Copy-Item (Join-Path $src "$scriptName.au3") $dest
        Copy-Item (Join-Path $src 'lib') (Join-Path $dest 'lib') -Recurse
        foreach ($doc in 'README.md', 'CHANGELOG.md', 'THIRD_PARTY.md') {
            Copy-Item (Join-Path $repo $doc) $dest
        }
    }

    # --- Ana paket ---
    $mainDir = Join-Path $work 'pkg\zapret-win-turkey'
    New-Item -ItemType Directory -Force -Path $mainDir | Out-Null
    Copy-Item (Join-Path $base 'bin') (Join-Path $mainDir 'bin') -Recurse
    Get-ChildItem (Join-Path $mainDir 'bin\zapret\blockcheck') -Filter '*.log' | Remove-Item
    Copy-Common $mainDir 'zapret-win-turkey'
    Copy-Item $mainExe $mainDir

    # --- Lite paket: yalnızca motor klasörü ---
    $liteDir = Join-Path $work 'pkg\zapret-win-turkey-lite'
    New-Item -ItemType Directory -Force -Path (Join-Path $liteDir 'bin\zapret') | Out-Null
    Copy-Item (Join-Path $base 'bin\zapret\zapret-winws') (Join-Path $liteDir 'bin\zapret\zapret-winws') -Recurse
    Copy-Common $liteDir 'zapret-win-turkey-lite'
    Copy-Item $liteExe $liteDir

    # --- ZIP + özetler ---
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $zips = @()
    foreach ($pkg in @(@{ Dir = $mainDir; Name = "zapret-win-turkey-$suffix.zip" }, @{ Dir = $liteDir; Name = "zapret-win-turkey-lite-$suffix.zip" })) {
        $zip = Join-Path $OutDir $pkg.Name
        if (Test-Path $zip) { Remove-Item $zip }
        Compress-Archive -Path (Join-Path $pkg.Dir '*') -DestinationPath $zip
        $zips += $zip
    }
    $sums = $zips | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_ -Algorithm SHA256).Hash.ToLower(), (Split-Path $_ -Leaf) }
    $sums += "{0}  {1}" -f (Get-FileHash $mainExe -Algorithm SHA256).Hash.ToLower(), 'zapret-win-turkey.exe'
    $sums += "{0}  {1}" -f (Get-FileHash $liteExe -Algorithm SHA256).Hash.ToLower(), 'zapret-win-turkey-lite.exe'
    Set-Content (Join-Path $OutDir 'SHA256SUMS.txt') $sums -Encoding utf8
    $sums | Write-Host
    Write-Host "Çıktı: $OutDir" -ForegroundColor Green
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
