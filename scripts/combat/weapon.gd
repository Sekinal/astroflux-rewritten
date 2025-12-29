class_name Weapon
extends RefCounted
## Weapon - Base class for all weapons
## Ported from core/weapon/Weapon.as

# =============================================================================
# SIGNALS
# =============================================================================

signal fired(projectile_data: Dictionary)
signal reload_complete

# =============================================================================
# IDENTIFICATION
# =============================================================================

var weapon_type: String = ""
var weapon_id: String = ""
var level: int = 1
var elite_level: int = 0

# =============================================================================
# DAMAGE
# =============================================================================

# Use untyped to avoid class loading order issues
var dmg = null  # Damage object
var debuffs: Array = []  # WeaponDebuff objects

# =============================================================================
# FIRING PROPERTIES
# =============================================================================

## Time between shots in milliseconds
var reload_time: float = 500.0

## Number of projectiles per burst
var burst: int = 1

## Delay between burst shots in ms
var burst_delay: float = 30.0

## Current burst counter
var _burst_remaining: int = 0

## Number of projectiles per shot (spread)
var multi_nr_of_p: int = 1

## Offset between multiple projectiles
var multi_offset: float = 0.0

## Angle spread between multiple projectiles (radians)
var multi_angle_offset: float = 0.0

## Random angle variance (radians)
var angle_variance: float = 0.0

## Fire backwards
var fire_backwards: bool = false

# =============================================================================
# PROJECTILE PROPERTIES
# =============================================================================

## Projectile speed (units per second)
var speed: float = 500.0

## Projectile acceleration
var acceleration: float = 0.0

## Time to live in milliseconds
var ttl: int = 2000

## Maximum range (for range checks)
var range_max: float = 1000.0

## Maximum active projectiles (0 = unlimited)
var max_projectiles: int = 0

## Projectile friction
var friction: float = 0.0

## Speed cap
var speed_max: float = 0.0

# =============================================================================
# POSITION OFFSETS
# =============================================================================

var position_offset: Vector2 = Vector2.ZERO
var position_variance: Vector2 = Vector2.ZERO
var side_shooter: bool = false

# =============================================================================
# EFFECTS
# =============================================================================

var fire_effect: String = ""
var fire_sound: String = ""
var explosion_effect: String = ""
var explosion_sound: String = ""
var projectile_sprite: String = "projectile_default"

# =============================================================================
# AREA DAMAGE
# =============================================================================

var dmg_radius: int = 0
var number_of_hits: int = 1

# =============================================================================
# CHARGE UP
# =============================================================================

var has_charge_up: bool = false
var charge_up_time_max: float = 0.0
var _charge_time: float = 0.0
var _is_charging: bool = false

# =============================================================================
# RESOURCE COSTS
# =============================================================================

## Heat/energy cost per shot (in 1000ths)
var heat_cost: float = 0.0

## Life steal percentages
var shield_vamp: float = 0.0
var health_vamp: float = 0.0

# =============================================================================
# AIMING
# =============================================================================

var aim_arc: float = 0.0
var rotation_speed: float = 0.0
var _current_rotation: float = 0.0

# =============================================================================
# STATE
# =============================================================================

var _last_fire_time: float = 0.0
var _owner: Node = null
var _active_projectiles: int = 0

# =============================================================================
# INITIALIZATION
# =============================================================================

# Preload Damage class to avoid loading order issues
const DamageClass = preload("res://scripts/combat/damage.gd")

func _init() -> void:
	dmg = DamageClass.new()

