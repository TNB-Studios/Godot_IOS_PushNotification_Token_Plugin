# Godot 4.5 iOS Push Notification Token Plugin

A GDExtension plugin for Godot 4.4+ that requests iOS push notification permission, registers for remote notifications, and exposes the APNs device token to GDScript/C# via signals.

This plugin handles the complexity of hooking into the iOS AppDelegate (which Godot owns) using method swizzling, so you don't have to modify any Godot engine code.

## Quick Start (Prebuilt)

If you just want to use the plugin without building it yourself:

1. Download `PushNotificationToken.zip` from the [Releases](../../releases) page
2. Extract the `addons/PushNotificationToken/` folder into your Godot project's `addons/` directory
3. Make sure your iOS export has the **Push Notifications** capability enabled in your provisioning profile

## Usage in GDScript

```gdscript
extends Node

@onready var push_token: PushNotificationToken = $PushNotificationToken

func _ready() -> void:
    push_token.token_received.connect(_on_token_received)
    push_token.token_failed.connect(_on_token_failed)
    push_token.permission_result.connect(_on_permission_result)

    # First launch: shows the iOS permission dialog
    push_token.request_permission()

    # Subsequent launches: re-register silently (no prompt)
    # push_token.register_for_remote_notifications()

func _on_permission_result(granted: bool) -> void:
    if granted:
        print("Permission granted - waiting for token...")
    else:
        print("Permission denied.")

func _on_token_received(token: String) -> void:
    print("APNs device token: ", token)
    # Send this token to your push notification server

func _on_token_failed(error: String) -> void:
    printerr("Push registration failed: ", error)
```

Add a `PushNotificationToken` node as a child in your scene, or create one in code.

## API Reference

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `request_permission()` | `void` | Shows the iOS notification permission dialog. If granted, automatically registers for remote notifications. |
| `register_for_remote_notifications()` | `void` | Re-registers for remote notifications without showing the permission dialog. Use on subsequent app launches after permission has already been granted. |
| `get_device_token()` | `String` | Returns the last known APNs device token as a hex string, or `""` if not yet available. |

### Signals

| Signal | Parameters | Description |
|--------|-----------|-------------|
| `permission_result` | `granted: bool` | Emitted after the user responds to the notification permission prompt. |
| `token_received` | `token: String` | Emitted when the APNs device token is successfully received. The token is a hex-encoded string. |
| `token_failed` | `error: String` | Emitted when registration for remote notifications fails. |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `device_token` | `String` | The most recently received APNs device token (hex-encoded). Empty until `token_received` fires. |

## Building from Source

### Prerequisites

- macOS
- Xcode 16+ (with iOS 17+ SDK)
- Swift 6.0+ (ships with Xcode 16)
- Command Line Tools installed (`xcode-select --install`)

### Build

```bash
git clone https://github.com/YOUR_USERNAME/Godot4.5_IOS_Push_Notifications_Token_Plugin.git
cd Godot4.5_IOS_Push_Notifications_Token_Plugin
./scripts/build.sh
```

The build script will:

1. Clone [SwiftGodot](https://github.com/migueldeicaza/SwiftGodot) v0.75.0 into `vendor/` and patch it for CLI builds (removes `unsafeFlags` that block Swift Package Manager on the command line)
2. Build for iOS device (arm64) and iOS Simulator (arm64) using `swift build`
3. Package both slices into an XCFramework at `addons/PushNotificationToken/bin/PushNotificationToken.xcframework`

Build time is roughly 8-10 minutes on the first run (SwiftGodot code generation + compilation). Subsequent builds are incremental and much faster.

### Build Output

After a successful build, the addon is ready at:

```
addons/PushNotificationToken/
  push_notification_token.gdextension
  doc_classes/
    PushNotificationToken.xml
  bin/
    PushNotificationToken.xcframework/
      ios-arm64/                    # Physical device
      ios-arm64-simulator/          # Simulator
```

Copy the entire `addons/PushNotificationToken/` folder into your Godot project.

## Project Structure

```
.
├── Package.swift                              # Swift Package Manager config
├── Sources/PushNotificationToken/
│   ├── Entry.swift                            # GDExtension entry point
│   └── PushNotificationToken.swift            # Plugin implementation
├── addons/PushNotificationToken/
│   ├── push_notification_token.gdextension    # Godot extension config
│   └── doc_classes/
│       └── PushNotificationToken.xml          # In-editor API docs
├── scripts/
│   └── build.sh                               # Build script
└── example/
    └── PushNotificationExample.gd             # Usage example
```

## How It Works

iOS delivers the APNs device token through `UIApplicationDelegate` callbacks:
- `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
- `application(_:didFailToRegisterForRemoteNotificationsWithError:)`

In a Godot app, the AppDelegate is owned by the engine. This plugin uses **Objective-C runtime method swizzling** to inject implementations for these callbacks onto Godot's AppDelegate at runtime. When the token arrives, it's converted to a hex string and emitted as a Godot signal.

The swizzling happens once, when the `PushNotificationToken` node enters the scene tree (`_ready`).

## iOS Configuration

For push notifications to work on a real device, your Xcode export must have:

1. **Push Notifications** capability enabled
2. An **Apple Developer account** with push notification entitlements configured for your App ID
3. A **provisioning profile** that includes the push notification entitlement

Push notifications do **not** work in the iOS Simulator - the simulator slice is included for development/testing of the permission flow only.

## Compatibility

- Godot 4.4+
- iOS 17.0+
- Swift 6.0+ / Xcode 16+
- Built with [SwiftGodot](https://github.com/migueldeicaza/SwiftGodot) v0.75.0

## License

MIT
