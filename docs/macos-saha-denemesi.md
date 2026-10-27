# macOS saha denemesi (Aşama 1)

Amaç: Mac'te Discord'un tpws + sistem proxy'siyle açılıp açılmadığını ve hangi stratejinin çalıştığını görmek.
Plan: `docs/superpowers/plans/2026-10-27-macos-asama-0-1.md` (Task 7). Sonuçlar en altta.

## Hazırlık
1. GitHub'da depoya giriş yapmışken **Actions → macOS** iş akışının son başarılı çalıştırmasını açın; altta **Artifacts** bölümündeki `RedRiveRR-Zapret-macOS-…` dosyasını indirin. (İçinde bir zip daha var; ikisini de açın.)
2. Çıkan **RedRiveRR Zapret.app**'e **sağ tıklayın → Aç** (imzasız olduğu için çift tıklama engellenir). "Yine de açmak istiyor musunuz?" → **Aç**.
   - macOS 15 (Sequoia) ve sonrasında sağ tık → Aç seçeneği yok: önce çift tıklayın, uyarıyı kapatın, sonra **Sistem Ayarları → Gizlilik ve Güvenlik** en altındaki **Yine de Aç** düğmesine basın.
3. "Uygulamalar klasörüne taşınsın mı?" → **Taşı**. Uygulama Uygulamalar'dan yeniden açılır.

## Deneme
4. Pencere Windows'taki yeni arayüzle aynı görünmeli (Bağlantı, Strateji, Servis, DNS, Diğer). Diğer sayfasında "Klasik arayüze geç" satırı olmamalı.
5. **Strateji** sekmesinden ilk stratejiyi seçin, **Bağlantı → Başlat**. İlk seferde macOS **yönetici parolası** ister (yardımcı bir kez kurulur).
6. Durum "Discord'a yol açık" olunca **Discord uygulamasını** açın (açıksa tamamen kapatıp yeniden açın). Mesajlar yükleniyor mu? Bir **sesli kanala** girip konuşabiliyor musunuz?
7. Tarayıcıda Discord dışı birkaç site (ör. e-posta) açılıyor mu?
8. Çalışmazsa **Durdur**, sonraki stratejiyi seçip 5–7'yi tekrarlayın. Dört stratejinin her biri için sonucu not edin.

## Güvenlik denetimleri
9. **Durdur**'dan sonra: Sistem Ayarları → Ağ → (bağlantınız) → Ayrıntılar → **Proxy'ler**: "SOCKS proxy" kapalı (ya da sizin eski ayarınız) olmalı.
10. Başlat'tan sonra uygulamayı **zorla kapatın** (⌥⌘⎋ → RedRiveRR Zapret → Zorla Çık). 5–10 sn içinde SOCKS proxy kendiliğinden kapanmalı ve internet çalışmalı.
11. Pencereyi kırmızı düğmeyle kapatın: uygulama menü çubuğunda (kilit simgesi) çalışmaya devam etmeli; simge → **Kapat** ile kapanmalı.

Takılırsanız: kayıtlar `~/Library/Logs/RedRiveRR Zapret/` (Diğer → Kayıtları aç).

## Sonuçlar
| Strateji | Discord mesaj | Sesli sohbet | Diğer siteler | Not |
|---|---|---|---|---|
| Bölme + sıra bozma | | | | |
| Orta alan adında bölme | | | | |
| TLS kaydı bölme | | | | |
| OOB + bölme | | | | |

Güvenlik denetimleri (9–11): …
