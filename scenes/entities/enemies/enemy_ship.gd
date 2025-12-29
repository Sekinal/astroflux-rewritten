class_name EnemyShip
extends CharacterBody2D
## EnemyShip - AI-controlled enemy ships
## Ported from core/ship/EnemyShip.as

# =============================================================================
# SIGNALS
# =============================================================================

signal health_changed(current: float, maximum: float)
signal destroyed
signal dropped_loot(items: Array)

# =============================================================================
# AI PROPERTIES
# =============================================================================

@export_group("Appearance")
@export var sprite_name: String = "enemy_blaster_11"  ## Sprite name from texture atlas
@export var animation_frames: int = 4  ## Number of animation frames (0 = no animation)
@export var animation_fps: float = 8.0  ## Animation speed

@export_group("AI Behavior")
@export var aggro_range: float = 400.0  ## Range to detect and chase targets
@export var chase_range: float = 800.0  ## Range before giving up chase
@export var aim_skill: float = 0.8  ## 0-1, lead prediction accuracy
@export var flee_threshold: float = 0.2  ## HP% to start fleeing
@export var flee_duration: float = 5.0  ## How long to flee
@export var can_flee: bool = true
@export var stop_when_close: bool = true  ## Stop moving when close to target
@export var sniper: bool = false  ## Maintain distance from target
@export var sniper_min_range: float = 300.0
@export var always_fire: bool = false  ## Fire even when not chasing

# Orbit behavior (for spawner-bound enemies)
@export_group("Orbit")
@export var orbit_angle: float = 0.0  ## Starting orbit angle
@export var orbit_radius: float = 100.0
@export var angle_velocity: float = 0.5  ## Radians per second

# =============================================================================
# ENGINE PROPERTIES
# =============================================================================

@export_group("Engine")
@export var max_speed: float = 200.0
@export var acceleration: float = 0.4
@export var rotation_speed: float = 120.0
@export var collision_radius: float = 20.0

# =============================================================================
# COMBAT PROPERTIES
# =============================================================================

@export_group("Combat")
@export var hp_max: float = 50.0
@export var shield_max: float = 0.0
@export var shield_regen: float = 0.0
@export var armor_threshold: float = 0.0

## Resistances [kinetic, energy, corrosive]
var resistances: Array[float] = [0.0, 0.0, 0.0]

# =============================================================================
# LOOT
# =============================================================================

@export_group("Loot")
@export var xp_value: int = 10
@export var drop_table: Array[Dictionary] = []  ## [{item: String, chance: float}]

# =============================================================================
# WEAPONS
# =============================================================================

var weapons: Array = []
var _weapon_cooldowns: Array[float] = []

# =============================================================================
# STATE
# =============================================================================

var hp: float = 50.0
var shield: float = 0.0
var is_dead: bool = false
var target: Node = null
var spawner = null  # Reference to spawner (if spawner-bound)

# =============================================================================
# NETWORK (multiplayer-ready)
# =============================================================================

var net_id: int = -1
static var _next_net_id: int = 1000000  # Start at 1M to avoid player ID conflicts

static func _generate_net_id() -> int:
	_next_net_id += 1
	return _next_net_id

# =============================================================================
# DEBUFFS
# =============================================================================

var debuffs: Array = []  # Array of WeaponDebuff objects
var _slow_multiplier: float = 1.0
var _armor_reduction: float = 0.0
var _resist_reduction: Array[float] = [0.0, 0.0, 0.0]  # kinetic, energy, corrosive
var _damage_multiplier: float = 1.0
var _regen_disabled: bool = false

# AI State Machine
var _current_state = null  # AIState instance
var _states: Dictionary = {}  # String -> AIState

# =============================================================================
# MOVEMENT
# =============================================================================

var converger: Converger

# Interpolation state for smooth rendering
var _prev_pos: Vector2 = Vector2.ZERO
var _prev_rotation: float = 0.0
var _current_pos: Vector2 = Vector2.ZERO
var _current_rotation: float = 0.0

