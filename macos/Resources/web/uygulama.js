// RedRiveRR Zapret — macOS menü çubuğu paneli (Windows arayüzü ui/web'de, ayrı).
//
// Program -> sayfa (window.chrome.webview 'message', Resources/bridge.js):
//   {tip:"durum", durum:"aktif|hazir|bekliyor|hata", rozet, baslik, aciklama, calisiyor:bool, dugme:bool, strateji}
//   {tip:"strateji", secenekler[], secili, secimAcik, analizAcik, zaman, sonuclar[{puan, ad, durum, tam, calisti, secim, secili}]}
//   {tip:"analiz", calisiyor:bool, metin, oran:0..1}
//   {tip:"discord", yenidenBaslat:bool}   (Discord, Zapret'ten önce açılmışsa yeniden başlatılmalı)
//   {tip:"paylasim", acik:bool, kullanilabilir:bool, gecit:bool, ip, maske, agGecidi, dns, dns2, mtu, adres, port, cihaz:int,
//    kablosuz:bool, guvenlikDuvari:bool, etkin:int, cihazlar:[{ip, tur, durum, etkin:bool, baglanti}]}   (gecit: ağ geçidi açık — cihaza IP elle; değilse yedek proxy yolu)
//   {tip:"guncelleme", surum:"5.3.0|", durum:"hazir|indiriliyor|hata", metin}
//   {tip:"surum", surum}, {tip:"bildirim", metin}
// Sayfa -> program (postMessage):
//   {tip:"hazir"}, {tip:"komut", ad:"baslat|durdur|analiz|sonuclar|kayitlar|github|cikis|gizle|discordYenile|
//                                   paylasimAc|paylasimKapat|guncelle"}
//   {tip:"secim", alan:"strateji", deger}, {tip:"kopyala", metin}, {tip:"boyut", yukseklik}   (panel içeriğe göre boyutlanır)
'use strict';

const wv = window.chrome && window.chrome.webview;
const $ = (id) => document.getElementById(id);
const gonder = (m) => { if (wv) wv.postMessage(m); };

// --- Menü ---
const menu = $('menu');
function menuAc(acik) {
  menu.hidden = !acik;
  $('menu-ac').setAttribute('aria-expanded', String(acik));
}
$('menu-ac').addEventListener('click', (e) => { e.stopPropagation(); menuAc(menu.hidden); });
document.addEventListener('click', (e) => { if (!menu.hidden && !menu.contains(e.target)) menuAc(false); });
menu.querySelectorAll('[data-komut]').forEach((b) => b.addEventListener('click', () => {
  menuAc(false);
  gonder({ tip: 'komut', ad: b.dataset.komut });
}));
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (!menu.hidden) menuAc(false); else gonder({ tip: 'komut', ad: 'gizle' });
});

// --- Bağlantı ---
let calisiyor = false;
$('guc').addEventListener('click', () => {
  $('guc').disabled = true; // yanıt gelene kadar çift tıklamayı engelle
  gonder({ tip: 'komut', ad: calisiyor ? 'durdur' : 'baslat' });
});
$('discord-yenile').addEventListener('click', () => {
  $('discord-yenile').disabled = true;
  gonder({ tip: 'komut', ad: 'discordYenile' });
});

function durumUygula(m) {
  $('kahraman').dataset.durum = m.durum || 'bekliyor';
  $('rozet').textContent = m.rozet || '';
  $('baslik').textContent = m.baslik || '';
  $('aciklama').textContent = m.aciklama || '';
  calisiyor = !!m.calisiyor;
  $('guc').disabled = !m.dugme;
  $('guc').setAttribute('aria-label', calisiyor ? 'Durdur' : 'Başlat');
  if (!calisiyor) $('discord-yenile').hidden = true;
}

// --- Strateji ---
$('sec-strateji').addEventListener('change', (e) => {
  e.target.disabled = true; // program yeni durumu gönderince açılır
  gonder({ tip: 'secim', alan: 'strateji', deger: e.target.value });
});
$('analiz').addEventListener('click', () => {
  $('analiz').disabled = true;
  gonder({ tip: 'komut', ad: 'analiz' });
});

function stratejiUygula(m) {
  const sel = $('sec-strateji');
  const liste = m.secenekler || [];
  if (Array.from(sel.options).map((o) => o.value).join('|') !== liste.join('|')) {
    sel.replaceChildren(...liste.map((ad) => new Option(ad, ad)));
  }
  sel.value = m.secili || '';
  sel.disabled = !m.secimAcik;
  $('analiz').disabled = !m.analizAcik;
  $('analiz').textContent = (m.sonuclar || []).length ? 'Yeniden analiz et' : 'Analiz et';
  $('zaman').textContent = m.zaman ? 'Son analiz ' + m.zaman + '. Bir satıra tıklayarak seçebilirsin.'
    : 'Analiz, sağlayıcında en iyi çalışan yöntemi ölçüp seçer (yaklaşık 20 sn).';
  $('sonuclar').replaceChildren(...(m.sonuclar || []).slice(0, 5).map(satir));
}

