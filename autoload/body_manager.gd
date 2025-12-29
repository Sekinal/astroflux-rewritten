extends Node
## BodyManager - Manages all celestial bodies in the current solar system
## Ported from core/solarSystem/BodyManager.as

# =============================================================================
# SIGNALS
# =============================================================================

signal solar_system_loaded(system_name: String)
signal body_added(body: Node)
signal body_removed(body: Node)
signal player_entered_safe_zone(body: Node)
signal player_exited_safe_zone

# =============================================================================
# STATE
# =============================================================================

var bodies: Array = []  # All bodies
var roots: Array = []   # Top-level bodies (no parent)
var bodies_by_key: Dictionary = {}  # Fast lookup by key
var suns: Array = []    # Sun bodies (for gravity)

var current_system_name: String = ""
var _container: Node2D = null
var _player_safe_zone_body: Node = null

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	print("[BodyManager] Initialized")

## Initialize with a container node for bodies
func initialize(container: Node2D) -> void:
	_container = container
	print("[BodyManager] Container set")

## Clear all bodies
func clear() -> void:
	for body in bodies:
		if is_instance_valid(body):
			body.queue_free()

	bodies.clear()
	roots.clear()
	bodies_by_key.clear()
	suns.clear()
	_player_safe_zone_body = null
	current_system_name = ""

# =============================================================================
# BODY MANAGEMENT
# =============================================================================

## Add a body to the manager
func add_body(body: Node) -> void:
	if body in bodies:
		return

	bodies.append(body)

	# Index by key
	if body.get("body_key") != null and body.body_key != "":
		bodies_by_key[body.body_key] = body

	# Track root bodies
	if body.get("parent_body") == null:
		roots.append(body)

	# Track suns for gravity
	if body.has_method("is_sun") and body.is_sun():
		suns.append(body)

	# Connect safe zone signals
	if body.has_signal("player_entered_safe_zone"):
		body.player_entered_safe_zone.connect(_on_body_safe_zone_entered.bind(body))
	if body.has_signal("player_exited_safe_zone"):
		body.player_exited_safe_zone.connect(_on_body_safe_zone_exited.bind(body))

	# Add to container
	if _container != null and body.get_parent() == null:
		_container.add_child(body)

	body_added.emit(body)

## Remove a body from the manager
func remove_body(body: Node) -> void:
	bodies.erase(body)
	roots.erase(body)
	suns.erase(body)

	if body.get("body_key") != null:
		bodies_by_key.erase(body.body_key)

	body_removed.emit(body)

## Get body by key
func get_body_by_key(key: String) -> Node:
	return bodies_by_key.get(key, null)

## Get all bodies of a specific type
func get_bodies_by_type(body_type: int) -> Array:
	var result: Array = []
	for body in bodies:
		if body.get("body_type") == body_type:
			result.append(body)
	return result

# =============================================================================
# GRAVITY
# =============================================================================

## Calculate total gravity force at position from all suns
func get_gravity_at(pos: Vector2) -> Vector2:
	var total_gravity := Vector2.ZERO

	for sun in suns:
		if is_instance_valid(sun) and sun.has_method("get_gravity_at"):
			total_gravity += sun.get_gravity_at(pos)

	return total_gravity

# =============================================================================
# SAFE ZONES
# =============================================================================

## Check if position is in any safe zone
func is_in_safe_zone(pos: Vector2) -> bool:
	for body in bodies:
		if is_instance_valid(body) and body.has_method("is_in_safe_zone"):
			if body.is_in_safe_zone(pos):
				return true
	return false

## Get the body whose safe zone contains the position
func get_safe_zone_body(pos: Vector2) -> Node:
	for body in bodies:
		if is_instance_valid(body) and body.has_method("is_in_safe_zone"):
			if body.is_in_safe_zone(pos):
				return body
	return null

## Update player safe zone status
func update_player_safe_zone(player_pos: Vector2) -> void:
	var zone_body: Node = get_safe_zone_body(player_pos)

	if zone_body != _player_safe_zone_body:
		if _player_safe_zone_body != null:
			player_exited_safe_zone.emit()

		_player_safe_zone_body = zone_body

		if _player_safe_zone_body != null:
			player_entered_safe_zone.emit(_player_safe_zone_body)

func _on_body_safe_zone_entered(body: Node) -> void:
	_player_safe_zone_body = body
	player_entered_safe_zone.emit(body)

