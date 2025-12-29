class_name BeamWeapon
extends RefCounted
## BeamWeapon - Continuous beam weapon that fires instant rays
## Ported from core/weapon/Beam.as

# =============================================================================
# SIGNALS
# =============================================================================

signal started_firing
signal stopped_firing
signal hit_target(target: Node, damage)

# =============================================================================
# CONFIGURATION
# =============================================================================

var weapon_type: String = "beam"
var weapon_id: String = ""
var level: int = 1

# Damage per tick (applied at reload_time intervals)
var dmg = null  # Damage object
var reload_time: float = 100.0  # ms between damage ticks

# Range
var range_max: float = 800.0

# Visual
var beam_color: Color = Color(1.0, 0.2, 0.2)  # Red by default
var beam_thickness: float = 3.0
var beam_amplitude: float = 2.0  # Wiggle amount
var beam_nodes: int = 10  # Segments in the beam
var glow_color: Color = Color(1.0, 0.5, 0.5)
var beam_alpha: float = 1.0

# Multi-target chaining
var nr_targets: int = 1  # How many targets to chain to
var chain_range: float = 300.0  # Range for chain targets

# Charge-up
var charge_up_max: int = 0  # Max charge level
var charge_up_current: int = 0
var charge_up_counter: int = 0
var charge_up_next: int = 8  # Ticks to next charge level
var charge_up_expire: float = 2000.0  # ms before charge resets

# Heat
var heat_cost: float = 0.002  # Cost per tick (continuous drain)

# Twin beams
var twin: bool = false
var twin_offset: float = 10.0

# Position offset from owner
var position_offset: Vector2 = Vector2(30.0, 0.0)

# =============================================================================
# STATE
# =============================================================================

var _owner: Node = null
var _is_firing: bool = false
var _last_fire_time: float = 0.0
var _last_damage_time: float = 0.0

# Targets
var primary_target: Node = null
var secondary_targets: Array = []

# Visual nodes (created when weapon is added to scene)
var _beam_line: Line2D = null
var _beam_line2: Line2D = null  # For twin beams

# =============================================================================
# INITIALIZATION
# =============================================================================

const DamageClass = preload("res://scripts/combat/damage.gd")

func _init() -> void:
	dmg = DamageClass.new()

## Initialize beam weapon from config
func init_from_config(config: Dictionary, wpn_level: int = 1) -> void:
	level = wpn_level

	weapon_type = config.get("type", "beam")
	weapon_id = config.get("id", weapon_type)

	# Damage per tick
	var dmg_type: int = config.get("damageType", DamageClass.Type.ENERGY)
	var dmg_amount: float = config.get("damage", 5.0)  # Lower per-tick damage
	dmg = DamageClass.new(dmg_type, dmg_amount)

	# Timing
	reload_time = config.get("reloadTime", 100.0)  # Faster for continuous

	# Range
	range_max = config.get("range", 800.0)

	# Visual properties
	if config.has("beamColor"):
		beam_color = Color(config.get("beamColor", 0xFF3333))
	beam_thickness = config.get("beamThickness", 3.0)
	beam_amplitude = config.get("beamAmplitude", 2.0)
	beam_nodes = config.get("beamNodes", 10)
	if config.has("glowColor"):
		glow_color = Color(config.get("glowColor", 0xFF8888))
	beam_alpha = config.get("beamAlpha", 1.0)

	# Multi-target
	nr_targets = config.get("nrTargets", 1)
	chain_range = config.get("chainRange", 300.0)

	# Charge-up
	charge_up_max = config.get("chargeUp", 0)
	charge_up_next = config.get("chargeUpNext", 8)
	charge_up_expire = config.get("chargeUpExpire", 2000.0)

	# Heat
	heat_cost = config.get("heatCost", 0.002)

	# Twin beams
	twin = config.get("twin", false)
	twin_offset = config.get("twinOffset", 10.0)

	# Position
	position_offset.x = config.get("positionOffsetX", 30.0)
	position_offset.y = config.get("positionOffsetY", 0.0)

	# Apply level scaling
	_apply_level_scaling()

func _apply_level_scaling() -> void:
	if level <= 1:
		return
	# Scale damage by 8% per level
	dmg.add_level_bonus(level - 1, GameConstants.DMGBONUS)

func set_owner(owner: Node) -> void:
	_owner = owner

# =============================================================================
# FIRING
# =============================================================================

## Start firing the beam
func start_fire() -> void:
	if _is_firing:
		return
	_is_firing = true
	started_firing.emit()

## Stop firing the beam
func stop_fire() -> void:
	if not _is_firing:
		return
	_is_firing = false
	primary_target = null
	secondary_targets.clear()
	stopped_firing.emit()

## Check if currently firing
func is_firing() -> bool:
	return _is_firing

