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
# HEAT/ENERGY SYSTEM
# =============================================================================

var heat: Heat = null  ## Heat/energy system for weapons

# =============================================================================
# STATE
# =============================================================================

var hp: float = 100.0
var shield: float = 100.0
var is_dead: bool = false
var _using_boost: bool = false

# =============================================================================
# DEBUFFS (multiplayer-ready)
# =============================================================================

var debuffs: Array[WeaponDebuff] = []
var net_id: int = -1  # For multiplayer entity identification

# Cached debuff effects (recalculated each frame)
var _slow_multiplier: float = 1.0
var _armor_reduction: float = 0.0
var _resist_reduction: Array[float] = [0.0, 0.0, 0.0]  # kinetic, energy, corrosive
var _damage_multiplier: float = 1.0
var _regen_disabled: bool = false
var _heal_disabled: bool = false

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

	# Initialize heat system
	heat = Heat.new()

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

	# Weapon 1: Basic Blaster
	var blaster = WeaponClass.new()
	blaster.init_from_config({
		"type": "blaster",
		"damage": 15.0,
		"damageType": DamageClass.Type.ENERGY,
		"reloadTime": 150.0,
		"speed": 800.0,
		"ttl": 1500,
		"range": 600.0,
		"projectileSprite": "proj_blaster",
		"positionOffsetX": 30.0,
		"heatCost": 0.05,
	})
	blaster.set_owner(self)
	weapons.append(blaster)

	# Weapon 2: Homing Missile
	var missile = WeaponClass.new()
	missile.init_from_config({
		"type": "missile",
		"damage": 25.0,
		"damageType": DamageClass.Type.KINETIC,
		"reloadTime": 800.0,
		"speed": 400.0,
		"acceleration": 200.0,
		"ttl": 3000,
		"range": 800.0,
		"projectileSprite": "proj_delayed_missile",
		"positionOffsetX": 25.0,
		"heatCost": 0.15,
		"ai": "homingMissile",
		"rotationSpeed": 3.5,
	})
	missile.set_owner(self)
	weapons.append(missile)

	# Weapon 3: Boomerang
	var boomerang = WeaponClass.new()
	boomerang.init_from_config({
		"type": "boomerang",
		"damage": 20.0,
		"damageType": DamageClass.Type.ENERGY,
		"reloadTime": 600.0,
		"speed": 600.0,
		"ttl": 4000,
		"range": 500.0,
		"projectileSprite": "proj_boomerang",
		"positionOffsetX": 30.0,
		"heatCost": 0.10,
		"ai": "boomerang",
		"boomerangReturnTime": 800.0,
		"rotationSpeed": 4.0,
	})
	boomerang.set_owner(self)
	weapons.append(boomerang)

	# Weapon 4: Cluster Bomb
	var cluster = WeaponClass.new()
	cluster.init_from_config({
		"type": "cluster",
		"damage": 10.0,
		"damageType": DamageClass.Type.CORROSIVE,
		"reloadTime": 1200.0,
		"speed": 500.0,
		"ttl": 800,
		"range": 400.0,
		"projectileSprite": "proj_agent_bomb",
		"positionOffsetX": 25.0,
		"heatCost": 0.20,
		"ai": "cluster",
		"clusterNrOfProjectiles": 5,
		"clusterAngle": 20.0,
		"clusterNrOfSplits": 1,
	})
	cluster.set_owner(self)
	weapons.append(cluster)

	# Weapon 5: Beam
	var BeamWeaponClass = preload("res://scripts/combat/weapons/beam_weapon.gd")
	var beam = BeamWeaponClass.new()
	beam.init_from_config({
		"type": "beam",
		"damage": 3.0,  # Per tick
		"damageType": DamageClass.Type.ENERGY,
		"reloadTime": 50.0,  # Fast ticks
		"range": 600.0,
		"beamThickness": 3.0,
		"beamAmplitude": 2.0,
		"beamNodes": 8,
		"beamAlpha": 0.9,
		"nrTargets": 1,
		"heatCost": 0.001,  # Low per-tick cost
		"positionOffsetX": 30.0,
	})
	beam.set_owner(self)
	weapons.append(beam)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Handle input
	_process_input()

	# Process active debuffs
	_process_debuffs(delta)

	# Update heat system
	if heat != null:
		heat.update(NetworkManager.server_time)

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

	# Regenerate shield (if not disabled by debuff)
	if not _regen_disabled:
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

	# Weapon switching with number keys
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"):
		switch_weapon(2)
	elif Input.is_action_just_pressed("weapon_4"):
		switch_weapon(3)
	elif Input.is_action_just_pressed("weapon_5"):
		switch_weapon(4)

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
	var was_firing := _is_firing
	_is_firing = firing
	if _is_firing:
		_try_fire_weapon()
	elif was_firing and not _is_firing:
		# Fire button released - stop beam weapons
		_on_stop_firing()

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

