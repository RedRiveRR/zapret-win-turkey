// swift-tools-version:5.7
// RedRiveRR Zapret — macOS sürümü (kullanıcı rehberi: docs/macos.md).
// GitHub Actions (macos.yml) ve Monterey (Xcode 14.2, Swift 5.7) ile derlenir.
import PackageDescription

let package = Package(
    name: "RedRiveRRZapret",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ZapretCore", targets: ["ZapretCore"]),
        .executable(name: "RedRiveRRZapret", targets: ["RedRiveRRZapret"]),
        .executable(name: "zwt-helper", targets: ["zwt-helper"]),
    ],
    targets: [
        // Saf mantık (arayüzden bağımsız, birim testli)
        .target(name: "ZapretCore"),
        // Uygulama: AppKit + WKWebView, arayüz repodaki ui/web
        .executableTarget(name: "RedRiveRRZapret", dependencies: ["ZapretCore"]),
        // Yönetici yardımcısı (root LaunchDaemon; yalnız sabit komutlar)
        .executableTarget(name: "zwt-helper", dependencies: ["ZapretCore"], path: "Sources/ZwtHelper"),
        .testTarget(name: "ZapretCoreTests", dependencies: ["ZapretCore"]),
    ]
)