func _on_body_safe_zone_exited(body: Node) -> void:
	if _player_safe_zone_body == body:
		_player_safe_zone_body = null
		player_exited_safe_zone.emit()

# =============================================================================
# COLLISION / INTERACTION
# =============================================================================

## Get body at position (for landing)
func get_body_at(pos: Vector2) -> Node:
	for body in bodies:
		if is_instance_valid(body) and body.has_method("is_player_over_me"):
			if body.is_player_over_me(pos):
				return body
	return null

## Get landable body at position
func get_landable_body_at(pos: Vector2) -> Node:
	var body: Node = get_body_at(pos)
	if body != null and body.has_method("can_land") and body.can_land():
		return body
	return null

# =============================================================================
# SOLAR SYSTEM LOADING
# =============================================================================

## Load a solar system from data
func load_solar_system(system_data: Dictionary) -> void:
	clear()

	current_system_name = system_data.get("name", "Unknown System")

	# Load bodies
	var bodies_data: Array = system_data.get("bodies", [])
	var body_instances: Dictionary = {}

	# First pass: create all bodies
	for body_data in bodies_data:
		var body: Node = _create_body_from_data(body_data)
		if body != null:
			body_instances[body.body_key] = body

	# Second pass: set up parent relationships
	for body_data in bodies_data:
		var body_key: String = body_data.get("key", "")
		var parent_key: String = body_data.get("parentKey", "")

		if parent_key != "" and body_key in body_instances and parent_key in body_instances:
			var child: Node = body_instances[body_key]
			var parent: Node = body_instances[parent_key]
			if child.has_method("set_parent_body"):
				child.set_parent_body(parent)

	# Add all bodies to manager
	for body in body_instances.values():
		add_body(body)

	solar_system_loaded.emit(current_system_name)
	print("[BodyManager] Loaded solar system: ", current_system_name, " with ", bodies.size(), " bodies")

func _create_body_from_data(data: Dictionary) -> Node:
	# Load the appropriate scene based on body type
	var body_type: int = data.get("type", 1)  # Default to planet
	var scene_path: String = _get_scene_for_type(body_type)

	if not ResourceLoader.exists(scene_path):
		push_warning("[BodyManager] Scene not found: ", scene_path)
		return null

	var scene: PackedScene = load(scene_path)
	var body: Node = scene.instantiate()

	if body.has_method("init_from_data"):
		body.init_from_data(data)

	return body

func _get_scene_for_type(body_type: int) -> String:
	# Body.Type enum values (avoid preload in autoload)
	const TYPE_SUN = 0
	const TYPE_PLANET = 1
	const TYPE_WARP_GATE = 2
	const TYPE_SHOP = 3
	const TYPE_RESEARCH_STATION = 4
	const TYPE_HANGAR = 9

	match body_type:
		TYPE_SUN:
			return "res://scenes/world/bodies/sun.tscn"
		TYPE_PLANET:
			return "res://scenes/world/bodies/planet.tscn"
		TYPE_WARP_GATE:
			return "res://scenes/world/bodies/warp_gate.tscn"
		TYPE_SHOP, TYPE_RESEARCH_STATION, TYPE_HANGAR:
			return "res://scenes/world/bodies/station.tscn"
		_:
			return "res://scenes/world/bodies/planet.tscn"

# =============================================================================
# DEBUG
# =============================================================================