# =============================================================================
# ANIMATION STATE
# =============================================================================

var _animation_textures: Array[AtlasTexture] = []
var _animation_frame: int = 0
var _animation_timer: float = 0.0
var _sprite_rotated: bool = false  # True if sprite is rotated in atlas

# =============================================================================
# NODES
# =============================================================================

@onready var sprite: Sprite2D = $Sprite
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $HealthBar

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	net_id = _generate_net_id()
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

	# Initialize AI states
	_init_ai_states()

	# Setup default weapon if none configured
	if weapons.is_empty():
		_setup_default_weapon()

	# Add to enemies group
	add_to_group("enemies")

	# Update health bar
	_update_health_bar()

func _load_sprite() -> void:
	if sprite == null:
		return

	# Check if TextureManager is available
	if not TextureManager.is_loaded():
		await TextureManager.atlases_loaded

	# Load animation frames or single sprite
	if animation_frames > 1:
		# Get base name without frame number
		# Enemy sprites use format like "enemy_blaster_11" (two-digit frames)
		var base_name := sprite_name
		# Remove trailing digits
		while base_name.length() > 0 and base_name[-1].is_valid_int():
			base_name = base_name.left(-1)

		# Try different frame naming conventions
		for i in range(1, animation_frames + 1):
			var frame_names: Array[String] = [
				"%s%d" % [base_name, i],      # enemy_blaster_1
				"%s%02d" % [base_name, i],    # enemy_blaster_01
				"%s%d%d" % [base_name, i, i], # enemy_blaster_11 (some animations)
			]

			for frame_name in frame_names:
				if TextureManager.has_sprite(frame_name):
					var tex := TextureManager.get_sprite(frame_name)
					if tex != null:
						_animation_textures.append(tex)
					break

		if _animation_textures.size() > 0:
			sprite.texture = _animation_textures[0]
			_check_sprite_rotation(sprite_name)
		else:
			# Fallback: just use the sprite_name directly
			var tex := TextureManager.get_sprite(sprite_name)
			if tex != null:
				sprite.texture = tex
				_check_sprite_rotation(sprite_name)
			else:
				push_warning("EnemyShip: Sprite not found: %s" % sprite_name)
	else:
		# Single sprite
		var tex := TextureManager.get_sprite(sprite_name)
		if tex != null:
			sprite.texture = tex
			_check_sprite_rotation(sprite_name)
		else:
			push_warning("EnemyShip: Sprite not found: %s" % sprite_name)

func _check_sprite_rotation(sprite_name_to_check: String) -> void:
	var data = TextureManager.get_sprite_data(sprite_name_to_check)
	if data != null and data.rotated:
		_sprite_rotated = true
		# Compensate for TexturePacker's 90 degree clockwise rotation
		sprite.rotation_degrees = -90.0

func _init_ai_states() -> void:
	# Load state classes (avoid preload for class loading order)
	var AIIdleClass = load("res://scripts/ai/ai_idle.gd")
	var AIChaseClass = load("res://scripts/ai/ai_chase.gd")
	var AIFleeClass = load("res://scripts/ai/ai_flee.gd")
	var AIOrbitClass = load("res://scripts/ai/ai_orbit.gd")

	_states["idle"] = AIIdleClass.new(self, target)
	_states["chase"] = AIChaseClass.new(self, target)
	_states["flee"] = AIFleeClass.new(self, target)
	_states["orbit"] = AIOrbitClass.new(self, target, spawner)

	# Start in idle or orbit state
	if spawner != null:
		_change_state("orbit")
	else:
		_change_state("idle")

