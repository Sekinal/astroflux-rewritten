extends Node
## EffectManager - Handles spawning and pooling of visual effects
## Centralized system for muzzle flashes, impacts, explosions, etc.

# =============================================================================
# EFFECT POOLS
# =============================================================================

const POOL_SIZE_MUZZLE := 20
const POOL_SIZE_IMPACT := 30
const POOL_SIZE_EXPLOSION := 10

var _muzzle_pool: Array[GPUParticles2D] = []
var _impact_pool: Array[GPUParticles2D] = []
var _explosion_pool: Array[GPUParticles2D] = []

var _container: Node2D = null

# =============================================================================
# CAMERA SHAKE
# =============================================================================

var _camera: Camera2D = null
var _shake_trauma: float = 0.0
var _shake_decay: float = 3.0
var _shake_max_offset: Vector2 = Vector2(30, 20)
var _noise: FastNoiseLite = null
var _noise_y: float = 0.0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	print("[EffectManager] Initialized")

	# Initialize noise for camera shake
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.5
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

func _process(delta: float) -> void:
	_update_camera_shake(delta)

func set_container(container: Node2D) -> void:
	_container = container
	_initialize_pools()

func set_camera(camera: Camera2D) -> void:
	_camera = camera

func _initialize_pools() -> void:
	# Create muzzle flash pool
	for i in range(POOL_SIZE_MUZZLE):
		var muzzle := _create_muzzle_flash()
		muzzle.emitting = false
		_container.add_child(muzzle)
		_muzzle_pool.append(muzzle)

	# Create impact pool
	for i in range(POOL_SIZE_IMPACT):
		var impact := _create_impact_particles()
		impact.emitting = false
		_container.add_child(impact)
		_impact_pool.append(impact)

	# Create explosion pool
	for i in range(POOL_SIZE_EXPLOSION):
		var explosion := _create_explosion()
		explosion.emitting = false
		_container.add_child(explosion)
		_explosion_pool.append(explosion)

	print("[EffectManager] Pools initialized: muzzle=%d, impact=%d, explosion=%d" % [
		_muzzle_pool.size(), _impact_pool.size(), _explosion_pool.size()
	])

# =============================================================================
# EFFECT SPAWNING
# =============================================================================

## Spawn a muzzle flash at position with given rotation and color
func spawn_muzzle_flash(pos: Vector2, angle: float, color: Color = Color.WHITE) -> void:
	var effect := _get_from_pool(_muzzle_pool)
	if effect == null:
		return

	effect.global_position = pos
	effect.rotation = angle
	effect.modulate = color
	effect.emitting = true

	# Return to pool after lifetime
	get_tree().create_timer(0.2).timeout.connect(
		func(): _return_to_pool(effect, _muzzle_pool),
		CONNECT_ONE_SHOT
	)

## Spawn impact particles at position with color based on damage type
func spawn_impact(pos: Vector2, damage_type: int = 0, scale_mult: float = 1.0) -> void:
	var effect := _get_from_pool(_impact_pool)
	if effect == null:
		return

	effect.global_position = pos
	effect.scale = Vector2.ONE * scale_mult
	effect.modulate = _get_damage_color(damage_type)
	effect.emitting = true

	get_tree().create_timer(0.5).timeout.connect(
		func(): _return_to_pool(effect, _impact_pool),
		CONNECT_ONE_SHOT
	)

## Spawn explosion at position
func spawn_explosion(pos: Vector2, scale_mult: float = 1.0, color: Color = Color.ORANGE) -> void:
	var effect := _get_from_pool(_explosion_pool)
	if effect == null:
		return

	effect.global_position = pos
	effect.scale = Vector2.ONE * scale_mult
	effect.modulate = color
	effect.emitting = true

	get_tree().create_timer(1.0).timeout.connect(
		func(): _return_to_pool(effect, _explosion_pool),
		CONNECT_ONE_SHOT
	)

## Spawn death explosion (larger, multi-stage)
func spawn_death_explosion(pos: Vector2, size: float = 1.0) -> void:
	# Main explosion
	spawn_explosion(pos, size * 1.5, Color(1.0, 0.6, 0.2))

	# Secondary smaller explosions around it
	for i in range(4):
		var offset := Vector2.from_angle(randf() * TAU) * (30.0 * size)
		get_tree().create_timer(0.05 + randf() * 0.15).timeout.connect(
			func(): spawn_explosion(pos + offset, size * 0.7, Color(1.0, 0.4, 0.1)),
			CONNECT_ONE_SHOT
		)

