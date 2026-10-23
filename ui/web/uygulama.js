// RedRiveRR Zapret — yeni arayüz betiği.
//
// Program -> sayfa (window.chrome.webview 'message'):
//   {tip:"durum", durum:"aktif|hazir|bekliyor|uyari|hata", rozet, baslik, aciklama,
//    calisiyor:bool, dugme:bool, strateji, stratejiDetay, onarim}
//   {tip:"bilgi", metin}
//   {tip:"tema", tema:"acik|koyu"}
//   {tip:"strateji", secenekler[], secili, motorlar[], motor, filtreler[], filtre,
//    secimAcik, filtreAcik, analizAcik, zaman, sonuclar[{puan, ad, durum, tam, calisti}]}
// Sayfa -> program (postMessage):
//   {tip:"hazir"}, {tip:"komut", ad:"baslat|durdur|eskiArayuz|sonuclar"}, {tip:"tema", tema}
//   {tip:"komut", ad:"analiz", tur:"hizli|tam"}, {tip:"secim", alan:"strateji|motor|filtre", deger}
//   {tip:"servis", durum:"aktif|hata|uyari|yok", baslik, aciklama, kurulu, onarim, yenidenBaslat, onarimNot,
//    kurAcik, kaldirAcik, ayarAcik}   (program -> sayfa)
//   {tip:"dns", durum, baslik, aciklama, mod:"saglayici|cloudflare|sifreli|diger|", sunucular, degistirAcik}
//   {tip:"dnsYenile"} (DNS sekmesi açılınca), {tip:"komut", ad:"dns", mod}
//   {tip:"bildirim", metin}   (program -> sayfa, birkaç saniye görünür)
//   {tip:"komut", ad:"servisKur|servisKaldir|servisAyarlar"}, {tip:"ayar", ad:"onarim|yenidenBaslat", deger:bool}
'use strict';

const wv = window.chrome && window.chrome.webview;
const $ = (id) => document.getElementById(id);

function gonder(m) { if (wv) wv.postMessage(m); }

// --- Sekmeler ---
function gorunumAc(ad) {
  if (ad === 'dns') gonder({ tip: 'dnsYenile' });
  document.querySelectorAll('.gorunum').forEach((g) => g.classList.toggle('acik', g.id === 'g-' + ad));
  document.querySelectorAll('nav a').forEach((a) => {
    const secili = a.dataset.gorunum === ad;
    a.classList.toggle('secili', secili);
    if (secili) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  });
}
document.querySelectorAll('nav a').forEach((a) => a.addEventListener('click', (e) => {
  e.preventDefault();
  gorunumAc(a.dataset.gorunum);
}));
$('strateji-kart').addEventListener('click', (e) => { e.preventDefault(); gorunumAc('strateji'); });

// Taşınmamış bölümler: eski arayüze geçiş
document.querySelectorAll('[data-komut]').forEach((b) => b.addEventListener('click', () => gonder({ tip: 'komut', ad: b.dataset.komut })));

// --- Tema ---
function temaUygula(t) { document.documentElement.dataset.tema = t === 'koyu' ? 'koyu' : 'acik'; }
$('tema').addEventListener('click', () => {
  const yeni = document.documentElement.dataset.tema === 'koyu' ? 'acik' : 'koyu';
  temaUygula(yeni);
  gonder({ tip: 'tema', tema: yeni });
});

// --- Bağlantı ---
let calisiyor = false;
$('guc').addEventListener('click', () => {
  $('guc').disabled = true; // yanıt gelene kadar çift tıklamayı engelle
  gonder({ tip: 'komut', ad: calisiyor ? 'durdur' : 'baslat' });
});

function durumUygula(m) {
  $('kahraman').dataset.durum = m.durum || 'bekliyor';
  $('rozet').textContent = m.rozet || '';
  $('baslik').textContent = m.baslik || '';
  $('aciklama').textContent = m.aciklama || '';
  calisiyor = !!m.calisiyor;
  const guc = $('guc');
  guc.disabled = !m.dugme;
  guc.setAttribute('aria-label', calisiyor ? 'Durdur' : 'Başlat');
  $('strateji-ad').textContent = m.strateji || '—';
  $('strateji-detay').textContent = m.stratejiDetay || '';
  $('onarim').textContent = m.onarim || 'Servis kurulunca etkinleşir';
}

