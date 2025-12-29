class_name Body
extends Node2D
## Body - Celestial body (planet, sun, station, warp gate, etc.)
## Ported from core/solarSystem/Body.as

# =============================================================================
# SIGNALS
# =============================================================================

signal player_entered_safe_zone
signal player_exited_safe_zone
signal all_spawners_cleared

# =============================================================================
# BODY TYPES
# =============================================================================

enum Type {
	SUN = 0,
	PLANET = 1,
	WARP_GATE = 2,
	SHOP = 3,
	RESEARCH_STATION = 4,
	JUNK_YARD = 5,
	COMET = 6,
	PIRATE_BASE = 7,
	BOSS = 8,
	HANGAR = 9,
	CANTINA = 10,
	PAINT_SHOP = 11,
	LORE = 12,
	HIDDEN = 13,
	WARNING = 14
}

const TYPE_NAMES: Dictionary = {
	Type.SUN: "sun",
	Type.PLANET: "planet",
	Type.WARP_GATE: "warpGate",
	Type.SHOP: "shop",
	Type.RESEARCH_STATION: "researchStation",
	Type.JUNK_YARD: "junkYard",
	Type.COMET: "comet",
	Type.PIRATE_BASE: "pirateBase",
	Type.BOSS: "boss",
	Type.HANGAR: "hangar",
	Type.CANTINA: "cantina",
	Type.PAINT_SHOP: "paintShop",
	Type.LORE: "lore",
	Type.HIDDEN: "hidden",
	Type.WARNING: "warning"
}

const TYPE_COLORS: Dictionary = {
	Type.WARP_GATE: Color("22a966"),
	Type.RESEARCH_STATION: Color("662222"),
	Type.SHOP: Color("444fff"),
	Type.PIRATE_BASE: Color("ff8484"),
	Type.JUNK_YARD: Color("88aa66"),
	Type.PLANET: Color("ff6663"),
	Type.WARNING: Color("eeee00"),
	Type.SUN: Color("ffdd44"),
}

# =============================================================================
# IDENTIFICATION
# =============================================================================

@export var body_key: String = ""
@export var body_name: String = ""
@export var body_type: Type = Type.PLANET
@export var level: int = 1

# =============================================================================
# ORBITAL PROPERTIES
# =============================================================================

@export_group("Orbit")
@export var orbit_radius: float = 0.0
@export var orbit_speed: float = 0.0
@export var orbit_angle: float = 0.0
@export var rotation_speed: float = 0.0

# =============================================================================
# PHYSICAL PROPERTIES
# =============================================================================

@export_group("Physical")
@export var radius: float = 50.0
@export var collision_radius: float = 40.0

# =============================================================================
# GAMEPLAY PROPERTIES
# =============================================================================

@export_group("Gameplay")
@export var landable: bool = false
@export var explorable: bool = false
@export var safe_zone_radius: float = 0.0
@export var hostile_zone_radius: float = 0.0

# =============================================================================
# GRAVITY (Sun only)
# =============================================================================

@export_group("Gravity")
@export var gravity_force: float = 0.0
@export var gravity_distance: float = 0.0
@export var gravity_min: float = 100.0

# =============================================================================
# INHABITANTS
# =============================================================================

enum Inhabitants { NONE, FRIENDLY, NEUTRAL, HOSTILE }
enum Defence { NONE, WEAK, MEDIUM, STRONG, VERY_STRONG }

@export_group("Inhabitants")
@export var inhabitants: Inhabitants = Inhabitants.NONE
@export var defence: Defence = Defence.NONE
@export var population: int = 0
@export var elite: bool = false

# =============================================================================
# STATE
# =============================================================================

var parent_body: Body = null
var children: Array[Body] = []
var spawners: Array = []  # Spawner nodes attached to this body
var spawners_cleared: bool = false
var _player_in_safe_zone: bool = false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("bodies")
	if body_type == Type.SUN:
		add_to_group("suns")

