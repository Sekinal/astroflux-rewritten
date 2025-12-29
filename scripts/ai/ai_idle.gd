class_name AIIdle
extends AIState
## AIIdle - Default idle state, wanders slowly and looks for targets

var _wander_timer: float = 0.0
var _wander_direction: float = 0.0

func enter() -> void:
	if ship:
		ship.stop_shooting()
		ship.converger.course.accelerate = false

func execute(delta: float) -> String:
	if ship == null:
		return ""

	# Look for targets in aggro range
	if ship.aggro_range > 0:
		var new_target = _find_target_in_range(ship.aggro_range)
		if new_target != null:
			target = new_target
			ship.target = new_target
			return "chase"

	# Slow wander behavior
	_wander_timer -= delta
	if _wander_timer <= 0:
		_wander_timer = randf_range(2.0, 5.0)
		_wander_direction = randf_range(-PI, PI)

	# Slowly rotate toward wander direction
	var angle_diff = _angle_difference(_wander_direction, ship.converger.course.rotation)
	if absf(angle_diff) > 0.1:
		ship.converger.course.rotate_left = angle_diff < 0
		ship.converger.course.rotate_right = angle_diff > 0
	else:
		ship.converger.course.rotate_left = false
		ship.converger.course.rotate_right = false

	return ""

func _find_target_in_range(range_sq_max: float) -> Node:
	var players = ship.get_tree().get_nodes_in_group("player")
	var my_pos: Vector2 = ship.global_position

	for player in players:
		if not is_instance_valid(player):
			continue
		if player.get("is_dead") == true:
			continue

		var dist_sq = my_pos.distance_squared_to(player.global_position)
		if dist_sq <= range_sq_max * range_sq_max:
			return player

	return null

func _angle_difference(target_angle: float, current_angle: float) -> float:
	var diff = fmod(target_angle - current_angle + PI, TAU) - PI
	return diff

func get_state_name() -> String:
	return "AIIdle"
