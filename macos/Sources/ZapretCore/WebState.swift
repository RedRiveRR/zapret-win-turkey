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
    public static func statusJson(status: AppStatus, running: Bool, buttonEnabled: Bool,
                                  strategy: String, detail: String, error: String?) -> String {
        return ""
    }

    public static func strategyJson(options: [String], selected: String) -> String {
        return ""
    }
}
