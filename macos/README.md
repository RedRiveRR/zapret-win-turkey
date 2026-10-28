# RedRiveRR Zapret — macOS (geliştirici notu)

Kullanıcı rehberi: [`docs/macos.md`](../docs/macos.md)

- Swift paketi (Swift 5.7+, macOS 12+, Intel + Apple Silicon universal).
- Hedefler:
  - `ZapretCore`: saf mantık (SOCKS5/HTTP ön proxy, DoH, strateji analizi, güncelleme, ağ paylaşımı planı); testleri `Tests/ZapretCoreTests`.
  - `RedRiveRRZapret`: menü çubuğu uygulaması; panel `Resources/web/` (WKWebView).
  - `zwt-helper`: yönetici yardımcısı (sistem proxy ayarı, go-pcap2socks ağ geçidi).
- Derleme ve test: `swift build && swift test`
- Paket: `bash scripts/build-app.sh` — tpws (zapret v72.13, SHA256 sabit) indirilir, go-pcap2socks v0.2.0 kaynaktan derlenir (`scripts/build-pcap2socks.sh`, Go gerekir), ad-hoc imzalanır.
- Sürüme ekleme: `bash scripts/release-mac.sh <etiket>` (deneme), `--yayinla` ile yükler.
- CI: `.github/workflows/macos.yml` (testler + universal paket).
