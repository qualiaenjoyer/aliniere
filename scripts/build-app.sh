#!/bin/zsh
set -euo pipefail

APP_NAME="Alinière"
PRODUCT_NAME="Aliniere"
EXECUTABLE_NAME="Aliniere"
BUNDLE_ID="com.razvan.aliniere"
VERSION="1.0.2"
BUILD="3"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/.build/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Missing app icon: $ICON_SRC" >&2
  exit 1
fi

swift build -c release --product "$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$RELEASE_DIR/$PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
