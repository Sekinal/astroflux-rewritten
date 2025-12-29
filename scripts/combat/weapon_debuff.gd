class_name WeaponDebuff
extends RefCounted
## WeaponDebuff - Status effects applied by weapons
## Ported from core/weapon/Debuff.as and WeaponDebuff.as

# =============================================================================
# DEBUFF TYPES (from original Debuff.as - 12 types)
# =============================================================================

enum Type {
	DOT = 0,                    # Damage over time
	DOT_STACKING = 1,           # DOT that stacks intensity
	BOMB = 2,                   # Delayed explosion damage
	REDUCE_ARMOR = 3,           # Reduces armor (stackable to 100x, can go negative)
	BURN = 4,                   # Fire DOT that decays over time
	DISABLE_REGEN = 5,          # Prevents shield regeneration
	DISABLE_HEAL = 6,           # Prevents healing
	REDUCED_DAMAGE = 7,         # Reduces target's damage output
	REDUCED_KINETIC_RESIST = 8, # Reduces kinetic resistance
	REDUCED_ENERGY_RESIST = 9,  # Reduces energy resistance
	REDUCED_CORROSIVE_RESIST = 10, # Reduces corrosive resistance
	SLOW_DOWN = 11,             # Reduces movement speed
}

const TOTAL_TYPES: int = 12

# =============================================================================
# NETWORK ID (for multiplayer sync)
# =============================================================================

var net_id: int = -1
static var _next_net_id: int = 0

static func _generate_net_id() -> int:
	_next_net_id += 1
	return _next_net_id

# =============================================================================
# STATE
# =============================================================================

var type: int = Type.DOT
var duration: float = 0.0          # Total duration in seconds
var remaining: float = 0.0         # Remaining time in seconds
var damage: Damage = null          # Damage object (for DOT types)
var value: float = 0.0             # Effect value (% for slow, armor reduction amount, etc.)
var effect_name: String = ""       # Visual effect sprite name
var stacks: int = 1                # Current stack count
var max_stacks: int = 1            # Maximum stacks (100 for armor reduction)
var source_net_id: int = -1        # Who applied this debuff (for multiplayer)
var tick_interval: float = 0.5     # Time between DOT ticks in seconds
var _tick_timer: float = 0.0       # Timer for DOT ticks

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(debuff_type: int = Type.DOT, dur: float = 3.0, dmg: Damage = null, val: float = 0.0) -> void:
	net_id = _generate_net_id()
	type = debuff_type
	duration = dur
	remaining = dur
	damage = dmg
	value = val
	_tick_timer = 0.0

	# Set max stacks based on type
	match type:
		Type.REDUCE_ARMOR:
			max_stacks = 100
		Type.DOT_STACKING:
			max_stacks = 10
		_:
			max_stacks = 1

# =============================================================================
# FACTORY METHODS
# =============================================================================

static func create_dot(dur: float, dmg: Damage, effect: String = "") -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.DOT, dur, dmg)
	d.effect_name = effect
	return d

static func create_dot_stacking(dur: float, dmg: Damage, effect: String = "") -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.DOT_STACKING, dur, dmg)
	d.effect_name = effect
	return d

static func create_bomb(delay: float, dmg: Damage, effect: String = "") -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.BOMB, delay, dmg)
	d.effect_name = effect
	return d

static func create_armor_reduction(dur: float, reduction_per_stack: float) -> WeaponDebuff:
	# Reduction is armor value reduced per stack
	# Can stack to 100x, can go below 0 for up to +50% bonus damage
	var d := WeaponDebuff.new(Type.REDUCE_ARMOR, dur, null, reduction_per_stack)
	return d

static func create_burn(dur: float, dmg: Damage, effect: String = "burn") -> WeaponDebuff:
	# Burn: does 50% of damage over duration, decays
	var d := WeaponDebuff.new(Type.BURN, dur, dmg)
	d.effect_name = effect
	return d

static func create_disable_regen(dur: float) -> WeaponDebuff:
	return WeaponDebuff.new(Type.DISABLE_REGEN, dur)

static func create_disable_heal(dur: float) -> WeaponDebuff:
	return WeaponDebuff.new(Type.DISABLE_HEAL, dur)

