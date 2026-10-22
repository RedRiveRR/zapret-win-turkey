<#
.SYNOPSIS
    AutoIt kaynaklarını Au3Check ile denetler ve birim testlerini çalıştırır.

.DESCRIPTION
    Au3Check, Türkçe karakter içeren yollarda göreli include'ları çözemiyor.
    Bu yüzden kaynaklar önce ASCII bir geçici klasöre kopyalanır, denetim orada yapılır.

.PARAMETER AutoItDir
    Au3Check.exe ve AutoIt3_x64.exe'nin bulunduğu klasör.
    Varsayılan: $env:AUTOIT_DIR, yoksa ~\tools\autoit-portable, yoksa Program Files (x86)\AutoIt3.

.EXAMPLE
    pwsh scripts/check.ps1
#>
param(
    [string]$AutoItDir = $env:AUTOIT_DIR
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not $AutoItDir) {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'tools\autoit-portable'),
        (Join-Path ${env:ProgramFiles(x86)} 'AutoIt3')
    )
    $AutoItDir = $candidates | Where-Object { Test-Path (Join-Path $_ 'Au3Check.exe') } | Select-Object -First 1
}
if (-not $AutoItDir -or -not (Test-Path (Join-Path $AutoItDir 'Au3Check.exe'))) {
    throw "Au3Check.exe bulunamadı. -AutoItDir veya AUTOIT_DIR ile AutoIt klasörünü belirtin."
}
$au3check = Join-Path $AutoItDir 'Au3Check.exe'
$autoit = Join-Path $AutoItDir 'AutoIt3_x64.exe'

# ASCII geçici çalışma klasörü
$work = Join-Path ([IO.Path]::GetTempPath()) ("zwt-check-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
if ($work -match '[^\x00-\x7F]') { $work = Join-Path $env:SystemDrive ("zwt-check-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Path $work | Out-Null

$failed = $false
try {
    Copy-Item (Join-Path $repo '*.au3') $work
    foreach ($dir in 'lib', 'ui', 'tests', 'config') {
        $src = Join-Path $repo $dir
        if (Test-Path $src) { Copy-Item $src (Join-Path $work $dir) -Recurse }
    }

    $targets = @(Get-ChildItem $work -Filter '*.au3' | ForEach-Object Name)
    if (Test-Path (Join-Path $work 'tests\run_tests.au3')) { $targets += 'tests\run_tests.au3' }

    Write-Host "== Au3Check" -ForegroundColor Cyan
    foreach ($t in $targets) {
        Push-Location (Split-Path (Join-Path $work $t) -Parent)
        try {
            $out = & $au3check -q -d -w 1 -w 2 -w 3 -w 4 -w 6 (Split-Path $t -Leaf) 2>&1
            $summary = $out | Where-Object { $_ -match 'error\(s\)' } | Select-Object -Last 1
            if (-not $summary) { $summary = "$t - 0 error(s), 0 warning(s)" }
            if ($LASTEXITCODE -eq 2 -or $summary -notmatch ' 0 error\(s\)') {
                $failed = $true
                $out | Where-Object { $_ -match ': error:' } | ForEach-Object { Write-Host $_ -ForegroundColor Red }
                Write-Host "FAIL $summary" -ForegroundColor Red
            }
            else {
                Write-Host "ok   $summary"
            }
        }
        finally { Pop-Location }
    }

    # Derleyici yönergelerindeki sürüm lib\Version.au3 ile aynı olmalı.
    $versionFile = Join-Path $work 'lib\Version.au3'
    if (Test-Path $versionFile) {
        Write-Host "== Sürüm tutarlılığı" -ForegroundColor Cyan
        $appVersion = [regex]::Match((Get-Content $versionFile -Raw), 'APP_VERSION\s*=\s*"([^"]+)"').Groups[1].Value
        foreach ($script in Get-ChildItem $work -Filter '*.au3') {
            $src = Get-Content $script.FullName -Raw
            $product = [regex]::Match($src, '#AutoIt3Wrapper_Res_ProductVersion=(\S+)').Groups[1].Value
            $file = [regex]::Match($src, '#AutoIt3Wrapper_Res_Fileversion=(\S+)').Groups[1].Value
            if ($product -ne $appVersion -or -not $file.StartsWith("$appVersion.")) {
                $failed = $true
                Write-Host "FAIL $($script.Name): ProductVersion=$product Fileversion=$file, APP_VERSION=$appVersion" -ForegroundColor Red
            }
            else {
                Write-Host "ok   $($script.Name): $appVersion"
            }
        }
    }

    $runner = Join-Path $work 'tests\run_tests.au3'
    if (Test-Path $runner) {
        Write-Host "== Birim testleri" -ForegroundColor Cyan
        $log = Join-Path $work 'tests\out.txt'
        $p = Start-Process -FilePath $autoit -ArgumentList '/ErrorStdOut', 'run_tests.au3' `
            -WorkingDirectory (Join-Path $work 'tests') -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log
        Get-Content $log -Encoding utf8 | Write-Host
        if ($p.ExitCode -ne 0) { $failed = $true; Write-Host "FAIL testler (çıkış kodu $($p.ExitCode))" -ForegroundColor Red }
    }
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { exit 1 }
Write-Host "Tüm denetimler geçti." -ForegroundColor Green
