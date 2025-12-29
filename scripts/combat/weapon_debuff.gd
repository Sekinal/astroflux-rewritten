class_name WeaponDebuff
extends RefCounted
## WeaponDebuff - Status effects applied by weapons
## Ported from core/weapon/WeaponDebuff.as

# =============================================================================
# DEBUFF TYPES
# =============================================================================

enum Type {
	NONE = 0,
	SLOW = 1,          # Reduces movement speed
	DOT = 2,           # Damage over time
	ARMOR_BREAK = 3,   # Reduces resistances
	STUN = 4,          # Prevents actions
	BURN = 5,          # Fire DOT
	POISON = 6,        # Corrosive DOT
	SHIELD_BREAK = 7,  # Prevents shield regen
	WEAKEN = 8,        # Reduces damage dealt
}

# =============================================================================
# STATE
# =============================================================================

var type: int = Type.NONE
var duration: float = 0.0          # Total duration in ms
var remaining: float = 0.0         # Remaining time in ms
var damage: float = 0.0            # Damage per tick (for DOT)
var damage_type: int = Damage.Type.KINETIC
var effect_strength: float = 0.0   # Modifier amount (0.0-1.0 for slow, etc.)
var effect_name: String = ""       # Visual effect to spawn
var stacks: int = 1                # Number of stacks
var max_stacks: int = 5            # Maximum stacks

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(debuff_type: int = Type.NONE, dur: float = 0.0, dmg: float = 0.0) -> void:
	type = debuff_type
	duration = dur
	remaining = dur
	damage = dmg

static func create_slow(dur: float, strength: float) -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.SLOW, dur)
	d.effect_strength = clampf(strength, 0.0, 0.9)  # Max 90% slow
	return d

static func create_dot(dur: float, dmg: float, dmg_type: int = Damage.Type.ENERGY) -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.DOT, dur, dmg)
	d.damage_type = dmg_type
	return d

static func create_armor_break(dur: float, reduction: float) -> WeaponDebuff:
	var d := WeaponDebuff.new(Type.ARMOR_BREAK, dur)
	d.effect_strength = clampf(reduction, 0.0, 0.5)  # Max 50% reduction
	return d

static func create_stun(dur: float) -> WeaponDebuff:
	return WeaponDebuff.new(Type.STUN, dur)

# =============================================================================
# UPDATE
# =============================================================================

## Update debuff, returns true if still active
func update(delta_ms: float) -> bool:
	remaining -= delta_ms
	return remaining > 0

## Check if debuff has expired
func is_expired() -> bool:
	return remaining <= 0

## Refresh duration (for reapplying same debuff)
func refresh() -> void:
	remaining = duration

## Add a stack
func add_stack() -> void:
	if stacks < max_stacks:
		stacks += 1
		refresh()

# =============================================================================
# GETTERS
# =============================================================================

## Get effective strength considering stacks
func get_effective_strength() -> float:
	return effect_strength * stacks

## Get damage per tick considering stacks
func get_tick_damage() -> float:
	return damage * stacks

func _to_string() -> String:
	return "Debuff(%s, %.0fms, x%d)" % [Type.keys()[type], remaining, stacks]