// --- Strateji ---
let analizTuru = 'hizli';
let klasikMotor = false;
function analizDugmesi() {
  $('analiz-baslat').textContent = klasikMotor ? 'Analizi başlat' : (analizTuru === 'tam' ? 'Tam analizi başlat' : 'Hızlı testi başlat');
}
document.querySelectorAll('#analiz-turu .secim').forEach((b) => b.addEventListener('click', () => {
  analizTuru = b.dataset.tur;
  document.querySelectorAll('#analiz-turu .secim').forEach((x) => x.setAttribute('aria-checked', String(x === b)));
  analizDugmesi();
}));
$('analiz-baslat').addEventListener('click', () => {
  $('analiz-baslat').disabled = true;
  gonder({ tip: 'komut', ad: 'analiz', tur: analizTuru });
});
$('tum-sonuclar').addEventListener('click', () => gonder({ tip: 'komut', ad: 'sonuclar' }));
document.querySelectorAll('select[data-alan]').forEach((s) => s.addEventListener('change', () => {
  s.disabled = true; // program yeni durumu gönderince açılır
  gonder({ tip: 'secim', alan: s.dataset.alan, deger: s.value });
}));

function seceneklerYaz(sel, liste, secili, acik) {
  const eski = Array.from(sel.options).map((o) => o.value).join('|');
  if (eski !== (liste || []).join('|')) {
    sel.replaceChildren(...(liste || []).map((ad) => new Option(ad, ad)));
  }
  if (secili && !(liste || []).includes(secili)) sel.append(new Option(secili, secili));
  sel.value = secili || '';
  sel.disabled = !acik;
}

function stratejiUygula(m) {
  seceneklerYaz($('sec-strateji'), m.secenekler, m.secili, m.secimAcik);
  seceneklerYaz($('sec-motor'), m.motorlar, m.motor, m.secimAcik);
  seceneklerYaz($('sec-filtre'), m.filtreler, m.filtre, m.filtreAcik);
  $('filtre-not').textContent = m.secimAcik && !m.filtreAcik && (m.filtre || '').includes('Uygulanamaz') ? 'Bu strateji tüm trafiğe uygulanır' : '';
  klasikMotor = !(m.motor || '').includes('Zapret2');
  document.querySelectorAll('#analiz-turu .secim').forEach((b) => { b.disabled = klasikMotor; });
  $('analiz-turu').hidden = klasikMotor;
  analizDugmesi();
  $('analiz-baslat').disabled = !m.analizAcik;
  const sonuclar = m.sonuclar || [];
  $('sonuclar').hidden = sonuclar.length === 0;
  $('sonuc-zaman').textContent = m.zaman ? 'Son analiz, ' + m.zaman : 'Son analiz';
  $('sonuc-liste').replaceChildren(...sonuclar.map((r) => {
    const satir = document.createElement('div');
    satir.className = 'sonuc' + (r.calisti ? '' : ' calismadi');
    satir.title = r.tam || '';
    const puan = document.createElement('span');
    puan.className = 'puan';
    puan.textContent = r.puan;
    const ad = document.createElement('span');
    ad.className = 'ad';
    const a1 = document.createElement('span');
    a1.textContent = r.ad;
    const a2 = document.createElement('span');
    a2.className = 'kucuk';
    a2.textContent = r.durum;
    ad.append(a1, a2);
    satir.append(puan, ad);
    return satir;
  }));
}

// --- Servis ---
document.querySelectorAll('.anahtar[data-ayar]').forEach((b) => b.addEventListener('click', () => {
  const yeni = b.getAttribute('aria-checked') !== 'true';
  b.setAttribute('aria-checked', String(yeni));
  b.disabled = true; // program uygulayıp yeni durumu gönderince açılır
  gonder({ tip: 'ayar', ad: b.dataset.ayar, deger: yeni });
}));
$('servis-kur').addEventListener('click', () => { $('servis-kur').disabled = true; gonder({ tip: 'komut', ad: 'servisKur' }); });
$('servis-ayar').addEventListener('click', () => gonder({ tip: 'komut', ad: 'servisAyarlar' }));
// Kaldırma iki adımlı: ilk tıklama onay ister, 4 sn içinde ikinci tıklama kaldırır.
let kaldirZaman = 0;
$('servis-kaldir').addEventListener('click', () => {
  const b = $('servis-kaldir');
  if (!b.classList.contains('onay')) {
    b.classList.add('onay');
    b.textContent = 'Kaldırmak için tekrar bas';
    clearTimeout(kaldirZaman);
    kaldirZaman = setTimeout(kaldirSifirla, 4000);
    return;
  }
  kaldirSifirla();
  b.disabled = true;
  gonder({ tip: 'komut', ad: 'servisKaldir' });
});
function kaldirSifirla() {
  clearTimeout(kaldirZaman);
  $('servis-kaldir').classList.remove('onay');
  $('servis-kaldir').textContent = 'Servisi kaldır';
}

