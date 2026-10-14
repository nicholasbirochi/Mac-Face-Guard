#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
team="$(security find-certificate -c 'Apple Development' -p | openssl x509 -noout -subject | sed -nE 's/.*\/OU=([^/]+).*/\1/p')"
if [[ -z "$team" ]]; then
    printf 'É necessário configurar sua equipe Apple de desenvolvimento no Xcode.\n' >&2
    exit 1
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/macfaceguard-signed.XXXXXX")"
xcodebuild -project MacFaceGuard.xcodeproj -scheme MacFaceGuard -configuration Release \
    -derivedDataPath "$scratch" -destination 'platform=macOS,arch=arm64' \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" build
app="$scratch/Build/Products/Release/MacFaceGuard.app"
codesign --verify --deep --strict "$app"
# Não distribua uma compilação que não consiga proteger a chave com presença biométrica.
"$app/Contents/MacOS/MacFaceGuard" --self-check-keychain
mkdir -p dist
ditto -c -k --norsrc --keepParent "$app" dist/MacFaceGuard.zip
printf 'App local compilado: %s\nPacote: %s/dist/MacFaceGuard.zip\n' "$app" "$PWD"
