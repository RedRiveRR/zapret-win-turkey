#!/bin/bash
# RedRiveRR Zapret (macOS): universal .app paketi + ad-hoc imza + zip. Yalnız macOS'ta (CI: macos.yml).
# Kullanım: macos/scripts/build-app.sh [çıktı klasörü]   (varsayılan: macos/dist)
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"          # macos/
REPO="$(cd "$HERE/.." && pwd)"
OUT="${1:-$HERE/dist}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Üçüncü taraf: bol-van/zapret v72.13 (zip ve içindeki macOS tpws'i sabit özetle doğrulanır)
ZAPRET_URL="https://github.com/bol-van/zapret/releases/download/v72.13/zapret-v72.13.zip"
ZAPRET_SHA256="c493e33a0dc4eba23a8686efdaba55f59755ad6ade3564aebd9d13f4c65e2e0c"
TPWS_SHA256="441524a76f52597a0e5c816d25ed1adfd93e5c34cc56c56e0dc00533929d1761"

VERSION="$(sed -n 's/.*APP_VERSION = "\([^"]*\)".*/\1/p' "$REPO/lib/Version.au3")"
COMMIT="$(git -C "$REPO" rev-parse --short HEAD)"
SUFFIX="${VERSION}-${COMMIT}"
if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then SUFFIX="$GITHUB_REF_NAME"; fi
echo "sürüm $VERSION ($SUFFIX)"

# 1) Derleme (universal)
swift build --package-path "$HERE" -c release --arch arm64 --arch x86_64
BIN="$(swift build --package-path "$HERE" -c release --arch arm64 --arch x86_64 --show-bin-path)"

# 2) tpws
curl -fsSL -o "$WORK/zapret.zip" "$ZAPRET_URL"
echo "$ZAPRET_SHA256  $WORK/zapret.zip" | shasum -a 256 -c -
unzip -q -o "$WORK/zapret.zip" "zapret-v72.13/binaries/mac64/tpws" -d "$WORK"
TPWS="$WORK/zapret-v72.13/binaries/mac64/tpws"
echo "$TPWS_SHA256  $TPWS" | shasum -a 256 -c -

# 3) .app paketi
APP="$WORK/RedRiveRR Zapret.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN/RedRiveRRZapret" "$APP/Contents/MacOS/RedRiveRRZapret"
cp "$BIN/zwt-helper" "$APP/Contents/MacOS/zwt-helper"
cp "$TPWS" "$APP/Contents/Resources/bin/tpws"
chmod 755 "$APP/Contents/MacOS/"* "$APP/Contents/Resources/bin/tpws"
cp -R "$HERE/Resources/web" "$APP/Contents/Resources/web"   # Mac menü çubuğu paneli (Windows arayüzü ui/web ayrı)
cp -R "$REPO/veri" "$APP/Contents/Resources/veri"
cp "$HERE/Resources/bridge.js" "$HERE/Resources/strategies-macos.ini" "$APP/Contents/Resources/"
cp "$REPO/config/hostlist.txt" "$APP/Contents/Resources/hostlist.txt"   # atlatma yalnız bu sitelere
sed "s/__SURUM__/$VERSION/g" "$HERE/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Simge: ui/simge/kilit.ico -> AppIcon.icns
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -s format png "$REPO/ui/simge/kilit.ico" --out "$WORK/kilit.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/kilit.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2)); sips -z $d $d "$WORK/kilit.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# 4) Ad-hoc imza (Apple Silicon imzasız kodu çalıştırmaz; ücretsiz)
codesign --force -s - "$APP/Contents/Resources/bin/tpws"
codesign --force -s - "$APP/Contents/MacOS/zwt-helper"
codesign --force -s - "$APP"

# 5) Denetim (Review Focus 5): mimariler, imza, çalıştırma izni
check_app() {
  local a="$1"
  for f in "$a/Contents/MacOS/RedRiveRRZapret" "$a/Contents/MacOS/zwt-helper" "$a/Contents/Resources/bin/tpws"; do
    test -x "$f" || { echo "çalıştırılamıyor: $f"; exit 1; }
    archs="$(lipo -archs "$f")"
    [[ "$archs" == *x86_64* && "$archs" == *arm64* ]] || { echo "universal değil: $f ($archs)"; exit 1; }
  done
  codesign -v --deep "$a" || { echo "imza doğrulanamadı: $a"; exit 1; }
  test -f "$a/Contents/Resources/web/index.html" || { echo "arayüz eksik"; exit 1; }
}
check_app "$APP"

# 6) Zip (ditto: izinleri ve imzayı korur) ve açılmış kopyada aynı denetim
mkdir -p "$OUT"
ZIP="$OUT/RedRiveRR-Zapret-macOS-$SUFFIX.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
mkdir -p "$WORK/acilmis"
ditto -x -k "$ZIP" "$WORK/acilmis"
check_app "$WORK/acilmis/RedRiveRR Zapret.app"
shasum -a 256 "$ZIP"
echo "Çıktı: $ZIP"
