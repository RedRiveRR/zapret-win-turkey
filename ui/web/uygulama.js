// RedRiveRR Zapret — yeni arayüz betiği.
//
// Program -> sayfa (window.chrome.webview 'message'):
//   {tip:"durum", durum:"aktif|hazir|bekliyor|uyari|hata", rozet, baslik, aciklama,
//    calisiyor:bool, dugme:bool, strateji, stratejiDetay, onarim}
//   {tip:"bilgi", metin}
//   {tip:"tema", tema:"acik|koyu"}
// Sayfa -> program (postMessage):
//   {tip:"hazir"}, {tip:"komut", ad:"baslat|durdur|eskiArayuz"}, {tip:"tema", tema}
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

if (wv) {
  wv.addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.tip === 'durum') durumUygula(m);
    else if (m.tip === 'bilgi') $('bilgi').textContent = m.metin || '';
    else if (m.tip === 'tema') temaUygula(m.tema);
  });
}
gonder({ tip: 'hazir' });