function satir(r) {
  const li = document.createElement('li');
  li.className = (r.calisti ? 'tam' : 'calismadi') + (r.secili ? ' secili' : '');
  li.title = r.tam || '';
  const puan = document.createElement('span');
  puan.className = 'puan';
  puan.textContent = r.puan;
  const ad = document.createElement('span');
  ad.className = 'ad';
  ad.textContent = (r.ad || '').replace(/^★\s*/, '');
  const ms = document.createElement('span');
  ms.className = 'ms';
  const m = /(\d+) ms/.exec(r.durum || '');
  ms.textContent = m ? m[1] + ' ms' : (r.durum || '').replace(' geçti', '');
  li.append(puan, ad, ms);
  if (r.secim) {
    li.dataset.secim = r.secim;
    li.tabIndex = 0;
    li.setAttribute('role', 'button');
    li.setAttribute('aria-pressed', String(!!r.secili));
    const sec = () => { if (!r.secili) gonder({ tip: 'secim', alan: 'strateji', deger: r.secim }); };
    li.addEventListener('click', sec);
    li.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); sec(); } });
  }
  return li;
}

function analizUygula(m) {
  $('ilerleme').hidden = !m.calisiyor;
  $('ilerleme-cubuk').style.width = Math.round((m.oran || 0) * 100) + '%';
  $('ilerleme-metin').textContent = m.metin || '';
}

// --- Ağ paylaşımı ---
let paylasimAcik = false;
$('paylasim-anahtar').addEventListener('click', () => {
  $('paylasim-anahtar').disabled = true;
  gonder({ tip: 'komut', ad: paylasimAcik ? 'paylasimKapat' : 'paylasimAc' });
});
$('paylasim-kopyala').addEventListener('click', () => gonder({ tip: 'kopyala', metin: $('paylasim-adres').textContent }));
document.querySelectorAll('[data-kopyala]').forEach((b) => b.addEventListener('click', () => gonder({ tip: 'kopyala', metin: $(b.dataset.kopyala).textContent })));

function paylasimUygula(m) {
  paylasimAcik = !!m.acik;
  const a = $('paylasim-anahtar');
  a.setAttribute('aria-checked', String(paylasimAcik));
  a.disabled = !m.kullanilabilir && !paylasimAcik;
  $('paylasim').dataset.acik = String(paylasimAcik);
  $('paylasim-govde').hidden = !paylasimAcik;
  $('paylasim-not').textContent = paylasimAcik ? ''
    : (m.kullanilabilir ? 'Konsol ve TV bu Mac üzerinden Discord\'a bağlansın.' : 'Paylaşım için önce Zapret\'i başlat.');
  $('gecit-blok').hidden = !m.gecit;
  $('proxy-blok').hidden = !!m.gecit;
  $('gecit-ip').textContent = m.ip || '—';
  $('gecit-maske').textContent = m.maske || '—';
  $('gecit-gecit').textContent = m.agGecidi || '—';
  $('gecit-dns').textContent = m.dns || '—';
  $('gecit-dns2').textContent = m.dns2 || '—';
  $('gecit-mtu').textContent = m.mtu || '—';
  $('paylasim-kablosuz').hidden = !(paylasimAcik && m.kablosuz);
  $('paylasim-adres').textContent = m.adres || 'Yerel ağ bulunamadı';
  $('paylasim-port').textContent = m.port || 8080;
  $('paylasim-kopyala').hidden = !m.adres;
  cihazlarUygula(m.cihazlar || [], m.etkin || 0);
  $('paylasim-duvar').hidden = !m.guvenlikDuvari;
}

// "Cihazda nasıl ayarlanır" açılınca panelin altında kalmasın: boyut değişince görünür alana kaydır.
document.querySelector('#paylasim details').addEventListener('toggle', (e) => {
  if (e.target.open) setTimeout(() => e.target.scrollIntoView({ block: 'end', behavior: 'smooth' }), 120);
});

