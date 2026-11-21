#!/bin/bash
# Builds MiniDict.app from the Swift package and installs it to /Applications.
#   ./build.sh               build + install
#   ./build.sh --no-install  build only
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="MiniDict"
BUNDLE="$APP_NAME.app"

echo "==> swift build"
swift build -c release

echo "==> icon"
rm -rf build/AppIcon.iconset
mkdir -p build
swift tools/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp build/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
cp Sources/MiniDict/Resources/ui.html "$BUNDLE/Contents/Resources/ui.html"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>com.user.minidict</string>
    <key>CFBundleVersion</key>              <string>1.8</string>
    <key>CFBundleShortVersionString</key>   <string>1.8</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>13.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key>      <string>MiniDict lookup</string>
        <key>CFBundleURLSchemes</key>   <array><string>minidict</string></array>
    </dict></array>
    <key>NSAccessibilityUsageDescription</key>
    <string>MiniDict đọc chữ bạn đang bôi đen để tra từ điển ngay.</string>
</dict>
</plist>
PLIST

# Sign with the local identity from tools/make-signing-cert.sh so the signature
# (and the Accessibility permission tied to it) stays the same across rebuilds.
SIGN_ID="${SIGN_ID:-MiniDict Local Signing}"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
    codesign --force --deep --sign "$SIGN_ID" "$BUNDLE"
else
    echo "    (no \"$SIGN_ID\" identity: ad-hoc signing; run tools/make-signing-cert.sh)"
    codesign --force --deep --sign - "$BUNDLE"
fi

if [ "${1:-}" != "--no-install" ]; then
    echo "==> install to /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$BUNDLE"
    cp -R "$BUNDLE" "/Applications/$BUNDLE"
fi

echo "Done: $BUNDLE"
