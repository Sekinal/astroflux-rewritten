class_name Converger
extends RefCounted
## Converger - Ported from core/sync/Converger.as
## Handles client-side prediction and interpolation for smooth movement
## This is the core of the multiplayer movement system

signal heading_updated(heading: Heading)

# =============================================================================
# CONSTANTS
# =============================================================================

const PI_DIVIDED_BY_8: float = 0.39269908169872414
const BLIP_OFFSET: float = 30.0
const RIGHT: int = 1
const LEFT: int = -1
const NONE: int = 0

# =============================================================================
# STATE
# =============================================================================

## Current course (authoritative position after prediction)
var course: Heading = Heading.new()

## Target heading for convergence (received from server)
var _target: Heading = null

## Error for smooth interpolation (enemy ships)
var _error: Vector2 = Vector2.ZERO
var _error_angle: float = 0.0

## Convergence timing
var _converge_time: float = 1000.0
var _converge_start_time: float = 0.0
var _error_old_time: float = 0.0

## Reference to the ship using this converger
var ship: Node = null

## For AI angle targeting
var _angle_target_pos: Vector2 = Vector2.ZERO
var _has_angle_target: bool = false
var _is_facing_target: bool = false
var _next_turn_direction: int = NONE

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(ship_ref: Node = null) -> void:
	ship = ship_ref

# =============================================================================
# MAIN UPDATE (called every physics tick)
# =============================================================================

## Main update function - call this every physics frame
func run(server_time: float) -> void:
	if course == null or course.time > server_time - GameConstants.TICK_LENGTH:
		return

	var is_enemy := _is_enemy_ship()

	if is_enemy:
		_ai_remove_error(course, server_time)
		update_heading(course, server_time)
		_ai_add_error(course, server_time)
	else:
		update_heading(course, server_time)
		if _target != null:
			_calculate_offset(server_time)

	heading_updated.emit(course)

# =============================================================================
# HEADING PHYSICS UPDATE (core physics from Converger.updateHeading)
# =============================================================================

## Update a heading's physics for one tick
func update_heading(h: Heading, server_time: float) -> void:
	var dt: float = GameConstants.TICK_LENGTH  # 33ms
	var is_enemy := _is_enemy_ship()

	# --- ROTATION ---
	if is_enemy and _has_angle_target:
		_update_ai_rotation(h, dt)
	else:
		# Player rotation (direct input)
		# rotation_speed is in degrees/sec, convert to radians
		var rot_delta: float = deg_to_rad(_get_rotation_speed()) * 0.001 * dt
		if h.rotate_left:
			h.rotation -= rot_delta
			h.rotation = GameConstantsClass.clamp_radians(h.rotation)
		if h.rotate_right:
			h.rotation += rot_delta
			h.rotation = GameConstantsClass.clamp_radians(h.rotation)

	# --- ACCELERATION ---
	if h.accelerate:
		var sx: float = h.speed.x
		var sy: float = h.speed.y
		var current_speed_sq: float = sx * sx + sy * sy

		var accel_rotation: float = h.rotation
		if is_enemy:
			accel_rotation += _get_roll_offset()

		var accel_force: float = _get_acceleration() * 0.5 * pow(dt, 2)
		sx += cos(accel_rotation) * accel_force
		sy += sin(accel_rotation) * accel_force

		# Determine max speed
		var max_speed: float = _get_max_speed()
		if _is_using_boost():
			max_speed *= (100.0 + _get_boost_bonus()) / 100.0
		elif current_speed_sq > max_speed * max_speed:
			# Already going faster than max (e.g., from external force)
			max_speed = sqrt(current_speed_sq)

		# Apply slowdown debuff if active
		if _is_slowed(server_time):
			max_speed = _get_max_speed() * (1.0 - _get_slowdown())

		# Clamp to max speed
		current_speed_sq = sx * sx + sy * sy
		if current_speed_sq <= max_speed * max_speed:
			h.speed.x = sx
			h.speed.y = sy
		else:
			var current_speed: float = sqrt(current_speed_sq)
			h.speed.x = sx / current_speed * max_speed
			h.speed.y = sy / current_speed * max_speed

	elif h.deaccelerate:
		# Deceleration (brake)
		h.speed.x *= 0.9
		h.speed.y *= 0.9

	elif is_enemy and h.roll:
		# Enemy roll/strafe movement
		_update_enemy_roll(h, dt)

	# --- FRICTION ---
	if is_enemy and not h.accelerate:
		# Enemies have stronger friction when idle
		h.speed.x *= 0.9
		h.speed.y *= 0.9
	else:
		# Player friction
		h.speed.x -= GameConstants.FRICTION * h.speed.x
		h.speed.y -= GameConstants.FRICTION * h.speed.y

	# --- GRAVITY (player ships near suns) ---
	if not is_enemy:
		_apply_gravity(h, dt)

	# --- POSITION UPDATE ---
	h.pos.x += h.speed.x * dt * 0.001
	h.pos.y += h.speed.y * dt * 0.001
	h.time += dt