## Create a test solar system for development
func create_test_system() -> void:
	clear()
	current_system_name = "Test System"

	# Body.Type enum values (avoid preload in autoload)
	const TYPE_SUN = 0
	const TYPE_PLANET = 1
	const TYPE_WARP_GATE = 2
	const TYPE_SHOP = 3

	# Create sun at center
	var sun_data := {
		"key": "sun_01",
		"name": "Sol",
		"type": TYPE_SUN,
		"x": 0.0,
		"y": 0.0,
		"radius": 150.0,
		"collisionRadius": 180.0,
		"gravityForce": 5000000.0,  # Increased 100x for noticeable effect
		"gravityDistance": 1200.0,   # Larger range
		"gravityMin": 200.0,
	}

	# Create planets
	var planet1_data := {
		"key": "planet_01",
		"name": "Terra",
		"type": TYPE_PLANET,
		"x": 600.0,
		"y": 0.0,
		"radius": 80.0,
		"collisionRadius": 70.0,
		"orbitRadius": 600.0,
		"orbitSpeed": 0.1,
		"orbitAngle": 0.0,
		"rotationSpeed": 0.5,
		"parentKey": "sun_01",
		"safeZoneRadius": 200.0,
		"landable": true,
		"level": 1,
	}

	var planet2_data := {
		"key": "planet_02",
		"name": "Mars",
		"type": TYPE_PLANET,
		"x": 1000.0,
		"y": 0.0,
		"radius": 60.0,
		"collisionRadius": 55.0,
		"orbitRadius": 1000.0,
		"orbitSpeed": 0.05,
		"orbitAngle": 2.0,
		"rotationSpeed": 0.3,
		"parentKey": "sun_01",
		"level": 5,
	}

	# Create warp gate
	var gate_data := {
		"key": "gate_01",
		"name": "Warp Gate Alpha",
		"type": TYPE_WARP_GATE,
		"x": -800.0,
		"y": 400.0,
		"radius": 40.0,
		"collisionRadius": 50.0,
		"safeZoneRadius": 150.0,
		"landable": true,
	}

	# Create station
	var station_data := {
		"key": "station_01",
		"name": "Trade Station",
		"type": TYPE_SHOP,
		"x": 400.0,
		"y": -500.0,
		"radius": 35.0,
		"collisionRadius": 45.0,
		"safeZoneRadius": 180.0,
		"landable": true,
		"level": 1,
	}

	var system_data := {
		"name": "Test System",
		"bodies": [sun_data, planet1_data, planet2_data, gate_data, station_data]
	}

	load_solar_system(system_data)

	# Add spawners to planets
	_add_spawners_to_test_system()

func _add_spawners_to_test_system() -> void:
	"""Add enemy spawners to test system planets."""
	# Add spawner to planet 1 (Terra) - low level
	var terra = get_body_by_key("planet_01")
	if terra != null and terra.has_method("create_default_spawner"):
		terra.create_default_spawner(3, 1)  # 3 enemies, level 1
		print("[BodyManager] Added spawner to Terra")

	# Add spawner to planet 2 (Mars) - higher level
	var mars = get_body_by_key("planet_02")
	if mars != null and mars.has_method("create_default_spawner"):
		mars.create_default_spawner(5, 5)  # 5 enemies, level 5
		print("[BodyManager] Added spawner to Mars")

# =============================================================================
# HYPERION LOADER
# =============================================================================

## Load the Hyperion solar system from JSON data
func load_hyperion() -> void:
	var json_path := "res://data/hyperion.json"

	if not FileAccess.file_exists(json_path):
		push_error("[BodyManager] Hyperion data not found: " + json_path)
		return

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("[BodyManager] Failed to open hyperion.json")
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("[BodyManager] Failed to parse hyperion.json: " + json.get_error_message())
		return

	var data: Dictionary = json.data
	_load_hyperion_from_data(data)

