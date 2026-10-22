# Değişiklik Günlüğü

Bu dosya, [alimali54/zapret-win-turkey](https://github.com/alimali54/zapret-win-turkey) üzerine bu fork'ta (`gelistirme` dalı) yapılan değişiklikleri listeler. Temel: upstream `9eeac04` (v4.5 kaynakları).

## [Yayınlanmadı]

### Yeni
- **Hazır stratejiler `config/strategies.ini` dosyasında.** Yeni bir ISS profili eklemek için kodu değiştirip yeniden derlemek gerekmiyor. Dosya silinirse gömülü varsayılanlar kullanılır.
- **Log dosyası** (`logs/app.log`, 512 KB'ta döner). Açılış, DNS kontrol sonucu, başlatma komut satırı, çökme, servis kurulumu ve blockcheck sonuçları kaydedilir.
- **Tanılama paketi:** tepsi menüsü → "Tanılama paketi oluştur". Log, ayarlar ve servis durumu masaüstüne ZIP olarak kaydedilir. Ziyaret edilen siteler, IP ve MAC adresleri pakete eklenmez.
- **Güncelleme bildirimi:** açılışta arka planda GitHub'daki son sürüme bakılır. Yeni sürüm varsa tepsi bildirimi gösterilir. Hiçbir şey otomatik indirilmez. `config.ini` → `[Settings] UpdateCheck=0` ile kapatılır.
- **Genişletilmiş çakışma tespiti:** GoodbyeDPI'ya ek olarak ByeDPI ve bu programın klasörü dışından çalışan `winws`/`winws2` (ikinci bir zapret paketi) de tespit edilir.

### Düzeltmeler
- Zapret1 analizi, Git Bash veya WSL açıkken hiç bitmiyordu. Artık yalnızca kendi bash süreci bekleniyor.
- Blockcheck sonunda sistemdeki **tüm** `bash.exe`, `sh.exe`, `tee.exe` süreçleri kapatılıyordu; açık Git Bash/MSYS pencereleri de kapanıyordu. Artık yalnızca program klasöründeki süreçler kapatılıyor.
- Zapret1 logu `SUMMARY` satırıyla bittiğinde program çöküyordu.
- Yalnızca VPN veya sanal ağ kartı açıkken DNS sessizce değiştirilemiyor, ama kullanıcıya "DNS otomatiğe alındı" deniyordu. Artık uyarı gösteriliyor.
- Zapret durdurulurken veya GoodbyeDPI kapatılırken süreç kapanmazsa arayüz sonsuza kadar donuyordu. Artık 5 sn sonra zorla kapatma deneniyor, olmazsa kullanıcı uyarılıyor.
- Servis oluşturma başarısız olduğunda hiçbir mesaj gösterilmiyordu.
- DNS kontrolü geçici bir ağ hatasında (boş yanıt, zaman aşımı) hemen "DNS zehirlenmesi" diyordu. Artık bir kez daha deneniyor.
- Footer'daki eski "v2.7.0" metni kaldırıldı. Sürüm bilgisi tek yerden geliyor.

### Geliştirici
- Ortak kod `lib/` altında: ana ve lite sürüm aynı modülleri kullanıyor. İki betik birlikte net 338 satır kısaldı (508 silindi, 170 eklendi).
- GUI'den bağımsız birim testleri (`tests/`, 116 test) ve `scripts/check.ps1` (Au3Check + sürüm tutarlılığı + testler).
- GitHub Actions CI, her push'ta aynı denetimi çalıştırıyor.
- `CONTRIBUTING.md`, `THIRD_PARTY.md` (ikililerin SHA256 özetleri), issue şablonları.