static func create_reduced_damage(dur: float, reduction_percent: float) -> WeaponDebuff:
	# reduction_percent: 0.0 to 1.0 (e.g., 0.3 = 30% less damage)
	return WeaponDebuff.new(Type.REDUCED_DAMAGE, dur, null, clampf(reduction_percent, 0.0, 0.9))

static func create_reduced_resist(dur: float, resist_type: int, reduction_percent: float) -> WeaponDebuff:
	# resist_type: 0=kinetic, 1=energy, 2=corrosive
	var debuff_type := Type.REDUCED_KINETIC_RESIST + resist_type
	return WeaponDebuff.new(debuff_type, dur, null, clampf(reduction_percent, 0.0, 0.5))

static func create_slow(dur: float, slow_percent: float) -> WeaponDebuff:
	# slow_percent: 0.0 to 1.0 (e.g., 0.5 = 50% slower)
	return WeaponDebuff.new(Type.SLOW_DOWN, dur, null, clampf(slow_percent, 0.0, 0.9))

# =============================================================================
# UPDATE (called by ship each physics frame)
# =============================================================================

## Update debuff, returns damage dealt this tick (if any)
## Call from ship's _process_debuffs
func update(delta: float, target) -> float:
	remaining -= delta

	var damage_dealt := 0.0

	# Handle DOT types
	if type in [Type.DOT, Type.DOT_STACKING, Type.BURN]:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer -= tick_interval
			damage_dealt = _calculate_tick_damage()

	# Handle BOMB (explodes when timer ends)
	if type == Type.BOMB and remaining <= 0 and damage != null:
		damage_dealt = damage.dmg() * stacks

	return damage_dealt

func _calculate_tick_damage() -> float:
	if damage == null:
		return 0.0

	var base_damage: float = damage.dmg()  # Use dmg() method
	var ticks_in_duration: float = duration / tick_interval
	var damage_per_tick: float = base_damage / ticks_in_duration

	match type:
		Type.DOT:
			return damage_per_tick * stacks
		Type.DOT_STACKING:
			return damage_per_tick * stacks
		Type.BURN:
			# Burn decays: starts at full damage, ends at 0
			var decay_factor: float = remaining / duration
			return damage_per_tick * 0.5 * decay_factor * stacks
		_:
			return 0.0

# =============================================================================
# STACKING
# =============================================================================

## Try to add a stack, returns true if stacked
func try_stack() -> bool:
	if stacks < max_stacks:
		stacks += 1
		refresh()
		return true
	else:
		refresh()  # Still refresh duration
		return false

## Refresh duration to full
func refresh() -> void:
	remaining = duration

## Check if expired
func is_expired() -> bool:
	return remaining <= 0

## Create a copy of this debuff (for applying to new targets)
func duplicate() -> WeaponDebuff:
	var d := WeaponDebuff.new(type, duration, null, value)
	# Copy damage if present
	if damage != null:
		d.damage = damage.duplicate_damage()
	d.effect_name = effect_name
	d.stacks = 1  # Start fresh for new application
	d.source_net_id = source_net_id
	d.tick_interval = tick_interval
	return d

# =============================================================================
# EFFECT GETTERS (for applying to target)
# =============================================================================

## Get slow multiplier (1.0 = no slow, 0.5 = 50% speed)
func get_slow_multiplier() -> float:
	if type != Type.SLOW_DOWN:
		return 1.0
	return 1.0 - (value * stacks)

## Get armor reduction amount
func get_armor_reduction() -> float:
	if type != Type.REDUCE_ARMOR:
		return 0.0
	return value * stacks

## Get resistance reduction (0.0 to 0.5)
func get_resist_reduction() -> float:
	if type not in [Type.REDUCED_KINETIC_RESIST, Type.REDUCED_ENERGY_RESIST, Type.REDUCED_CORROSIVE_RESIST]:
		return 0.0
	return value * stacks

## Get damage reduction multiplier
func get_damage_multiplier() -> float:
	if type != Type.REDUCED_DAMAGE:
		return 1.0
	return 1.0 - (value * stacks)

## Check if this debuff disables regen
func disables_regen() -> bool:
	return type == Type.DISABLE_REGEN and remaining > 0

