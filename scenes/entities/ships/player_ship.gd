class_name PlayerShip
extends CharacterBody2D
## PlayerShip - The player's controllable ship
## Ported from core/ship/PlayerShip.as

# =============================================================================
# SIGNALS
# =============================================================================

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal died

# =============================================================================
# APPEARANCE
# =============================================================================

@export_group("Appearance")
@export var sprite_name: String = "c-2-1"  ## Sprite name from texture atlas (e.g. c-2, c-18, c-30)
@export var animation_frames: int = 4  ## Number of animation frames
@export var animation_fps: float = 8.0  ## Animation speed

# =============================================================================
# ENGINE PROPERTIES
# =============================================================================

@export_group("Engine")
@export var max_speed: float = 300.0
@export var acceleration: float = 0.5
@export var rotation_speed: float = 180.0
@export var boost_bonus: float = 50.0

# =============================================================================
# COMBAT PROPERTIES
# =============================================================================

@export_group("Combat")
@export var hp_max: float = 100.0
@export var shield_max: float = 100.0
@export var shield_regen: float = 5.0
@export var armor_threshold: float = 50.0

## Resistances [kinetic, energy, corrosive]
var resistances: Array[float] = [0.0, 0.0, 0.0]

# =============================================================================
# WEAPONS
# =============================================================================

# Use untyped array to avoid class loading order issues
var weapons: Array = []
var active_weapon_index: int = 0
var _is_firing: bool = false

# =============================================================================
# STATE
# =============================================================================

var hp: float = 100.0
var shield: float = 100.0
var is_dead: bool = false
var _using_boost: bool = false
var _slowed_until: float = 0.0
var _slowdown_amount: float = 0.0

# =============================================================================
# MOVEMENT
# =============================================================================

var converger: Converger
var _last_command_time: float = 0.0
var _pending_commands: Array[Dictionary] = []

# Interpolation state for smooth rendering
var _prev_pos: Vector2 = Vector2.ZERO
var _prev_rotation: float = 0.0
var _current_pos: Vector2 = Vector2.ZERO
var _current_rotation: float = 0.0

# Animation state
var _animation_textures: Array[AtlasTexture] = []
var _animation_frame: int = 0
var _animation_timer: float = 0.0
var _sprite_rotated: bool = false

# =============================================================================
# NODES
# =============================================================================

@onready var sprite: Sprite2D = $Sprite
@onready var engine_glow: Sprite2D = $EngineGlow
@onready var collision: CollisionShape2D = $CollisionShape2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	converger = Converger.new(self)
	hp = hp_max
	shield = shield_max

	# Initialize converger position from spawn position
	converger.course.pos = global_position
	converger.course.rotation = rotation

	# Initialize interpolation state
	_prev_pos = global_position
	_current_pos = global_position
	_prev_rotation = rotation
	_current_rotation = rotation

	# Load sprite from TextureManager
	_load_sprite()

	# Create default weapon
	_setup_default_weapon()

	# Register message handlers
	NetworkManager.add_message_handler("playerCourse", _on_player_course)

	# Add to player group for AI targeting
	add_to_group("player")

func _load_sprite() -> void:
	if sprite == null:
		return

	# Check if TextureManager is available
	if not TextureManager.is_loaded():
		await TextureManager.atlases_loaded

	# Load animation frames (player ships have 4 frames)
	if animation_frames > 1:
		# Get base name without frame number (e.g., "c-2" from "c-2-1")
		var base_name := sprite_name
		var last_dash := base_name.rfind("-")
		if last_dash > 0 and base_name.substr(last_dash + 1).is_valid_int():
			base_name = base_name.left(last_dash)

		# Player ship frame format is "c-X-1", "c-X-2", etc.
		for i in range(1, animation_frames + 1):
			var frame_name := "%s-%d" % [base_name, i]
			if TextureManager.has_sprite(frame_name):
				var tex := TextureManager.get_sprite(frame_name)
				if tex != null:
					_animation_textures.append(tex)

		if _animation_textures.size() > 0:
			sprite.texture = _animation_textures[0]
			_check_sprite_rotation("%s-1" % base_name)
		else:
			push_warning("PlayerShip: No animation frames found for %s" % base_name)
	else:
		var tex := TextureManager.get_sprite(sprite_name)
		if tex != null:
			sprite.texture = tex
			_check_sprite_rotation(sprite_name)
		else:
			push_warning("PlayerShip: Sprite not found: %s" % sprite_name)

func _check_sprite_rotation(sprite_name_to_check: String) -> void:
	var data = TextureManager.get_sprite_data(sprite_name_to_check)
	if data != null and data.rotated:
		_sprite_rotated = true
		sprite.rotation_degrees = -90.0

func _setup_default_weapon() -> void:
	var WeaponClass = preload("res://scripts/combat/weapon.gd")
	var DamageClass = preload("res://scripts/combat/damage.gd")

	var weapon = WeaponClass.new()
	weapon.init_from_config({
		"type": "blaster",
		"damage": 15.0,
		"damageType": DamageClass.Type.ENERGY,
		"reloadTime": 150.0,
		"speed": 800.0,
		"ttl": 1500,
		"range": 600.0,
		"projectileSprite": "proj_blaster",
		"positionOffsetX": 30.0,
	})
	weapon.set_owner(self)
	weapons.append(weapon)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Handle input
	_process_input()

	# Store previous state for interpolation
	_prev_pos = _current_pos
	_prev_rotation = _current_rotation

	# Run physics through converger
	converger.run(NetworkManager.server_time)

	# Store current physics state
	_current_pos = converger.course.pos
	_current_rotation = converger.course.rotation

	# Update engine glow visibility
	if engine_glow:
		engine_glow.visible = converger.course.accelerate

	# Regenerate shield
	_regenerate_shield(delta)

