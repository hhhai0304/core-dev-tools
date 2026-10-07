#!/bin/zsh
# Builds a local-only native macOS app without an Xcode project or developer account.
set -euo pipefail
cd "${0:a:h}"

APP="Core Dev Tools.app"
EXECUTABLE="CoreDevTools"
ICON="CoreDevTools.icns"
ARCH="$(uname -m)"
SOURCES=(Sources/*.swift(N))

if (( ${#SOURCES[@]} == 0 )); then
  echo "error: no Swift source files found" >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  echo "▸ rendering icon"
  rm -rf build/AppIcon.iconset
  mkdir -p build
  swift tools/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o "$ICON"
fi

echo "▸ compiling ($ARCH, macOS 13+)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target "$ARCH-apple-macos13.0" \
  "${SOURCES[@]}" \
  -o "$APP/Contents/MacOS/$EXECUTABLE" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreImage

cp "$ICON" "$APP/Contents/Resources/$ICON"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Core Dev Tools</string>
  <key>CFBundleDisplayName</key><string>Core Dev Tools</string>
  <key>CFBundleExecutable</key><string>CoreDevTools</string>
  <key>CFBundleIdentifier</key><string>com.local.coredevtools</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>CoreDevTools</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local developer utility</string>
</dict>
</plist>
PLIST

echo "▸ applying ad-hoc signature"
codesign --force --sign - "$APP" 2>/dev/null

SIZE=$(du -sh "$APP" | cut -f1)
echo "✓ built $APP ($SIZE)"
echo "  open: open '$APP'"