## Update beam each frame (call from owner's _physics_process)
func update(delta: float, current_time: float, owner_pos: Vector2, owner_rotation: float) -> Dictionary:
	var result: Dictionary = {
		"firing": _is_firing,
		"start_pos": Vector2.ZERO,
		"end_pos": Vector2.ZERO,
		"targets_hit": [],
	}

	if not _is_firing:
		# Reset charge if not firing for too long
		if current_time - _last_damage_time > charge_up_expire:
			charge_up_current = 0
			charge_up_counter = 0
		return result

	# Calculate beam start position
	var start_pos: Vector2 = owner_pos + position_offset.rotated(owner_rotation)
	result["start_pos"] = start_pos

	# Find target using raycast
	_find_target(start_pos, owner_rotation)

	# Calculate end position
	var end_pos: Vector2
	if primary_target != null and is_instance_valid(primary_target):
		end_pos = primary_target.global_position
	else:
		# No target - beam extends to max range
		end_pos = start_pos + Vector2.RIGHT.rotated(owner_rotation) * range_max

	result["end_pos"] = end_pos

	# Apply damage at reload intervals
	if current_time - _last_fire_time >= reload_time:
		_last_fire_time = current_time

		if primary_target != null and is_instance_valid(primary_target):
			_apply_damage_to_target(primary_target)
			result["targets_hit"].append(primary_target)
			_last_damage_time = current_time

			# Update charge-up
			charge_up_counter += 1
			if charge_up_counter >= charge_up_next and charge_up_current < charge_up_max:
				charge_up_counter = 0
				charge_up_current += 1

			# Handle chain targets
			if nr_targets > 1:
				_find_chain_targets(end_pos)
				for target in secondary_targets:
					if is_instance_valid(target):
						_apply_damage_to_target(target)
						result["targets_hit"].append(target)

	return result

func _find_target(start_pos: Vector2, owner_rotation: float) -> void:
	if _owner == null:
		return

	var world: World2D = _owner.get_world_2d()
	if world == null:
		return

	var space_state: PhysicsDirectSpaceState2D = world.direct_space_state
	if space_state == null:
		return
	var end_pos: Vector2 = start_pos + Vector2.RIGHT.rotated(owner_rotation) * range_max

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start_pos, end_pos)
	query.exclude = [_owner]

	# Set collision mask based on owner type
	var is_enemy: bool = _owner.is_enemy() if _owner.has_method("is_enemy") else false
	if is_enemy:
		query.collision_mask = 2  # Layer 2 = player
	else:
		query.collision_mask = 4  # Layer 3 = enemies

	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		var collider = result.get("collider")
		if collider and collider.has_method("take_damage"):
			primary_target = collider
		else:
			primary_target = null
	else:
		primary_target = null

func _find_chain_targets(from_pos: Vector2) -> void:
	secondary_targets.clear()

	if _owner == null or nr_targets <= 1:
		return

	var targets_needed := nr_targets - 1
	var is_enemy: bool = _owner.is_enemy() if _owner.has_method("is_enemy") else false

	# Get potential targets
	var group_name := "player" if is_enemy else "enemies"
	var potential := _owner.get_tree().get_nodes_in_group(group_name)

	# Sort by distance from last beam position
	var valid_targets: Array = []
	for target in potential:
		if not is_instance_valid(target):
			continue
		if target == primary_target:
			continue
		var is_dead: bool = target.is_dead if "is_dead" in target else false
		if is_dead:
			continue

		var dist_sq := from_pos.distance_squared_to(target.global_position)
		if dist_sq <= chain_range * chain_range:
			valid_targets.append({"target": target, "dist_sq": dist_sq})

	# Sort by distance
	valid_targets.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)

	# Take closest targets up to limit
	for i in range(mini(targets_needed, valid_targets.size())):
		secondary_targets.append(valid_targets[i].target)

func _apply_damage_to_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return

	if target.has_method("take_damage"):
		# Apply charge bonus to damage
		var bonus_mult := 1.0 + (charge_up_current * 0.1)  # 10% per charge level
		var scaled_dmg = dmg.duplicate_damage()
		scaled_dmg.multiply(bonus_mult)

		target.take_damage(scaled_dmg, _owner)
		hit_target.emit(target, scaled_dmg)

# =============================================================================
# UTILITY
# =============================================================================

## Get reload progress (0.0-1.0)
func get_reload_progress(current_time: float) -> float:
	var elapsed: float = current_time - _last_fire_time
	return clampf(elapsed / reload_time, 0.0, 1.0)

## Get charge level (0.0-1.0)
func get_charge_level() -> float:
	if charge_up_max <= 0:
		return 0.0
	return float(charge_up_current) / float(charge_up_max)

## Get beam visual data for rendering
func get_beam_visual_data(start_pos: Vector2, end_pos: Vector2) -> Dictionary:
	return {
		"start": start_pos,
		"end": end_pos,
		"color": beam_color,
		"thickness": beam_thickness * (1.0 + get_charge_level()),
		"amplitude": beam_amplitude,
		"nodes": beam_nodes,
		"alpha": beam_alpha,
		"glow_color": glow_color,
	}

func _to_string() -> String:
	return "BeamWeapon(%s, lvl=%d, dmg=%.0f/tick, range=%.0f)" % [
		weapon_type, level, dmg.dmg(), range_max
	]