func _process(delta: float) -> void:
	if is_dead:
		return

	# Interpolate visual position between physics frames for smooth rendering
	var physics_fps := float(Engine.physics_ticks_per_second)
	var interp_fraction := Engine.get_physics_interpolation_fraction()

	# Lerp position and rotation
	global_position = _prev_pos.lerp(_current_pos, interp_fraction)
	rotation = lerp_angle(_prev_rotation, _current_rotation, interp_fraction)

	# Update animation
	if _animation_textures.size() > 1 and sprite != null:
		_animation_timer += delta
		var frame_duration := 1.0 / animation_fps
		if _animation_timer >= frame_duration:
			_animation_timer -= frame_duration
			_animation_frame = (_animation_frame + 1) % _animation_textures.size()
			sprite.texture = _animation_textures[_animation_frame]

func _process_input() -> void:
	var heading := converger.course

	# Get input state
	var accelerating := Input.is_action_pressed("accelerate")
	var braking := Input.is_action_pressed("brake")
	var rotating_left := Input.is_action_pressed("rotate_left")
	var rotating_right := Input.is_action_pressed("rotate_right")
	var boosting := Input.is_action_pressed("boost")
	var firing := Input.is_action_pressed("fire")

	# Check for state changes
	var changed := false

	if heading.accelerate != accelerating:
		heading.accelerate = accelerating
		changed = true
	if heading.deaccelerate != braking:
		heading.deaccelerate = braking
		changed = true
	if heading.rotate_left != rotating_left:
		heading.rotate_left = rotating_left
		changed = true
	if heading.rotate_right != rotating_right:
		heading.rotate_right = rotating_right
		changed = true
	if _using_boost != boosting:
		_using_boost = boosting
		changed = true

	# Send command to server if changed
	if changed:
		_send_movement_command()

	# Handle weapon firing
	_is_firing = firing
	if _is_firing:
		_try_fire_weapon()

func _send_movement_command() -> void:
	var heading := converger.course
	var msg := Message.new("playerCourse")
	heading.time = NetworkManager.server_time
	heading.populate_message(msg)
	NetworkManager.send_message(msg)

# =============================================================================
# NETWORK HANDLERS
# =============================================================================

func _on_player_course(msg: Message) -> void:
	# First arg is player ID
	var player_id := msg.get_string(0)

	# Check if this is for us
	if player_id != LocalServer.player_id:
		return

	# Parse heading starting at index 1
	var new_heading := Heading.new()
	new_heading.parse_message(msg, 1)

	# Set as converge target for smooth interpolation
	converger.set_converge_target(new_heading, NetworkManager.server_time)

# =============================================================================
# WEAPONS
# =============================================================================

func _try_fire_weapon() -> void:
	if weapons.is_empty():
		return

	var weapon = weapons[active_weapon_index]
	var current_time: float = NetworkManager.server_time

	if weapon.can_fire(current_time):
		var projectile_data: Array = weapon.fire(
			current_time,
			global_position,
			rotation,
			converger.course.speed
		)

		# Spawn projectiles through manager
		for data in projectile_data:
			ProjectileManager.spawn(data)

func get_active_weapon() -> Variant:
	if weapons.is_empty():
		return null
	return weapons[active_weapon_index]

func switch_weapon(index: int) -> void:
	if index >= 0 and index < weapons.size():
		active_weapon_index = index

# =============================================================================
# COMBAT
# =============================================================================

func take_damage(dmg: Variant, attacker: Node = null) -> void:
	if is_dead:
		return

	var damage_amount: float = 0.0

	# Handle both Damage object and raw float (duck typing)
	if dmg != null and dmg is Object and dmg.has_method("calculate_resisted"):
		damage_amount = dmg.calculate_resisted(resistances)
	elif dmg is float or dmg is int:
		damage_amount = float(dmg)
	else:
		damage_amount = 10.0  # Default damage

	# Apply to shield first
	if shield > 0:
		var shield_damage := minf(damage_amount, shield)
		shield -= shield_damage
		damage_amount -= shield_damage
		shield_changed.emit(shield, shield_max)

	# Remaining damage to health
	if damage_amount > 0:
		hp -= damage_amount
		health_changed.emit(hp, hp_max)

		if hp <= 0:
			_die()

func _die() -> void:
	is_dead = true
	died.emit()
	# TODO: Play death effects, respawn timer

func _regenerate_shield(delta: float) -> void:
	if shield < shield_max:
		shield = minf(shield + shield_regen * delta, shield_max)
		# Only emit if changed significantly
		if int(shield) != int(shield - shield_regen * delta):
			shield_changed.emit(shield, shield_max)

# =============================================================================
# SHIP PROPERTY ACCESSORS (used by Converger)
# =============================================================================

func is_enemy() -> bool:
	return false

func get_rotation_speed() -> float:
	return rotation_speed

func get_acceleration() -> float:
	return acceleration

func get_max_speed() -> float:
	return max_speed

func is_using_boost() -> bool:
	return _using_boost

func get_boost_bonus() -> float:
	return boost_bonus

func is_slowed(server_time: float) -> bool:
	return _slowed_until > server_time

func get_slowdown() -> float:
	return _slowdown_amount
