extends Node

## Example: how to use the PushNotificationToken plugin from GDScript.
## Add a PushNotificationToken node as a child, or instance it in code.

@onready var push_token: PushNotificationToken = $PushNotificationToken

func _ready() -> void:
	push_token.token_received.connect(_on_token_received)
	push_token.token_failed.connect(_on_token_failed)
	push_token.permission_result.connect(_on_permission_result)

	# On first launch, request permission (shows the iOS prompt).
	# On subsequent launches, call register_for_remote_notifications() instead
	# to silently re-register without prompting.
	push_token.request_permission()

func _on_permission_result(granted: bool) -> void:
	if granted:
		print("User granted push notification permission – waiting for token…")
	else:
		print("User denied push notification permission.")

func _on_token_received(token: String) -> void:
	print("APNs device token: ", token)
	# Send the token to your backend / third-party push service
	_send_token_to_server(token)

func _on_token_failed(error: String) -> void:
	printerr("Failed to register for push notifications: ", error)

func _send_token_to_server(token: String) -> void:
	# Replace with your actual API call
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_result, _code, _headers, _body):
		http.queue_free()
	)
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"device_token": token, "platform": "ios"})
	http.request("https://your-api.example.com/register-device", headers, HTTPClient.METHOD_POST, body)