function servisUygula(m) {
  $('servis-durum').dataset.durum = m.durum || 'yok';
  $('servis-baslik').textContent = m.baslik || '';
  $('servis-aciklama').textContent = m.aciklama || '';
  document.querySelectorAll('.anahtar[data-ayar]').forEach((b) => {
    b.setAttribute('aria-checked', String(!!m[b.dataset.ayar]));
    b.disabled = false;
  });
  $('onarim-not').textContent = m.onarimNot || '';
  $('servis-kur').hidden = !!m.kurulu;
  $('servis-kur').disabled = !m.kurAcik;
  $('servis-kaldir').hidden = !m.kurulu;
  $('kaldir-not').hidden = !m.kurulu;
  $('servis-kaldir').disabled = !m.kaldirAcik;
  $('servis-ayar').disabled = !m.ayarAcik;
}

// --- DNS ---
let dnsMod = '';
function dnsSecili() {
  const r = document.querySelector('input[name=dns]:checked');
  return r ? r.value : '';
}
function dnsDugmesi() {
  const sec = dnsSecili();
  const ad = { saglayici: "sağlayıcının DNS'ine", cloudflare: "Cloudflare'e", sifreli: "şifreli DNS'e" }[sec];
  const degisti = sec !== '' && sec !== dnsMod;
  $('dns-uygula').textContent = degisti ? ad.charAt(0).toUpperCase() + ad.slice(1) + ' geç' : 'Değişiklik yok';
  $('dns-uygula').disabled = !degisti || $('dns-secim').disabled;
}
document.querySelectorAll('input[name=dns]').forEach((r) => r.addEventListener('change', dnsDugmesi));
$('dns-uygula').addEventListener('click', () => {
  $('dns-uygula').disabled = true;
  $('dns-secim').disabled = true;
  gonder({ tip: 'komut', ad: 'dns', mod: dnsSecili() });
});

function dnsUygula(m) {
  $('dns-durum').dataset.durum = m.durum || 'bekliyor';
  $('dns-baslik').textContent = m.baslik || '';
  $('dns-aciklama').textContent = m.aciklama || '';
  $('dns-sunucu').textContent = m.sunucular ? 'Şu an: ' + m.sunucular : (m.mod === 'saglayici' ? 'Şu an: otomatik' : '');
  const modDegisti = dnsMod !== (m.mod || '');
  dnsMod = m.mod || '';
  $('dns-secim').disabled = !m.degistirAcik;
  // Şifreli DNS açıkken doğrudan Cloudflare'e geçilmez: önce kaldırılır (sağlayıcı DNS'ine döner).
  const cf = document.querySelector('input[name=dns][value=cloudflare]');
  cf.disabled = dnsMod === 'sifreli';
  document.querySelector('[data-not=cloudflare]').textContent = dnsMod === 'sifreli'
    ? "Önce şifreli DNS'i kaldır; DNS sağlayıcınınkine döner, sonra buradan seçebilirsin." : 'Çoğu bağlantıda yeterli.';
  if (modDegisti || !dnsSecili()) {
    document.querySelectorAll('input[name=dns]').forEach((r) => { r.checked = r.value === dnsMod; });
  }
  dnsDugmesi();
}

// --- Bildirim ---
let bildirimZaman = 0;
function bildirimGoster(metin) {
  const b = $('bildirim');
  b.textContent = metin || '';
  b.classList.add('gorunur');
  clearTimeout(bildirimZaman);
  bildirimZaman = setTimeout(() => b.classList.remove('gorunur'), 5000);
}

if (wv) {
  wv.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.tip === 'durum') durumUygula(m);
    else if (m.tip === 'bilgi') $('bilgi').textContent = m.metin || '';
    else if (m.tip === 'tema') temaUygula(m.tema);
    else if (m.tip === 'strateji') stratejiUygula(m);
    else if (m.tip === 'servis') servisUygula(m);
    else if (m.tip === 'bildirim') bildirimGoster(m.metin);
    else if (m.tip === 'dns') dnsUygula(m);
  });
}
gonder({ tip: 'hazir' });