## Initialize weapon from configuration dictionary
func init_from_config(config: Dictionary, wpn_level: int = 1) -> void:
	level = wpn_level

	weapon_type = config.get("type", "")
	weapon_id = config.get("id", weapon_type)

	# Damage
	var dmg_type: int = config.get("damageType", DamageClass.Type.KINETIC)
	var dmg_amount: float = config.get("damage", 10.0)
	dmg = DamageClass.new(dmg_type, dmg_amount)

	# Firing
	reload_time = config.get("reloadTime", 500.0)
	burst = config.get("burst", 1)
	burst_delay = config.get("burstDelay", 30.0)
	multi_nr_of_p = config.get("multiNrOfP", 1)
	multi_offset = config.get("multiOffset", 0.0)
	multi_angle_offset = config.get("multiAngleOffset", 0.0)
	angle_variance = config.get("angleVariance", 0.0)
	fire_backwards = config.get("fireBackwards", false)

	# Projectile
	speed = config.get("speed", 500.0)
	acceleration = config.get("acceleration", 0.0)
	ttl = config.get("ttl", 2000)
	range_max = config.get("range", 1000.0)
	max_projectiles = config.get("maxProjectiles", 0)
	friction = config.get("friction", 0.0)
	speed_max = config.get("speedMax", speed * 2.0)

	# Position
	position_offset.x = config.get("positionOffsetX", 0.0)
	position_offset.y = config.get("positionOffsetY", 0.0)
	position_variance.x = config.get("positionXVariance", 0.0)
	position_variance.y = config.get("positionYVariance", 0.0)
	side_shooter = config.get("sideShooter", false)

	# Effects
	fire_effect = config.get("fireEffect", "")
	fire_sound = config.get("fireSound", "")
	explosion_effect = config.get("explosionEffect", "")
	explosion_sound = config.get("explosionSound", "")
	projectile_sprite = config.get("projectileSprite", "projectile_default")

	# Area damage
	dmg_radius = config.get("dmgRadius", 0)
	number_of_hits = config.get("numberOfHits", 1)

	# Charge up
	has_charge_up = config.get("hasChargeUp", false)
	charge_up_time_max = config.get("chargeUpTimeMax", 0.0)

	# Resources
	heat_cost = config.get("heatCost", 0.0)
	shield_vamp = config.get("shieldVamp", 0.0)
	health_vamp = config.get("healthVamp", 0.0)

	# Aiming
	aim_arc = config.get("aimArc", 0.0)
	rotation_speed = config.get("rotationSpeed", 0.0)

	# Parse debuffs from config (from original Weapon.as)
	_parse_debuffs(config)

	# Apply level scaling
	_apply_level_scaling()

func _apply_level_scaling() -> void:
	if level <= 1:
		return

	# Scale damage by 8% per level (matching DMGBONUS constant)
	dmg.add_level_bonus(level - 1, GameConstants.DMGBONUS)

# Preload WeaponDebuff class
const WeaponDebuffClass = preload("res://scripts/combat/weapon_debuff.gd")

