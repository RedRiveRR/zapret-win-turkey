# RedRiveRR Zapret — macOS (geliştirici notu)

Tasarım: [`docs/superpowers/specs/2026-10-27-macos-design.md`](../docs/superpowers/specs/2026-10-27-macos-design.md)

- Swift paketi (macOS 12+, Intel + Apple Silicon). Arayüz repodaki `ui/web/` dosyalarıdır; pakete kopyalanır.
- Geliştirme Windows'ta yapıldığı için derleme ve birim testleri **yalnız GitHub Actions macOS sunucusunda** koşar: `.github/workflows/macos.yml` (`swift test`, ardından `.app` paketi).
- Hedefler: `ZapretCore` (saf mantık, `Tests/ZapretCoreTests`), `RedRiveRRZapret` (uygulama), `zwt-helper` (yönetici yardımcısı).