# =============================================================================
# CONVERGENCE (smooth interpolation to server state)
# =============================================================================

## Calculate offset for player convergence to server state
func _calculate_offset(server_time: float) -> void:
	# Fast-forward target to current time
	while _target.time < course.time:
		update_heading(_target, server_time)

	# Calculate error
	var dx: float = _target.pos.x - course.pos.x
	var dy: float = _target.pos.y - course.pos.y
	var dist: float = sqrt(dx * dx + dy * dy)
	var angle_diff: float = GameConstantsClass.angle_difference(_target.rotation, course.rotation)

	# If too far, snap to target
	if dist > BLIP_OFFSET:
		set_course(_target)
		return

	# If angle too different, snap rotation
	if angle_diff > PI_DIVIDED_BY_8 or angle_diff < -PI_DIVIDED_BY_8:
		course.rotation = _target.rotation
		return

	# Smooth convergence
	var converge_factor: float = 0.4
	course.speed.x = _target.speed.x + converge_factor * dx
	course.speed.y = _target.speed.y + converge_factor * dy
	course.rotation += angle_diff * 0.05
	course.rotation = GameConstantsClass.clamp_radians(course.rotation)

## Add error back for smooth AI movement
func _ai_add_error(h: Heading, server_time: float) -> void:
	if _error == Vector2.ZERO:
		return

	var t: float = (_converge_time - (server_time - _converge_start_time)) / _converge_time
	# Cubic easing: 3t² - 2t³
	var eased: float = 3.0 * t * t - 2.0 * t * t * t

	if t > 0:
		h.pos.x += eased * _error.x
		h.pos.y += eased * _error.y
		h.rotation += eased * _error_angle
		_error_old_time = server_time
	else:
		_error = Vector2.ZERO
		_error_old_time = 0.0

## Remove error before physics update for AI
func _ai_remove_error(h: Heading, server_time: float) -> void:
	if _error == Vector2.ZERO or _error_old_time == 0.0:
		return

	var t: float = (_converge_time - (_error_old_time - _converge_start_time)) / _converge_time
	var eased: float = 3.0 * t * t - 2.0 * t * t * t

	h.pos.x -= eased * _error.x
	h.pos.y -= eased * _error.y
	h.rotation -= eased * _error_angle

# =============================================================================
# PUBLIC API
# =============================================================================

## Set a new course (usually from server)
func set_course(new_course: Heading, fast_forward: bool = true) -> void:
	if fast_forward and new_course != null:
		_fast_forward_to_server_time(new_course)
	course = new_course
	_target = null

## Set convergence target (for smooth interpolation)
func set_converge_target(target_heading: Heading, server_time: float) -> void:
	_target = target_heading

	if _is_enemy_ship():
		# Calculate error for smooth interpolation
		_error.x = course.pos.x - _target.pos.x
		_error.y = course.pos.y - _target.pos.y
		_error_angle = GameConstantsClass.angle_difference(course.rotation, _target.rotation)
		_converge_start_time = server_time

		# Snap to target position (error will smooth it)
		course.speed = _target.speed
		course.pos = _target.pos
		course.rotation = _target.rotation
		course.time = _target.time
		_ai_add_error(course, server_time)

## Clear convergence target
func clear_converge_target() -> void:
	_target = null
	_error = Vector2.ZERO

## Set AI angle target position
func set_angle_target_pos(target_pos: Vector2) -> void:
	_is_facing_target = false
	_angle_target_pos = target_pos
	_has_angle_target = true

## Check if AI is facing its target
func is_facing_angle_target() -> bool:
	return _is_facing_target

## Set next turn direction hint for AI
func set_next_turn_direction(direction: int) -> void:
	_next_turn_direction = direction

# =============================================================================
# PRIVATE HELPERS
# =============================================================================

## Fast forward heading to current server time
func _fast_forward_to_server_time(h: Heading) -> void:
	if h == null:
		return
	var server_time := NetworkManager.server_time
	while h.time < server_time - GameConstants.TICK_LENGTH:
		update_heading(h, server_time)

