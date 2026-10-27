# RedRiveRR Zapret — macOS sürümü: tasarım

Tarih: 2026-10-27 · Durum: onay bekliyor · Hedef sürüm: Windows ile aynı numara (ilk Mac sürümü 5.3.0 olarak planlanır)

## 1. Amaç ve neden

Windows'taki RedRiveRR Zapret'in yaptığını macOS'ta yapan bir uygulama: Türkiye'de Discord (ve benzeri) engellerini aşan stratejiyi **kendisi ölçerek bulur**, onu **çalıştırır**, aynı aşmayı **ağ paylaşımıyla** konsol/TV gibi cihazlara yayar; **arayüz ve tasarım Windows'takiyle aynıdır**. GitHub'da Windows sürümüyle aynı depoda, aynı sürüm numarasıyla yayınlanır.

Kullanıcının sözleri: "aynı amacı sergileyen macOS'ta strateji geliştirip analiz edip en iyi stratejiyi seçip kısıtlamaları aşan ve bu işlemi ağ paylaşımıyla diğer cihazlara da yayan ve tasarımı ve arayüzü bizimkine benzeyen bir app" · "kapsam tamam, hepsi olsun".

## 2. Hedefler

- Ekranlar Windows'takiyle aynı: Bağlantı, Strateji, Servis, DNS, Diğer (+ Ağ paylaşımı sayfası, bağlı cihazlar).
- Strateji analizi: hızlı test + tam analiz, Discord'a gerçek bağlantılarla ölçüm ve 0–100 puan, "en iyisini kullan".
- Bilgisayarda engel aşma (Discord uygulaması ve tarayıcılar).
- Arka plan hizmeti: Mac açılınca kendiliğinden başlar (Windows "Servis" karşılığı).
- DNS: sağlayıcı / Cloudflare / şifreli DNS (DNSCrypt).
- Ağ paylaşımı + bağlı cihazlar listesi (tür etiketi dahil).
- Kendini güncelleme, tanılama paketi (maskelemeli), kayıtlar.
- Test cihazı: kullanıcının MacBook Air 2018 (Intel), **macOS 12 Monterey**. En düşük desteklenen sürüm: macOS 12. Derleme **universal** (Intel + Apple Silicon).

## 3. Hedef dışı

- Windows'a özgü olanlar Mac'e gelmez: klasik (alimali) pencere, Lite sürüm, Blockcheck (cygwin bash) taraması, WinDivert, Akıllı Uygulama Denetimi/Defender adımları.
- Apple geliştirici hesabıyla imza/notarization (yıllık ücret; kullanıcı ödemeyecek).
- macOS 11 ve öncesi.
- Sesli sohbet (UDP) için özel strateji: tpws UDP işlemez (bkz. 5.3).

## 4. Kaçınılacaklar (çalışsa bile başarısızlık sayılır)

- Mac'te sistem ayarlarını (proxy, DNS, pf) kalıcı bozuk bırakmak: her değişiklik geri alınabilir olmalı; uygulama kapanınca/kaldırılınca eski hâline dönmeli.
- Her başlat/durdur'da yönetici şifresi sormak.
- Windows sürümünü bozmak: ortak arayüz dosyaları değişirse Windows'ta da çalışmaya devam etmeli; Windows derleme/test akışı aynen geçmeli.
- Kişisel veri sızdırmak (repo, paket, tanılama) — Windows'taki kurallar aynen.

## 5. Kısıtlar ve doğrulanmış gerçekler (araştırma 2026-10-27)

