# Godot 4.5 iOS Push Notification Token Plugin

A GDExtension plugin for Godot 4.4+ that requests iOS push notification permission, registers for remote notifications, and exposes the APNs device token to GDScript/C# via signals.

This plugin handles the complexity of hooking into the iOS AppDelegate (which Godot owns) using method swizzling, so you don't have to modify any Godot engine code.

## Quick Start (Prebuilt)

If you just want to use the plugin without building it yourself:

1. Download `PushNotificationToken.zip` from the [Releases](../../releases) page
2. Extract the `addons/PushNotificationToken/` folder into your Godot project's `addons/` directory
3. Make sure your iOS export has the **Push Notifications** capability enabled in your provisioning profile

## Important: How to Instantiate

The plugin **must be added to the scene tree** for it to work. It automatically requests permission and registers for remote notifications when `_ready()` fires. You do **not** need to call `request_permission()` manually.

**Key details:**
- The node swizzles the Godot AppDelegate in `_ready()` to capture APNs callbacks
- Permission is requested automatically on `_ready()` — iOS shows the dialog on first launch, and silently returns the previous result on subsequent launches
- Async results (from iOS background threads) are delivered via `_process()` polling, since `DispatchQueue.main.async` does not work reliably in Godot's iOS runtime
- Connect your signal handlers **before** adding the node to the tree

### Usage from C# (GDExtension objects)

When using this plugin from C#, you must use `ClassDB.Instantiate()` and `.AsGodotObject()` — do **not** use `.As<Node>()` as this causes instance binding conflicts with GDExtension objects.

Use `CallDeferred("add_child", variant)` on a scene tree node to add it, passing the raw `Variant` from `ClassDB.Instantiate()`.

```csharp
// Instantiate — keep the raw Variant for AddChild
Variant pushVariant = ClassDB.Instantiate("PushNotificationToken");
GodotObject pushToken = pushVariant.AsGodotObject();

// Connect signals BEFORE adding to tree
pushToken.Connect("token_received", Callable.From<string>((token) => {
    GD.Print($"APNs token: {token}");
}));

pushToken.Connect("token_failed", Callable.From<string>((error) => {
    GD.PrintErr($"Push registration failed: {error}");
}));

pushToken.Connect("permission_result", Callable.From<bool>((granted) => {
    GD.Print($"Permission granted: {granted}");
}));

// Add to scene tree — use the raw Variant, not the GodotObject
// Permission is requested automatically from _ready()
someNode.GetTree().Root.CallDeferred("add_child", pushVariant);
```

### Usage from GDScript

```gdscript
extends Node

func _ready() -> void:
    var push_token = PushNotificationToken.new()
    push_token.token_received.connect(_on_token_received)
    push_token.token_failed.connect(_on_token_failed)
    push_token.permission_result.connect(_on_permission_result)
    add_child(push_token)
    # Permission is requested automatically from _ready()

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

## API Reference

### Automatic Behavior

When the node enters the scene tree (`_ready()`):
1. Swizzles the Godot AppDelegate to capture APNs token callbacks
2. Calls `UNUserNotificationCenter.requestAuthorization()` — shows the permission dialog on first launch
3. If permission is granted, calls `UIApplication.shared.registerForRemoteNotifications()`
4. Emits `permission_result`, then `token_received` or `token_failed`

### Methods

| Method | Return | Description |
|--------|--------|-------------|
| `request_permission()` | `void` | Re-triggers the permission + registration flow. Called automatically from `_ready()`. |
| `register_for_remote_notifications()` | `void` | Re-registers for remote notifications without showing the permission dialog. Use if you need to refresh the token. |
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

## Technical Notes

### Why `DispatchQueue.main.async` is not used

Godot's iOS runtime manages its own run loop. The main GCD dispatch queue is not reliably serviced, which means `DispatchQueue.main.async` blocks may never execute. This plugin uses a polling pattern instead: iOS callbacks store results in instance variables, and `_process()` drains them on the Godot thread each frame.

### Why C# must use `AsGodotObject()` instead of `As<Node>()`

GDExtension objects created via `ClassDB.Instantiate()` already have native instance bindings. Calling `.As<Node>()` creates a conflicting C# binding, causing a crash: `"Condition '_instance_bindings != nullptr' is true"`. Using `.AsGodotObject()` avoids this by working with the generic `GodotObject` wrapper.

### Why `CallDeferred("add_child", variant)` is needed from C#

Calling `AddChild()` directly from C# on a GDExtension object triggers the same instance binding conflict. Passing the raw `Variant` to `CallDeferred("add_child", ...)` lets the engine handle the native add without creating a conflicting C# binding.

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
