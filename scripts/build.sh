#!/bin/bash
set -euo pipefail

# Build PushNotificationToken as an XCFramework for iOS (device + simulator)
# Prerequisites: Xcode 16+, macOS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build-xcfw"
OUTPUT_DIR="$PROJECT_ROOT/addons/PushNotificationToken/bin"
FRAMEWORK_NAME="PushNotificationToken"

IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

cd "$PROJECT_ROOT"

# Clone SwiftGodot locally and strip unsafeFlags (required for CLI builds)
if [ ! -d "vendor/SwiftGodot" ]; then
    echo "=== Cloning SwiftGodot ==="
    mkdir -p vendor
    git clone --depth 1 --branch v0.75.0 https://github.com/migueldeicaza/SwiftGodot vendor/SwiftGodot
    # Remove unsafeFlags that block SPM CLI builds
    sed -i '' '/\.unsafeFlags(/,/)/d' vendor/SwiftGodot/Package.swift
    echo "  SwiftGodot cloned and patched"
fi

echo "=== Resolving Swift packages ==="
swift package resolve

echo "=== Building for iOS device (arm64) ==="
swift build \
    -c release \
    --sdk "$IOS_SDK" \
    --triple arm64-apple-ios17.0 \
    --scratch-path "$BUILD_DIR/device"

echo "=== Building for iOS Simulator (arm64) ==="
swift build \
    -c release \
    --sdk "$SIM_SDK" \
    --triple arm64-apple-ios17.0-simulator \
    --scratch-path "$BUILD_DIR/simulator"

echo "=== Packaging XCFramework ==="

DEVICE_LIB="$BUILD_DIR/device/release/lib${FRAMEWORK_NAME}.dylib"
SIM_LIB="$BUILD_DIR/simulator/release/lib${FRAMEWORK_NAME}.dylib"

if [ ! -f "$DEVICE_LIB" ] || [ ! -f "$SIM_LIB" ]; then
    echo "ERROR: Built libraries not found."
    [ ! -f "$DEVICE_LIB" ] && echo "  Missing: $DEVICE_LIB"
    [ ! -f "$SIM_LIB" ] && echo "  Missing: $SIM_LIB"
    exit 1
fi

# Create framework structures for each slice
create_framework() {
    local LIB_PATH=$1
    local DEST_DIR=$2
    local FW_DIR="$DEST_DIR/$FRAMEWORK_NAME.framework"

    mkdir -p "$FW_DIR/Resources/doc_classes"
    cp "$LIB_PATH" "$FW_DIR/$FRAMEWORK_NAME"
    install_name_tool -id "@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$FW_DIR/$FRAMEWORK_NAME" 2>/dev/null || true

    cat > "$FW_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.pushnotificationtoken.plugin</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
</dict>
</plist>
PLIST

    # Embed doc_classes
    local DOC_SRC="$PROJECT_ROOT/addons/PushNotificationToken/doc_classes"
    if [ -d "$DOC_SRC" ]; then
        cp "$DOC_SRC"/*.xml "$FW_DIR/Resources/doc_classes/"
    fi
}

STAGING="$BUILD_DIR/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/device" "$STAGING/simulator"

create_framework "$DEVICE_LIB" "$STAGING/device"
create_framework "$SIM_LIB" "$STAGING/simulator"

rm -rf "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
xcodebuild -create-xcframework \
    -framework "$STAGING/device/$FRAMEWORK_NAME.framework" \
    -framework "$STAGING/simulator/$FRAMEWORK_NAME.framework" \
    -output "$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"

echo ""
echo "=== Build complete ==="
echo "XCFramework: $OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
echo ""
echo "Copy addons/PushNotificationToken/ into your Godot project's addons/ directory."
