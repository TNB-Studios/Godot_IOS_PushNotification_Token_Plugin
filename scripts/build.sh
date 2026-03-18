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
IOS_SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
IOS_SDK_BUILD=$(xcrun --sdk iphoneos --show-sdk-build-version)
SIM_SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
SIM_SDK_BUILD=$(xcrun --sdk iphonesimulator --show-sdk-build-version)
XCODE_VERSION=$(/usr/bin/xcodebuild -version | head -1 | awk '{print $2}')
XCODE_BUILD=$(/usr/bin/xcodebuild -version | tail -1 | awk '{print $3}')

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
    local PLATFORM_NAME=$3       # iphoneos or iphonesimulator
    local SUPPORTED_PLATFORM=$4  # iPhoneOS or iPhoneSimulator
    local PLAT_SDK_VERSION=$5
    local PLAT_SDK_BUILD=$6
    local FW_DIR="$DEST_DIR/$FRAMEWORK_NAME.framework"

    mkdir -p "$FW_DIR"
    cp "$LIB_PATH" "$FW_DIR/$FRAMEWORK_NAME"
    install_name_tool -id "@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$FW_DIR/$FRAMEWORK_NAME" 2>/dev/null || true

    cat > "$FW_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.pushnotificationtoken.plugin</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$SUPPORTED_PLATFORM</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
    <key>DTPlatformName</key>
    <string>$PLATFORM_NAME</string>
    <key>DTPlatformVersion</key>
    <string>$PLAT_SDK_VERSION</string>
    <key>DTSDKName</key>
    <string>${PLATFORM_NAME}${PLAT_SDK_VERSION}</string>
    <key>DTSDKBuild</key>
    <string>$PLAT_SDK_BUILD</string>
    <key>DTXcode</key>
    <string>$XCODE_VERSION</string>
    <key>DTXcodeBuild</key>
    <string>$XCODE_BUILD</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
</dict>
</plist>
PLIST

    # Convert plist to binary (required by iOS)
    plutil -convert binary1 "$FW_DIR/Info.plist"
}

STAGING="$BUILD_DIR/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/device" "$STAGING/simulator"

create_framework "$DEVICE_LIB" "$STAGING/device" "iphoneos" "iPhoneOS" "$IOS_SDK_VERSION" "$IOS_SDK_BUILD"
create_framework "$SIM_LIB" "$STAGING/simulator" "iphonesimulator" "iPhoneSimulator" "$SIM_SDK_VERSION" "$SIM_SDK_BUILD"

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
