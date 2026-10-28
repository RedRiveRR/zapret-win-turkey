## macOS (ilk sürüm)

**İndir:** `RedRiveRR-Zapret-macOS-v5.2.4.zip` — Intel ve Apple Silicon (universal), macOS 12 Monterey ve sonrası. Kurulum ve ilk açılış (macOS 15'te "Yine de Aç"): [docs/macos.md](https://github.com/RedRiveRR/zapret-win-turkey/blob/master/docs/macos.md)

- Menü çubuğu uygulaması: kilit simgesinden açılan panel; açık kilit = Zapret çalışıyor.
- Discord ve Roblox: adlar şifreli DNS (DoH) ile çözülür (Mac'in DNS ayarı değişmez), bağlantı zapret `tpws` ile TLS kaydı bölünerek DPI'den geçirilir. Discord güncelleyicisi dahil.
- **Strateji analizi:** sağlayıcınızda çalışan yöntemi ~20 sn'de ölçer (Discord uygulaması, Discord güncelleyicisi ve tarayıcı gibi davranan üç bağlantı türüyle), en iyisini seçer.
- **Ağ paylaşımı:** PS5/PS4/Xbox/Switch/TV bu Mac üzerinden Discord'a (ağ geçidi, go-pcap2socks); bağlı cihazlar listesi.
- **Discord'u yeniden başlat** düğmesi, **otomatik güncelleme** (SHA256 ve imza denetimli).
- Bilinen: uygulama Apple'a imzalatılmadı (ilk açılışta onay gerekir); sesli sohbet (UDP) bu yoldan geçmez — şu an engelsiz.
