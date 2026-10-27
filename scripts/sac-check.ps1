<#
.SYNOPSIS
    Windows Akıllı Uygulama Denetimi (Smart App Control) bir exe'yi çalıştırır mı, engeller mi?

.DESCRIPTION
    Exe'ler imzasız; Akıllı Uygulama Denetimi her yeni derlemeyi ayrı değerlendirir ve bazen engeller (H25).
    Yoklama, exe'yi normal izinle ve askıda (CREATE_SUSPENDED) başlatmayı dener; programın tek satırı çalışmaz:
      - exe "yönetici gerekli" (requireAdministrator) olduğundan Windows denetimden geçirip 740 döndürür,
      - engellerse 4551 (ERROR_SYSTEM_INTEGRITY_POLICY_VIOLATION) döner,
      - süreç oluşursa (yönetici gerektirmeyen exe) askıdayken hemen sonlandırılır.
    Yalnızca Akıllı Uygulama Denetimi zorunlu modda olan bilgisayarda anlamlıdır; değilse "yoklanmadı".

.EXAMPLE
    pwsh scripts/sac-check.ps1 "dist\RedRiveRR Zapret.exe"
    . .\scripts\sac-check.ps1; Test-SacAllowed 'x.exe'   # $true / $false / $null (uygulanamaz)
#>
param([Parameter(ValueFromRemainingArguments)][string[]]$Path)

if (-not ('ZwtSacProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ZwtSacProbe {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string reserved, desktop, title;
        public int x, y, xSize, ySize, xCount, yCount, fill, flags;
        public short show, reserved2; public IntPtr reserved3, stdIn, stdOut, stdErr;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public int pid, tid; }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags,
        IntPtr env, string dir, ref StartupInfo si, out ProcessInfo pi);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    const uint CREATE_SUSPENDED = 0x4;

    // 0 = süreç oluştu (askıda sonlandırıldı), aksi halde Win32 hata kodu (740 geçti, 4551 engellendi).
    public static int Probe(string exe) {
        var si = new StartupInfo(); si.cb = Marshal.SizeOf(typeof(StartupInfo));
        ProcessInfo pi;
        if (!CreateProcessW(exe, "\"" + exe + "\" /sac-yoklama", IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED,
                IntPtr.Zero, null, ref si, out pi))
            return Marshal.GetLastWin32Error();
        TerminateProcess(pi.process, 1);
        CloseHandle(pi.thread); CloseHandle(pi.process);
        return 0;
    }
}
'@
}

# Akıllı Uygulama Denetimi zorunlu modda mı (1 = açık, 2 = değerlendirme, 0 = kapalı)?
function Get-SacState {
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue
    if ($v) { return [int]$v.VerifiedAndReputablePolicyState }
    return 0
}

# $true = çalışır, $false = engellenir, $null = bu bilgisayarda denetim zorunlu değil (yoklama anlamsız).
function Test-SacAllowed([string]$Exe) {
    if ((Get-SacState) -ne 1) { return $null }
    $full = (Resolve-Path -LiteralPath $Exe).Path
    $code = [ZwtSacProbe]::Probe($full)
    if ($code -eq 4551 -or $code -eq 1260) { return $false }
    if ($code -eq 0 -or $code -eq 740) { return $true }
    throw "Akıllı Uygulama Denetimi yoklaması beklenmeyen sonuç verdi ($code): $full"
}

if ($Path) {
    $blocked = 0
    foreach ($p in $Path) {
        $r = Test-SacAllowed $p
        $text = if ($null -eq $r) { 'yoklanmadı (Akıllı Uygulama Denetimi bu bilgisayarda zorunlu modda değil)' } elseif ($r) { 'geçti' } else { $blocked++; 'ENGELLENİYOR' }
        Write-Host ("{0}: {1}" -f $p, $text)
    }
    if ($blocked) { exit 1 }
}
