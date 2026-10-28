import Foundation

/// Ana durum (Windows: lib/AppState.au3 metinleri).
public enum AppStatus: String {
    case ready = "ÇALIŞMAYA HAZIR"
    case manual = "MANUEL MOD AKTİF"
    case starting = "BAŞLATILIYOR..."
    case error = "HATA"
}

/// Arayüze giden mesajlar (Windows: lib/WebState.au3; alan adları ui/web/uygulama.js sözleşmesi).
public enum WebState {
    /// Durum kartı metinleri: durum, rozet, başlık, açıklama (Windows _WebStatusParts ile aynı).
    static func parts(_ status: AppStatus, error: String?) -> (String, String, String, String) {
        switch status {
        case .manual:
            return ("aktif", "Zapret çalışıyor", "Discord'a yol açık", "Discord'u şimdi açın; zaten açıksa yeniden başlatın.")
        case .ready:
            return ("hazir", "Çalışmaya hazır", "Zapret kapalı", "Başlatmak için düğmeye basın.")
        case .starting:
            return ("bekliyor", "Lütfen bekleyin", "Başlatılıyor", "")
        case .error:
            return ("hata", "Başlatılamadı", "Zapret kapalı", error ?? "")
        }
    }

    public static func statusJson(status: AppStatus, running: Bool, buttonEnabled: Bool,
                                  strategy: String, detail: String, error: String?) -> String {
        let p = parts(status, error: error)
        return Json.object(["tip": "durum", "durum": p.0, "rozet": p.1, "baslik": p.2, "aciklama": p.3,
                            "calisiyor": running, "dugme": buttonEnabled, "strateji": strategy,
                            "stratejiDetay": detail, "onarim": ""])
    }

    public static func strategyJson(options: [String], selected: String) -> String {
        return Json.object(["tip": "strateji", "secenekler": Json.Raw(list(options)), "secili": selected,
                            "motorlar": Json.Raw(list(["tpws (macOS)"])), "motor": "tpws (macOS)",
                            "filtreler": Json.Raw("[]"), "filtre": "", "secimAcik": true, "filtreAcik": false,
                            "analizAcik": false, "zaman": "", "sonuclar": Json.Raw("[]")])
    }

    static func list(_ items: [String]) -> String {
        "[" + items.map(Json.quote).joined(separator: ",") + "]"
    }
}
