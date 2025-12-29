class_name Heading
extends RefCounted
## Heading - Ported from movement/Heading.as
## Represents the movement state of an entity (position, velocity, rotation, input flags)

## Number of variables in a heading message
const NR_OF_VARS: int = 10

## Server timestamp of this heading state
var time: float = 0.0

## Position in world coordinates
var pos: Vector2 = Vector2.ZERO

## Rotation in radians
var rotation: float = 0.0

## Velocity vector
var speed: Vector2 = Vector2.ZERO

## Input flags
var rotate_left: bool = false
var rotate_right: bool = false
var accelerate: bool = false
var deaccelerate: bool = false
var roll: bool = false

# =============================================================================
# MESSAGE SERIALIZATION
# =============================================================================

## Parse heading data from a network message
## Returns the next index to read from
func parse_message(msg: Message, index: int) -> int:
	# Original format uses x100 for position/speed, x1000 for rotation
	time = msg.get_number(index)
	pos.x = 0.01 * msg.get_int(index + 1)
	pos.y = 0.01 * msg.get_int(index + 2)
	speed.x = 0.01 * msg.get_int(index + 3)
	speed.y = 0.01 * msg.get_int(index + 4)
	rotation = 0.001 * msg.get_int(index + 5)
	accelerate = msg.get_boolean(index + 6)
	deaccelerate = msg.get_boolean(index + 7)
	rotate_left = msg.get_boolean(index + 8)
	rotate_right = msg.get_boolean(index + 9)
	return index + NR_OF_VARS

## Add heading data to a network message (scaled for network precision)
func populate_message(msg: Message) -> Message:
	msg.add(time)
	msg.add(int(pos.x * 100))      # x100 for position precision
	msg.add(int(pos.y * 100))
	msg.add(int(speed.x * 100))    # x100 for speed precision
	msg.add(int(speed.y * 100))
	msg.add(int(rotation * 1000))  # x1000 for rotation precision
	msg.add(accelerate)
	msg.add(deaccelerate)
	msg.add(rotate_left)
	msg.add(rotate_right)
	return msg

## Convert to array for local server processing
func to_array() -> Array:
	return [
		time,
		int(pos.x * 100),  # x100 for network precision
		int(pos.y * 100),
		int(speed.x * 100),
		int(speed.y * 100),
		int(rotation * 1000),  # x1000 for rotation precision
		accelerate,
		deaccelerate,
		rotate_left,
		rotate_right
	]

## Create heading from array (reverse of to_array)
static func from_array(arr: Array) -> Heading:
	var h := Heading.new()
	if arr.size() >= NR_OF_VARS:
		h.time = arr[0]
		h.pos.x = arr[1] / 100.0
		h.pos.y = arr[2] / 100.0
		h.speed.x = arr[3] / 100.0
		h.speed.y = arr[4] / 100.0
		h.rotation = arr[5] / 1000.0
		h.accelerate = arr[6]
		h.deaccelerate = arr[7]
		h.rotate_left = arr[8]
		h.rotate_right = arr[9]
	return h

# =============================================================================
# COMPARISON & COPYING
# =============================================================================

## Check if two headings are approximately equal
func almost_equal(other: Heading, tolerance: float = 0.01) -> bool:
	if absf(pos.x - other.pos.x) > tolerance:
		return false
	if absf(pos.y - other.pos.y) > tolerance:
		return false
	if absf(rotation - other.rotation) > tolerance:
		return false
	if absf(speed.x - other.speed.x) > tolerance:
		return false
	if absf(speed.y - other.speed.y) > tolerance:
		return false
	return true

## Copy values from another heading
func copy_from(other: Heading) -> void:
	time = other.time
	pos = other.pos
	rotation = other.rotation
	speed = other.speed
	accelerate = other.accelerate
	deaccelerate = other.deaccelerate
	rotate_left = other.rotate_left
	rotate_right = other.rotate_right
	roll = other.roll

## Create a duplicate heading
func duplicate() -> Heading:
	var h := Heading.new()
	h.copy_from(self)
	return h

# =============================================================================
# COMMAND HANDLING
# =============================================================================

## Apply a command to this heading (matches Heading.runCommand from AS3)
func run_command(cmd_type: int, active: bool) -> void:
	match cmd_type:
		GameConstantsClass.CommandType.ACCELERATE:
			accelerate = active
		GameConstantsClass.CommandType.ROTATE_LEFT:
			rotate_left = active
		GameConstantsClass.CommandType.ROTATE_RIGHT:
			rotate_right = active
		GameConstantsClass.CommandType.SPEED_BOOST:
			# Speed boost: accelerate + deaccelerate, no rotation
			accelerate = true
			deaccelerate = true
			rotate_left = false
			rotate_right = false
		GameConstantsClass.CommandType.DEACCELERATE:
			deaccelerate = active

# =============================================================================
# UTILITY
# =============================================================================

## Reset to default state
func reset() -> void:
	time = 0.0
	pos = Vector2.ZERO
	rotation = 0.0
	speed = Vector2.ZERO
	accelerate = false
	deaccelerate = false
	rotate_left = false
	rotate_right = false
	roll = false

func _to_string() -> String:
	return "Heading(pos: %s, speed: %s, rot: %.2f, time: %.0f, accel: %s)" % [
		pos, speed, rotation, time, accelerate
	]
