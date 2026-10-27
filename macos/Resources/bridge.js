// RedRiveRR Zapret (macOS): Windows WebView2 köprüsünün taklidi. ui/web/uygulama.js değişmeden çalışsın diye
// window.chrome.webview sağlanır: sayfa -> program postMessage (webkit.messageHandlers.zwt),
// program -> sayfa window.__zwtGelen(jsonMetni) ile 'message' olayı (e.data = nesne).
(function () {
  'use strict';
  const dinleyiciler = [];
  window.chrome = window.chrome || {};
  window.chrome.webview = {
    postMessage(m) {
      window.webkit.messageHandlers.zwt.postMessage(typeof m === 'string' ? m : JSON.stringify(m));
    },
    addEventListener(tur, f) { if (tur === 'message') dinleyiciler.push(f); },
    removeEventListener(tur, f) {
      const i = dinleyiciler.indexOf(f);
      if (tur === 'message' && i >= 0) dinleyiciler.splice(i, 1);
    },
  };
  window.__zwtGelen = function (metin) {
    let veri;
    try { veri = JSON.parse(metin); } catch (e) { return; }
    for (const f of dinleyiciler.slice()) { try { f({ data: veri }); } catch (e) { console.error(e); } }
  };
})();
