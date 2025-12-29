class_name NetworkProtocol
extends RefCounted
## NetworkProtocol - Binary message serialization matching PlayerIO format
## Ported from playerio_client.py

# =============================================================================
# TYPE PATTERNS (from PlayerIO binary format)
# =============================================================================

const SHORT_STRING: int = 0xC0      # String < 64 bytes
const SHORT_UINT: int = 0x80        # Unsigned int < 64
const SHORT_BYTEARRAY: int = 0x40   # Byte array < 64 bytes
const STRING: int = 0x0C            # String with length prefix
const UINT: int = 0x08              # Unsigned integer
const INT: int = 0x04               # Signed integer
const DOUBLE: int = 0x03            # 64-bit float
const FLOAT: int = 0x02             # 32-bit float
const TRUE: int = 0x01              # Boolean true
const FALSE: int = 0x00             # Boolean false
const BYTEARRAY: int = 0x10         # Byte array with length

# =============================================================================
# SERIALIZATION
# =============================================================================

## Serialize a Message to binary format
static func serialize_message(msg: Message) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()

	# Serialize arg count
	result.append_array(_serialize_value(msg.args.size()))

	# Serialize message type
	result.append_array(_serialize_value(msg.type))

	# Serialize each argument
	for arg in msg.args:
		result.append_array(_serialize_value(arg))

	return result

## Serialize a single value
static func _serialize_value(value: Variant) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()

	if value is String:
		var str_value: String = value as String
		var encoded: PackedByteArray = str_value.to_utf8_buffer()
		if encoded.size() < 64:
			result.append(SHORT_STRING | encoded.size())
		else:
			var len_bytes: PackedByteArray = _get_uint_bytes(encoded.size())
			result.append(STRING | (len_bytes.size() - 1))
			result.append_array(len_bytes)
		result.append_array(encoded)

	elif value is bool:
		result.append(TRUE if value else FALSE)

	elif value is int:
		var int_value: int = value as int
		if int_value >= 0 and int_value < 64:
			result.append(SHORT_UINT | int_value)
		elif int_value >= 0:
			var uint_bytes: PackedByteArray = _get_uint_bytes(int_value)
			result.append(UINT | (uint_bytes.size() - 1))
			result.append_array(uint_bytes)
		else:
			var int_bytes: PackedByteArray = _get_int_bytes(int_value)
			result.append(INT | (int_bytes.size() - 1))
			result.append_array(int_bytes)

	elif value is float:
		var float_value: float = value as float
		# Try float first, use double if needed for precision
		var float_buf: PackedByteArray = PackedByteArray()
		float_buf.resize(4)
		float_buf.encode_float(0, float_value)
		var test: float = float_buf.decode_float(0)
		if is_equal_approx(test, float_value):
			result.append(FLOAT)
			result.append_array(float_buf)
		else:
			var double_buf: PackedByteArray = PackedByteArray()
			double_buf.resize(8)
			double_buf.encode_double(0, float_value)
			result.append(DOUBLE)
			result.append_array(double_buf)

	elif value is PackedByteArray:
		var byte_value: PackedByteArray = value as PackedByteArray
		if byte_value.size() < 64:
			result.append(SHORT_BYTEARRAY | byte_value.size())
		else:
			var len_bytes: PackedByteArray = _get_uint_bytes(byte_value.size())
			result.append(BYTEARRAY | (len_bytes.size() - 1))
			result.append_array(len_bytes)
		result.append_array(byte_value)

	return result

## Get unsigned int as minimal bytes (big-endian)
static func _get_uint_bytes(value: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(4)
	result.encode_u32(0, value)
	# Reverse for big-endian
	result.reverse()
	# Trim leading zeros
	while result.size() > 1 and result[0] == 0:
		result.remove_at(0)
	return result

## Get signed int as minimal bytes (big-endian)
static func _get_int_bytes(value: int) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	result.resize(4)
	result.encode_s32(0, value)
	# Reverse for big-endian
	result.reverse()
	# Trim leading bytes while preserving sign
	while result.size() > 1:
		if (result[0] == 0 and (result[1] & 0x80) == 0) or \
		   (result[0] == 0xFF and (result[1] & 0x80) != 0):
			result.remove_at(0)
		else:
			break
	return result

# =============================================================================
# DESERIALIZATION
# =============================================================================

## Deserialize a Message from binary data
static func deserialize_message(data: PackedByteArray) -> Message:
	var reader: ByteReader = ByteReader.new(data)

	# Read arg count
	var arg_count: int = reader.read_value() as int

	# Read message type
	var msg_type: String = reader.read_value() as String

	# Read arguments
	var args: Array = []
	for i in range(arg_count):
		args.append(reader.read_value())

	return Message.new(msg_type, args)

## Helper class for reading binary data
class ByteReader:
	var data: PackedByteArray
	var pos: int = 0

	func _init(bytes: PackedByteArray) -> void:
		data = bytes

	func read_byte() -> int:
		if pos >= data.size():
			return 0
		var b: int = data[pos]
		pos += 1
		return b

	func read_bytes(count: int) -> PackedByteArray:
		var result: PackedByteArray = data.slice(pos, pos + count)
		pos += count
		return result

	func read_value() -> Variant:
		var type_byte: int = read_byte()

		# Boolean
		if type_byte == NetworkProtocol.TRUE:
			return true
		elif type_byte == NetworkProtocol.FALSE:
			return false

		# Float
		elif type_byte == NetworkProtocol.FLOAT:
			var buf: PackedByteArray = read_bytes(4)
			return buf.decode_float(0)

		# Double
		elif type_byte == NetworkProtocol.DOUBLE:
			var buf: PackedByteArray = read_bytes(8)
			return buf.decode_double(0)

		# Short string
		elif (type_byte & 0xC0) == NetworkProtocol.SHORT_STRING:
			var length: int = type_byte & 0x3F
			return read_bytes(length).get_string_from_utf8()

		# Long string
		elif (type_byte & 0x0F) == NetworkProtocol.STRING:
			var byte_count: int = (type_byte & 0x03) + 1
			var length: int = _read_uint(byte_count)
			return read_bytes(length).get_string_from_utf8()

		# Short unsigned int
		elif (type_byte & 0xC0) == NetworkProtocol.SHORT_UINT:
			return type_byte & 0x3F

		# Unsigned int
		elif (type_byte & 0x0F) == NetworkProtocol.UINT:
			var byte_count: int = (type_byte & 0x03) + 1
			return _read_uint(byte_count)

		# Signed int
		elif (type_byte & 0x0F) == NetworkProtocol.INT:
			var byte_count: int = (type_byte & 0x03) + 1
			return _read_int(byte_count)

		# Short byte array
		elif (type_byte & 0xC0) == NetworkProtocol.SHORT_BYTEARRAY:
			var length: int = type_byte & 0x3F
			return read_bytes(length)

		# Long byte array
		elif (type_byte & 0x0F) == NetworkProtocol.BYTEARRAY:
			var byte_count: int = (type_byte & 0x03) + 1
			var length: int = _read_uint(byte_count)
			return read_bytes(length)

		return null

	func _read_uint(byte_count: int) -> int:
		var bytes: PackedByteArray = read_bytes(byte_count)
		var result: int = 0
		for b in bytes:
			result = (result << 8) | b
		return result

	func _read_int(byte_count: int) -> int:
		var bytes: PackedByteArray = read_bytes(byte_count)
		var result: int = 0
		var is_negative: bool = (bytes[0] & 0x80) != 0
		for b in bytes:
			result = (result << 8) | b
		if is_negative:
			# Sign extend
			result = result - (1 << (byte_count * 8))
		return result
