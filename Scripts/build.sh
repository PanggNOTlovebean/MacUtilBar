#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build/candidate}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
mkdir -p "$out"
swift build -c release --arch arm64 --arch x86_64
bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
app="$out/MacUtilBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MacUtilBar" "$app/Contents/MacOS/"
swift Scripts/make-icon.swift "$out/AppIcon.iconset"
iconutil -c icns "$out/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${MACUTILBAR_SIGN_IDENTITY:--}" --options runtime "$app"
codesign --verify --deep --strict "$app"
mkdir -p "$out/payload/Applications"
ditto "$app" "$out/payload/Applications/MacUtilBar.app"
xattr -cr "$out/payload"
pkgbuild --analyze --root "$out/payload" "$out/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$out/components.plist"
pkgbuild --root "$out/payload" --component-plist "$out/components.plist" --install-location / --identifier local.macutilbar.app --version "$version" "$out/MacUtilBar-${version}.pkg"
(cd "$out" && shasum -a 256 MacUtilBar-${version}.pkg > SHA256SUMS.txt)
