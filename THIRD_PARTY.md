# Üçüncü Taraf Bileşenler

Bu araç yönetici yetkisiyle çalışır ve aşağıdaki programları kullanır. Repoda bulunan ikili dosyaların SHA256 özetleri, indirdiğiniz paketteki dosyalarla karşılaştırabilmeniz için listelenmiştir.

## Repoda bulunanlar

| Bileşen | Sürüm | Kaynak | Lisans | Dosya | SHA256 |
|---|---|---|---|---|---|
| dnscrypt-proxy | 2.1.18 | [DNSCrypt/dnscrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) | ISC (`bin/dnscrypt-proxy/LICENSE`) | `bin/dnscrypt-proxy/dnscrypt-proxy.exe` | `d847f834aef02f8705a649dc1060f520cdb7931d7361035728770dce2c16eeb6` |
| go-pcap2socks | bilinmiyor | [DaniilSokolyuk/go-pcap2socks](https://github.com/DaniilSokolyuk/go-pcap2socks) | kaynak repoya bakın | `bin/go-pcap2socks/go-pcap2socks.exe` | `9e0aee0c7d65d09dc0e7063c589f7224b720f29a743c3226c9daa1b493f94b25` |
| blockcheck betikleri | zapret / zapret2 ile gelen | [bol-van/zapret](https://github.com/bol-van/zapret) | MIT | `bin/zapret/blockcheck/*/blockcheck*.sh` | — |
| oui.txt | — | IEEE OUI kaydı | IEEE | `oui.txt` | — |

## Repoda bulunmayanlar (zapret-win-bundle'dan kopyalanır)

`bin/zapret/` altına kullanıcı tarafından yerleştirilir; bkz. `bin/zapret/önce oku - read first.txt`.

| Bileşen | Kaynak | Lisans |
|---|---|---|
| winws.exe, winws2.exe, lua betikleri | [bol-van/zapret-win-bundle](https://github.com/bol-van/zapret-win-bundle) | MIT |
| WinDivert sürücüsü | [basil00/WinDivert](https://github.com/basil00/WinDivert) | LGPLv3 / GPLv2 |
| cygwin (blockcheck için bash) | [cygwin.com](https://cygwin.com) | GPL / LGPL |

## Derleme sırasında pakete eklenenler

| Bileşen | Sürüm | Kaynak | Lisans | Pakette | SHA256 |
|---|---|---|---|---|---|
| WebView2Loader.dll (x64) | 1.0.2903.40 | [Microsoft.Web.WebView2 NuGet](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.2903.40) | BSD 3 maddeli (`bin/webview2/LICENSE.txt`) | `bin/webview2/WebView2Loader.dll` | `462b36fd1be6ca9f7563466a89e57c41ef4a4def3e0a84fa885d203aea4a3aaf` |

Yeni arayüz Windows'un WebView2 çalışma zamanını kullanır (Windows 11'de yüklü gelir). Yoksa program eski arayüzle açılır.

## Harici gereksinimler

| Bileşen | Neden | Kaynak |
|---|---|---|
| Npcap | go-pcap2socks ile ağ paylaşımı | [npcap.com](https://npcap.com) |

## Özetleri doğrulama

PowerShell ile:

```powershell
Get-FileHash bin\dnscrypt-proxy\dnscrypt-proxy.exe -Algorithm SHA256
```