# Beam visual
var _beam_line: Line2D = null

func _try_fire_weapon() -> void:
	if weapons.is_empty():
		return

	var weapon = weapons[active_weapon_index]
	var current_time: float = NetworkManager.server_time

	# Check heat first - can't fire if locked out or not enough energy
	if heat != null:
		if heat.is_locked_out(current_time):
			_stop_beam_if_active(weapon)
			return
		if not heat.can_fire(weapon.heat_cost, _using_boost, 0.5):
			_stop_beam_if_active(weapon)
			return

	# Check if this is a beam weapon (has is_firing method)
	if weapon.has_method("is_firing"):
		_fire_beam_weapon(weapon, current_time)
	elif weapon.can_fire(current_time):
		_fire_projectile_weapon(weapon, current_time)

func _fire_projectile_weapon(weapon, current_time: float) -> void:
	# Calculate velocity vector from speed and rotation
	var owner_velocity := Vector2.RIGHT.rotated(converger.course.rotation) * converger.course.speed
	var projectile_data: Array = weapon.fire(
		current_time,
		global_position,
		rotation,
		owner_velocity
	)

	# Spawn projectiles through manager
	for data in projectile_data:
		ProjectileManager.spawn(data)

	# Spawn muzzle flash effect at fire position
	if projectile_data.size() > 0:
		var fire_pos: Vector2 = projectile_data[0].get("position", global_position)
		var fire_angle: float = projectile_data[0].get("rotation", rotation)
		var flash_color: Color = _get_weapon_flash_color(weapon)
		EffectManager.spawn_muzzle_flash(fire_pos, fire_angle, flash_color)

		# Play weapon fire sound based on weapon type
		_play_weapon_sound(weapon)

		# Consume heat when firing
		if heat != null:
			heat.consume(weapon.heat_cost)

func _play_weapon_sound(weapon) -> void:
	var ai_type: String = weapon.ai_type if "ai_type" in weapon else ""
	match ai_type:
		"homingMissile":
			SoundManager.play_missile()
		_:
			# Default laser sound for projectile weapons
			SoundManager.play_laser()

func _get_weapon_flash_color(weapon) -> Color:
	if weapon.dmg == null:
		return Color.WHITE
	var dmg_type: int = weapon.dmg.type() if weapon.dmg.has_method("type") else 0
	match dmg_type:
		0:  # KINETIC
			return Color(1.0, 0.9, 0.6)
		1:  # ENERGY
			return Color(0.4, 0.7, 1.0)
		2:  # CORROSIVE
			return Color(0.4, 1.0, 0.4)
		_:
			return Color.WHITE

func _fire_beam_weapon(weapon, current_time: float) -> void:
	# Start firing if not already
	if not weapon.is_firing():
		weapon.start_fire()
		_create_beam_line()

	# Update beam each frame
	var result: Dictionary = weapon.update(
		Engine.get_physics_interpolation_fraction(),
		current_time,
		global_position,
		rotation
	)

	# Update beam visual
	if result.firing and _beam_line != null:
		_update_beam_visual(result.start_pos, result.end_pos, weapon)

	# Apply heat cost per tick
	if result.targets_hit.size() > 0:
		if heat != null:
			heat.consume(weapon.heat_cost)

func _stop_beam_if_active(weapon) -> void:
	if weapon.has_method("is_firing") and weapon.is_firing():
		weapon.stop_fire()
		_hide_beam_line()

