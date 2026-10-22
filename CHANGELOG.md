# Değişiklik Günlüğü

Bu dosya, [alimali54/zapret-win-turkey](https://github.com/alimali54/zapret-win-turkey) üzerine bu fork'ta (`gelistirme` dalı) yapılan değişiklikleri listeler. Temel: upstream `9eeac04` (v4.5 kaynakları).

## [Yayınlanmadı]

### Yeni
- **Akıllı ISS analizi.** "ISS Analizi" artık şu seçenekleri sunuyor:
  - *Tam analiz:* ISS taraması yapılır, ardından bulunan stratejiler otomatik sınanır.
  - *Hızlı akıllı test:* tarama yapılmaz; hazır profiller, kayıtlı ve önceki stratejiler sınanır.
  - *Önceki sonuçlar:* eski akıllı analiz sonucu veya eski tarama listesi açılır.

  Her strateji winws2 ile başlatılıp Discord'un sohbet sunucusuna (`gateway.discord.gg`), discord.com, roblox.com ve Discord CDN'ine TLS 1.2 ve 1.3 ile defalarca bağlanılarak ölçülür. Ölçüm başarı, gecikme ve sadeliğe göre 0–100 arasında puanlanır. Sonuç tablosunda ★ önerilen strateji tek tıkla kullanılabilir. Tarayıcıda deneme yanıltıcıdır (tarayıcı Discord'u QUIC ile zapret olmadan da açabiliyor); akıllı analiz uygulamanın gerçekten kullandığı TCP bağlantısını ölçer. Hedefler `config.ini` → `[SmartAnalysis] Targets=` ile değiştirilebilir. Lite sürümde tepsi menüsünden "Hazır profilleri akıllı test et".

  **Sınır:** yalnızca TCP bağlantıları ölçülür (mesajlaşma, sunucu bağlantısı, sayfalar). Discord **sesli görüşmesi (UDP) ölçülmez**; puan yüksek olsa da sesi ayrıca bir sesli görüşmeyle deneyin.
- Akıllı analiz yüzlerce adayla da hızlı: kayıtlı strateji ve hazır profiller her zaman, tarama sonuçları sadeden karmaşığa doğru ölçülür; 25 tam başarılı aday bulunca eleme erken biter, en fazla 150 tarama adayı elenir. Blockcheck 60 stratejiye ulaşınca "Yeterli — akıllı analize geç" önerilir.
- Blockcheck sonuçları okunamazsa (log biçimi değişmişse) artık "strateji bulunamadı" yerine açık uyarı veriliyor.
- **Hazır stratejiler `config/strategies.ini` dosyasında.** Yeni bir ISS profili eklemek için kodu değiştirip yeniden derlemek gerekmiyor. Dosya silinirse gömülü varsayılanlar kullanılır.
- **Log dosyası** (`logs/app.log`, 512 KB'ta döner). Açılış, DNS kontrol sonucu, başlatma komut satırı, çökme, servis kurulumu ve blockcheck sonuçları kaydedilir.
- **Tanılama paketi:** tepsi menüsü → "Tanılama paketi oluştur". Log, ayarlar ve servis durumu masaüstüne ZIP olarak kaydedilir. Ziyaret edilen siteler, IP ve MAC adresleri pakete eklenmez.
- **Güncelleme bildirimi:** açılışta arka planda bu fork'un GitHub'daki son sürümüne bakılır (upstream'e değil; upstream sürümleri bu geliştirmeleri içermez). Yeni sürüm varsa tepsi bildirimi gösterilir. Hiçbir şey otomatik indirilmez. `config.ini` → `[Settings] UpdateCheck=0` ile kapatılır.
- **Servis stratejisini güncelleme:** servis kuruluyken "ISS Analizi" düğmesi "Servis Stratejisini Güncelle" olur. Analiz süresince servis durdurulur, seçilen strateji servise yazılıp yeniden başlatılır. DNS ayarına dokunulmaz; artık "Temizle → analiz → yeniden kur" gerekmiyor.
- **İsteğe bağlı otomatik yeniden başlatma:** servis kurulurken, servis kapanırsa Windows'un onu yeniden başlatıp başlatmayacağı sorulur. Varsayılan *Hayır*: hile korumalı oyunlarda Zapret'in tekrar tekrar açılması hesap için risk olabilir. *Evet* denirse en fazla 2 kez (10 sn ve 60 sn sonra) yeniden başlatılır.
- **Eski kurulumdan geçiş:** yeni sürüm başka bir klasöre çıkarıldığında, eski klasörü gösteren `ZapretService` ve `dnscrypt-proxy` servisleri tespit edilir ve onayla kaldırılır. DNSCrypt kaldırılırsa DNS otomatiğe alınır, internet kesilmez.
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
- `scripts/build.ps1` ile tekrarlanabilir paketleme: upstream v4.5 ikilileri (SHA256 ile sabitlenmiş) + bu repodaki kaynak + derlenen exe. Paketlerde geliştiriciye ait `config.ini` ve loglar yok. Her geliştirme push'unda "Paket" iş akışı test paketi üretir.
- `CONTRIBUTING.md`, `THIRD_PARTY.md` (ikililerin SHA256 özetleri), issue şablonları.