### 5.1 Motor: tpws
- bol-van/zapret v72.13 paketinde `binaries/mac64/tpws` var; **universal** (x86_64 + arm64; Mach-O başlığından doğrulandı). Belge: "partially MacOS Sierra+".
- Mac'te paket seviyesindeki motor (dvtws) kullanılamaz (pf'de divert yok). Yalnız **tpws** (TCP aracı/proxy).
- tpws iki kipte çalışır: **şeffaf** (pf `rdr`/`route-to`, root, `/etc/pf.conf` anchor yaması; belge: "gelecek sürümlerde garanti değil") ve **SOCKS4/5** (`--socks --port --bind-addr`).
- Mac'te desteklenen atlatma ayarları: `--split-pos` (sayı ya da `method|host|endhost|sld|endsld|midsld|sniext` işaretleri ±N), `--disorder[=http|tls]`, `--oob[=http|tls]`, `--oob-data`, `--tlsrec`/`--tlsrec-pos`, `--hostcase`, `--hostspell`, `--hostdot`, `--hosttab`, `--hostnospace`, `--hostpad`, `--domcase`, `--methodspace`, `--methodeol`, `--unixeol`, `--fix-seg`, `--tamper-start/--tamper-cutoff`. Yalnız Linux: `--mss`, `--oob`+`--disorder` birlikte.
- Mac'in kendi **İnternet Paylaşımı desteklenmez** ("If you enable internet sharing tpws stops functioning").

### 5.2 Paylaşım: go-pcap2socks
- macOS'ta çalışır (`sudo`, libpcap — macOS'ta sistemde var), trafiği bir **SOCKS5 outbound**'a yollayabilir (`"socks": {"address": "127.0.0.1:<port>"}`). Hazır Mac dosyası yok → GitHub Actions macOS sunucusunda derlenir (universal).
- Cihaz bağlama Windows'takiyle aynı: go-pcap2socks sanal ağın ağ geçidi olarak ARP'a cevap verir; cihaza IP/maske/geçit/DNS/MTU elle girilir. Bağlı cihazlar listesi aynı log satırlarından okunur.
- Cihazların DNS'i Windows'taki gibi (ADR-016): Mac DNSCrypt kullanıyorsa o, değilse paylaşıma özel geçici dnscrypt-proxy kopyası (127.0.0.1:5354); sağlayıcı Discord adları için şifresiz DNS'i düşürüyor (H23).

### 5.3 Sesli sohbet
- tpws (iki kipte de) ve SOCKS üzerinden UDP geçmez; Discord sesi doğrudan gider. Windows'ta sesli sohbet çalıştı (TCP stratejisiyle) → tahmin: Türkiye'de ses engellenmiyor. **Mac'te sahada doğrulanacak** (kabul ölçütü 10.4).

### 5.4 Mac güvenliği
- İmzasız dağıtım: ilk açılışta Monterey'de sağ tık → **Aç**; macOS 15'te Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç**. README'de resimli anlatılır.
- Apple Silicon imzasız kodu hiç çalıştırmaz → derlemede tüm ikililere **ad-hoc imza** (`codesign -s -`, ücretsiz).
- Uygulamanın kendi indirdiği dosyalara karantina işareti konmaz (indirme uygulamada `LSFileQuarantineEnabled` yok) → güvenlik uyarısı yalnız ilk kurulumda.
- Sistem proxy'si (`networksetup`), DNS, go-pcap2socks (BPF) yönetici ister.

### 5.5 Geliştirme ortamı
- Geliştirme Windows bilgisayarında yapılır; Swift burada derlenip çalıştırılamaz. **Derleme ve birim testleri GitHub Actions macOS sunucusunda** (`macos-14`, Xcode 15+, `swift build/test`) koşar. Sahada deneme kullanıcının Mac'inde.
- Windows'taki doğrulama akışı (`check.ps1`) Mac kodunu derleyemez; Mac için ayrı CI işi zorunlu kapı olur.

## 6. Kullanıcının verdiği kararlar

- GitHub'da Mac sürümü olarak herkese açık yayın.
- Kapsam: Bölüm 2'nin tamamı ilk sürümde.
- Test: kullanıcının MacBook Air 2018 (Monterey).
- Para harcanmayacak (imza/notarization yok).

