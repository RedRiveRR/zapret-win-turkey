#!/bin/bash
# go-pcap2socks (DaniilSokolyuk, GPL-3.0) — ağ paylaşımı için ağ geçidi aracı. Sabit sürüm, kaynaktan, universal
# (Intel için hazır ikili yok). Modüller Go sağlama veritabanıyla doğrulanır. Çıktı yolunu yazdırır; önbellek .build/.
# Gerekli: Go (macos.yml'de actions/setup-go), Xcode araçları (cgo + libpcap).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VER="v0.2.0"
CACHE="$HERE/.build/pcap2socks"
OUTBIN="$CACHE/go-pcap2socks-$VER-universal"
if [ -x "$OUTBIN" ]; then echo "$OUTBIN"; exit 0; fi
command -v go >/dev/null || { echo "go bulunamadı (brew install go ya da actions/setup-go)" >&2; exit 1; }
mkdir -p "$CACHE"
export GOPATH="$CACHE/gopath" GOMODCACHE="$CACHE/gopath/mod" GOFLAGS=-mod=mod GOSUMDB=sum.golang.org CGO_ENABLED=1 GOOS=darwin
unset GOBIN
for ARCH in amd64 arm64; do
  CLANG_ARCH=$([ "$ARCH" = amd64 ] && echo x86_64 || echo arm64)
  GOARCH=$ARCH CC="clang -arch $CLANG_ARCH" MACOSX_DEPLOYMENT_TARGET=12.0 \
    go install -trimpath -ldflags="-s -w" "github.com/DaniilSokolyuk/go-pcap2socks@$VER" >&2
done
HOSTARCH=$(go env GOHOSTARCH)
pick() { if [ "$1" = "$HOSTARCH" ]; then echo "$GOPATH/bin/go-pcap2socks"; else echo "$GOPATH/bin/darwin_$1/go-pcap2socks"; fi; }
lipo -create "$(pick amd64)" "$(pick arm64)" -output "$OUTBIN"
chmod 755 "$OUTBIN"
echo "$OUTBIN"
