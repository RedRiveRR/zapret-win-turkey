// swift-tools-version:5.9
// RedRiveRR Zapret — macOS sürümü (tasarım: docs/superpowers/specs/2026-10-27-macos-design.md).
// Yalnız GitHub Actions macOS sunucusunda derlenir ve test edilir (.github/workflows/macos.yml).
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