## Parse debuffs from weapon config (from original Weapon.as lines 200-203)
func _parse_debuffs(config: Dictionary) -> void:
	debuffs.clear()

	# Check for primary debuff config (original format)
	if config.has("debuffType") and config.has("dot") and config.has("dotDamageType") and config.has("dotDuration"):
		var debuff_type: int = config.get("debuffType", 0)
		var dot_damage: float = config.get("dot", 0.0)
		var dot_damage_type: int = config.get("dotDamageType", 0)
		var dot_duration: float = config.get("dotDuration", 3.0)
		var dot_effect: String = config.get("dotEffect", "")

		var dot_dmg := DamageClass.new(dot_damage_type, dot_damage)
		var debuff := WeaponDebuffClass.new(debuff_type, dot_duration, dot_dmg)
		debuff.effect_name = dot_effect
		debuffs.append(debuff)

	# Check for slow debuff
	if config.has("slowPercent") and config.get("slowPercent", 0.0) > 0:
		var slow_percent: float = config.get("slowPercent", 0.0)
		var slow_duration: float = config.get("slowDuration", 3.0)
		var slow := WeaponDebuffClass.create_slow(slow_duration, slow_percent)
		debuffs.append(slow)

	# Check for armor reduction debuff
	if config.has("armorReduction") and config.get("armorReduction", 0.0) > 0:
		var armor_reduction: float = config.get("armorReduction", 0.0)
		var armor_duration: float = config.get("armorDuration", 5.0)
		var armor := WeaponDebuffClass.create_armor_reduction(armor_duration, armor_reduction)
		debuffs.append(armor)

	# Check for burn debuff
	if config.has("burnDamage") and config.get("burnDamage", 0.0) > 0:
		var burn_damage: float = config.get("burnDamage", 0.0)
		var burn_duration: float = config.get("burnDuration", 4.0)
		var burn_type: int = config.get("burnDamageType", DamageClass.Type.ENERGY)
		var burn_dmg := DamageClass.new(burn_type, burn_damage)
		var burn := WeaponDebuffClass.create_burn(burn_duration, burn_dmg)
		debuffs.append(burn)

	# Check for disable regen
	if config.has("disableRegen") and config.get("disableRegen", false):
		var regen_duration: float = config.get("disableRegenDuration", 3.0)
		var disable_regen := WeaponDebuffClass.create_disable_regen(regen_duration)
		debuffs.append(disable_regen)

	# Check for disable heal
	if config.has("disableHeal") and config.get("disableHeal", false):
		var heal_duration: float = config.get("disableHealDuration", 3.0)
		var disable_heal := WeaponDebuffClass.create_disable_heal(heal_duration)
		debuffs.append(disable_heal)

	# Check for resistance reduction
	for resist_name in ["kinetic", "energy", "corrosive"]:
		var key := "reduce%sResist" % resist_name.capitalize()
		if config.has(key) and config.get(key, 0.0) > 0:
			var reduction: float = config.get(key, 0.0)
			var duration: float = config.get(key + "Duration", 5.0)
			var resist_type: int = ["kinetic", "energy", "corrosive"].find(resist_name)
			var resist_debuff := WeaponDebuffClass.create_reduced_resist(duration, resist_type, reduction)
			debuffs.append(resist_debuff)

	# Check for damage reduction debuff (weaken)
	if config.has("weakenPercent") and config.get("weakenPercent", 0.0) > 0:
		var weaken_percent: float = config.get("weakenPercent", 0.0)
		var weaken_duration: float = config.get("weakenDuration", 5.0)
		var weaken := WeaponDebuffClass.create_reduced_damage(weaken_duration, weaken_percent)
		debuffs.append(weaken)

# =============================================================================
# FIRING
# =============================================================================

## Set the owner ship
func set_owner(owner: Node) -> void:
	_owner = owner

## Check if weapon can fire
func can_fire(current_time: float) -> bool:
	# Check reload
	if current_time - _last_fire_time < reload_time:
		return false

	# Check projectile cap
	if max_projectiles > 0 and _active_projectiles >= max_projectiles:
		return false

	# Check charge up
	if has_charge_up and not _is_fully_charged():
		return false

	return true

## Start charging (for charge-up weapons)
func start_charge() -> void:
	if has_charge_up and not _is_charging:
		_is_charging = true
		_charge_time = 0.0

## Update charge (call every frame while firing input held)
func update_charge(delta_ms: float) -> void:
	if _is_charging:
		_charge_time += delta_ms

func _is_fully_charged() -> bool:
	return not has_charge_up or _charge_time >= charge_up_time_max

## Fire the weapon - returns array of projectile data dictionaries
func fire(current_time: float, owner_pos: Vector2, owner_rotation: float, owner_velocity: Vector2) -> Array[Dictionary]:
	if not can_fire(current_time):
		return []

	_last_fire_time = current_time
	_is_charging = false
	_charge_time = 0.0

	var projectiles: Array[Dictionary] = []

	# Handle burst
	_burst_remaining = burst

	# Fire first shot of burst
	projectiles.append_array(_fire_single(owner_pos, owner_rotation, owner_velocity))

	return projectiles

