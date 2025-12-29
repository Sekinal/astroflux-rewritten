extends Node
## LocalServer - Mock server for offline development
## Simulates server responses instantly for rapid development
## This will be replaced by the real Go backend

# =============================================================================
# STATE
# =============================================================================

## Player state
var player_id: String = "local_player"
var player_heading: Heading = Heading.new()
var player_health: float = 100.0
var player_shield: float = 100.0

## Solar system state
var current_system: String = "antor"
var current_room_id: String = "local_room_001"

## Time tracking
var _start_time: float = 0.0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_start_time = Time.get_ticks_msec()
	print("[LocalServer] Mock server initialized")

## Get current server time (simulated)
func get_server_time() -> float:
	return Time.get_ticks_msec()

# =============================================================================
# MESSAGE PROCESSING
# =============================================================================

## Process an incoming message from the client
func process_message(msg: Message) -> void:
	match msg.type:
		# =====================================================================
		# MOVEMENT
		# =====================================================================
		"playerCourse":
			_handle_player_course(msg)

		"command":
			_handle_command(msg)

		# =====================================================================
		# ROOM MANAGEMENT
		# =====================================================================
		"join":
			_handle_join(msg)

		"initSolarSystem":
			_handle_init_solar_system()

		"initGame":
			_handle_init_game()

		"initSyncEnemies":
			_handle_init_sync_enemies()

		# =====================================================================
		# COMBAT
		# =====================================================================
		"fire":
			_handle_fire(msg)

		# =====================================================================
		# OTHER
		# =====================================================================
		_:
			print("[LocalServer] Unhandled message: ", msg.type)

# =============================================================================
# MESSAGE HANDLERS
# =============================================================================

func _handle_player_course(msg: Message) -> void:
	# Parse the heading from the message
	if msg.args.size() >= Heading.NR_OF_VARS:
		player_heading = Heading.from_array(msg.args)

	# Echo back the course (server-authoritative)
	var response := Message.new("playerCourse")
	player_heading.populate_message(response)
	response.args.insert(0, player_id)  # Prepend player ID

	_send_response(response)

func _handle_command(msg: Message) -> void:
	# Command format: [player_id, command_type, active, time, ...]
	if msg.args.size() < 4:
		return

	var cmd_type: int = msg.get_int(1)
	var active: bool = msg.get_boolean(2)
	var cmd_time: float = msg.get_number(3)

	# Apply command to heading
	player_heading.run_command(cmd_type, active)
	player_heading.time = cmd_time

	# Echo back updated course
	var response := Message.new("playerCourse")
	response.add(player_id)
	player_heading.populate_message(response)

	_send_response(response)

func _handle_join(msg: Message) -> void:
	# Send join success
	var response := Message.new("playerio.joinresult")
	response.add(true)  # success
	response.add("")    # reserved
	response.add("")    # error (empty = no error)
	_send_response(response)

func _handle_init_solar_system() -> void:
	# Send basic solar system data
	var response := Message.new("initSolarSystem")
	response.add(current_system)  # system key
	response.add("Antor")         # system name
	response.add("friendly")      # system type
	response.add(0)               # pvp level cap
	response.add(false)           # pvp above cap
	response.add(1)               # body count

	# Add a basic planet
	response.add("antor_prime")   # body key
	response.add("Antor Prime")   # body name
	response.add("planet")        # body type
	response.add(0)               # x position
	response.add(0)               # y position
	response.add(500)             # radius
	response.add(true)            # is safe zone

	_send_response(response)

func _handle_init_game() -> void:
	# Send player init data
	_send_init_player()

	# Send empty enemy players
	var enemy_players := Message.new("initEnemyPlayers")
	_send_response(enemy_players)

	# Send empty enemies
	var enemies := Message.new("initEnemies")
	_send_response(enemies)

	# Send empty drops
	var drops := Message.new("initDrops")
	_send_response(drops)

	# Send server complete
	var complete := Message.new("initServerComplete")
	_send_response(complete)

func _send_init_player() -> void:
	var msg := Message.new("initPlayer")

	# Player ID
	msg.add(player_id)

	# Basic player data (matching Player.init format)
	msg.add("Captain")      # name
	msg.add("")             # inviter_id
	msg.add(3)              # tos version
	msg.add(false)          # isDeveloper
	msg.add(false)          # isTester
	msg.add(false)          # isModerator
	msg.add(false)          # isTranslator
	msg.add(1)              # level
	msg.add(0)              # xp
	msg.add(0)              # techPoints
	msg.add(false)          # isHostile
	msg.add(1.0)            # rotationSpeedMod
	msg.add(0)              # reputation
	msg.add("")             # group id
	msg.add("")             # split
	msg.add("")             # current body (empty = not landed)
	msg.add(0)              # spree

	# Ship data (ship ID != -1 means flying)
	msg.add(1)              # ship ID
	msg.add(100)            # shield max
	msg.add(100)            # hp max
	msg.add(50)             # armor threshold
	msg.add(5)              # shield regen
	msg.add(300.0)          # engine speed
	msg.add(0.5)            # engine acceleration

	# Heading
	player_heading.time = get_server_time()
	player_heading.populate_message(msg)

	# Slots and upgrades
	msg.add(5)              # unlocked weapon slots
	msg.add(5)              # unlocked artifact slots
	msg.add(5)              # unlocked crew slots
	msg.add(0)              # compressor level
	msg.add(0)              # artifact capacity level
	msg.add(0)              # artifact auto recycle level

	# Stats
	msg.add(0)              # player kills
	msg.add(0)              # player deaths
	msg.add(0)              # enemy kills
	msg.add(false)          # show intro

	# Boosts
	msg.add(0.0)            # exp boost
	msg.add(0.0)            # tractor beam
	msg.add(0.0)            # xp protection
	msg.add(0.0)            # cargo protection
	msg.add(0.0)            # supporter

	# Packages
	msg.add(false)          # beginner package
	msg.add(false)          # power package
	msg.add(false)          # mega package
	msg.add(false)          # guest

	# Clan
	msg.add("")             # clan id
	msg.add("")             # clan application id

	# Currency
	msg.add(1000)           # troons
	msg.add(0)              # free resets
	msg.add(0)              # free paint jobs
	msg.add(0)              # artifact count

	# Factions
	msg.add(0)              # faction count

	# Fleet
	msg.add(1)              # fleet count
	msg.add("starter")      # ship key
	msg.add("Starter Ship") # ship name

	_send_response(msg)

func _handle_init_sync_enemies() -> void:
	var response := Message.new("initSyncEnemies")
	_send_response(response)

func _handle_fire(msg: Message) -> void:
	# TODO: Implement weapon firing
	pass

# =============================================================================
# UTILITY
# =============================================================================

func _send_response(msg: Message) -> void:
	# Use call_deferred to simulate network delay and avoid recursion
	NetworkManager.call_deferred("receive_local", msg)
