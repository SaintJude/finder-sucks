#!/bin/zsh
# Builds a universal (Apple silicon + Intel) "build/Finder Sucks.app" and a drag-to-install
# disk image "build/FinderSucks-<version>.dmg".
#
# Signing is ad-hoc by default: the app runs anywhere, but other Macs show an
# "unidentified developer" warning the first time. For a warning-free build, set:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<name saved with `xcrun notarytool store-credentials`>
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="Finder Sucks"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP="build/$NAME.app"
DMG="build/FinderSucks-$VERSION.dmg"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/FinderSucks"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FinderSucks"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>com.stevebarr.findersucks</string>
    <key>CFBundleExecutable</key><string>FinderSucks</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSDesktopFolderUsageDescription</key><string>Finder Sucks shows and manages the files on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Finder Sucks shows and manages the files in your Documents folder.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Finder Sucks shows and manages the files in your Downloads folder.</string>
    <key>NSRemovableVolumesUsageDescription</key><string>Finder Sucks shows and manages files on external drives.</string>
    <key>NSNetworkVolumesUsageDescription</key><string>Finder Sucks shows and manages files on network drives.</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/FinderSucks"))"

# Disk image: the app next to an Applications shortcut, for drag-to-install.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
fi
echo "Built $DMG"
