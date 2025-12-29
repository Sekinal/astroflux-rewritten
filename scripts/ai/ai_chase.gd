class_name AIChase
extends AIState
## AIChase - Active pursuit and combat state

var _close_range_sq: float = 10000.0  # Stop approaching when this close
var _roll_dir: int = 1
var _roll_timer: float = 0.0
var _fire_timer: float = 0.0

func enter() -> void:
	if ship == null:
		return

	# Randomize close range based on ship
	_close_range_sq = 80.0 + randf() * 60.0 + ship.collision_radius
	_close_range_sq *= _close_range_sq

	# Randomize roll direction
	_roll_dir = 1 if randf() > 0.5 else -1

	ship.converger.course.accelerate = true

func execute(delta: float) -> String:
	if ship == null:
		return "idle"

	# Check if target is still valid
	if target == null or not is_instance_valid(target):
		ship.target = null
		return "idle"

	if target.get("is_dead") == true:
		ship.target = null
		return "idle"

	var my_pos: Vector2 = ship.global_position
	var target_pos: Vector2 = target.global_position
	var to_target: Vector2 = target_pos - my_pos
	var dist_sq: float = to_target.length_squared()

	# Check if target left chase range
	if dist_sq > ship.chase_range * ship.chase_range:
		ship.target = null
		return "idle"

	# Check flee condition
	if ship.can_flee and ship.hp <= ship.hp_max * ship.flee_threshold:
		return "flee"

	# Aim at target (with lead calculation)
	var aim_angle: float = _calculate_aim_angle(target_pos, target)

	# Rotate toward aim angle
	var current_rot: float = ship.converger.course.rotation
	var angle_diff: float = _angle_difference(aim_angle, current_rot)

	ship.converger.course.rotate_left = angle_diff < -0.05
	ship.converger.course.rotate_right = angle_diff > 0.05

	# Movement - approach or maintain distance
	if ship.stop_when_close and dist_sq < _close_range_sq:
		ship.converger.course.accelerate = false
		# Strafe/roll behavior
		_roll_timer -= delta
		if _roll_timer <= 0:
			_roll_timer = randf_range(1.0, 3.0)
			_roll_dir *= -1
	elif ship.sniper and dist_sq < ship.sniper_min_range * ship.sniper_min_range:
		# Sniper - maintain minimum distance
		ship.converger.course.accelerate = false
		ship.converger.course.deaccelerate = true
	else:
		ship.converger.course.accelerate = true
		ship.converger.course.deaccelerate = false

	# Fire weapons if facing target
	if absf(angle_diff) < 0.3:  # ~17 degrees
		ship.try_fire_weapons()

	return ""

func _calculate_aim_angle(target_pos: Vector2, target_node: Node) -> float:
	if ship.aim_skill <= 0:
		return ship.converger.course.rotation

	var my_pos: Vector2 = ship.global_position
	var to_target: Vector2 = target_pos - my_pos
	var dist: float = to_target.length()

	if dist < 1.0:
		return ship.converger.course.rotation

	# Get target velocity for lead calculation
	var target_vel := Vector2.ZERO
	if target_node.get("converger") != null:
		target_vel = target_node.converger.course.speed

	# Get weapon speed (use first weapon)
	var weapon_speed: float = 800.0  # Default
	if ship.weapons.size() > 0:
		var weapon = ship.weapons[0]
		if weapon.get("speed") != null:
			weapon_speed = weapon.speed

	# Time to impact
	var time_to_impact: float = dist / weapon_speed

	# Lead position
	var lead_pos: Vector2 = target_pos + target_vel * time_to_impact * ship.aim_skill

	return my_pos.angle_to_point(lead_pos)

func _angle_difference(target_angle: float, current_angle: float) -> float:
	var diff = fmod(target_angle - current_angle + PI, TAU) - PI
	return diff

func get_state_name() -> String:
	return "AIChase"
