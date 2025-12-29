class_name Projectile
extends Area2D
## Projectile - Individual projectile entity
## Ported from core/projectile/Projectile.as

# =============================================================================
# SIGNALS
# =============================================================================

signal hit(target: Node, damage_obj)  # damage_obj is a Damage instance
signal destroyed

# =============================================================================
# STATE
# =============================================================================

var alive: bool = false
var ttl: float = 0.0
var ttl_max: float = 2000.0

# =============================================================================
# PHYSICS
# =============================================================================

var velocity: Vector2 = Vector2.ZERO
var speed_max: float = 1000.0
var acceleration: float = 0.0
var friction: float = 0.0

# =============================================================================
# COMBAT
# =============================================================================

var damage = null  # Damage object (untyped to avoid loading order issues)
var dmg_radius: int = 0
var number_of_hits: int = 1
var _hits_remaining: int = 1
var debuffs: Array = []  # WeaponDebuff objects

# =============================================================================
# OWNERSHIP
# =============================================================================

var owner_node: Node = null
var weapon_ref = null  # Weapon object

# =============================================================================
# EFFECTS
# =============================================================================

var explosion_effect: String = ""
var explosion_sound: String = ""

# =============================================================================
# WAVE MOTION
# =============================================================================

var wave_enabled: bool = false
var wave_direction: int = 1
var wave_amplitude: float = 50.0
var wave_frequency: float = 5.0
var _wave_time: float = 0.0

# =============================================================================
# VISUAL
# =============================================================================

var sprite_name: String = "proj_blaster"
var _sprite_rotated: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Start inactive
	set_physics_process(false)
	visible = false

func _physics_process(delta: float) -> void:
	if not alive:
		return

	var dt_ms: float = delta * 1000.0

	# Update TTL
	ttl -= dt_ms
	if ttl <= 0:
		destroy(false)
		return

	# Apply acceleration
	if acceleration != 0:
		var accel_vec: Vector2 = Vector2.RIGHT.rotated(rotation) * acceleration
		velocity += accel_vec * delta

	# Apply wave motion
	if wave_enabled:
		_wave_time += delta
		var wave_offset: float = sin(_wave_time * wave_frequency * TAU) * wave_amplitude
		var perpendicular: Vector2 = Vector2.RIGHT.rotated(rotation + PI / 2)
		position += perpendicular * wave_offset * wave_direction * delta

	# Apply friction
	if friction > 0:
		velocity *= (1.0 - friction)

	# Clamp speed
	if speed_max > 0 and velocity.length_squared() > speed_max * speed_max:
		velocity = velocity.normalized() * speed_max

	# Update position
	position += velocity * delta

	# Update rotation to match velocity direction
	if velocity.length_squared() > 1:
		rotation = velocity.angle()

# =============================================================================
# ACTIVATION / POOLING
# =============================================================================

## Activate projectile with given parameters
func activate(data: Dictionary) -> void:
	position = data.get("position", Vector2.ZERO)
	rotation = data.get("rotation", 0.0)
	velocity = data.get("velocity", Vector2.ZERO)
	speed_max = data.get("speed_max", 1000.0)
	acceleration = data.get("acceleration", 0.0)
	ttl = data.get("ttl", 2000.0)
	ttl_max = ttl
	friction = data.get("friction", 0.0)

	damage = data.get("damage", null)
	dmg_radius = data.get("dmg_radius", 0)
	number_of_hits = data.get("number_of_hits", 1)
	_hits_remaining = number_of_hits

	debuffs = data.get("debuffs", [])

	owner_node = data.get("owner", null)
	weapon_ref = data.get("weapon", null)

	explosion_effect = data.get("explosion_effect", "")
	explosion_sound = data.get("explosion_sound", "")

	# Wave motion
	wave_enabled = data.get("wave_enabled", false)
	wave_amplitude = data.get("wave_amplitude", 50.0)
	wave_frequency = data.get("wave_frequency", 5.0)
	wave_direction = 1 if randf() > 0.5 else -1
	_wave_time = 0.0

	# Load sprite from TextureManager
	var new_sprite_name: String = data.get("sprite_name", "proj_blaster")
	if new_sprite_name != sprite_name or sprite.texture == null:
		sprite_name = new_sprite_name
		_load_sprite()

	# Set collision mask based on owner type
	# Player projectiles hit enemies (layer 3 = value 4)
	# Enemy projectiles hit player (layer 2 = value 2)
	var is_enemy: bool = data.get("is_enemy", false)
	if is_enemy:
		collision_mask = 3  # Detect layers 1 and 2 (player)
	else:
		collision_mask = 5  # Detect layers 1 and 3 (enemies)

	# Activate
	alive = true
	visible = true
	set_physics_process(true)

	# Enable collision
	if collision:
		collision.disabled = false

func _load_sprite() -> void:
	if sprite == null:
		return

	# Check if TextureManager is available
	if not TextureManager.is_loaded():
		# Use a placeholder until loaded
		return

	var tex := TextureManager.get_sprite(sprite_name)
	if tex != null:
		sprite.texture = tex

		# Check if sprite is rotated in atlas
		var data = TextureManager.get_sprite_data(sprite_name)
		if data != null and data.rotated:
			_sprite_rotated = true
			sprite.rotation_degrees = -90.0
		else:
			_sprite_rotated = false
			sprite.rotation_degrees = 0.0

## Deactivate and return to pool
func deactivate() -> void:
	alive = false
	visible = false
	set_physics_process(false)

	if collision:
		# Use set_deferred to avoid errors when called during physics callbacks
		collision.set_deferred("disabled", true)

	velocity = Vector2.ZERO
	damage = null
	owner_node = null
	weapon_ref = null
	debuffs.clear()

# =============================================================================
# COLLISION
# =============================================================================

func _on_body_entered(body: Node2D) -> void:
	if not alive:
		return

	# Don't hit owner
	if body == owner_node:
		return

	# Check if target can take damage
	if body.has_method("take_damage"):
		_apply_damage(body)

func _on_area_entered(area: Area2D) -> void:
	if not alive:
		return

	# Don't hit own projectiles or owner
	if area == self or area.get_parent() == owner_node:
		return

	# Check if it's a damageable area
	var parent := area.get_parent()
	if parent and parent.has_method("take_damage"):
		_apply_damage(parent)

func _apply_damage(target: Node) -> void:
	# Apply damage
	if damage != null:
		target.take_damage(damage, owner_node)
		hit.emit(target, damage)
	else:
		# Default damage if none set
		target.take_damage(10.0, owner_node)
		hit.emit(target, null)

	# Apply debuffs
	if target.has_method("apply_debuff"):
		for debuff in debuffs:
			target.apply_debuff(debuff.duplicate())

	# Decrement hits
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		destroy(true)

# =============================================================================
# DESTRUCTION
# =============================================================================

func destroy(with_explosion: bool = true) -> void:
	if not alive:
		return

	alive = false

	# Spawn explosion effect
	if with_explosion and explosion_effect != "":
		# TODO: Spawn particle effect
		pass

	# Play sound
	if with_explosion and explosion_sound != "":
		# TODO: Play sound
		pass

	# Notify weapon
	if weapon_ref:
		weapon_ref.on_projectile_destroyed()

	destroyed.emit()

	# Return to pool (ProjectileManager will handle this)
	deactivate()

# =============================================================================
# UTILITY
# =============================================================================

## Get remaining lifetime as fraction
func get_life_fraction() -> float:
	return clampf(ttl / ttl_max, 0.0, 1.0)