# =============================================================================
# POOL MANAGEMENT
# =============================================================================

func _get_from_pool(pool: Array) -> GPUParticles2D:
	for effect in pool:
		if not effect.emitting:
			return effect
	return null

func _return_to_pool(effect: GPUParticles2D, _pool: Array) -> void:
	effect.emitting = false

# =============================================================================
# EFFECT CREATION
# =============================================================================

func _create_muzzle_flash() -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = 8
	particles.lifetime = 0.15
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.z_index = 10

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(1, 0, 0)
	material.spread = 20.0
	material.initial_velocity_min = 100.0
	material.initial_velocity_max = 200.0
	material.gravity = Vector3.ZERO
	material.scale_min = 2.0
	material.scale_max = 4.0
	material.color = Color(1.0, 0.8, 0.3, 1.0)

	# Fade out
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.5, 1.0))
	gradient.add_point(1.0, Color(1.0, 0.5, 0.2, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	return particles

func _create_impact_particles() -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = 12
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.z_index = 10

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 5.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 50.0
	material.initial_velocity_max = 150.0
	material.gravity = Vector3.ZERO
	material.damping_min = 50.0
	material.damping_max = 100.0
	material.scale_min = 1.5
	material.scale_max = 3.0

	# Spark colors
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.7, 0.3, 0.8))
	gradient.add_point(1.0, Color(1.0, 0.3, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	return particles

func _create_explosion() -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = 24
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.z_index = 15

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 10.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 80.0
	material.initial_velocity_max = 200.0
	material.gravity = Vector3.ZERO
	material.damping_min = 100.0
	material.damping_max = 200.0
	material.scale_min = 4.0
	material.scale_max = 8.0

	# Scale over lifetime (shrink)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.3, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	material.scale_curve = scale_tex

	# Fire colors
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.8, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.7, 0.2, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.4, 0.1, 0.8))
	gradient.add_point(1.0, Color(0.3, 0.1, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	material.color_ramp = gradient_tex

	particles.process_material = material

	return particles

# =============================================================================
# UTILITY
# =============================================================================

func _get_damage_color(damage_type: int) -> Color:
	# Match damage types from damage.gd
	match damage_type:
		0:  # KINETIC
			return Color(1.0, 0.9, 0.7)
		1:  # ENERGY
			return Color(0.3, 0.7, 1.0)
		2:  # CORROSIVE
			return Color(0.3, 1.0, 0.3)
		_:
			return Color.WHITE

# =============================================================================
# CAMERA SHAKE
# =============================================================================

func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return

	if _shake_trauma > 0:
		# Decay trauma over time
		_shake_trauma = maxf(0.0, _shake_trauma - _shake_decay * delta)

		# Apply shake using noise for smooth randomness
		_noise_y += delta * 50.0
		var shake_amount: float = _shake_trauma * _shake_trauma  # Quadratic for better feel

		var offset_x := _shake_max_offset.x * shake_amount * _noise.get_noise_2d(_noise_y, 0.0)
		var offset_y := _shake_max_offset.y * shake_amount * _noise.get_noise_2d(0.0, _noise_y)

		_camera.offset = Vector2(offset_x, offset_y)
	else:
		# Smoothly return to zero
		if _camera.offset.length_squared() > 0.1:
			_camera.offset = _camera.offset.lerp(Vector2.ZERO, delta * 10.0)
		else:
			_camera.offset = Vector2.ZERO

## Add trauma to trigger shake (0.0-1.0)
func add_trauma(amount: float) -> void:
	_shake_trauma = clampf(_shake_trauma + amount, 0.0, 1.0)

## Shake camera based on damage taken (scales with damage percentage)
func shake_on_damage(damage: float, max_health: float) -> void:
	var damage_percent: float = damage / maxf(max_health, 1.0)
	var trauma_amount: float = clampf(damage_percent * 2.0, 0.1, 0.5)
	add_trauma(trauma_amount)

## Strong shake for explosions or big hits
func shake_explosion(intensity: float = 0.4) -> void:
	add_trauma(intensity)

## Quick small shake for impacts
func shake_impact() -> void:
	add_trauma(0.15)
