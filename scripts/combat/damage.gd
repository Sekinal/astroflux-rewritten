class_name Damage
extends RefCounted
## Damage - Ported from core/weapon/Damage.as
## Handles damage types, resistances, and calculations

# =============================================================================
# DAMAGE TYPE CONSTANTS
# =============================================================================

enum Type {
	KINETIC = 0,
	ENERGY = 1,
	CORROSIVE = 2,
	KINETIC_ENERGY = 3,      # 50% Kinetic + 50% Energy
	CORROSIVE_KINETIC = 4,   # 50% Kinetic + 50% Corrosive
	ALL = 5,                 # 33% of each
	HEAL = 6,
	KINETIC_ENERGY_CORROSIVE = 7,  # 33% each
	DONT_SCALE = 8,          # Fixed damage
	ENERGY_CORROSIVE = 9     # 50% Energy + 50% Corrosive
}

const SINGLE_TYPES: int = 5
const TOTAL_TYPES: int = 10
const RESISTANCE_CAP: float = 0.75

# Component indices
const IDX_KINETIC: int = 0
const IDX_ENERGY: int = 1
const IDX_CORROSIVE: int = 2
const IDX_HEAL: int = 3
const IDX_SPECIAL: int = 4

# =============================================================================
# STATE
# =============================================================================

## Current damage type
var type: int = Type.KINETIC

## Damage values per component [kinetic, energy, corrosive, heal, special]
var damage: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]

## Base damage before scaling
var damage_base: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]

# =============================================================================
# CONSTRUCTORS
# =============================================================================

func _init(dmg_type: int = Type.KINETIC, amount: float = 0.0) -> void:
	type = dmg_type
	if amount > 0:
		set_base_dmg(amount)

# Static factory method - caller uses: preload("damage.gd").create(...)
static func create(dmg_type: int, amount: float) -> RefCounted:
	var script := load("res://scripts/combat/damage.gd")
	return script.new(dmg_type, amount)

# =============================================================================
# DAMAGE ACCESSORS
# =============================================================================

## Get total damage across all types
func dmg() -> float:
	var total: float = 0.0
	for i in range(SINGLE_TYPES):
		total += damage[i]
	return total

## Get damage for a specific component
func get_component(idx: int) -> float:
	if idx >= 0 and idx < damage.size():
		return damage[idx]
	return 0.0

## Get kinetic damage
func kinetic() -> float:
	return damage[IDX_KINETIC]

## Get energy damage
func energy() -> float:
	return damage[IDX_ENERGY]

## Get corrosive damage
func corrosive() -> float:
	return damage[IDX_CORROSIVE]

## Get heal amount
func heal() -> float:
	return damage[IDX_HEAL]

# =============================================================================
# DAMAGE MODIFICATION
# =============================================================================

## Set base damage according to type distribution
func set_base_dmg(amount: float) -> void:
	# Reset base
	for i in range(damage_base.size()):
		damage_base[i] = 0.0

	match type:
		Type.KINETIC:
			damage_base[IDX_KINETIC] = amount
		Type.ENERGY:
			damage_base[IDX_ENERGY] = amount
		Type.CORROSIVE:
			damage_base[IDX_CORROSIVE] = amount
		Type.KINETIC_ENERGY:
			damage_base[IDX_KINETIC] = amount * 0.5
			damage_base[IDX_ENERGY] = amount * 0.5
		Type.CORROSIVE_KINETIC:
			damage_base[IDX_KINETIC] = amount * 0.5
			damage_base[IDX_CORROSIVE] = amount * 0.5
		Type.ENERGY_CORROSIVE:
			damage_base[IDX_ENERGY] = amount * 0.5
			damage_base[IDX_CORROSIVE] = amount * 0.5
		Type.ALL, Type.KINETIC_ENERGY_CORROSIVE:
			damage_base[IDX_KINETIC] = amount / 3.0
			damage_base[IDX_ENERGY] = amount / 3.0
			damage_base[IDX_CORROSIVE] = amount / 3.0
		Type.HEAL:
			damage_base[IDX_HEAL] = amount
		Type.DONT_SCALE:
			damage_base[IDX_SPECIAL] = amount

	# Copy to current damage
	_apply_base_to_current()