func _process(delta: float) -> void:
	# Update orbital position
	if orbit_speed != 0 and parent_body != null:
		orbit_angle += orbit_speed * delta
		_update_orbital_position()

	# Self rotation
	if rotation_speed != 0:
		rotation += rotation_speed * delta

# =============================================================================
# ORBITAL MECHANICS
# =============================================================================

func _update_orbital_position() -> void:
	if parent_body == null:
		return

	var parent_pos: Vector2 = parent_body.global_position
	position = Vector2(
		cos(orbit_angle) * orbit_radius,
		sin(orbit_angle) * orbit_radius
	)

## Set parent body for orbital relationship
func set_parent_body(parent: Body) -> void:
	if parent_body != null:
		parent_body.children.erase(self)

	parent_body = parent

	if parent_body != null:
		parent_body.children.append(self)
		# Only reparent if we have a parent node
		if get_parent() != null:
			reparent(parent_body)
		_update_orbital_position()

# =============================================================================
# SAFE ZONE
# =============================================================================

func is_in_safe_zone(pos: Vector2) -> bool:
	if safe_zone_radius <= 0:
		return false
	if not spawners_cleared:
		return false
	return global_position.distance_squared_to(pos) <= safe_zone_radius * safe_zone_radius

func is_in_hostile_zone(pos: Vector2) -> bool:
	if hostile_zone_radius <= 0:
		return false
	return global_position.distance_squared_to(pos) <= hostile_zone_radius * hostile_zone_radius

func check_player_safe_zone(player_pos: Vector2) -> void:
	var in_zone := is_in_safe_zone(player_pos)
	if in_zone and not _player_in_safe_zone:
		_player_in_safe_zone = true
		player_entered_safe_zone.emit()
	elif not in_zone and _player_in_safe_zone:
		_player_in_safe_zone = false
		player_exited_safe_zone.emit()

# =============================================================================
# GRAVITY
# =============================================================================

## Calculate gravity force at given position (for suns)
func get_gravity_at(pos: Vector2) -> Vector2:
	if gravity_force <= 0 or gravity_distance <= 0:
		return Vector2.ZERO

	var to_body: Vector2 = global_position - pos
	var dist_sq: float = to_body.length_squared()

	if dist_sq > gravity_distance * gravity_distance:
		return Vector2.ZERO

	# Clamp minimum distance
	if dist_sq < gravity_min * gravity_min:
		dist_sq = gravity_min * gravity_min

	# F = gravityForce / distance²
	var force_magnitude: float = gravity_force / dist_sq
	return to_body.normalized() * force_magnitude

# =============================================================================
# INTERACTION
# =============================================================================

func is_player_over_me(player_pos: Vector2) -> bool:
	return global_position.distance_squared_to(player_pos) <= collision_radius * collision_radius

func can_land() -> bool:
	return landable and is_station_type()

func can_explore() -> bool:
	return explorable

func is_station_type() -> bool:
	return body_type in [
		Type.WARP_GATE, Type.SHOP, Type.RESEARCH_STATION,
		Type.JUNK_YARD, Type.PIRATE_BASE, Type.HANGAR,
		Type.CANTINA, Type.PAINT_SHOP, Type.LORE
	]

func is_sun() -> bool:
	return body_type == Type.SUN

func is_planet() -> bool:
	return body_type == Type.PLANET

func is_warp_gate() -> bool:
	return body_type == Type.WARP_GATE

# =============================================================================
# INITIALIZATION
# =============================================================================

