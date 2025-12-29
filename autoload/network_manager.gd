extends Node
## NetworkManager - Handles network communication
## Supports both real WebSocket connections and local mock server

# =============================================================================
# SIGNALS
# =============================================================================

signal connected
signal disconnected
signal message_received(message: Message)
signal join_result(success: bool, error: String)

# =============================================================================
# CONFIGURATION
# =============================================================================

## Set to true to use local mock server (for development)
@export var use_local_server: bool = true

## WebSocket URL for real server
@export var server_url: String = "wss://game.astroflux.com:8184"

## Reconnection settings
@export var auto_reconnect: bool = true
@export var reconnect_delay: float = 2.0

# =============================================================================
# STATE
# =============================================================================

var _socket: WebSocketPeer = null
var _connected: bool = false
var _handlers: Dictionary = {}  # message_type -> Array[Callable]
var server_time: float = 0.0
var _last_server_time_update: float = 0.0
var _clock_offset: float = 0.0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if use_local_server:
		print("[NetworkManager] Using LOCAL mock server")
		_connected = true
		call_deferred("emit_signal", "connected")
	else:
		print("[NetworkManager] Will connect to: ", server_url)

func _process(delta: float) -> void:
	# Update estimated server time
	server_time = Time.get_ticks_msec() + _clock_offset

	if use_local_server:
		return

	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				connected.emit()
				print("[NetworkManager] Connected to server")

			while _socket.get_available_packet_count() > 0:
				var data := _socket.get_packet()
				_handle_incoming_data(data)

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				disconnected.emit()
				print("[NetworkManager] Disconnected from server")
				if auto_reconnect:
					_schedule_reconnect()

# =============================================================================
# CONNECTION API
# =============================================================================

## Connect to the game server
func connect_to_server(url: String = "") -> void:
	if use_local_server:
		_connected = true
		connected.emit()
		return

	if url != "":
		server_url = url

	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(server_url)
	if err != OK:
		push_error("[NetworkManager] Connection failed: %s" % err)

## Disconnect from server
func disconnect_from_server() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_connected = false

## Check if connected
func is_connected_to_server() -> bool:
	return _connected

# =============================================================================
# MESSAGE SENDING
# =============================================================================

## Send a message (shorthand)
func send(msg_type: String, args: Array = []) -> void:
	send_message(Message.new(msg_type, args))

## Send a Message object
func send_message(msg: Message) -> void:
	if use_local_server:
		# Process locally through mock server
		LocalServer.process_message(msg)
		return

	if not _connected or _socket == null:
		push_warning("[NetworkManager] Cannot send - not connected")
		return

	var data := NetworkProtocol.serialize_message(msg)
	_socket.send(data)

# =============================================================================
# MESSAGE HANDLERS
# =============================================================================

## Register a handler for a message type
func add_message_handler(msg_type: String, handler: Callable) -> void:
	if not _handlers.has(msg_type):
		_handlers[msg_type] = []
	_handlers[msg_type].append(handler)

## Remove a handler
func remove_message_handler(msg_type: String, handler: Callable) -> void:
	if _handlers.has(msg_type):
		_handlers[msg_type].erase(handler)

## Receive a message from local server (called by LocalServer)
func receive_local(msg: Message) -> void:
	_dispatch_message(msg)

# =============================================================================
# INTERNAL
# =============================================================================

func _handle_incoming_data(data: PackedByteArray) -> void:
	var msg := NetworkProtocol.deserialize_message(data)
	_dispatch_message(msg)

func _dispatch_message(msg: Message) -> void:
	# Handle join result specially
	if msg.type == "playerio.joinresult":
		var success := msg.get_boolean(0)
		var error := "" if success else msg.get_string(2)
		join_result.emit(success, error)
		return

	# Specific handlers
	if _handlers.has(msg.type):
		for handler in _handlers[msg.type]:
			handler.call(msg)

	# Wildcard handlers
	if _handlers.has("*"):
		for handler in _handlers["*"]:
			handler.call(msg)

	message_received.emit(msg)

func _schedule_reconnect() -> void:
	await get_tree().create_timer(reconnect_delay).timeout
	if not _connected and not use_local_server:
		print("[NetworkManager] Attempting reconnection...")
		connect_to_server()

# =============================================================================
# CLOCK SYNC
# =============================================================================

## Sync clock with server
func sync_clock(server_timestamp: float) -> void:
	var local_time := float(Time.get_ticks_msec())
	_clock_offset = server_timestamp - local_time
	_last_server_time_update = local_time
	print("[NetworkManager] Clock synced. Offset: %.0fms" % _clock_offset)
