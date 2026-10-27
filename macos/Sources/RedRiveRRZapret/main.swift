// RedRiveRR Zapret (macOS) giriş noktası.
import AppKit

// Yardımcı bağlantıyı reddedip kapatırsa write SIGPIPE ile uygulamayı öldürmesin (gözden geçirme #4)
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
