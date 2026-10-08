#!/usr/bin/env bash
set -e

# Build the project
echo "==> Building ScreenSense binary..."
swift build -c release

APP_NAME="ScreenSense.app"
APP_DIR="./build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Packaging $APP_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp .build/release/ScreenSense "$MACOS_DIR/ScreenSense"

# Copy Info.plist
cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"

# Code sign for local macOS execution & stable permission handling
echo "==> Code signing $APP_NAME with stable designated requirement..."
# Detect if a valid development signing identity exists, else use ad-hoc with explicit stable designated requirement
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Mac Developer' | head -n 1 | awk -F '"' '{print $2}' || true)

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "    Using keychain signing identity: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" --identifier "com.screensense.app" "$MACOS_DIR/ScreenSense"
    codesign --force --sign "$SIGNING_IDENTITY" --identifier "com.screensense.app" "$APP_DIR"
else
    echo "    Using ad-hoc signing with stable designated requirement (identifier \"com.screensense.app\")..."
    codesign --force --sign - --identifier "com.screensense.app" -r='designated => identifier "com.screensense.app"' "$MACOS_DIR/ScreenSense"
    codesign --force --sign - --identifier "com.screensense.app" -r='designated => identifier "com.screensense.app"' "$APP_DIR"
fi

echo "==> Built successfully at: $(pwd)/build/ScreenSense.app"
echo "To launch, run:"
echo "    open build/ScreenSense.app"