## 7. Tasarım (ajanın kararları — onayda kontrol edin)

### 7.1 Uygulama yapısı
- **Swift + AppKit + WKWebView**, en düşük macOS 12. Arayüz: repodaki `ui/web/` (HTML/CSS/JS) **aynı dosyalar**; Mac uygulaması paketine kopyalanır.
- Köprü: Mac uygulaması sayfaya `window.chrome.webview` taklidi enjekte eder (`postMessage` → `webkit.messageHandlers`, programdan sayfaya mesajlar `message` olayı olarak). Böylece `uygulama.js` köprü değişmeden çalışır.
- Platform farkları sayfaya `{tip:"platform", ad:"macos"}` mesajıyla bildirilir; JS Windows'a özgü satırları gizler/metinleri değiştirir (ör. "Npcap" satırı yok, "Klasik arayüze geç" yok, servis metinleri "arka plan hizmeti"). Windows bu mesajı göndermediği için davranışı değişmez.
- Neden: tasarım birebir aynı kalır, tek arayüz kaynağı; Mojave/Monterey'de çalışır; uygulama küçük (Electron'un ~100 MB'ı yok); Tauri'nin Rust zinciri yok.

### 7.2 Program mantığı (Swift modülleri; AutoIt `lib/` karşılıkları)
| Modül | Karşılık | Not |
|---|---|---|
| `AppState` | `lib/AppState.au3` | durum tek kaynak |
| `WebBridge`, `WebState` | `WebMsg`, `WebState` | **aynı JSON mesaj sözleşmesi** (`uygulama.js` başındaki liste) |
| `TpwsEngine`, `Strategies` | `Winws`, `Strategies` | tpws argümanları, strateji listesi (`config/strategies-macos.ini`) |
| `SmartAnalysis` | `SmartAnalysis.au3` | aynı ölçüm hedefleri ve puan formülü; ölçüm `/usr/bin/curl --socks5-hostname` ile |
| `SystemProxy`, `Dns` | `Network.au3` | `networksetup` (yardımcı üzerinden) |
| `BackgroundService` | `Service`, `Health` | launchd (bkz. 7.4) |
| `LanShare` | `LanShare.au3` | go-pcap2socks + tpws SOCKS; bağlı cihazlar, OUI (`veri/cihaz-ureticileri.txt` ortak) |
| `SelfUpdate` | `SelfUpdate.au3` | bkz. 7.6 |
| `Diag` | `Diag.au3` | aynı maskeleme kuralları |
| `Log` | `Log.au3` | `~/Library/Logs/RedRiveRR Zapret/` |
Saf mantık (puanlama, ayrıştırma, maskeleme, JSON) birim testli (`swift test`); Windows'taki test vakaları referans alınır.

### 7.3 Engel aşma (bilgisayarın kendisi)
- Varsayılan: tpws **SOCKS kipinde** `127.0.0.1:<sabit port>` (yönetici gerekmez), macOS **sistem SOCKS proxy'si** ona yönlendirilir (`networksetup -setsocksfirewallproxy` her etkin ağ hizmeti için). Discord (Electron/Chromium) ve tarayıcılar sistem proxy'sine uyar — **tahmin, sahada doğrulanacak**.
- Durdurunca / uygulama kapanınca / kaldırılınca proxy eski hâline döner; önceki proxy ayarları kaydedilip geri yüklenir.
- **Site filtresi** Windows'taki gibi: Kapalı (tüm trafik), Auto (tpws `--hostlist-auto`, otomatik öğrenilen liste), Manuel (`--hostlist`). Listeler ve dışlama listesi Windows'taki dosya adlarıyla, `config/varsayilan/` varsayılanlarından eksikse kopyalanır.
- Yedek yol (yalnız gerekirse, ayrı karar): tpws şeffaf kip + pf anchor.

