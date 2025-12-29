class_name AIFlee
extends AIState
## AIFlee - Escape state when health is low

var _flee_direction: float = 0.0
var _flee_timer: float = 0.0
var _flee_duration: float = 5.0

func enter() -> void:
	if ship == null:
		return

	ship.stop_shooting()
	ship.converger.course.accelerate = true
	ship.converger.course.deaccelerate = false

	# Calculate flee direction (away from target or random)
	if target != null and is_instance_valid(target):
		var away_from_target: Vector2 = ship.global_position - target.global_position
		_flee_direction = away_from_target.angle()
	else:
		_flee_direction = randf_range(-PI, PI)

	_flee_timer = 0.0
	_flee_duration = ship.flee_duration if ship.flee_duration > 0 else 5.0

func execute(delta: float) -> String:
	if ship == null:
		return "idle"

	_flee_timer += delta

	# Check if flee duration is over
	if _flee_timer >= _flee_duration:
		# If health recovered, go back to idle/chase
		if ship.hp > ship.hp_max * ship.flee_threshold * 1.5:
			return "idle"
		# Otherwise keep fleeing
		_flee_timer = 0.0

	# Rotate toward flee direction
	var current_rot: float = ship.converger.course.rotation
	var angle_diff: float = _angle_difference(_flee_direction, current_rot)

	ship.converger.course.rotate_left = angle_diff < -0.1
	ship.converger.course.rotate_right = angle_diff > 0.1

	# Full speed ahead
	ship.converger.course.accelerate = true

	return ""

func _angle_difference(target_angle: float, current_angle: float) -> float:
	var diff = fmod(target_angle - current_angle + PI, TAU) - PI
	return diff

func get_state_name() -> String:
	return "AIFlee"
