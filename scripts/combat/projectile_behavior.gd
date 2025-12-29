class_name ProjectileBehavior
extends RefCounted
## ProjectileBehavior - Base class for projectile AI behaviors
## Ported from core/states/AIStates/*.as

# =============================================================================
# BEHAVIOR TYPES (from AIStateFactory.as)
# =============================================================================

enum Type {
	BULLET = 0,          # Basic straight projectile
	HOMING_MISSILE = 1,  # Tracks target
	BOOMERANG = 2,       # Returns to owner
	CLUSTER = 3,         # Splits on detonation
	BOUNCING = 4,        # Bounces off walls
	MINE = 5,            # Delayed activation
	BLASTWAVE = 6,       # Expanding AOE
}

# =============================================================================
# STATE
# =============================================================================

var projectile: Node = null  # The projectile this behavior controls
var behavior_type: int = Type.BULLET

# Homing properties
var target: Node = null
var rotation_speed: float = 3.0  # Radians per second
var delayed_acceleration: bool = false
var delayed_acceleration_time: float = 0.0
var _start_time: float = 0.0

# Boomerang properties
var return_time: float = 500.0  # ms before returning
var is_returning: bool = false
var return_direction: int = 0  # 1=clockwise, 2=counter-clockwise, 3=straight
var _elapsed_time: float = 0.0
var _return_start_time: float = 0.0

# Cluster properties
var cluster_projectile: String = ""
var cluster_count: int = 3
var cluster_splits: int = 1
var cluster_angle: float = 0.3  # Radians between projectiles

# Mine properties
var activation_delay: float = 1000.0
var is_activated: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(proj: Node = null, type: int = Type.BULLET) -> void:
	projectile = proj
	behavior_type = type

## Configure behavior from weapon/projectile data
func configure(config: Dictionary) -> void:
	# Homing config
	rotation_speed = config.get("rotationSpeed", 3.0)
	delayed_acceleration = config.get("aiDelayedAcceleration", false)
	delayed_acceleration_time = config.get("aiDelayedAccelerationTime", 0.0)

	# Boomerang config
	return_time = config.get("boomerangReturnTime", 500.0)

	# Cluster config
	cluster_projectile = config.get("clusterProjectile", "")
	cluster_count = config.get("clusterNrOfProjectiles", 3)
	cluster_splits = config.get("clusterNrOfSplits", 1)
	cluster_angle = deg_to_rad(config.get("clusterAngle", 15.0))

	# Mine config
	activation_delay = config.get("aiDelay", 5000.0)

func enter(current_time: float) -> void:
	_start_time = current_time
	_elapsed_time = 0.0
	is_returning = false
	is_activated = false

# =============================================================================
# UPDATE (called each physics frame)
# =============================================================================

## Update behavior, returns true if projectile should continue, false to destroy
func update(delta: float, current_time: float) -> bool:
	match behavior_type:
		Type.BULLET:
			return _update_bullet(delta)
		Type.HOMING_MISSILE:
			return _update_homing(delta, current_time)
		Type.BOOMERANG:
			return _update_boomerang(delta, current_time)
		Type.CLUSTER:
			return _update_cluster(delta)
		Type.MINE:
			return _update_mine(delta, current_time)
		_:
			return _update_bullet(delta)

# =============================================================================
# BULLET (basic straight movement)
# =============================================================================

func _update_bullet(_delta: float) -> bool:
	# Basic bullet has no special behavior, physics handles movement
	return true

# =============================================================================
# HOMING MISSILE (tracks target)
# =============================================================================

func _update_homing(delta: float, current_time: float) -> bool:
	if projectile == null:
		return false

	# Find target if we don't have one
	if target == null or not is_instance_valid(target):
		_find_target()

	# Rotate toward target
	if target != null and is_instance_valid(target):
		var target_pos: Vector2 = target.global_position
		var proj_pos: Vector2 = projectile.global_position
		var target_angle: float = (target_pos - proj_pos).angle()

		# Calculate angle difference
		var current_rot: float = projectile.rotation
		var angle_diff: float = _angle_difference(current_rot, target_angle)

		# Rotate toward target (with max rotation speed)
		var max_rot: float = rotation_speed * delta
		if absf(angle_diff) <= max_rot:
			projectile.rotation = target_angle
		elif angle_diff > 0:
			projectile.rotation += max_rot
		else:
			projectile.rotation -= max_rot

		# Update velocity direction to match rotation
		var speed: float = projectile.velocity.length()
		projectile.velocity = Vector2.RIGHT.rotated(projectile.rotation) * speed

	# Handle delayed acceleration
	if delayed_acceleration:
		if current_time - _start_time < delayed_acceleration_time:
			# Don't apply acceleration yet
			return true

	return true