func _setup_default_weapon() -> void:
	var WeaponClass = load("res://scripts/combat/weapon.gd")
	var DamageClass = load("res://scripts/combat/damage.gd")

	var weapon = WeaponClass.new()
	weapon.init_from_config({
		"type": "enemy_blaster",
		"damage": 8.0,
		"damageType": DamageClass.Type.ENERGY,
		"reloadTime": 500.0,  # Slower than player
		"speed": 600.0,
		"ttl": 1500,
		"range": 400.0,
		"projectileSprite": "proj_blaster",
		"positionOffsetX": 20.0,
	})
	weapon.set_owner(self)
	weapons.append(weapon)
	_weapon_cooldowns.append(0.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Store previous state for interpolation
	_prev_pos = _current_pos
	_prev_rotation = _current_rotation

	# Execute AI state
	if _current_state != null:
		var next_state: String = _current_state.execute(delta)
		if next_state != "":
			_change_state(next_state)

	# Run physics through converger
	converger.run(NetworkManager.server_time)

	# Store current physics state
	_current_pos = converger.course.pos
	_current_rotation = converger.course.rotation

	# Process debuffs
	_process_debuffs(delta)

	# Regenerate shield (if not disabled)
	if not _regen_disabled:
		_regenerate_shield(delta)

func _process(delta: float) -> void:
	if is_dead:
		return

	# Interpolate visual position between physics frames
	var interp_fraction := Engine.get_physics_interpolation_fraction()
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

# =============================================================================
# AI STATE MACHINE
# =============================================================================

func _change_state(state_name: String) -> void:
	if not _states.has(state_name):
		push_warning("EnemyShip: Unknown state '%s'" % state_name)
		return

	# Exit current state
	if _current_state != null:
		_current_state.exit()

	# Enter new state
	_current_state = _states[state_name]
	_current_state.target = target
	_current_state.enter()

func get_current_state_name() -> String:
	if _current_state != null:
		return _current_state.get_state_name()
	return "none"

# =============================================================================
# WEAPONS
# =============================================================================

func try_fire_weapons() -> void:
	var current_time: float = NetworkManager.server_time

	for i in range(weapons.size()):
		var weapon = weapons[i]
		if weapon.can_fire(current_time):
			# Calculate velocity vector from speed and rotation
			var owner_velocity := Vector2.RIGHT.rotated(converger.course.rotation) * converger.course.speed
			var projectile_data: Array = weapon.fire(
				current_time,
				global_position,
				converger.course.rotation,
				owner_velocity
			)

			# Spawn projectiles through manager
			for data in projectile_data:
				# Mark as enemy projectile
				data["is_enemy"] = true
				ProjectileManager.spawn(data)

func stop_shooting() -> void:
	# Reset weapon states if needed
	pass

# =============================================================================
# COMBAT
# =============================================================================

func take_damage(dmg: Variant, attacker: Node = null) -> void:
	if is_dead:
		return

	var damage_amount: float = 0.0

	# Calculate effective resistances (base - debuff reductions)
	var effective_resist: Array[float] = [
		maxf(0.0, resistances[0] - _resist_reduction[0]),
		maxf(0.0, resistances[1] - _resist_reduction[1]),
		maxf(0.0, resistances[2] - _resist_reduction[2]),
	]

	# Handle both Damage object and raw float (duck typing)
	if dmg != null and dmg is Object and dmg.has_method("calculate_resisted"):
		damage_amount = dmg.calculate_resisted(effective_resist)
		# Apply armor reduction bonus damage
		if _armor_reduction > 0 and damage_amount > 0:
			var bonus := minf(_armor_reduction * 0.5, 50.0) / 100.0  # Up to 50% bonus damage
			damage_amount *= (1.0 + bonus)
	elif dmg is float or dmg is int:
		damage_amount = float(dmg)
	else:
		damage_amount = 10.0

	# Apply to shield first
	if shield > 0:
		var shield_damage := minf(damage_amount, shield)
		shield -= shield_damage
		damage_amount -= shield_damage

	# Remaining damage to health
	if damage_amount > 0:
		hp -= damage_amount
		health_changed.emit(hp, hp_max)
		_update_health_bar()

		# Visual feedback
		_flash_damage()
		_spawn_damage_number(damage_amount)

		# Set attacker as target if we don't have one
		if target == null and attacker != null:
			target = attacker
			if _current_state != null:
				_current_state.target = attacker

		if hp <= 0:
			_die()

func _flash_damage() -> void:
	if sprite:
		var original_modulate: Color = sprite.modulate
		sprite.modulate = Color.RED

		await get_tree().create_timer(0.1).timeout

		if is_instance_valid(sprite):
			sprite.modulate = original_modulate

func _spawn_damage_number(amount: float) -> void:
	var label := Label.new()
	label.text = str(int(amount))
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color.ORANGE
	label.position = Vector2(-15, -40)
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)