func _on_stop_firing() -> void:
	# Called when fire button released
	var weapon = get_active_weapon()
	if weapon and weapon.has_method("is_firing"):
		weapon.stop_fire()
		_hide_beam_line()

func _create_beam_line() -> void:
	if _beam_line == null:
		_beam_line = Line2D.new()
		_beam_line.width = 3.0
		_beam_line.default_color = Color(1.0, 0.3, 0.3, 0.9)
		_beam_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_beam_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		_beam_line.top_level = true  # Don't inherit parent transform
		_beam_line.z_index = 10  # Render above other objects
		add_child(_beam_line)
	_beam_line.visible = true

func _hide_beam_line() -> void:
	if _beam_line != null:
		_beam_line.visible = false

func _update_beam_visual(start_pos: Vector2, end_pos: Vector2, weapon) -> void:
	if _beam_line == null:
		return

	# Get visual data from weapon
	var visual: Dictionary = weapon.get_beam_visual_data(start_pos, end_pos)

	# Update line properties
	_beam_line.width = visual.thickness
	_beam_line.default_color = visual.color
	_beam_line.default_color.a = visual.alpha

	# Generate beam points with slight waviness
	var points: PackedVector2Array = []
	var direction := (end_pos - start_pos).normalized()
	var length := start_pos.distance_to(end_pos)
	var segments: int = visual.nodes

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var point := start_pos.lerp(end_pos, t)

		# Add waviness (except for endpoints)
		if i > 0 and i < segments:
			var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
			var wave: float = sin(t * PI * 4 + NetworkManager.server_time * 0.01) * visual.amplitude
			point += perpendicular * wave

		points.append(point)

	_beam_line.points = points

func get_active_weapon() -> Variant:
	if weapons.is_empty():
		return null
	return weapons[active_weapon_index]

func switch_weapon(index: int) -> void:
	if index >= 0 and index < weapons.size():
		# Stop beam if switching away from beam weapon
		var current_weapon = get_active_weapon()
		if current_weapon and current_weapon.has_method("is_firing"):
			current_weapon.stop_fire()
			_hide_beam_line()
		active_weapon_index = index

# =============================================================================
# COMBAT
# =============================================================================

func take_damage(dmg: Variant, attacker: Node = null, apply_debuffs: bool = true) -> void:
	if is_dead:
		return

	var damage_amount: float = 0.0
	var weapon_debuffs: Array = []

	# Handle both Damage object and raw float (duck typing)
	if dmg != null and dmg is Object and dmg.has_method("calculate_resisted"):
		# Use effective resistances (after debuff reductions)
		var effective_resist := get_effective_resistances()
		damage_amount = dmg.calculate_resisted(effective_resist)

		# Apply armor reduction bonus (negative armor = bonus damage)
		var armor := get_armor_after_debuffs()
		if armor < 0:
			# Negative armor gives up to 50% bonus damage
			var bonus := minf(0.5, absf(armor) / 100.0)
			damage_amount *= (1.0 + bonus)

		# Get debuffs from damage object if available
		if apply_debuffs and dmg.has_method("get_debuffs"):
			weapon_debuffs = dmg.get_debuffs()
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

		# Camera shake on damage
		EffectManager.shake_on_damage(damage_amount, hp_max)

		if hp <= 0:
			_die()

	# Apply debuffs from the weapon
	for debuff_data in weapon_debuffs:
		if debuff_data is WeaponDebuff:
			apply_debuff(debuff_data)

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

func is_slowed(_server_time: float) -> bool:
	return _slow_multiplier < 1.0

func get_slowdown() -> float:
	return 1.0 - _slow_multiplier

# =============================================================================
# DEBUFF SYSTEM
# =============================================================================