func _find_target() -> void:
	if projectile == null:
		return

	var proj_is_enemy: bool = projectile.is_enemy if "is_enemy" in projectile else false

	var best_target: Node = null
	var best_dist_sq: float = INF
	var proj_pos: Vector2 = projectile.global_position

	if proj_is_enemy:
		# Enemy projectile - target player
		var players = projectile.get_tree().get_nodes_in_group("player")
		for player in players:
			if is_instance_valid(player):
				var is_dead: bool = player.is_dead if "is_dead" in player else false
				if not is_dead:
					var dist_sq: float = proj_pos.distance_squared_to(player.global_position)
					if dist_sq < best_dist_sq:
						best_dist_sq = dist_sq
						best_target = player
	else:
		# Player projectile - target enemies
		var enemies = projectile.get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy):
				var is_dead: bool = enemy.is_dead if "is_dead" in enemy else false
				if not is_dead:
					var dist_sq: float = proj_pos.distance_squared_to(enemy.global_position)
					if dist_sq < best_dist_sq:
						best_dist_sq = dist_sq
						best_target = enemy

	target = best_target

# =============================================================================
# BOOMERANG (returns to owner)
# =============================================================================

func _update_boomerang(delta: float, current_time: float) -> bool:
	if projectile == null:
		return false

	var delta_ms: float = delta * 1000.0
	_elapsed_time += delta_ms

	var owner_node = projectile.get("owner_node")
	if owner_node == null or not is_instance_valid(owner_node):
		return true  # Just fly straight if no owner

	# Check if it's time to return
	if not is_returning and _elapsed_time > return_time:
		is_returning = true
		_return_start_time = current_time

	if is_returning:
		var owner_pos: Vector2 = owner_node.global_position
		var proj_pos: Vector2 = projectile.global_position

		# Determine rotation direction (only once, after a small delay)
		if return_direction == 0 and current_time - _return_start_time > 100:
			var target_angle: float = (owner_pos - proj_pos).angle()
			var angle_diff: float = _angle_difference(projectile.rotation, target_angle)
			if angle_diff > 0 and angle_diff < PI * 0.95:
				return_direction = 1  # Clockwise
			elif angle_diff < 0 and angle_diff > -PI * 0.95:
				return_direction = 2  # Counter-clockwise
			else:
				return_direction = 3  # Straight

		# Rotate based on direction
		var max_rot: float = rotation_speed * delta
		if return_direction == 1:
			projectile.rotation += max_rot
		elif return_direction == 2:
			projectile.rotation -= max_rot

		# Update velocity direction
		var speed: float = projectile.velocity.length()
		projectile.velocity = Vector2.RIGHT.rotated(projectile.rotation) * speed

		# Check if close to owner - destroy if reached
		if proj_pos.distance_squared_to(owner_pos) < 2500:  # 50 units
			return false  # Destroy

	return true

# =============================================================================
# CLUSTER (splits on detonation)
# =============================================================================

func _update_cluster(delta: float) -> bool:
	if projectile == null:
		return false

	# Check if TTL is about to expire and we should split
	var proj_ttl: float = projectile.ttl if "ttl" in projectile else 0.0
	var delta_ms: float = delta * 1000.0

	if proj_ttl - delta_ms <= 33 and cluster_splits > 0:
		_spawn_cluster_projectiles()
		cluster_splits -= 1
		return false  # Destroy original

	return true

