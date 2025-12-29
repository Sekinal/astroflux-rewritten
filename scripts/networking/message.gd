class_name Message
extends RefCounted
## Network Message - Ported from playerio/Message.as
## Container for network messages with typed accessors

var type: String = ""
var args: Array = []

func _init(msg_type: String = "", initial_args: Array = []) -> void:
	type = msg_type
	args = initial_args.duplicate()

# =============================================================================
# ADD METHODS
# =============================================================================

func add(value: Variant) -> Message:
	args.append(value)
	return self

func add_string(value: String) -> Message:
	args.append(value)
	return self

func add_int(value: int) -> Message:
	args.append(value)
	return self

func add_float(value: float) -> Message:
	args.append(value)
	return self

func add_bool(value: bool) -> Message:
	args.append(value)
	return self

# =============================================================================
# GET METHODS (with type safety)
# =============================================================================

func get_string(index: int) -> String:
	if index < 0 or index >= args.size():
		push_error("Message.get_string: index %d out of bounds (size: %d)" % [index, args.size()])
		return ""
	return str(args[index])

func get_int(index: int) -> int:
	if index < 0 or index >= args.size():
		push_error("Message.get_int: index %d out of bounds (size: %d)" % [index, args.size()])
		return 0
	var val = args[index]
	if val is float:
		return int(val)
	return int(val) if val != null else 0

func get_number(index: int) -> float:
	if index < 0 or index >= args.size():
		push_error("Message.get_number: index %d out of bounds (size: %d)" % [index, args.size()])
		return 0.0
	var val = args[index]
	return float(val) if val != null else 0.0

func get_boolean(index: int) -> bool:
	if index < 0 or index >= args.size():
		push_error("Message.get_boolean: index %d out of bounds (size: %d)" % [index, args.size()])
		return false
	return bool(args[index])

func get_bytes(index: int) -> PackedByteArray:
	if index < 0 or index >= args.size():
		push_error("Message.get_bytes: index %d out of bounds (size: %d)" % [index, args.size()])
		return PackedByteArray()
	var val = args[index]
	if val is PackedByteArray:
		return val
	return PackedByteArray()

# =============================================================================
# UTILITY
# =============================================================================

var length: int:
	get: return args.size()

func clear() -> void:
	args.clear()

func duplicate_msg() -> Message:
	return Message.new(type, args.duplicate())

func _to_string() -> String:
	return "Message(%s, %s)" % [type, str(args)]

# =============================================================================
# SERIALIZATION (Binary format matching PlayerIO)
# =============================================================================

## Serialize message to binary format for network transmission
func to_bytes() -> PackedByteArray:
	return NetworkProtocol.serialize_message(self)

## Create message from binary data
static func from_bytes(data: PackedByteArray) -> Message:
	return NetworkProtocol.deserialize_message(data)