func _load_hyperion_from_data(data: Dictionary) -> void:
	clear()

	var solar_system: Dictionary = data.get("solarSystem", {})
	current_system_name = solar_system.get("name", "Hyperion")

	print("[BodyManager] Loading Hyperion solar system...")

	# Map body type strings to enum values
	var type_map := {
		"sun": 0,
		"planet": 1,
		"warpGate": 2,
		"shop": 3,
		"research": 4,
		"junk yard": 5,
		"comet": 6,
		"pirate bay": 7,
		"boss": 8,
		"hangar": 9,
		"cantina": 10,
		"paint shop": 11,
		"lore": 12,
		"hidden": 13,
		"warning": 14,
	}

	# Convert bodies from Hyperion format to Godot format
	var bodies_data: Dictionary = data.get("bodies", {})
	var spawners_data: Dictionary = data.get("spawners", {})
	var enemies_data: Dictionary = data.get("enemies", {})

	var body_instances: Dictionary = {}
	var converted_bodies: Array = []

	# First pass: convert and create all bodies
	for key in bodies_data:
		var body_raw: Dictionary = bodies_data[key]

		# Skip hidden bodies (they're usually invisible markers)
		if body_raw.get("type", "") == "hidden":
			continue

		var body_type_str: String = body_raw.get("type", "planet")
		var body_type: int = type_map.get(body_type_str, 1)

		var body_data := {
			"key": key,
			"name": body_raw.get("name", "Unknown"),
			"type": body_type,
			"x": body_raw.get("x", 0.0),
			"y": body_raw.get("y", 0.0),
			"radius": body_raw.get("collisionRadius", 50.0),
			"collisionRadius": body_raw.get("collisionRadius", 50.0),
			"orbitRadius": body_raw.get("orbitRadius", 0.0),
			"orbitSpeed": body_raw.get("orbitSpeed", 0.0) / 80.0 if body_raw.get("orbitRadius", 0.0) > 0 else 0.0,
			"orbitAngle": body_raw.get("orbitAngle", 0.0),
			"rotationSpeed": body_raw.get("rotationSpeed", 0.0),
			"parentKey": body_raw.get("parent", ""),
			"safeZoneRadius": body_raw.get("safeZoneRadius", 0.0),
			"landable": body_raw.get("landable", false),
			"explorable": body_raw.get("explorable", false),
			"level": body_raw.get("level", 1),
			"elite": body_raw.get("elite", false),
		}

		# Add gravity for suns
		if body_type == 0:  # sun
			body_data["gravityForce"] = 5000000.0
			body_data["gravityDistance"] = 1200.0
			body_data["gravityMin"] = 200.0

		converted_bodies.append(body_data)

		# Create the body instance
		var body: Node = _create_body_from_data(body_data)
		if body != null:
			body_instances[key] = body

	# Second pass: set up parent relationships
	for body_data in converted_bodies:
		var body_key: String = body_data.get("key", "")
		var parent_key: String = body_data.get("parentKey", "")

		if parent_key != "" and body_key in body_instances and parent_key in body_instances:
			var child: Node = body_instances[body_key]
			var parent: Node = body_instances[parent_key]
			if child.has_method("set_parent_body"):
				child.set_parent_body(parent)

	# Add all bodies to manager
	for body in body_instances.values():
		add_body(body)

	# Third pass: add spawners
	_add_hyperion_spawners(spawners_data, enemies_data, body_instances)

	solar_system_loaded.emit(current_system_name)
	print("[BodyManager] Loaded Hyperion with ", bodies.size(), " bodies")

func _add_hyperion_spawners(spawners_data: Dictionary, enemies_data: Dictionary, body_instances: Dictionary) -> void:
	"""Add spawners from Hyperion data to bodies."""
	var spawner_scene := preload("res://scenes/world/spawner.tscn")

	var spawner_count := 0

	for spawner_key in spawners_data:
		var spawner_raw: Dictionary = spawners_data[spawner_key]

		# Skip hidden spawners or those with no enemies
		if spawner_raw.get("hidden", false):
			continue

		var body_key: String = spawner_raw.get("body", "")
		if body_key == "" or body_key not in body_instances:
			continue

		var body: Node = body_instances[body_key]

		# Get enemy data
		var enemy_key: String = spawner_raw.get("enemy", "")
		if enemy_key == "" or enemy_key not in enemies_data:
			continue

		var enemy_data: Dictionary = enemies_data[enemy_key]

		# Create spawner
		var spawner: Node = spawner_scene.instantiate()

		# Configure spawner
		spawner.max_enemies = spawner_raw.get("nrOfEnemies", 5)
		spawner.spawn_delay = spawner_raw.get("resetTime", 2.0)
		spawner.orbit_radius = spawner_raw.get("orbitRadius", 150.0)

		# Configure enemy
		# Sprite names in data are like "enemy_slug_1" but atlas uses "enemy_slug_11" (variant + frame)
		var raw_sprite_name: String = enemy_data.get("spriteName", "enemy_slug_1")
		var sprite_name: String = raw_sprite_name
		# Append "1" for first frame if the sprite name ends with a variant number
		if raw_sprite_name.contains("_") and raw_sprite_name[-1].is_valid_int():
			sprite_name = raw_sprite_name + "1"  # e.g., enemy_slug_1 -> enemy_slug_11

		spawner.enemy_config = {
			"spriteName": sprite_name,
			"animationFrames": 4 if enemy_data.get("animate", false) else 1,
			"hpMax": float(enemy_data.get("hp", 100)),
			"shieldMax": float(enemy_data.get("shieldHp", 0)),
			"xpValue": int(spawner_raw.get("xp", 10)),
			"maxSpeed": 150.0,
			"acceleration": 0.5,
			"rotationSpeed": 120.0,
			"aggroRange": float(enemy_data.get("aggroRange", 400)),
			"chaseRange": float(enemy_data.get("chaseRange", 600)),
			"alwaysFire": enemy_data.get("alwaysFire", false),
		}

		# Add spawner to body
		if body.has_method("add_spawner"):
			body.add_spawner(spawner)
			spawner_count += 1

	print("[BodyManager] Added ", spawner_count, " spawners to Hyperion")