func _spawn_cluster_projectiles() -> void:
	if projectile == null:
		return

	var proj_pos: Vector2 = projectile.global_position
	var proj_rot: float = projectile.rotation
	var proj_vel: Vector2 = projectile.velocity
	var speed: float = proj_vel.length()

	# Calculate starting angle offset
	var total_angle: float = cluster_angle * (cluster_count - 1)
	var start_angle: float = proj_rot - total_angle / 2.0

	# Get projectile properties
	var proj_speed_max: float = projectile.speed_max if "speed_max" in projectile else 1000.0
	var proj_accel: float = projectile.acceleration if "acceleration" in projectile else 0.0
	var proj_ttl_max: float = projectile.ttl_max if "ttl_max" in projectile else 2000.0
	var proj_damage = projectile.damage if "damage" in projectile else null
	var proj_dmg_radius: int = projectile.dmg_radius if "dmg_radius" in projectile else 0
	var proj_sprite: String = projectile.sprite_name if "sprite_name" in projectile else "proj_blaster"
	var proj_owner = projectile.owner_node if "owner_node" in projectile else null
	var proj_weapon = projectile.weapon_ref if "weapon_ref" in projectile else null
	var proj_is_enemy: bool = projectile.is_enemy if "is_enemy" in projectile else false

	for i in range(cluster_count):
		var spawn_angle: float = start_angle + i * cluster_angle
		var spawn_vel: Vector2 = Vector2.RIGHT.rotated(spawn_angle) * speed

		# Create projectile data
		var spawn_data: Dictionary = {
			"position": proj_pos,
			"rotation": spawn_angle,
			"velocity": spawn_vel,
			"speed_max": proj_speed_max,
			"acceleration": proj_accel,
			"ttl": proj_ttl_max * (0.6 if cluster_count > 4 else 1.0),
			"damage": proj_damage,
			"dmg_radius": proj_dmg_radius,
			"number_of_hits": 1,
			"sprite_name": cluster_projectile if cluster_projectile != "" else proj_sprite,
			"owner": proj_owner,
			"weapon": proj_weapon,
			"is_enemy": proj_is_enemy,
			# Pass cluster config for recursive splitting
			"behavior_type": Type.CLUSTER if cluster_splits > 1 else Type.BULLET,
			"clusterNrOfSplits": cluster_splits - 1,
			"clusterNrOfProjectiles": cluster_count,
			"clusterAngle": rad_to_deg(cluster_angle),
		}

		ProjectileManager.spawn(spawn_data)

# =============================================================================
# MINE (delayed activation)
# =============================================================================

func _update_mine(delta: float, current_time: float) -> bool:
	if projectile == null:
		return false

	var delta_ms: float = delta * 1000.0
	_elapsed_time += delta_ms

	if not is_activated and _elapsed_time >= activation_delay:
		is_activated = true
		# Could trigger visual change here

	# Mines typically slow down and stop
	if is_activated:
		projectile.velocity *= 0.95  # Decelerate
		if projectile.velocity.length_squared() < 1.0:
			projectile.velocity = Vector2.ZERO

	return true

# =============================================================================
# UTILITY
# =============================================================================

## Calculate shortest angle difference (handles wraparound)
func _angle_difference(from_angle: float, to_angle: float) -> float:
	var diff: float = fmod(to_angle - from_angle + PI, TAU) - PI
	return diff

# =============================================================================
# FACTORY
# =============================================================================

static func create_bullet(proj: Node):
	return new(proj, Type.BULLET)

static func create_homing(proj: Node, rot_speed: float = 3.0):
	var b := new(proj, Type.HOMING_MISSILE)
	b.rotation_speed = rot_speed
	return b

static func create_boomerang(proj: Node, ret_time: float = 500.0):
	var b := new(proj, Type.BOOMERANG)
	b.return_time = ret_time
	return b

static func create_cluster(proj: Node, count: int = 3, angle_deg: float = 15.0, splits: int = 1):
	var b := new(proj, Type.CLUSTER)
	b.cluster_count = count
	b.cluster_angle = deg_to_rad(angle_deg)
	b.cluster_splits = splits
	return b

static func create_mine(proj: Node, delay: float = 5000.0):
	var b := new(proj, Type.MINE)
	b.activation_delay = delay
	return b

static func create_from_config(proj: Node, config: Dictionary):
	var ai_type: String = config.get("ai", "bullet")
	var b

	match ai_type:
		"homingMissile":
			b = create_homing(proj, config.get("rotationSpeed", 3.0))
		"boomerang":
			b = create_boomerang(proj, config.get("boomerangReturnTime", 500.0))
		"cluster":
			b = create_cluster(proj,
				config.get("clusterNrOfProjectiles", 3),
				config.get("clusterAngle", 15.0),
				config.get("clusterNrOfSplits", 1))
		"mine":
			b = create_mine(proj, config.get("aiDelay", 5000.0))
		_:
			b = create_bullet(proj)

	b.configure(config)
	return b
