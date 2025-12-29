class_name AIOrbit
extends AIState
## AIOrbit - Orbits around a spawner/body
## Ported from core/states/AIStates/AIOrbit.as
## NOTE: Original directly sets position each frame, not using converger

var spawner = null  # Spawner reference
var orbit_angle: float = 0.0
var orbit_radius: float = 100.0
var angle_velocity: float = 0.5
var ellipse_factor: float = 1.0  # For elliptical orbits
var ellipse_alpha: float = 0.0   # Rotation of ellipse
var _orbit_start_time: float = 0.0

func _init(enemy_ship, initial_target: Node = null, spawner_ref = null) -> void:
	super._init(enemy_ship, initial_target)
	spawner = spawner_ref

func enter() -> void:
	if ship == null:
		return

	ship.target = null
	ship.stop_shooting()

	_orbit_start_time = NetworkManager.server_time
	orbit_angle = ship.orbit_angle
	orbit_radius = ship.orbit_radius
	angle_velocity = ship.angle_velocity

	# Stop converger movement - we control position directly
	ship.converger.course.accelerate = false
	ship.converger.course.deaccelerate = false
	ship.converger.course.rotate_left = false
	ship.converger.course.rotate_right = false

	# Clear angle target so converger doesn't override our rotation
	ship.converger._has_angle_target = false

func execute(delta: float) -> String:
	if ship == null:
		return "idle"

	if spawner == null or not is_instance_valid(spawner):
		return "idle"

	# Check for targets - switch to chase if player in aggro range
	if ship.aggro_range > 0:
		var new_target = _find_target_in_range(ship.aggro_range)
		if new_target != null:
			target = new_target
			ship.target = new_target
			return "chase"

	# Get parent position (spawner's position)
	var parent_pos: Vector2 = spawner.global_position

	# Calculate orbit position based on time (like original)
	var current_time: float = NetworkManager.server_time
	var elapsed_ticks: float = (current_time - _orbit_start_time)  # In milliseconds
	var current_angle: float = orbit_angle + angle_velocity * 0.001 * 33.0 * elapsed_ticks / 33.0

	# Calculate position on ellipse (like original)
	var orbit_x: float = orbit_radius * ellipse_factor * cos(current_angle)
	var orbit_y: float = orbit_radius * sin(current_angle)

	# Apply ellipse rotation
	var final_x: float = orbit_x * cos(ellipse_alpha) - orbit_y * sin(ellipse_alpha) + parent_pos.x
	var final_y: float = orbit_x * sin(ellipse_alpha) + orbit_y * cos(ellipse_alpha) + parent_pos.y

	# Calculate tangent angle for facing direction
	# The ship should face along the orbit tangent (perpendicular to radius)
	var tangent_angle: float = current_angle + PI/2 * sign(angle_velocity)

	# Directly set position and rotation (like original does)
	# Zero out speed so converger doesn't add velocity to our position
	ship.converger.course.speed = Vector2.ZERO
	ship.converger.course.pos.x = final_x
	ship.converger.course.pos.y = final_y
	ship.converger.course.rotation = tangent_angle

	# Fire at targets if always_fire
	if ship.always_fire:
		ship.try_fire_weapons()

	return ""

func exit() -> void:
	if ship == null:
		return

	# Calculate orbit velocity for smooth transition (like original)
	var orbit_speed := _calculate_orbit_speed()
	ship.converger.course.speed = orbit_speed

func _calculate_orbit_speed() -> Vector2:
	# Calculate instantaneous velocity at current orbit position
	var current_time: float = NetworkManager.server_time
	var elapsed: float = (current_time - _orbit_start_time)
	var current_angle: float = orbit_angle + angle_velocity * 0.001 * elapsed

	# Position now
	var orbit_x: float = orbit_radius * ellipse_factor * cos(current_angle)
	var orbit_y: float = orbit_radius * sin(current_angle)

	# Position one tick ago
	var prev_angle: float = orbit_angle + angle_velocity * 0.001 * (elapsed - 33.0)
	var prev_x: float = orbit_radius * ellipse_factor * cos(prev_angle)
	var prev_y: float = orbit_radius * sin(prev_angle)

	# Velocity (scaled to per-second)
	var vel_x: float = (orbit_x - prev_x) * cos(ellipse_alpha) - (orbit_y - prev_y) * sin(ellipse_alpha)
	var vel_y: float = (orbit_x - prev_x) * sin(ellipse_alpha) + (orbit_y - prev_y) * cos(ellipse_alpha)

	return Vector2(vel_x * 1000.0 / 33.0, vel_y * 1000.0 / 33.0)

func _find_target_in_range(range_max: float) -> Node:
	var players = ship.get_tree().get_nodes_in_group("player")
	var my_pos: Vector2 = ship.global_position

	for player in players:
		if not is_instance_valid(player):
			continue
		if player.get("is_dead") == true:
			continue

		var dist_sq = my_pos.distance_squared_to(player.global_position)
		if dist_sq <= range_max * range_max:
			return player

	return null

func get_state_name() -> String:
	return "AIOrbit"
