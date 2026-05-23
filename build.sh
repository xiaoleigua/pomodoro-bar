#!/bin/bash
set -e

APP_NAME="PomodoroBar"
SWIFT_FILE="PomodoroBar.swift"
BUILD_DIR="./build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

echo "=== 编译 PomodoroBar ==="

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"

# Compile Swift source
echo "→ 编译 Swift 源码..."
swiftc "$SWIFT_FILE" \
    -o "$MACOS_DIR/$APP_NAME" \
    -framework AppKit \
    -framework UserNotifications \
    -O

# Create Info.plist
echo "→ 创建 Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PomodoroBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.pomodoro.bar</string>
    <key>CFBundleName</key>
    <string>PomodoroBar</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign to reduce Gatekeeper friction
echo "→ 签名..."
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✓ 编译完成: $APP_BUNDLE"
echo ""
echo "运行方式:"
echo "  open $APP_BUNDLE"
echo "  或双击 Finder 中的 PomodoroBar.app"