## Check if this debuff disables healing
func disables_heal() -> bool:
	return type == Type.DISABLE_HEAL and remaining > 0

# =============================================================================
# NETWORK SERIALIZATION (multiplayer-ready)
# =============================================================================

func to_array() -> Array:
	## Serialize for network transmission
	var dmg_array := []
	if damage != null:
		dmg_array = [damage.kinetic(), damage.energy(), damage.corrosive()]

	return [
		net_id,
		type,
		duration,
		remaining,
		dmg_array,
		value,
		effect_name,
		stacks,
		source_net_id
	]

static func from_array(arr: Array) -> WeaponDebuff:
	## Deserialize from network
	var d := WeaponDebuff.new()
	d.net_id = arr[0]
	d.type = arr[1]
	d.duration = arr[2]
	d.remaining = arr[3]

	var dmg_arr: Array = arr[4]
	if dmg_arr.size() >= 3:
		# Reconstruct Damage object from components
		# Create with total damage, then we'd need to set components manually
		# For simplicity, use the total and default to ALL type
		var total_dmg: float = dmg_arr[0] + dmg_arr[1] + dmg_arr[2]
		if total_dmg > 0:
			d.damage = Damage.new(Damage.Type.ALL, total_dmg)

	d.value = arr[5]
	d.effect_name = arr[6]
	d.stacks = arr[7]
	d.source_net_id = arr[8]

	# Recalculate max_stacks
	match d.type:
		Type.REDUCE_ARMOR:
			d.max_stacks = 100
		Type.DOT_STACKING:
			d.max_stacks = 10
		_:
			d.max_stacks = 1

	return d

func to_dict() -> Dictionary:
	## For local storage/debugging
	return {
		"net_id": net_id,
		"type": type,
		"type_name": Type.keys()[type],
		"duration": duration,
		"remaining": remaining,
		"value": value,
		"stacks": stacks,
		"source": source_net_id
	}

# =============================================================================
# DEBUG
# =============================================================================

func _to_string() -> String:
	return "Debuff(%s, %.1fs, x%d)" % [Type.keys()[type], remaining, stacks]

## Get display name for UI
func get_display_name() -> String:
	match type:
		Type.DOT: return "Damage"
		Type.DOT_STACKING: return "Damage (Stacking)"
		Type.BOMB: return "Bomb"
		Type.REDUCE_ARMOR: return "Armor Break"
		Type.BURN: return "Burning"
		Type.DISABLE_REGEN: return "Regen Disabled"
		Type.DISABLE_HEAL: return "Heal Disabled"
		Type.REDUCED_DAMAGE: return "Weakened"
		Type.REDUCED_KINETIC_RESIST: return "Kinetic Vulnerability"
		Type.REDUCED_ENERGY_RESIST: return "Energy Vulnerability"
		Type.REDUCED_CORROSIVE_RESIST: return "Corrosive Vulnerability"
		Type.SLOW_DOWN: return "Slowed"
		_: return "Unknown"

## Get color for UI
func get_display_color() -> Color:
	match type:
		Type.DOT, Type.DOT_STACKING: return Color(1.0, 0.3, 0.3)  # Red
		Type.BOMB: return Color(1.0, 0.5, 0.0)  # Orange
		Type.REDUCE_ARMOR: return Color(0.8, 0.8, 0.2)  # Yellow
		Type.BURN: return Color(1.0, 0.4, 0.1)  # Fire orange
		Type.DISABLE_REGEN, Type.DISABLE_HEAL: return Color(0.5, 0.0, 0.5)  # Purple
		Type.REDUCED_DAMAGE: return Color(0.5, 0.5, 0.5)  # Gray
		Type.REDUCED_KINETIC_RESIST: return Color(0.0, 1.0, 1.0)  # Cyan (kinetic)
		Type.REDUCED_ENERGY_RESIST: return Color(1.0, 0.0, 0.05)  # Red (energy)
		Type.REDUCED_CORROSIVE_RESIST: return Color(0.0, 0.6, 0.0)  # Green (corrosive)
		Type.SLOW_DOWN: return Color(0.3, 0.3, 1.0)  # Blue
		_: return Color.WHITE
