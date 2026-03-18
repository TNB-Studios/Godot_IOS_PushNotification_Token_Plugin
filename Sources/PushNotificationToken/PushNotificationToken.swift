import SwiftGodot
import UserNotifications
import UIKit

/// Singleton that requests iOS push notification permission and exposes the APNs device token.
/// Add this node to the scene tree — it automatically requests permission and registers for
/// remote notifications from _ready().
@Godot
class PushNotificationToken: Node {

    // MARK: - Signals

    /// Emitted when the APNs device token is received. `token` is the hex-encoded string.
    #signal("token_received", arguments: ["token": String.self])

    /// Emitted when registration for remote notifications fails. `error` is the localised description.
    #signal("token_failed", arguments: ["error": String.self])

    /// Emitted after the user responds to the permission prompt. `granted` indicates whether they allowed notifications.
    #signal("permission_result", arguments: ["granted": Bool.self])

    // MARK: - State

    /// The most recently received APNs device token (hex string), or empty if not yet available.
    @Export var deviceToken: String = ""

    /// Whether we have already swizzled the AppDelegate.
    private static var swizzled = false

    // MARK: - Pending results (set from background threads, emitted in _process)
    private var pendingPermissionResult: Bool? = nil
    private var pendingToken: String? = nil
    private var pendingError: String? = nil

    // MARK: - Singleton access

    /// Shared reference so the swizzled AppDelegate methods can forward the token back.
    static weak var shared: PushNotificationToken?

    override func _ready() {
        PushNotificationToken.shared = self
        swizzleAppDelegateIfNeeded()
        requestPermission()
    }

    override func _process(delta: Double) {
        // Drain pending results on the Godot main thread
        if let granted = pendingPermissionResult {
            pendingPermissionResult = nil
            emit(signal: PushNotificationToken.permissionResult, granted)
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        if let token = pendingToken {
            pendingToken = nil
            deviceToken = token
            emit(signal: PushNotificationToken.tokenReceived, token)
        }

        if let error = pendingError {
            pendingError = nil
            emit(signal: PushNotificationToken.tokenFailed, error)
        }
    }

    // MARK: - Public API

    /// Request notification permission and, if granted, register for remote notifications.
    /// This is called automatically from _ready(). You only need to call it manually if
    /// you want to re-trigger the permission flow.
    @Callable
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            self?.pendingPermissionResult = granted
        }
    }

    /// If the user already granted permission in a previous session, call this to re-register
    /// without showing the permission dialog again.
    @Callable
    func registerForRemoteNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Returns the last known device token, or an empty string.
    @Callable
    func getDeviceToken() -> String {
        return deviceToken
    }

    // MARK: - Token delivery (called from swizzled AppDelegate)

    func didReceiveToken(_ token: String) {
        pendingToken = token
    }

    func didFailToRegister(_ error: String) {
        pendingError = error
    }

    // MARK: - AppDelegate swizzling

    private func swizzleAppDelegateIfNeeded() {
        guard !PushNotificationToken.swizzled else { return }
        PushNotificationToken.swizzled = true

        guard let delegate = UIApplication.shared.delegate,
              let appDelegateClass: AnyClass = object_getClass(delegate) else {
            GD.pushWarning("PushNotificationToken: Could not get AppDelegate class for swizzling")
            return
        }

        // Swizzle didRegisterForRemoteNotificationsWithDeviceToken
        let successSel = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let successImpl: @convention(block) (AnyObject, UIApplication, Data) -> Void = { _, _, deviceToken in
            let token = deviceToken.map { String(format: "%02x", $0) }.joined()
            PushNotificationToken.shared?.didReceiveToken(token)
        }
        addOrReplaceMethod(cls: appDelegateClass, selector: successSel, block: successImpl,
                           types: "v@:@@")

        // Swizzle didFailToRegisterForRemoteNotificationsWithError
        let failSel = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let failImpl: @convention(block) (AnyObject, UIApplication, NSError) -> Void = { _, _, error in
            PushNotificationToken.shared?.didFailToRegister(error.localizedDescription)
        }
        addOrReplaceMethod(cls: appDelegateClass, selector: failSel, block: failImpl,
                           types: "v@:@@")
    }

    /// Add a new implementation for `selector` on `cls`, or replace the existing one.
    private func addOrReplaceMethod(cls: AnyClass, selector: Selector, block: Any, types: UnsafePointer<CChar>) {
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, selector, imp, types) {
            method_setImplementation(class_getInstanceMethod(cls, selector)!, imp)
        }
    }
}