// Bağlı cihazlar: türüne göre simge, ad (üretici), IP, durum. Liste açık/kapalı durumu yeniden çizimde korunur.
const SIMGE = {
  konsol: '<path d="M6 9h12a3 3 0 0 1 3 3v2.5a2.5 2.5 0 0 1-4.6 1.3L15 14H9l-1.4 1.8A2.5 2.5 0 0 1 3 14.5V12a3 3 0 0 1 3-3z"/><path d="M8 11v2M7 12h2M16 11.5h.01M18 12.5h.01"/>',
  tv: '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 20h8"/>',
  telefon: '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 18h2"/>',
  bilgisayar: '<rect x="4" y="5" width="16" height="11" rx="1.5"/><path d="M2 19h20"/>',
  baglanti: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  cihaz: '<rect x="5" y="4" width="14" height="16" rx="2"/><circle cx="12" cy="15" r="1"/>',
};
function cihazSimgesi(tur) {
  const t = (tur || '').toLowerCase();
  if (/playstation|sony|xbox|microsoft|nintendo|valve|steam/.test(t)) return SIMGE.konsol;
  if (/samsung|lg|vestel|tcl|hisense|philips|roku|google|android tv|chromecast|amazon|fire|apple tv|tv/.test(t)) return SIMGE.tv;
  if (/gizli adres|telefon|tablet|xiaomi|huawei|oppo|realme|apple|iphone/.test(t)) return SIMGE.telefon;
  if (/proxy/.test(t)) return SIMGE.baglanti;
  if (/intel|dell|lenovo|hp|asus|acer|msi|gigabyte|realtek/.test(t)) return SIMGE.bilgisayar;
  return SIMGE.cihaz;
}
function cihazlarUygula(liste, etkin) {
  $('cihazlar-baslik').textContent = liste.length
    ? liste.length + ' cihaz bağlı' + (etkin ? ', ' + etkin + ' etkin' : '')
    : 'Henüz bağlanan cihaz yok';
  $('cihaz-liste').replaceChildren(...liste.map((d) => {
    const li = document.createElement('li');
    if (d.etkin) li.className = 'etkin';
    const i = document.createElement('span');
    i.className = 'cihaz-simge';
    i.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + cihazSimgesi(d.tur) + '</svg>';
    const ad = document.createElement('span');
    ad.className = 'cihaz-ad';
    const a1 = document.createElement('b');
    a1.textContent = d.tur || 'Bilinmeyen cihaz';
    const a2 = document.createElement('span');
    a2.textContent = d.ip;
    ad.append(a1, a2);
    const du = document.createElement('span');
    du.className = 'cihaz-durum';
    du.textContent = d.durum || '';
    li.append(i, ad, du);
    li.title = d.baglanti + ' bağlantı';
    return li;
  }));
}

// --- Güncelleme ---
$('guncelle').addEventListener('click', () => gonder({ tip: 'komut', ad: 'guncelle' }));
function guncellemeUygula(m) {
  const g = $('guncelleme');
  g.hidden = !m.surum;
  g.dataset.durum = m.durum || 'hazir';
  $('guncelleme-metin').textContent = m.durum === 'hata' ? (m.metin || 'Güncelleme kurulamadı')
    : m.durum === 'indiriliyor' ? 'Sürüm ' + m.surum + ' indiriliyor…' : 'Sürüm ' + m.surum + ' hazır';
  $('guncelle').hidden = m.durum === 'indiriliyor';
  $('guncelle').textContent = m.durum === 'hata' ? 'Yeniden dene' : 'Güncelle';
}

// --- Bildirim ---
let bildirimZaman = 0;
function bildirimGoster(metin) {
  const b = $('bildirim');
  b.textContent = metin;
  b.classList.toggle('goster', !!metin);
  clearTimeout(bildirimZaman);
  if (metin) bildirimZaman = setTimeout(() => b.classList.remove('goster'), 4500);
}

// --- Panel boyutu: içerik değiştikçe programa bildir ---
let sonYukseklik = 0;
new ResizeObserver(() => {
  const h = Math.ceil($('app').getBoundingClientRect().height);
  if (h !== sonYukseklik) { sonYukseklik = h; gonder({ tip: 'boyut', yukseklik: h }); }
}).observe($('app'));

if (wv) wv.addEventListener('message', (e) => {
  const m = e.data || {};
  if (m.tip === 'durum') durumUygula(m);
  else if (m.tip === 'strateji') stratejiUygula(m);
  else if (m.tip === 'analiz') analizUygula(m);
  else if (m.tip === 'discord') { $('discord-yenile').hidden = !m.yenidenBaslat; $('discord-yenile').disabled = false; }
  else if (m.tip === 'paylasim') paylasimUygula(m);
  else if (m.tip === 'guncelleme') guncellemeUygula(m);
  else if (m.tip === 'surum') $('surum').textContent = 'Sürüm ' + m.surum;
  else if (m.tip === 'bildirim') bildirimGoster(m.metin || '');
});

// Panel açılınca WebKit ilk odaklanabilir öğeye (strateji seçici) odak verip çerçeve çiziyordu; fareyle açılışta odak olmasın.
const odagiBirak = () => { if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur(); };
window.addEventListener('focus', () => setTimeout(odagiBirak, 0));

gonder({ tip: 'hazir' });
