#!/bin/bash
# macOS paketini bir GitHub sürümüne ekler (Windows ADR-019 sözleşmesi: aynı release'te SHA256SUMS.txt).
# Varsayılan: yalnız denetler ve planı yazar. Gerçekten yüklemek için: --yayinla (kullanıcı açıkça "yayınla" demeden kullanma).
# Kullanım: macos/scripts/release-mac.sh v5.2.3 [--yayinla]
set -euo pipefail

TAG="${1:?kullanım: release-mac.sh <etiket> [--yayinla]}"
DO="${2:-}"
REPO_SLUG="RedRiveRR/zapret-win-turkey"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VERSION="$(sed -n 's/.*APP_VERSION = "\([^"]*\)".*/\1/p' "$REPO/lib/Version.au3")"
[ "v$VERSION" = "$TAG" ] || { echo "Uygulama sürümü ($VERSION) etiketle ($TAG) aynı olmalı: Mac güncelleyicisi sürümü etiketten okur."; exit 1; }
gh release view "$TAG" -R "$REPO_SLUG" >/dev/null || { echo "Sürüm yok: $TAG"; exit 1; }
[ -z "$(git -C "$REPO" status --porcelain -- macos ui veri config lib/Version.au3)" ] || { echo "Çalışma ağacında commit'lenmemiş değişiklik var."; exit 1; }

# Paket: etiket adıyla (RedRiveRR-Zapret-macOS-<etiket>.zip) — güncelleyici bu adı arar.
GITHUB_REF_TYPE=tag GITHUB_REF_NAME="$TAG" bash "$HERE/scripts/build-app.sh" "$WORK/dist"
ZIP="$WORK/dist/RedRiveRR-Zapret-macOS-$TAG.zip"
test -f "$ZIP"
SUM="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

# SHA256SUMS.txt: Windows satırları korunur, Mac satırı eklenir/yenilenir.
gh release download "$TAG" -R "$REPO_SLUG" -p SHA256SUMS.txt -D "$WORK" --clobber
grep -v "RedRiveRR-Zapret-macOS-" "$WORK/SHA256SUMS.txt" > "$WORK/SHA256SUMS.new" || true
echo "$SUM  $(basename "$ZIP")" >> "$WORK/SHA256SUMS.new"
mv "$WORK/SHA256SUMS.new" "$WORK/SHA256SUMS.txt"

echo "== Plan ($TAG)"
echo "Yüklenecek: $(basename "$ZIP") ($(du -h "$ZIP" | cut -f1)), SHA256 $SUM"
echo "Yeni SHA256SUMS.txt:"; cat "$WORK/SHA256SUMS.txt"
if [ "$DO" != "--yayinla" ]; then echo "(deneme: yüklenmedi; yüklemek için --yayinla)"; exit 0; fi

gh release upload "$TAG" -R "$REPO_SLUG" "$ZIP" "$WORK/SHA256SUMS.txt" --clobber
# Doğrulama: yüklenen dosyanın özeti yayındaki listeyle aynı mı
gh release download "$TAG" -R "$REPO_SLUG" -p "$(basename "$ZIP")" -p SHA256SUMS.txt -D "$WORK/kontrol"
(cd "$WORK/kontrol" && grep "RedRiveRR-Zapret-macOS-" SHA256SUMS.txt | shasum -a 256 -c -)
echo "Yüklendi ve doğrulandı: $TAG"