## Fire a single shot (or multi-projectile spread)
func _fire_single(owner_pos: Vector2, owner_rotation: float, owner_velocity: Vector2) -> Array[Dictionary]:
	var projectiles: Array[Dictionary] = []

	var base_angle: float = owner_rotation
	if fire_backwards:
		base_angle += PI

	# Calculate fire position
	var fire_pos: Vector2 = owner_pos + position_offset.rotated(owner_rotation)

	# Add variance
	if position_variance.x > 0 or position_variance.y > 0:
		fire_pos.x += randf_range(-position_variance.x, position_variance.x)
		fire_pos.y += randf_range(-position_variance.y, position_variance.y)

	# Fire multiple projectiles if configured
	for i in range(multi_nr_of_p):
		var proj_angle: float = base_angle

		# Apply multi-projectile angle offset
		if multi_nr_of_p > 1 and multi_angle_offset > 0:
			var spread_start: float = -multi_angle_offset * (multi_nr_of_p - 1) / 2.0
			proj_angle += spread_start + i * multi_angle_offset

		# Apply random variance
		if angle_variance > 0:
			proj_angle += randf_range(-angle_variance, angle_variance)

		# Calculate projectile offset for multi-shot
		var proj_pos: Vector2 = fire_pos
		if multi_nr_of_p > 1 and multi_offset > 0:
			var offset_start: float = -multi_offset * (multi_nr_of_p - 1) / 2.0
			var perpendicular: Vector2 = Vector2.RIGHT.rotated(owner_rotation + PI / 2)
			proj_pos += perpendicular * (offset_start + i * multi_offset)

		# Calculate velocity
		var proj_velocity: Vector2 = Vector2.RIGHT.rotated(proj_angle) * speed

		# Inherit some owner velocity
		proj_velocity += owner_velocity * 0.5

		# Create projectile data
		var proj_data: Dictionary = {
			"position": proj_pos,
			"rotation": proj_angle,
			"velocity": proj_velocity,
			"speed": speed,
			"acceleration": acceleration,
			"ttl": ttl,
			"damage": dmg.duplicate_damage(),
			"dmg_radius": dmg_radius,
			"number_of_hits": number_of_hits,
			"friction": friction,
			"speed_max": speed_max,
			"sprite_name": projectile_sprite,
			"explosion_effect": explosion_effect,
			"explosion_sound": explosion_sound,
			"debuffs": debuffs.duplicate(),
			"owner": _owner,
			"weapon": self,
		}

		projectiles.append(proj_data)
		_active_projectiles += 1

	fired.emit(projectiles[0] if projectiles.size() > 0 else {})
	return projectiles

## Called when a projectile is destroyed
func on_projectile_destroyed() -> void:
	_active_projectiles = maxi(_active_projectiles - 1, 0)

# =============================================================================
# DEBUFFS
# =============================================================================

func add_debuff(debuff: Variant) -> void:
	debuffs.append(debuff)

func remove_debuff(debuff_type: int) -> void:
	for i in range(debuffs.size() - 1, -1, -1):
		if debuffs[i].type == debuff_type:
			debuffs.remove_at(i)

func clear_debuffs() -> void:
	debuffs.clear()

# =============================================================================
# UTILITY
# =============================================================================

## Check if target is in range
func in_range(target_pos: Vector2, owner_pos: Vector2) -> bool:
	return owner_pos.distance_squared_to(target_pos) <= range_max * range_max

## Get reload progress (0.0-1.0)
func get_reload_progress(current_time: float) -> float:
	var elapsed: float = current_time - _last_fire_time
	return clampf(elapsed / reload_time, 0.0, 1.0)

## Get charge progress (0.0-1.0)
func get_charge_progress() -> float:
	if not has_charge_up:
		return 1.0
	return clampf(_charge_time / charge_up_time_max, 0.0, 1.0)

func _to_string() -> String:
	return "Weapon(%s, lvl=%d, dmg=%.0f, reload=%.0fms)" % [
		weapon_type, level, dmg.dmg(), reload_time
	]
