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
'use strict';

const wv = window.chrome && window.chrome.webview;
const $ = (id) => document.getElementById(id);

function gonder(m) { if (wv) wv.postMessage(m); }

// --- Sekmeler ---
function gorunumAc(ad) {
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

if (wv) {
  wv.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.tip === 'durum') durumUygula(m);
    else if (m.tip === 'bilgi') $('bilgi').textContent = m.metin || '';
    else if (m.tip === 'tema') temaUygula(m.tema);
    else if (m.tip === 'strateji') stratejiUygula(m);
  });
}
gonder({ tip: 'hazir' });
