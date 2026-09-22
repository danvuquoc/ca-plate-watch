#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_ARCH="${CA_BUILD_ARCH:-$(uname -m)}"
case "$BUILD_ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $BUILD_ARCH" >&2; exit 1 ;; esac
swift build -c release --arch "$BUILD_ARCH" --product CAPlateWatch
APP="${CA_OUTPUT_DIR:-$PWD/dist}/CA Plate Watch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Remove generated executables from earlier builds before packaging this version.
find "$APP/Contents/MacOS" -maxdepth 1 -type f -delete
cp "$(swift build -c release --arch "$BUILD_ARCH" --show-bin-path)/CAPlateWatch" "$APP/Contents/MacOS/CAPlateWatch"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CAPlateWatch</string>
<key>CFBundleIdentifier</key><string>local.CAPlateWatch</string>
<key>CFBundleName</key><string>CA Plate Watch</string>
<key>CFBundleDisplayName</key><string>CA Plate Watch</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc Sources/CAPlateWatch/PlateArtwork.swift scripts/render-icon.swift -o .build/render-icon
.build/render-icon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