func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = hp_max
		health_bar.value = hp

func _regenerate_shield(delta: float) -> void:
	if shield < shield_max and shield_regen > 0:
		shield = minf(shield + shield_regen * delta, shield_max)

func _die() -> void:
	is_dead = true
	destroyed.emit()

	# Generate and drop loot
	var loot := _generate_loot()
	if loot.size() > 0:
		dropped_loot.emit(loot)
		# Spawn loot through manager
		LootManager.spawn_loot(global_position, loot)

	# Notify spawner
	if spawner != null and spawner.has_method("on_enemy_died"):
		spawner.on_enemy_died(self)

	# Remove from scene
	queue_free()

func _generate_loot() -> Array:
	var loot: Array = []

	# Always drop XP
	loot.append({"type": "xp", "amount": xp_value})

	# Check drop table
	for drop in drop_table:
		var roll := randf()
		if roll <= drop.get("chance", 0.0):
			loot.append(drop.get("item", {}))

	return loot

# =============================================================================
# DEBUFFS
# =============================================================================

# Preload WeaponDebuff for type checking
const WeaponDebuffClass = preload("res://scripts/combat/weapon_debuff.gd")

## Apply a debuff to this enemy
func apply_debuff(debuff: Variant) -> void:
	if debuff == null:
		return

	# Check for existing debuff of same type to stack
	for existing in debuffs:
		if existing.type == debuff.type:
			existing.try_stack()
			return

	# New debuff
	debuff.source_net_id = debuff.source_net_id if debuff.get("source_net_id") else -1
	debuffs.append(debuff)

## Process all active debuffs (called from _physics_process)
func _process_debuffs(delta: float) -> void:
	if debuffs.is_empty():
		_reset_debuff_effects()
		return

	var total_dot_damage: float = 0.0
	var expired: Array = []

	# Reset effect accumulators
	_slow_multiplier = 1.0
	_armor_reduction = 0.0
	_resist_reduction = [0.0, 0.0, 0.0]
	_damage_multiplier = 1.0
	_regen_disabled = false

	for debuff in debuffs:
		# Update debuff timer and get tick damage
		var tick_damage: float = debuff.update(delta, self)
		total_dot_damage += tick_damage

		# Accumulate effects based on type
		match debuff.type:
			WeaponDebuffClass.Type.SLOW_DOWN:
				_slow_multiplier = minf(_slow_multiplier, debuff.get_slow_multiplier())
			WeaponDebuffClass.Type.REDUCE_ARMOR:
				_armor_reduction += debuff.get_armor_reduction()
			WeaponDebuffClass.Type.REDUCED_KINETIC_RESIST:
				_resist_reduction[0] += debuff.get_resist_reduction()
			WeaponDebuffClass.Type.REDUCED_ENERGY_RESIST:
				_resist_reduction[1] += debuff.get_resist_reduction()
			WeaponDebuffClass.Type.REDUCED_CORROSIVE_RESIST:
				_resist_reduction[2] += debuff.get_resist_reduction()
			WeaponDebuffClass.Type.REDUCED_DAMAGE:
				_damage_multiplier = minf(_damage_multiplier, debuff.get_damage_multiplier())
			WeaponDebuffClass.Type.DISABLE_REGEN:
				_regen_disabled = true

		# Mark expired debuffs
		if debuff.is_expired():
			expired.append(debuff)

	# Apply DOT damage
	if total_dot_damage > 0 and not is_dead:
		hp -= total_dot_damage
		health_changed.emit(hp, hp_max)
		_update_health_bar()
		_spawn_damage_number(total_dot_damage)
		if hp <= 0:
			_die()

	# Remove expired debuffs
	for debuff in expired:
		debuffs.erase(debuff)