func _process_debuffs(delta: float) -> void:
	## Process all active debuffs and update cached effects

	# Reset cached effects
	_slow_multiplier = 1.0
	_armor_reduction = 0.0
	_resist_reduction = [0.0, 0.0, 0.0]
	_damage_multiplier = 1.0
	_regen_disabled = false
	_heal_disabled = false

	var total_dot_damage := 0.0
	var expired_indices: Array[int] = []

	# Process each debuff
	for i in range(debuffs.size()):
		var debuff := debuffs[i]

		# Update debuff and get DOT damage
		var dot_damage := debuff.update(delta, self)
		total_dot_damage += dot_damage

		# Accumulate effects
		match debuff.type:
			WeaponDebuff.Type.SLOW_DOWN:
				_slow_multiplier = minf(_slow_multiplier, debuff.get_slow_multiplier())
			WeaponDebuff.Type.REDUCE_ARMOR:
				_armor_reduction += debuff.get_armor_reduction()
			WeaponDebuff.Type.REDUCED_KINETIC_RESIST:
				_resist_reduction[0] += debuff.get_resist_reduction()
			WeaponDebuff.Type.REDUCED_ENERGY_RESIST:
				_resist_reduction[1] += debuff.get_resist_reduction()
			WeaponDebuff.Type.REDUCED_CORROSIVE_RESIST:
				_resist_reduction[2] += debuff.get_resist_reduction()
			WeaponDebuff.Type.REDUCED_DAMAGE:
				_damage_multiplier *= debuff.get_damage_multiplier()
			WeaponDebuff.Type.DISABLE_REGEN:
				_regen_disabled = debuff.disables_regen() or _regen_disabled
			WeaponDebuff.Type.DISABLE_HEAL:
				_heal_disabled = debuff.disables_heal() or _heal_disabled

		# Mark expired
		if debuff.is_expired():
			expired_indices.append(i)

	# Remove expired debuffs (reverse order to maintain indices)
	for i in range(expired_indices.size() - 1, -1, -1):
		debuffs.remove_at(expired_indices[i])

	# Apply DOT damage
	if total_dot_damage > 0:
		_apply_dot_damage(total_dot_damage)

func _apply_dot_damage(amount: float) -> void:
	## Apply DOT damage directly to health (bypasses shield)
	if _heal_disabled and amount < 0:
		return  # Can't heal while heal disabled

	hp -= amount
	health_changed.emit(hp, hp_max)

	if hp <= 0:
		_die()

func apply_debuff(debuff: WeaponDebuff) -> void:
	## Apply a debuff to this ship (multiplayer-ready)
	## In multiplayer, this should be called via server message

	# Check for existing debuff of same type to stack
	for existing in debuffs:
		if existing.type == debuff.type:
			existing.try_stack()
			return

	# Add new debuff
	debuffs.append(debuff)

func remove_debuff(debuff_net_id: int) -> void:
	## Remove a debuff by network ID
	for i in range(debuffs.size()):
		if debuffs[i].net_id == debuff_net_id:
			debuffs.remove_at(i)
			return

func clear_debuffs() -> void:
	## Clear all debuffs (e.g., on respawn)
	debuffs.clear()

func get_effective_resistances() -> Array[float]:
	## Get resistances after debuff reductions
	return [
		maxf(0.0, resistances[0] - _resist_reduction[0]),
		maxf(0.0, resistances[1] - _resist_reduction[1]),
		maxf(0.0, resistances[2] - _resist_reduction[2])
	]

func get_armor_after_debuffs() -> float:
	## Get armor after reduction (can go negative for bonus damage)
	return armor_threshold - _armor_reduction

# =============================================================================
# NETWORK SYNC (multiplayer-ready)
# =============================================================================

func to_sync_data() -> Dictionary:
	## Serialize state for network sync
	return {
		"net_id": net_id,
		"pos": [global_position.x, global_position.y],
		"rot": rotation,
		"hp": hp,
		"shield": shield,
		"debuffs": debuffs.map(func(d): return d.to_array())
	}

func from_sync_data(data: Dictionary) -> void:
	## Apply state from network sync
	if data.has("pos"):
		global_position = Vector2(data.pos[0], data.pos[1])
	if data.has("rot"):
		rotation = data.rot
	if data.has("hp"):
		hp = data.hp
		health_changed.emit(hp, hp_max)
	if data.has("shield"):
		shield = data.shield
		shield_changed.emit(shield, shield_max)
	if data.has("debuffs"):
		debuffs.clear()
		for d_arr in data.debuffs:
			debuffs.append(WeaponDebuff.from_array(d_arr))