### 7.4 Yönetici işleri: yardımcı hizmet
- Her işlemde şifre sormamak için **bir kez** yönetici onayıyla (macOS'un kendi parola penceresi; `osascript ... with administrator privileges`) root **LaunchDaemon** kurulur: küçük bir Swift yardımcısı (`zwt-helper`), yalnız root'un ve uygulamanın kullanıcısının erişebildiği bir Unix soketi dinler.
- Yardımcı **yalnız sabit komutları** kabul eder: sistem proxy'sini aç/kapat (yalnız 127.0.0.1:<port>), DNS'i ayarla (yalnız izinli listeden: sağlayıcı/1.1.1.1/127.0.0.1), go-pcap2socks'ı paketteki sabit yoldan başlat/durdur, durum sor. Rastgele komut/yol çalıştırmaz; parametreler doğrulanır.
- "Servis kur" = yardımcı + kullanıcı LaunchAgent'ı (tpws SOCKS'u ve proxy'yi oturum açılınca başlatır). "Servisi kaldır" = hepsini kaldırır, proxy/DNS'i geri alır.
- Neden: SMJobBless gibi Apple yöntemleri imza ister; imzasız dağıtımda tek kurulumluk root hizmeti en az şifre isteyen yol.

### 7.5 Strateji analizi
- Her aday strateji için tpws SOCKS kipinde **geçici bir portta** açılır; `/usr/bin/curl --socks5-hostname` ile Windows'taki aynı hedeflere (gateway.discord.gg, discord.com, roblox.com, Discord CDN; TLS 1.2 ve 1.3, tekrarlı) bağlanılır; aynı puan formülü. Sisteme dokunmaz, yönetici gerekmez.
- Hızlı test: seçilmiş ~10 tpws stratejisi; tam analiz: Bölüm 5.1 ayarlarının sistematik birleşimleri (~40–60). Sonuçlar ve "önerilen" Windows'taki gibi.
- Strateji adları ve açıklamalar Türkçe; liste dosyası güncellemeyle yenilenebilir.

### 7.6 Kendini güncelleme
- Windows'takiyle aynı sözleşme: release'te `RedRiveRR-Zapret-macOS-<etiket>.zip` + `SHA256SUMS.txt`; adres denetimi; SHA256; `ditto -x -k` ile açma; eski uygulama kapanınca **indirilen yeni uygulamanın** `--guncelle-uygula` kipi `.app` paketini yerine koyar (`/Applications` ya da bulunduğu yer) ve yeni sürümü açar; ayarlar `~/Library/Application Support/RedRiveRR Zapret/` altında olduğu için korunur.

### 7.6a Uygulamanın konumu
- macOS, karantinalı (internetten inmiş) uygulamayı İndirilenler'den açınca rastgele salt okunur bir yerden çalıştırır (App Translocation) → kendini güncelleme ve yardımcı hizmet yolları bozulur. İlk açılışta uygulama `/Applications` dışındaysa taşımayı önerir (Windows'taki "Program Files'a taşı" karşılığı); servis kurmak ve güncellemek için `/Applications` şarttır.

### 7.7 Dosya ve paket düzeni
- Repo: `macos/` (Swift paketi: `Package.swift`, `Sources/RedRiveRRZapret`, `Sources/ZwtHelper`, `Tests/`), `macos/scripts/build-app.sh` (.app paketini kurar: Info.plist, simge `.icns`, `ui/web`, `veri/`, tpws, go-pcap2socks, dnscrypt-proxy; ad-hoc imza; zip). Ortak: `ui/web/`, `veri/`, CHANGELOG, README (Mac bölümü).
- Üçüncü taraf ikililer: tpws zapret v72.13 paketinden (SHA256 sabit), dnscrypt-proxy Mac sürümü (SHA256 sabit), go-pcap2socks kaynağından derlenir (sürüm sabit).
- CI: `.github/workflows/macos.yml` — her push'ta `swift build` + `swift test` + paket; etikette release'e Mac zip'i eklenir. Windows iş akışı değişmez.
- Sürüm yayını: Windows ve Mac zip'leri aynı release'te; `SHA256SUMS.txt` ikisini birlikte içerir (iki sürümün güncelleyicisi de aynı dosyayı okur). Mac zip adı Windows güncelleyicisinin aradığı adla (`RedRiveRR-Zapret-<etiket>.zip`) çakışmaz.

