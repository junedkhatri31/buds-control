#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Buds Control.app, then a DMG, a ZIP and SHA256SUMS in ./dist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64 --product BudsControl
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="$ROOT/dist/Buds Control.app"
if [[ -d "$APP" ]]; then
    # Only replace this script's generated application bundle.
    rm -rf "$APP"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/BudsControl" "$APP/Contents/MacOS/BudsControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
swift scripts/generate-icon.swift "$APP/Contents/Resources"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ROOT/dist/BudsControl.zip" "$ROOT/dist/BudsControl.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/BudsControl.zip"
mkdir -p "$ROOT/.build"
DMG_ROOT="$(mktemp -d "$ROOT/.build/dmg-root.XXXXXX")"
trap 'rm -rf "$DMG_ROOT"' EXIT
ditto "$APP" "$DMG_ROOT/Buds Control.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp docs/INSTALL.md "$DMG_ROOT/Read Me.txt"
hdiutil create -volname "Buds Control" -srcfolder "$DMG_ROOT" -fs HFS+ \
    -format UDZO -ov "$ROOT/dist/BudsControl.dmg"
(
    cd "$ROOT/dist"
    shasum -a 256 BudsControl.dmg BudsControl.zip > SHA256SUMS.txt
)
echo "Built $APP"
echo "Installer: $ROOT/dist/BudsControl.dmg"
echo "Run: open \"$APP\""
