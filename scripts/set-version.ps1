<#
.SYNOPSIS
    Derlenmiş exe'ye Windows sürüm bilgisi (VERSIONINFO) yazar.

.DESCRIPTION
    Aut2Exe #AutoIt3Wrapper_Res_* yönergelerini işlemediği için exe'nin ürün adı, açıklama ve
    sürüm alanları boş kalıyordu (Özellikler > Ayrıntılar). Boş kimlikli imzasız exe'ler Windows
    Akıllı Uygulama Denetimi / SmartScreen tarafından daha kolay "bilinmeyen" sayılır (H25).
    Kaynak, Windows'un UpdateResource API'siyle eklenir; betik kaynağı (RCDATA SCRIPT) korunur.

.EXAMPLE
    . .\scripts\set-version.ps1
    Set-ExeVersionInfo -Path 'x.exe' -Version '5.0.0' -Description 'RedRiveRR Zapret' -OriginalName 'x.exe'
#>

if (-not ('ZwtVersionResource' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class ZwtVersionResource {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResourceW(string file, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateResourceW(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EndUpdateResourceW(IntPtr h, bool discard);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryExW(string file, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll")]
    static extern bool FreeLibrary(IntPtr h);
    delegate bool EnumLangProc(IntPtr module, IntPtr type, IntPtr name, ushort lang, IntPtr param);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EnumResourceLanguagesW(IntPtr module, IntPtr type, IntPtr name, EnumLangProc proc, IntPtr param);

    const int RT_VERSION = 16;

    static void Pad(MemoryStream s) { while (s.Length % 4 != 0) s.WriteByte(0); }

    static void WriteStr(MemoryStream s, string text) {
        byte[] b = Encoding.Unicode.GetBytes(text + "\0");
        s.Write(b, 0, b.Length);
    }

    // VS_VERSIONINFO düğümü: wLength, wValueLength, wType, szKey, hizalama, değer, hizalama, çocuklar.
    static byte[] Node(string key, byte[] value, ushort valueLength, ushort type, List<byte[]> children) {
        var s = new MemoryStream();
        s.Write(new byte[6], 0, 6);
        WriteStr(s, key);
        Pad(s);
        if (value != null) s.Write(value, 0, value.Length);
        if (children != null) {
            foreach (var c in children) { Pad(s); s.Write(c, 0, c.Length); }
        }
        byte[] r = s.ToArray();
        BitConverter.GetBytes((ushort)r.Length).CopyTo(r, 0);
        BitConverter.GetBytes(valueLength).CopyTo(r, 2);
        BitConverter.GetBytes(type).CopyTo(r, 4);
        return r;
    }

    static byte[] StringEntry(string key, string val) {
        byte[] v = Encoding.Unicode.GetBytes(val + "\0");
        return Node(key, v, (ushort)(val.Length + 1), 1, null);
    }

    public static byte[] Build(int[] ver, string[] keys, string[] values, ushort lang) {
        var f = new MemoryStream();
        var w = new BinaryWriter(f);
        uint ms = (uint)((ver[0] << 16) | ver[1]);
        uint ls = (uint)((ver[2] << 16) | ver[3]);
        w.Write(0xFEEF04BDu); w.Write(0x00010000u);
        w.Write(ms); w.Write(ls); w.Write(ms); w.Write(ls);
        w.Write(0x3Fu); w.Write(0u); w.Write(0x00040004u); w.Write(1u); w.Write(0u); w.Write(0u); w.Write(0u);
        byte[] fixedInfo = f.ToArray();

        var strings = new List<byte[]>();
        for (int i = 0; i < keys.Length; i++) strings.Add(StringEntry(keys[i], values[i]));
        string tableKey = lang.ToString("X4") + "04B0";
        var table = Node(tableKey, null, 0, 1, strings);
        var sfi = Node("StringFileInfo", null, 0, 1, new List<byte[]> { table });

        byte[] tr = new byte[4];
        BitConverter.GetBytes(lang).CopyTo(tr, 0);
        BitConverter.GetBytes((ushort)1200).CopyTo(tr, 2);
        var var = Node("Translation", tr, 4, 0, null);
        var vfi = Node("VarFileInfo", null, 0, 1, new List<byte[]> { var });

        return Node("VS_VERSION_INFO", fixedInfo, (ushort)fixedInfo.Length, 0, new List<byte[]> { sfi, vfi });
    }

    // Exe'deki mevcut sürüm kaynaklarının dilleri (varsa silinip yenisi yazılır).
    public static List<ushort> ExistingLangs(string file) {
        var langs = new List<ushort>();
        IntPtr m = LoadLibraryExW(file, IntPtr.Zero, 0x2); // LOAD_LIBRARY_AS_DATAFILE
        if (m == IntPtr.Zero) return langs;
        try {
            EnumResourceLanguagesW(m, (IntPtr)RT_VERSION, (IntPtr)1, (a, b, c, l, p) => { langs.Add(l); return true; }, IntPtr.Zero);
        } finally { FreeLibrary(m); }
        return langs;
    }

    public static void Write(string file, byte[] data, ushort lang) {
        var old = ExistingLangs(file);
        IntPtr h = BeginUpdateResourceW(file, false);
        if (h == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        bool ok = true;
        foreach (var l in old) ok &= UpdateResourceW(h, (IntPtr)RT_VERSION, (IntPtr)1, l, null, 0);
        ok &= UpdateResourceW(h, (IntPtr)RT_VERSION, (IntPtr)1, lang, data, (uint)data.Length);
        int err = Marshal.GetLastWin32Error();
        if (!EndUpdateResourceW(h, !ok) || !ok) throw new System.ComponentModel.Win32Exception(ok ? Marshal.GetLastWin32Error() : err);
    }
}
'@
}

function Set-ExeVersionInfo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$OriginalName,
        [string]$Product = 'RedRiveRR Zapret',
        [string]$Company = 'RedRiveRR',
        [string]$Comments = "Türkiye'de Discord ve engelli sitelere erişim için zapret arayüzü. https://github.com/RedRiveRR/zapret-win-turkey"
    )
    $parts = @($Version -split '[^0-9]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
    while ($parts.Count -lt 4) { $parts += 0 }
    $parts = $parts[0..3]
    $verText = $parts -join '.'
    $year = (Get-Date).Year
    $keys = 'Comments', 'CompanyName', 'FileDescription', 'FileVersion', 'InternalName', 'LegalCopyright', 'OriginalFilename', 'ProductName', 'ProductVersion'
    $values = $Comments, $Company, $Description, $verText, ([IO.Path]::GetFileNameWithoutExtension($OriginalName)),
        "Copyright (c) $year RedRiveRR. alimali54/zapret-win-turkey tabanlı.", $OriginalName, $Product, $Version
    $data = [ZwtVersionResource]::Build([int[]]$parts, [string[]]$keys, [string[]]$values, [uint16]0x041F)
    # Yeni derlenen exe'yi antivirüs kısa süre kilitleyebiliyor; yazma ara sıra sessizce boşa gidiyordu
    # (2026-10-27, lite exe, 3 derlemede 2 kez). Doğrulanana kadar en fazla 5 kez denenir.
    for ($try = 1; $try -le 5; $try++) {
        try { [ZwtVersionResource]::Write($Path, $data, [uint16]0x041F) } catch { if ($try -eq 5) { throw } }
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($vi.FileDescription -eq $Description -and $vi.ProductName -eq $Product) { return }
        Start-Sleep -Milliseconds (500 * $try)
    }
    throw "Sürüm bilgisi yazılamadı: $Path (okunan açıklama '$($vi.FileDescription)')"
}
