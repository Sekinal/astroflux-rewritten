extends Node2D
## Game - Main game scene
## Ported from core/scene/Game.as

# =============================================================================
# NODES
# =============================================================================

@onready var player_ship: CharacterBody2D = $PlayerShip
@onready var camera: Camera2D = $Camera2D
@onready var starfield: Node2D = $Starfield
@onready var bodies_container: Node2D = $Bodies
@onready var minimap: Control = $CanvasLayer/Minimap
@onready var full_map: Control = $CanvasLayer/FullMap

# =============================================================================
# STATE
# =============================================================================

var game_started: bool = false
var game_start_time: float = 0.0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	print("[Game] Initializing...")

	# Initialize projectile manager with this scene as container
	ProjectileManager.initialize(self)

	# Initialize body manager with bodies container
	BodyManager.initialize(bodies_container)

	# Wait for network connection
	if NetworkManager.use_local_server:
		_on_connected()
	else:
		NetworkManager.connected.connect(_on_connected)
		NetworkManager.disconnected.connect(_on_disconnected)
		NetworkManager.connect_to_server()

func _on_connected() -> void:
	print("[Game] Connected to server")

	# Request game initialization
	NetworkManager.send("initSolarSystem")

	# Register handlers
	NetworkManager.add_message_handler("initSolarSystem", _on_init_solar_system)
	NetworkManager.add_message_handler("initServerComplete", _on_init_complete)

func _on_disconnected() -> void:
	print("[Game] Disconnected from server")
	# TODO: Show reconnection dialog

func _on_init_solar_system(msg: Message) -> void:
	print("[Game] Solar system initialized: ", msg.get_string(1))

	# Load Hyperion solar system from JSON data
	BodyManager.load_hyperion()

	# Set up nebula tint from solar system (Antor System blue tint)
	# nebulaTint from Hyperion data: 1055231 = 0x101AFF (blueish)
	if starfield != null:
		var tint_color := Color(0.06, 0.08, 0.15, 1.0)  # Dark blue Antor tint
		starfield.set_nebula_tint(tint_color)

	# Initialize minimap with player reference
	if minimap != null:
		minimap.set_player(player_ship)

	# Initialize full map with player reference
	if full_map != null:
		full_map.set_player(player_ship)

	# Move player to safe starting position (near Endarion planet)
	if player_ship != null:
		# Position player near Endarion (friendly planet) which is at orbit around sun
		player_ship.converger.course.pos = Vector2(4000, 0)
		player_ship.global_position = Vector2(4000, 0)

	# Request game data
	NetworkManager.send("initGame")

func _on_init_complete(msg: Message) -> void:
	print("[Game] Server initialization complete")
	game_started = true
	game_start_time = NetworkManager.server_time

	# Start sync
	NetworkManager.send("initSyncEnemies")

func _physics_process(delta: float) -> void:
	if not game_started:
		return

	# Camera follows player
	if player_ship != null:
		camera.global_position = player_ship.global_position

func _input(event: InputEvent) -> void:
	# Debug: Reset position with R
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if player_ship != null:
			player_ship.converger.course.pos = Vector2.ZERO
			player_ship.converger.course.speed = Vector2.ZERO
			player_ship.global_position = Vector2.ZERO
			print("[Game] Reset player position")