## 8. Riskler

| Risk | Etki | Önlem |
|---|---|---|
| Discord sistem SOCKS proxy'sine uymazsa | Bilgisayarda aşma çalışmaz | Erken saha denemesi (aşama 1); yedek: pf şeffaf kip |
| tpws stratejileri Türkiye'deki DPI'ya yetmezse | Mac'te hiçbir strateji çalışmaz | Aşama 1'de elle birkaç tpws stratejisi sahada denenir; sonuç kötüyse kullanıcıya bildirilir, kapsam yeniden konuşulur |
| Sesli sohbet (UDP) engelliyse | Ses çalışmaz | Sahada doğrulama; tpws ile çözüm yok — açıkça belgelenir |
| go-pcap2socks Mac'te beklenmedik sorun | Paylaşım çalışmaz | Paylaşım ayrı aşama; Windows'taki gibi gerçek log satırlarıyla test |
| Uzaktan geliştirme (Windows'ta yazıp CI'da derleme) | Yavaş döngü | Saf mantık birim testli; her aşamada kullanıcı Mac'inde kısa deneme listesi |
| macOS sürüm farkları (12 → 15) | Güvenlik adımları değişir | README iki yolu da anlatır; CI en düşük hedef 12 |

## 9. Aşamalar (her biri ayrı onay/deneme)

0. **İskelet ve CI:** Swift paketi, WKWebView içinde `ui/web` + köprü, sahte durum; GitHub Actions'ta universal derleme ve `.app` zip. Kabul: Mac'te açılıyor, ekranlar Windows'taki gibi.
1. **Motor ve engel aşma (en riskli, en önce):** tpws + sistem SOCKS proxy (yardımcı hizmetle); elle seçilen 3–4 tpws stratejisi. Kabul: Mac'te Discord açılıyor; ses denemesi.
2. **Strateji analizi:** hızlı test + tam analiz + puan + "en iyisini kullan".
3. **Arka plan hizmeti + DNS** (launchd, networksetup, DNSCrypt).
4. **Ağ paylaşımı + bağlı cihazlar** (go-pcap2socks derlemesi dahil). Kabul: PS5'te Discord.
5. **Kendini güncelleme, tanılama, kayıtlar, README/CHANGELOG, ilk Mac sürümü yayını.**

## 10. Kabul ölçütleri (ilk Mac sürümü)

1. Monterey'de (Intel) ve CI'da (Apple Silicon) açılır; tasarım Windows'takiyle aynı.
2. Analiz en az bir çalışan strateji bulur ve "en iyisini kullan" ile Discord uygulaması açılır.
3. Durdur / kapat / servisi kaldır sonrası sistem proxy ve DNS önceki hâline döner.
4. Sesli sohbet denenir; sonuç (çalışıyor/çalışmıyor) README'ye yazılır.
5. PS5 paylaşımla internete ve Discord'a çıkar; bağlı cihazlarda "PlayStation" görünür.
6. Program içinden bir sonraki Mac sürümüne güncellenir.
7. Repo/paket/tanılamada kişisel veri yok; Windows sürümü ve testleri etkilenmez.

## 11. Yapıcıya bırakılanlar

Swift kod düzeni, modüllerin iç ayrıntıları, tpws strateji adayı listesinin tam içeriği, yardımcı hizmetin mesaj biçimi (Bölüm 7.4 sınırları içinde), tpws SOCKS port numarası, `.icns` üretimi, CI ayrıntıları.
