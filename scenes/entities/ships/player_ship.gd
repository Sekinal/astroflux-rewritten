class_name PlayerShip
extends CharacterBody2D
## PlayerShip - The player's controllable ship
## Ported from core/ship/PlayerShip.as

# =============================================================================
# SIGNALS
# =============================================================================

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal died

# =============================================================================
# ENGINE PROPERTIES
# =============================================================================

@export_group("Engine")
@export var max_speed: float = 300.0
@export var acceleration: float = 0.5
@export var rotation_speed: float = 180.0
@export var boost_bonus: float = 50.0

# =============================================================================
# COMBAT PROPERTIES
# =============================================================================

@export_group("Combat")
@export var hp_max: float = 100.0
@export var shield_max: float = 100.0
@export var shield_regen: float = 5.0
@export var armor_threshold: float = 50.0

# =============================================================================
# STATE
# =============================================================================

var hp: float = 100.0
var shield: float = 100.0
var is_dead: bool = false
var _using_boost: bool = false
var _slowed_until: float = 0.0
var _slowdown_amount: float = 0.0

# =============================================================================
# MOVEMENT
# =============================================================================

var converger: Converger
var _last_command_time: float = 0.0
var _pending_commands: Array[Dictionary] = []

# =============================================================================
# NODES
# =============================================================================

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	converger = Converger.new(self)
	hp = hp_max
	shield = shield_max

	# Register message handlers
	NetworkManager.add_message_handler("playerCourse", _on_player_course)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Handle input
	_process_input()

	# Run physics through converger
	converger.run(NetworkManager.server_time)

	# Apply converger state to node
	global_position = converger.course.pos
	rotation = converger.course.rotation

	# Regenerate shield
	_regenerate_shield(delta)

func _process_input() -> void:
	var heading := converger.course

	# Get input state
	var accelerating := Input.is_action_pressed("accelerate")
	var braking := Input.is_action_pressed("brake")
	var rotating_left := Input.is_action_pressed("rotate_left")
	var rotating_right := Input.is_action_pressed("rotate_right")
	var boosting := Input.is_action_pressed("boost")

	# Check for state changes
	var changed := false

	if heading.accelerate != accelerating:
		heading.accelerate = accelerating
		changed = true
	if heading.deaccelerate != braking:
		heading.deaccelerate = braking
		changed = true
	if heading.rotate_left != rotating_left:
		heading.rotate_left = rotating_left
		changed = true
	if heading.rotate_right != rotating_right:
		heading.rotate_right = rotating_right
		changed = true
	if _using_boost != boosting:
		_using_boost = boosting
		changed = true

	# Send command to server if changed
	if changed:
		_send_movement_command()

func _send_movement_command() -> void:
	var heading := converger.course
	var msg := Message.new("playerCourse")
	heading.time = NetworkManager.server_time
	heading.populate_message(msg)
	NetworkManager.send_message(msg)

# =============================================================================
# NETWORK HANDLERS
# =============================================================================

func _on_player_course(msg: Message) -> void:
	# First arg is player ID
	var player_id := msg.get_string(0)

	# Check if this is for us
	if player_id != LocalServer.player_id:
		return

	# Parse heading starting at index 1
	var new_heading := Heading.new()
	new_heading.parse_message(msg, 1)

	# Set as converge target for smooth interpolation
	converger.set_converge_target(new_heading, NetworkManager.server_time)

# =============================================================================
# COMBAT
# =============================================================================

func take_damage(damage: float, damage_type: int = 0) -> void:
	if is_dead:
		return

	# Apply to shield first
	if shield > 0:
		var shield_damage := minf(damage, shield)
		shield -= shield_damage
		damage -= shield_damage
		shield_changed.emit(shield, shield_max)

	# Remaining damage to health
	if damage > 0:
		hp -= damage
		health_changed.emit(hp, hp_max)

		if hp <= 0:
			_die()

func _die() -> void:
	is_dead = true
	died.emit()
	# TODO: Play death effects, respawn timer

func _regenerate_shield(delta: float) -> void:
	if shield < shield_max:
		shield = minf(shield + shield_regen * delta, shield_max)
		# Only emit if changed significantly
		if int(shield) != int(shield - shield_regen * delta):
			shield_changed.emit(shield, shield_max)

# =============================================================================
# SHIP PROPERTY ACCESSORS (used by Converger)
# =============================================================================

func is_enemy() -> bool:
	return false

func get_rotation_speed() -> float:
	return rotation_speed

func get_acceleration() -> float:
	return acceleration

func get_max_speed() -> float:
	return max_speed

func is_using_boost() -> bool:
	return _using_boost

func get_boost_bonus() -> float:
	return boost_bonus

func is_slowed(server_time: float) -> bool:
	return _slowed_until > server_time

func get_slowdown() -> float:
	return _slowdown_amount
