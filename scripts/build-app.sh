#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/macfaceguard-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/macfaceguard-swift-cache"
scratch="${TMPDIR:-/tmp}/macfaceguard-build-release"
swift build --scratch-path "$scratch" -c release
bin_dir="$(swift build --scratch-path "$scratch" -c release --show-bin-path)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/macfaceguard-package.XXXXXX")"
app="$staging/MacFaceGuard.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -X "$bin_dir/MacFaceGuard" "$app/Contents/MacOS/MacFaceGuard"
cp -X scripts/Info.plist "$app/Contents/Info.plist"
if [[ -f docs/images/AppIcon.icns ]]; then cp -X docs/images/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --identifier com.macfaceguard.local "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
# Pastas sincronizadas acrescentam FinderInfo ao .app; o ZIP preserva o pacote assinado.
ditto -c -k --norsrc --keepParent "$app" dist/MacFaceGuard.zip
printf 'App local compilado: %s\nPacote: %s/dist/MacFaceGuard.zip\n' "$app" "$PWD"