func _reset_debuff_effects() -> void:
	_slow_multiplier = 1.0
	_armor_reduction = 0.0
	_resist_reduction = [0.0, 0.0, 0.0]
	_damage_multiplier = 1.0
	_regen_disabled = false

func remove_debuff(debuff_type: int) -> void:
	for i in range(debuffs.size() - 1, -1, -1):
		if debuffs[i].type == debuff_type:
			debuffs.remove_at(i)

func clear_debuffs() -> void:
	debuffs.clear()
	_reset_debuff_effects()

# =============================================================================
# SHIP PROPERTY ACCESSORS (used by Converger)
# =============================================================================

func is_enemy() -> bool:
	return true

func get_rotation_speed() -> float:
	return rotation_speed

func get_acceleration() -> float:
	return acceleration

func get_max_speed() -> float:
	return max_speed

func is_using_boost() -> bool:
	return false

func get_boost_bonus() -> float:
	return 0.0

func is_slowed(_server_time: float) -> bool:
	return _slow_multiplier < 1.0

func get_slowdown() -> float:
	return 1.0 - _slow_multiplier  # Convert multiplier to slowdown value

# =============================================================================
# CONFIGURATION
# =============================================================================

func init_from_config(config: Dictionary) -> void:
	# Appearance
	if config.has("spriteName"):
		sprite_name = config.get("spriteName")
	if config.has("animationFrames"):
		animation_frames = config.get("animationFrames")

	# AI
	aggro_range = config.get("aggroRange", aggro_range)
	chase_range = config.get("chaseRange", chase_range)
	aim_skill = config.get("aimSkill", aim_skill)
	flee_threshold = config.get("fleeThreshold", flee_threshold)
	can_flee = config.get("canFlee", can_flee)
	stop_when_close = config.get("stopWhenClose", stop_when_close)
	sniper = config.get("sniper", sniper)
	sniper_min_range = config.get("sniperMinRange", sniper_min_range)
	always_fire = config.get("alwaysFire", always_fire)

	# Orbit
	orbit_angle = config.get("orbitAngle", orbit_angle)
	orbit_radius = config.get("orbitRadius", orbit_radius)
	angle_velocity = config.get("angleVelocity", angle_velocity)

	# Engine
	max_speed = config.get("maxSpeed", max_speed)
	acceleration = config.get("acceleration", acceleration)
	rotation_speed = config.get("rotationSpeed", rotation_speed)
	collision_radius = config.get("collisionRadius", collision_radius)

	# Combat
	hp_max = config.get("hpMax", hp_max)
	hp = hp_max
	shield_max = config.get("shieldMax", shield_max)
	shield = shield_max
	shield_regen = config.get("shieldRegen", shield_regen)

	# Resistances
	if config.has("resistances"):
		resistances = config.get("resistances")

	# Loot
	xp_value = config.get("xpValue", xp_value)
	if config.has("dropTable"):
		drop_table = config.get("dropTable")

func set_spawner(spawner_ref) -> void:
	spawner = spawner_ref
	# Update orbit state with spawner reference
	if _states.has("orbit"):
		_states["orbit"].spawner = spawner_ref
	# Switch to orbit if we have a spawner
	if spawner != null and _current_state != null:
		_change_state("orbit")
