# Katkı Rehberi

## Proje yapısı

| Yol | İçerik |
|---|---|
| `zapret-win-turkey.au3` | Ana uygulama (GUI + akış) |
| `zapret-win-turkey-lite.au3` | Lite sürüm (blockcheck, ağ paylaşımı, DNSCrypt yok) |
| `lib/` | Ortak, GUI'den bağımsız modüller. Ana ve lite sürüm aynı modülleri kullanır |
| `config/strategies.ini` | Hazır ISS stratejileri |
| `tests/` | Birim testleri (GUI ve yönetici yetkisi gerektirmez) |
| `scripts/check.ps1` | Au3Check + sürüm tutarlılığı + birim testleri |

## Yeni bir ISS stratejisi eklemek

Kod değiştirmeye gerek yok. `config/strategies.ini` içinde ilgili motorun bölümüne bir satır ekleyin:

```ini
[Zapret2]
Yeni ISS=--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1
```

Yeni bir profili varsayılan olarak dağıtmak istiyorsanız aynı satırı `lib/Strategies.au3` içindeki `_StrategyDefaults` dizisine de ekleyin. Test, iki listenin aynı kalmasını denetler.

## Geliştirme ortamı

1. [AutoIt](https://www.autoitscript.com/site/autoit/downloads/) kurun ya da taşınabilir `autoit-v3.zip` arşivini **ASCII karakterli bir yola** çıkarın (ör. `C:\tools\autoit`). Au3Check, Türkçe karakter içeren yollarda include'ları doğru çözemez.
2. Denetimi çalıştırın:
   ```powershell
   $env:AUTOIT_DIR = 'C:\tools\autoit'
   pwsh scripts/check.ps1
   ```
3. Uygulamayı denemek için release ZIP'indeki `bin/zapret/zapret-winws` ve `bin/zapret/cygwin` klasörlerini kopyalayın, ardından `.au3` dosyasını yönetici olarak çalıştırın.

## Kurallar

- `.au3` dosyaları UTF-8 (BOM) ve CRLF satır sonuyla saklanır.
- Kullanıcıya gösterilen metinler Türkçedir.
- GUI'den bağımsız her yeni fonksiyon `lib/` altına, testi `tests/test_*.au3` içine yazılır.
- Davranışı değiştiren düzeltmeler ile salt yeniden düzenlemeler ayrı commit'lerde olmalıdır.
- Commit mesajları [Conventional Commits](https://www.conventionalcommits.org/) biçimindedir: `fix(dns): ...`, `feat(strateji): ...`.
- Pull request açmadan önce `scripts/check.ps1` geçmelidir. CI da aynı betiği çalıştırır.