## Update AI rotation to face target
func _update_ai_rotation(h: Heading, dt: float) -> void:
	var ship_pos: Vector2 = course.pos if ship == null else ship.global_position
	var current_rot: float = h.rotation

	var target_angle: float = atan2(
		_angle_target_pos.y - ship_pos.y,
		_angle_target_pos.x - ship_pos.x
	)

	var angle_diff: float = GameConstantsClass.angle_difference(current_rot, target_angle + PI)
	# rotation_speed is in degrees/sec, convert to radians
	var rot_speed: float = deg_to_rad(_get_rotation_speed()) * 0.001 * dt
	var is_facing_away: bool = angle_diff > 0.5 * PI or angle_diff < -0.5 * PI

	if not is_facing_away:
		h.accelerate = true
		h.roll = false

	# Rotate towards target
	if angle_diff > 0 and angle_diff < PI - rot_speed:
		h.rotation += rot_speed
		h.rotation = GameConstantsClass.clamp_radians(h.rotation)
		_is_facing_target = false
	elif angle_diff <= 0 and angle_diff > -PI + rot_speed:
		h.rotation -= rot_speed
		h.rotation = GameConstantsClass.clamp_radians(h.rotation)
		_is_facing_target = false
	else:
		_is_facing_target = true
		h.rotation = GameConstantsClass.clamp_radians(target_angle)

## Update enemy roll/strafe movement
func _update_enemy_roll(h: Heading, dt: float) -> void:
	var sx: float = h.speed.x
	var sy: float = h.speed.y
	var speed_sq: float = sx * sx + sy * sy
	var roll_speed: float = _get_roll_speed()

	if speed_sq <= roll_speed * roll_speed:
		var roll_rotation: float = h.rotation + _get_roll_dir() * _get_roll_mod() * PI * 0.5
		var accel_force: float = _get_acceleration() * 0.5 * pow(dt, 2)
		sx += cos(roll_rotation) * accel_force
		sy += sin(roll_rotation) * accel_force

		speed_sq = sx * sx + sy * sy
		if speed_sq <= roll_speed * roll_speed:
			h.speed.x = sx
			h.speed.y = sy
		else:
			var current_speed: float = sqrt(speed_sq)
			h.speed.x = sx / current_speed * roll_speed
			h.speed.y = sy / current_speed * roll_speed
	else:
		h.speed.x -= 0.02 * h.speed.x
		h.speed.y -= 0.02 * h.speed.y

# =============================================================================
# SHIP PROPERTY ACCESSORS (override these or use signals)
# =============================================================================

func _is_enemy_ship() -> bool:
	if ship == null:
		return false
	return ship.has_method("is_enemy") and ship.is_enemy()

func _get_rotation_speed() -> float:
	if ship != null and ship.has_method("get_rotation_speed"):
		return ship.get_rotation_speed()
	return 180.0  # Default rotation speed

func _get_acceleration() -> float:
	if ship != null and ship.has_method("get_acceleration"):
		return ship.get_acceleration()
	return 0.5  # Default acceleration

func _get_max_speed() -> float:
	if ship != null and ship.has_method("get_max_speed"):
		return ship.get_max_speed()
	return 300.0  # Default max speed

func _is_using_boost() -> bool:
	if ship != null and ship.has_method("is_using_boost"):
		return ship.is_using_boost()
	return false

func _get_boost_bonus() -> float:
	if ship != null and ship.has_method("get_boost_bonus"):
		return ship.get_boost_bonus()
	return 50.0

func _is_slowed(server_time: float) -> bool:
	if ship != null and ship.has_method("is_slowed"):
		return ship.is_slowed(server_time)
	return false

func _get_slowdown() -> float:
	if ship != null and ship.has_method("get_slowdown"):
		return ship.get_slowdown()
	return 0.0

func _get_roll_offset() -> float:
	if ship != null and ship.has_method("get_roll_offset"):
		return ship.get_roll_offset()
	return 0.0

func _get_roll_speed() -> float:
	if ship != null and ship.has_method("get_roll_speed"):
		return ship.get_roll_speed()
	return 100.0

func _get_roll_dir() -> float:
	if ship != null and ship.has_method("get_roll_dir"):
		return ship.get_roll_dir()
	return 1.0

func _get_roll_mod() -> float:
	if ship != null and ship.has_method("get_roll_mod"):
		return ship.get_roll_mod()
	return 1.0

# =============================================================================
# GRAVITY
# =============================================================================

## Apply gravity from all suns to the heading (only for player ships)
func _apply_gravity(h: Heading, dt: float) -> void:
	# Get gravity from BodyManager autoload
	var main_loop = Engine.get_main_loop()
	if main_loop == null:
		return

	var root = main_loop.root
	if root == null:
		return

	var body_manager = root.get_node_or_null("BodyManager")
	if body_manager == null:
		return

	var gravity: Vector2 = body_manager.get_gravity_at(h.pos)
	if gravity != Vector2.ZERO:
		# Apply gravity acceleration (scaled by dt in milliseconds)
		h.speed.x += gravity.x * dt * 0.001
		h.speed.y += gravity.y * dt * 0.001
