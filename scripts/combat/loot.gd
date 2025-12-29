class_name Loot
extends Area2D
## Loot - Droppable item/XP pickup
## Ported from core/loot/

# =============================================================================
# SIGNALS
# =============================================================================

signal collected(by: Node)

# =============================================================================
# LOOT TYPES
# =============================================================================

enum Type {
	XP,
	ARTIFACT,
	RESOURCE,
	WEAPON,
	SHIP_PART,
}

# =============================================================================
# PROPERTIES
# =============================================================================

@export var loot_type: Type = Type.XP
@export var loot_data: Dictionary = {}  ## Type-specific data
@export var pickup_range: float = 50.0  ## Auto-pickup range
@export var magnet_range: float = 200.0  ## Magnet attraction range
@export var magnet_speed: float = 400.0
@export var lifetime: float = 60.0  ## Despawn time

var _target: Node = null  # Player being attracted to
var _velocity: Vector2 = Vector2.ZERO
var _spawn_velocity: Vector2 = Vector2.ZERO
var _spawn_timer: float = 0.5  # Brief spawn animation
var _lifetime_timer: float = 0.0

# Visual
@onready var sprite: Polygon2D = $Sprite
@onready var glow: Polygon2D = $Glow

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Setup collision
	collision_layer = 0
	collision_mask = 2  # Detect player layer

	body_entered.connect(_on_body_entered)

	# Set visual based on type
	_setup_visual()

	# Random spawn velocity
	var angle := randf() * TAU
	var speed := randf_range(50, 150)
	_spawn_velocity = Vector2(cos(angle), sin(angle)) * speed

func _physics_process(delta: float) -> void:
	# Spawn animation
	if _spawn_timer > 0:
		_spawn_timer -= delta
		global_position += _spawn_velocity * delta
		_spawn_velocity *= 0.9  # Slow down
		return

	# Lifetime
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		_despawn()
		return

	# Fade when close to despawn
	if _lifetime_timer > lifetime - 5.0:
		modulate.a = (lifetime - _lifetime_timer) / 5.0

	# Find nearest player for magnet
	if _target == null or not is_instance_valid(_target):
		_find_target()

	# Magnet attraction
	if _target != null and is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		var dist: float = to_target.length()

		if dist < pickup_range:
			_collect(_target)
			return
		elif dist < magnet_range:
			# Accelerate toward player
			_velocity = to_target.normalized() * magnet_speed
			global_position += _velocity * delta

func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	var my_pos := global_position
	var best_dist := magnet_range * magnet_range

	for player in players:
		if not is_instance_valid(player):
			continue
		if player.get("is_dead") == true:
			continue

		var dist_sq = my_pos.distance_squared_to(player.global_position)
		if dist_sq < best_dist:
			best_dist = dist_sq
			_target = player

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_collect(body)

func _collect(collector: Node) -> void:
	# Apply loot effect
	match loot_type:
		Type.XP:
			_give_xp(collector)
		Type.ARTIFACT:
			_give_artifact(collector)
		Type.RESOURCE:
			_give_resource(collector)
		Type.WEAPON:
			_give_weapon(collector)
		Type.SHIP_PART:
			_give_ship_part(collector)

	collected.emit(collector)
	queue_free()

func _despawn() -> void:
	# Fade out and remove
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)

# =============================================================================
# LOOT EFFECTS
# =============================================================================

func _give_xp(collector: Node) -> void:
	var amount: int = loot_data.get("amount", 10)
	if collector.has_method("add_xp"):
		collector.add_xp(amount)

func _give_artifact(collector: Node) -> void:
	var artifact_id: String = loot_data.get("id", "")
	if collector.has_method("add_artifact"):
		collector.add_artifact(artifact_id, loot_data)

func _give_resource(collector: Node) -> void:
	var resource_type: String = loot_data.get("type", "")
	var amount: int = loot_data.get("amount", 1)
	if collector.has_method("add_resource"):
		collector.add_resource(resource_type, amount)

func _give_weapon(collector: Node) -> void:
	var weapon_data: Dictionary = loot_data.get("weapon", {})
	if collector.has_method("add_weapon"):
		collector.add_weapon(weapon_data)

func _give_ship_part(collector: Node) -> void:
	var part_data: Dictionary = loot_data.get("part", {})
	if collector.has_method("add_ship_part"):
		collector.add_ship_part(part_data)

# =============================================================================
# VISUAL SETUP
# =============================================================================

func _setup_visual() -> void:
	if sprite == null:
		return

	match loot_type:
		Type.XP:
			sprite.color = Color(0.2, 0.8, 1.0, 1.0)  # Cyan
			if glow:
				glow.color = Color(0.2, 0.8, 1.0, 0.3)
		Type.ARTIFACT:
			sprite.color = Color(1.0, 0.8, 0.0, 1.0)  # Gold
			if glow:
				glow.color = Color(1.0, 0.8, 0.0, 0.3)
		Type.RESOURCE:
			sprite.color = Color(0.5, 1.0, 0.5, 1.0)  # Green
			if glow:
				glow.color = Color(0.5, 1.0, 0.5, 0.3)
		Type.WEAPON:
			sprite.color = Color(1.0, 0.3, 0.3, 1.0)  # Red
			if glow:
				glow.color = Color(1.0, 0.3, 0.3, 0.3)
		Type.SHIP_PART:
			sprite.color = Color(0.8, 0.4, 1.0, 1.0)  # Purple
			if glow:
				glow.color = Color(0.8, 0.4, 1.0, 0.3)

# =============================================================================
# CONFIGURATION
# =============================================================================

func init(type: Type, data: Dictionary) -> void:
	loot_type = type
	loot_data = data

# =============================================================================
# STATIC FACTORY
# =============================================================================

static func create_xp(amount: int) -> Loot:
	var loot_scene = load("res://scenes/entities/loot/loot.tscn")
	var loot: Loot = loot_scene.instantiate()
	loot.init(Type.XP, {"amount": amount})
	return loot

static func create_artifact(id: String, data: Dictionary = {}) -> Loot:
	var loot_scene = load("res://scenes/entities/loot/loot.tscn")
	var loot: Loot = loot_scene.instantiate()
	data["id"] = id
	loot.init(Type.ARTIFACT, data)
	return loot
