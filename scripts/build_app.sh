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

# Ad-hoc code sign for local macOS execution & permission handling
echo "==> Ad-hoc code signing $APP_NAME..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Built successfully at: $(pwd)/build/ScreenSense.app"
echo "To launch, run:"
echo "    open build/ScreenSense.app"
