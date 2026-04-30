#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="YIYI"
BUNDLE_ID="${BUNDLE_ID:-com.local.yiyi}"
VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
DMG_STAGING_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

if [[ ! -f "$ROOT_DIR/logo.png" ]]; then
  echo "Missing logo.png at project root" >&2
  exit 1
fi

swift build --configuration release --product "$APP_NAME"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>YIYI</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>YIYI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1 && [[ "${SKIP_CODE_SIGN:-0}" != "1" ]]; then
  code_sign_args=(--force --deep --sign "$CODE_SIGN_IDENTITY")
  if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    code_sign_args+=(--timestamp=none)
  else
    code_sign_args+=(--options runtime --timestamp)
  fi

  codesign "${code_sign_args[@]}" "$APP_DIR" >/dev/null
fi

echo "Packaged $APP_DIR"

if command -v hdiutil >/dev/null 2>&1 && [[ "${SKIP_DMG:-0}" != "1" ]]; then
  rm -rf "$DMG_STAGING_DIR" "$DMG_PATH"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
  echo "Packaged $DMG_PATH"
fi