func init_from_data(data: Dictionary) -> void:
	body_key = data.get("key", "")
	body_name = data.get("name", "Unknown")
	body_type = data.get("type", Type.PLANET)
	level = data.get("level", 1)

	# Position
	var pos_x: float = data.get("x", 0.0)
	var pos_y: float = data.get("y", 0.0)
	position = Vector2(pos_x, pos_y)

	# Orbit
	orbit_radius = data.get("orbitRadius", 0.0)
	orbit_speed = data.get("orbitSpeed", 0.0)
	orbit_angle = data.get("orbitAngle", 0.0)
	rotation_speed = data.get("rotationSpeed", 0.0)

	# Physical
	radius = data.get("radius", 50.0)
	collision_radius = data.get("collisionRadius", radius * 0.8)

	# Gameplay
	landable = data.get("landable", false)
	explorable = data.get("explorable", false)
	safe_zone_radius = data.get("safeZoneRadius", 0.0)
	hostile_zone_radius = data.get("hostileZoneRadius", 0.0)

	# Gravity
	gravity_force = data.get("gravityForce", 0.0)
	gravity_distance = data.get("gravityDistance", 0.0)
	gravity_min = data.get("gravityMin", 100.0)

	# Inhabitants
	inhabitants = data.get("inhabitants", Inhabitants.NONE)
	defence = data.get("defence", Defence.NONE)
	population = data.get("population", 0)
	elite = data.get("elite", false)

func get_color() -> Color:
	if body_type in TYPE_COLORS:
		return TYPE_COLORS[body_type]
	return Color.WHITE

func _to_string() -> String:
	return "Body(%s, type=%s, level=%d)" % [body_name, TYPE_NAMES.get(body_type, "unknown"), level]

# =============================================================================
# SPAWNER MANAGEMENT
# =============================================================================

func add_spawner(spawner) -> void:
	"""Add a spawner to this body."""
	if spawner == null:
		return

	spawners.append(spawner)
	spawner.set_parent_body(self)

	# Position spawner relative to body
	if spawner.get_parent() != self:
		add_child(spawner)

	# Connect to spawner signals
	if spawner.has_signal("all_waves_cleared"):
		spawner.all_waves_cleared.connect(_on_spawner_cleared.bind(spawner))

	spawners_cleared = false

func remove_spawner(spawner) -> void:
	"""Remove a spawner from this body."""
	spawners.erase(spawner)
	_check_all_spawners_cleared()

func on_spawner_cleared(spawner) -> void:
	"""Called when a spawner finishes all waves."""
	_check_all_spawners_cleared()

func _on_spawner_cleared(spawner) -> void:
	"""Internal handler for spawner cleared signal."""
	_check_all_spawners_cleared()

func _check_all_spawners_cleared() -> void:
	"""Check if all spawners are cleared."""
	for spawner in spawners:
		if is_instance_valid(spawner) and not spawner.is_cleared():
			return

	if not spawners_cleared:
		spawners_cleared = true
		all_spawners_cleared.emit()

func create_default_spawner(enemy_count: int = 5, enemy_level: int = -1) -> void:
	"""Create a default spawner for this body."""
	if enemy_level < 0:
		enemy_level = level

	var spawner_scene = load("res://scenes/world/spawner.tscn")
	var spawner = spawner_scene.instantiate()

	# Select enemy sprite based on level
	var enemy_sprites: Array[String] = ["enemy_blaster_11", "enemy_beamer_11", "enemy_beetle_baby1", "enemy_beetle_scarab1"]
	var sprite_index: int = mini(enemy_level / 3, enemy_sprites.size() - 1)
	var enemy_sprite: String = enemy_sprites[sprite_index]

	spawner.max_enemies = enemy_count
	spawner.orbit_radius = radius + 100.0
	spawner.enemy_config = {
		"spriteName": enemy_sprite,
		"animationFrames": 4,
		"hpMax": 30.0 + enemy_level * 10.0,
		"xpValue": 5 + enemy_level * 3,
		"maxSpeed": 150.0 + enemy_level * 5.0,
	}

	add_spawner(spawner)

func get_spawner_count() -> int:
	return spawners.size()

func get_enemies_alive() -> int:
	"""Get total enemies alive across all spawners."""
	var count := 0
	for spawner in spawners:
		if is_instance_valid(spawner):
			count += spawner.get_enemies_alive()
	return count