## Add flat damage to base
func add_base_dmg(amount: float, dmg_type: int = -1) -> void:
	if dmg_type < 0:
		dmg_type = type

	match dmg_type:
		Type.KINETIC:
			damage_base[IDX_KINETIC] += amount
		Type.ENERGY:
			damage_base[IDX_ENERGY] += amount
		Type.CORROSIVE:
			damage_base[IDX_CORROSIVE] += amount
		Type.KINETIC_ENERGY:
			damage_base[IDX_KINETIC] += amount * 0.5
			damage_base[IDX_ENERGY] += amount * 0.5
		Type.CORROSIVE_KINETIC:
			damage_base[IDX_KINETIC] += amount * 0.5
			damage_base[IDX_CORROSIVE] += amount * 0.5
		Type.ENERGY_CORROSIVE:
			damage_base[IDX_ENERGY] += amount * 0.5
			damage_base[IDX_CORROSIVE] += amount * 0.5
		Type.ALL, Type.KINETIC_ENERGY_CORROSIVE:
			damage_base[IDX_KINETIC] += amount / 3.0
			damage_base[IDX_ENERGY] += amount / 3.0
			damage_base[IDX_CORROSIVE] += amount / 3.0
		Type.HEAL:
			damage_base[IDX_HEAL] += amount

	_apply_base_to_current()

## Add percentage to base damage
func add_base_percent(percentage: float, dmg_type: int = -1) -> void:
	if dmg_type < 0:
		dmg_type = type

	var bonus: float = dmg() * (percentage / 100.0)
	add_base_dmg(bonus, dmg_type)

## Add percentage to current damage
func add_dmg_percent(percentage: float, dmg_type: int = -1) -> void:
	if dmg_type < 0:
		# Add to all components proportionally
		for i in range(SINGLE_TYPES):
			damage[i] *= (1.0 + percentage / 100.0)
	else:
		match dmg_type:
			Type.KINETIC:
				damage[IDX_KINETIC] *= (1.0 + percentage / 100.0)
			Type.ENERGY:
				damage[IDX_ENERGY] *= (1.0 + percentage / 100.0)
			Type.CORROSIVE:
				damage[IDX_CORROSIVE] *= (1.0 + percentage / 100.0)

## Scale damage by level bonus
func add_level_bonus(level: int, percent_per_level: float) -> void:
	var multiplier: float = 1.0 + (level * percent_per_level / 100.0)
	for i in range(SINGLE_TYPES):
		damage[i] = damage_base[i] * multiplier

func _apply_base_to_current() -> void:
	for i in range(damage.size()):
		damage[i] = damage_base[i]

# =============================================================================
# RESISTANCE CALCULATION
# =============================================================================

## Calculate damage after applying resistances
## resistances: [kinetic_res, energy_res, corrosive_res] as 0.0-1.0
func calculate_resisted(resistances: Array[float]) -> float:
	var total: float = 0.0

	# Cap resistances
	var capped_res: Array[float] = []
	for r in resistances:
		capped_res.append(minf(r, RESISTANCE_CAP))

	# Apply resistance to each component
	if damage[IDX_KINETIC] > 0:
		total += damage[IDX_KINETIC] * (1.0 - capped_res[IDX_KINETIC])
	if damage[IDX_ENERGY] > 0:
		total += damage[IDX_ENERGY] * (1.0 - capped_res[IDX_ENERGY])
	if damage[IDX_CORROSIVE] > 0:
		total += damage[IDX_CORROSIVE] * (1.0 - capped_res[IDX_CORROSIVE])

	# Heal and special are unaffected by resistance
	total += damage[IDX_HEAL]
	total += damage[IDX_SPECIAL]

	return maxf(total, 0.0)

# =============================================================================
# UTILITY
# =============================================================================

func duplicate_damage() -> RefCounted:
	var d = get_script().new()
	d.type = type
	d.damage = damage.duplicate()
	d.damage_base = damage_base.duplicate()
	return d

## Multiply all damage values by a factor
func multiply(factor: float) -> void:
	for i in range(damage.size()):
		damage[i] *= factor

func reset() -> void:
	for i in range(damage.size()):
		damage[i] = 0.0
		damage_base[i] = 0.0

func _to_string() -> String:
	return "Damage(type=%d, total=%.1f, K=%.1f E=%.1f C=%.1f)" % [
		type, dmg(), kinetic(), energy(), corrosive()
	]
