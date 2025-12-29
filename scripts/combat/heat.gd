class_name Heat
extends RefCounted
## Heat - Energy/heat management for weapon firing
## Ported from core/weapon/Heat.as

# =============================================================================
# CONSTANTS (from original Heat.as)
# =============================================================================

const LOCKOUT_TIME: float = 2.0  ## 2 seconds lockout when depleted
const MAX_DEFAULT: float = 1.0   ## Default max heat/energy
const REGEN_DEFAULT: float = 0.05  ## Base regen per second

# =============================================================================
# STATE
# =============================================================================

var _current: float = 1.0  ## Current heat/energy (1.0 = full)
var _max: float = 1.0  ## Maximum heat/energy
var _regen: float = 0.05  ## Regen rate per second
var _lockout_end: float = 0.0  ## Time when lockout ends (ms)
var _last_update: float = 0.0  ## Last update time

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init() -> void:
	_current = MAX_DEFAULT
	_max = MAX_DEFAULT
	_regen = REGEN_DEFAULT
	_lockout_end = 0.0

# =============================================================================
# BONUSES (from artifacts/upgrades)
# =============================================================================

## Set bonus multipliers (from original Heat.as)
## max_multiplier: Multiplies maximum heat capacity
## regen_multiplier: Multiplies regen rate
func set_bonuses(max_multiplier: float, regen_multiplier: float) -> void:
	_max = MAX_DEFAULT * max_multiplier
	_regen = REGEN_DEFAULT * regen_multiplier
	# Cap current at new max
	_current = minf(_current, _max)

# =============================================================================
# UPDATE
# =============================================================================

## Update heat regeneration (call every frame with server time in ms)
func update(current_time_ms: float) -> void:
	# Check if in lockout
	if _lockout_end > current_time_ms:
		_last_update = current_time_ms
		return

	# Calculate time delta in seconds
	var delta_sec: float = (current_time_ms - _last_update) / 1000.0
	_last_update = current_time_ms

	# Regenerate heat (from original Heat.as)
	# 4x regen when above 25%, 2x regen when below
	if _current > 0.25:
		_current += 4.0 * _regen * delta_sec
	else:
		_current += 2.0 * _regen * delta_sec

	# Clamp to max
	_current = minf(_current, _max)

# =============================================================================
# FIRING
# =============================================================================

## Check if weapon can fire with given heat cost
## Returns true and consumes heat if possible
## dmg_boost_active: If true, increases heat cost
## dmg_boost_cost: Additional cost multiplier when boosting
func can_fire(cost: float, dmg_boost_active: bool = false, dmg_boost_cost: float = 0.0) -> bool:
	var actual_cost: float = cost

	# Apply damage boost cost if active
	if dmg_boost_active:
		actual_cost *= (1.0 + dmg_boost_cost)

	# Check if enough heat
	if _current < actual_cost:
		return false

	# Consume heat
	_current -= actual_cost
	return true

## Force consume heat (used for charged weapons, etc.)
func consume(amount: float) -> void:
	_current = maxf(0.0, _current - amount)

# =============================================================================
# LOCKOUT
# =============================================================================

## Pause/lockout heat for specified duration (seconds)
func pause(duration_sec: float, current_time_ms: float) -> void:
	_lockout_end = current_time_ms + duration_sec * 1000.0

## Check if currently in lockout
func is_locked_out(current_time_ms: float) -> bool:
	return _lockout_end > current_time_ms

## Get remaining lockout time in seconds
func get_lockout_remaining(current_time_ms: float) -> float:
	if _lockout_end <= current_time_ms:
		return 0.0
	return (_lockout_end - current_time_ms) / 1000.0

# =============================================================================
# GETTERS
# =============================================================================

## Get current heat/energy (0.0 to max)
func get_heat() -> float:
	return clampf(_current, 0.0, _max)

## Get maximum heat
func get_max() -> float:
	return _max

## Get heat as percentage (0.0 to 1.0)
func get_heat_percent() -> float:
	if _max <= 0:
		return 0.0
	return clampf(_current / _max, 0.0, 1.0)

## Set heat directly (for network sync, etc.)
func set_heat(value: float) -> void:
	_current = clampf(value, 0.0, _max)

# =============================================================================
# NETWORK SERIALIZATION
# =============================================================================

func to_array() -> Array:
	return [_current, _max, _regen, _lockout_end]

func from_array(arr: Array) -> void:
	if arr.size() >= 4:
		_current = arr[0]
		_max = arr[1]
		_regen = arr[2]
		_lockout_end = arr[3]

func _to_string() -> String:
	return "Heat(%.1f/%.1f, regen=%.2f)" % [_current, _max, _regen]
