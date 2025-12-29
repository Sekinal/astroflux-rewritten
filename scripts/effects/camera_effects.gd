class_name CameraEffects
extends Node
## CameraEffects - Handles camera shake and other screen effects
## Attach to Camera2D as a child node

# =============================================================================
# CONFIGURATION
# =============================================================================

@export var decay_rate: float = 5.0  # How fast shake decays
@export var max_offset: Vector2 = Vector2(50, 30)  # Maximum shake offset

# =============================================================================
# STATE
# =============================================================================

var _trauma: float = 0.0  # Current trauma level (0-1)
var _camera: Camera2D = null
var _noise: FastNoiseLite = null
var _noise_y: float = 0.0

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_camera = get_parent() as Camera2D

	# Create noise for smooth shake
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.5
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

func _process(delta: float) -> void:
	if _camera == null:
		return

	if _trauma > 0:
		# Decay trauma over time
		_trauma = maxf(0.0, _trauma - decay_rate * delta)

		# Apply shake using noise for smooth randomness
		_noise_y += delta * 50.0
		var shake_amount: float = _trauma * _trauma  # Quadratic for better feel

		var offset_x := max_offset.x * shake_amount * _noise.get_noise_2d(_noise_y, 0.0)
		var offset_y := max_offset.y * shake_amount * _noise.get_noise_2d(0.0, _noise_y)

		_camera.offset = Vector2(offset_x, offset_y)
	else:
		# Reset offset when not shaking
		_camera.offset = Vector2.ZERO

# =============================================================================
# PUBLIC API
# =============================================================================

## Add trauma to trigger shake (0.0-1.0)
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Shake based on damage taken (scales with damage percentage)
func shake_on_damage(damage: float, max_health: float) -> void:
	var damage_percent: float = damage / maxf(max_health, 1.0)
	var trauma_amount: float = clampf(damage_percent * 2.0, 0.1, 0.6)
	add_trauma(trauma_amount)

## Strong shake for explosions or big hits
func shake_explosion(intensity: float = 0.5) -> void:
	add_trauma(intensity)

## Quick small shake for impacts
func shake_impact() -> void:
	add_trauma(0.2)
