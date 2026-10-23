# Arayüz tasarımı — RedRiveRR Zapret

Yeni arayüzün tasarım kaynakları. Ekranlar Claude Design kanvasında çizildi; buradaki
`.dc.html` dosyaları o kanvasın kaynak kopyalarıdır (çalıştırılabilir uygulama değil,
kanvas çalışma zamanı olmadan tarayıcıda tam görünmezler).

## Klasör

| Dosya | İçerik |
|---|---|
| `yonler/Gecit.dc.html` | A — Geçit: koyu lacivert, büyük durum halkası |
| `yonler/Rota.dc.html` | B — Rota: açık tema, bağlantı yolu çizimi |
| `yonler/Anahtar.dc.html` | C — Anahtar: kompakt pencere, tek büyük düğme |
| `ekranlar/Baglanti.dc.html` | Seçilen yön (B'nin ayrıntısı + C'nin kompaktlığı): Bağlantı ekranı |
| `ekranlar/Strateji.dc.html` | Strateji bul: hızlı test / tam analiz, son sonuçlar |
| `ekranlar/Servis.dc.html` | Servis durumu, otomatik onarım, yeniden başlatma |
| `ekranlar/DNS.dc.html` | DNS durumu ve seçimi |
| `ekranlar/Diger.dc.html` | Ağ paylaşımı, güncelleme, tanılama, temizlik |
| `logo/Logo.dc.html` | Logo seçenekleri ve küçük boyut denemeleri |
| `canvas.json` | Kanvas düzeni |

## Kararlar

- **Yön:** B'nin ayrıntı düzeyi ve menü rahatlığı + C'nin küçük penceresi (460×660), altta simgeli sekme çubuğu.
- **Renkler:** yumuşak gri zemin, çivit-mor vurgu `#5B5BD6`, yeşil "yol açık", sarı uyarı; açık ve koyu tema.
- **Ad:** RedRiveRR Zapret.
- **Logo:** açık kilit (erişim açıldı) — kullanıcı seçimi.
- **Uygulama teknolojisi:** henüz karar verilmedi (WebView2 denemesi önerildi; ADR-011 gözden geçirilecek).
