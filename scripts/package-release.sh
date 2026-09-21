#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep release builds separate from the local app that may currently be running.
RELEASE_DIR="$PWD/dist/release"
mkdir -p "$RELEASE_DIR"
for BUILD_ARCH in arm64 x86_64; do
    CA_BUILD_ARCH="$BUILD_ARCH" CA_OUTPUT_DIR="$RELEASE_DIR/$BUILD_ARCH" ./scripts/build-app.sh
    APP="$RELEASE_DIR/$BUILD_ARCH/CA Plate Watch.app"
    VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
    if [ -n "${CA_RELEASE_TAG:-}" ] && [ "$CA_RELEASE_TAG" != "v$VERSION" ]; then
        echo "Release tag $CA_RELEASE_TAG does not match app version v$VERSION" >&2
        exit 1
    fi
    lipo "$APP/Contents/MacOS/CAPlateWatch" -verify_arch "$BUILD_ARCH"
    ARCHIVE="$RELEASE_DIR/CA-Plate-Watch-$VERSION-$BUILD_ARCH.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
    # Verify that signing survives the actual downloadable ZIP round trip.
    VERIFY_DIR=$(mktemp -d)
    trap 'rm -rf "$VERIFY_DIR"' EXIT
    ditto -x -k "$ARCHIVE" "$VERIFY_DIR"
    codesign --verify --strict "$VERIFY_DIR/CA Plate Watch.app"
    rm -rf "$VERIFY_DIR"
    trap - EXIT
done
(
    cd "$RELEASE_DIR"
    shasum -a 256 "CA-Plate-Watch-$VERSION-arm64.zip" "CA-Plate-Watch-$VERSION-x86_64.zip" > SHA256SUMS.txt
)
printf 'Release downloads: %s\n' "$RELEASE_DIR"
