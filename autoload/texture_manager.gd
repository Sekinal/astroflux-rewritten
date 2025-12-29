class_name TextureManagerClass
extends Node
## TextureManager - Loads and manages texture atlases from TexturePacker XML format
## Provides AtlasTexture regions for sprites from the original game assets

# =============================================================================
# SIGNALS
# =============================================================================

signal atlases_loaded

# =============================================================================
# ATLAS DATA
# =============================================================================

## Loaded atlas textures (PNG images)
var _atlas_textures: Dictionary = {}

## Sprite data from XML (name -> SubTextureData)
var _sprite_data: Dictionary = {}

## Cached AtlasTexture instances
var _atlas_cache: Dictionary = {}

## Whether atlases have been loaded
var _loaded: bool = false

# =============================================================================
# SUBTEXTURE DATA CLASS
# =============================================================================

class SubTextureData:
	var atlas_name: String = ""
	var x: int = 0
	var y: int = 0
	var width: int = 0
	var height: int = 0
	var rotated: bool = false
	var frame_x: int = 0
	var frame_y: int = 0
	var frame_width: int = 0
	var frame_height: int = 0

	func has_frame() -> bool:
		return frame_width > 0 or frame_height > 0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	load_all_atlases()

func load_all_atlases() -> void:
	if _loaded:
		return

	var atlas_files := [
		"texture_main_NEW",
		"texture_body",
		"texture_gui1_test",
		"texture_gui2"
	]

	for atlas_name in atlas_files:
		_load_atlas(atlas_name)

	_loaded = true
	atlases_loaded.emit()
	print("[TextureManager] Loaded %d sprites from %d atlases" % [_sprite_data.size(), _atlas_textures.size()])

func _load_atlas(atlas_name: String) -> void:
	var base_path := "res://assets/textures/"
	var png_path := base_path + atlas_name + ".png"
	var xml_path := base_path + atlas_name + ".xml"

	# Load the PNG texture
	if not FileAccess.file_exists(png_path):
		push_warning("[TextureManager] Atlas PNG not found: %s" % png_path)
		return

	var texture := load(png_path) as Texture2D
	if texture == null:
		push_warning("[TextureManager] Failed to load atlas texture: %s" % png_path)
		return

	_atlas_textures[atlas_name] = texture

	# Parse the XML
	if not FileAccess.file_exists(xml_path):
		push_warning("[TextureManager] Atlas XML not found: %s" % xml_path)
		return

	_parse_atlas_xml(atlas_name, xml_path)

func _parse_atlas_xml(atlas_name: String, xml_path: String) -> void:
	var file := FileAccess.open(xml_path, FileAccess.READ)
	if file == null:
		push_warning("[TextureManager] Failed to open XML: %s" % xml_path)
		return

	var parser := XMLParser.new()
	var err := parser.open(xml_path)
	if err != OK:
		push_warning("[TextureManager] Failed to parse XML: %s" % xml_path)
		return

	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()
			if node_name == "SubTexture":
				var data := SubTextureData.new()
				data.atlas_name = atlas_name

				var sprite_name := ""
				for i in parser.get_attribute_count():
					var attr_name := parser.get_attribute_name(i)
					var attr_value := parser.get_attribute_value(i)

					match attr_name:
						"name":
							sprite_name = attr_value
						"x":
							data.x = int(attr_value)
						"y":
							data.y = int(attr_value)
						"width":
							data.width = int(attr_value)
						"height":
							data.height = int(attr_value)
						"rotated":
							data.rotated = attr_value == "true"
						"frameX":
							data.frame_x = int(attr_value)
						"frameY":
							data.frame_y = int(attr_value)
						"frameWidth":
							data.frame_width = int(attr_value)
						"frameHeight":
							data.frame_height = int(attr_value)

				if sprite_name != "":
					_sprite_data[sprite_name] = data

# =============================================================================
# PUBLIC API
# =============================================================================

## Get an AtlasTexture for a sprite by name
func get_sprite(sprite_name: String) -> AtlasTexture:
	# Check cache first
	if _atlas_cache.has(sprite_name):
		return _atlas_cache[sprite_name]

	# Look up sprite data
	if not _sprite_data.has(sprite_name):
		push_warning("[TextureManager] Sprite not found: %s" % sprite_name)
		return null

	var data: SubTextureData = _sprite_data[sprite_name]
	var atlas_texture: Texture2D = _atlas_textures.get(data.atlas_name)
	if atlas_texture == null:
		push_warning("[TextureManager] Atlas not loaded: %s" % data.atlas_name)
		return null

	# Create AtlasTexture
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_texture

	# Handle rotation (TexturePacker rotates 90 degrees clockwise)
	if data.rotated:
		# When rotated, width and height are swapped in the atlas
		atlas.region = Rect2(data.x, data.y, data.height, data.width)
	else:
		atlas.region = Rect2(data.x, data.y, data.width, data.height)

	# Handle frame (for trimmed sprites)
	if data.has_frame():
		atlas.margin = Rect2(
			-data.frame_x if not data.rotated else -data.frame_y,
			-data.frame_y if not data.rotated else -data.frame_x,
			data.frame_width - data.width if not data.rotated else data.frame_height - data.height,
			data.frame_height - data.height if not data.rotated else data.frame_width - data.width
		)

	# Cache and return
	_atlas_cache[sprite_name] = atlas
	return atlas

## Get all sprites matching a pattern (for animations)
func get_sprites_matching(pattern: String) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []
	var regex := RegEx.new()
	regex.compile(pattern)

	for sprite_name in _sprite_data.keys():
		if regex.search(sprite_name):
			var tex := get_sprite(sprite_name)
			if tex != null:
				result.append(tex)

	return result

## Get animation frames for a sprite (expects naming like "name_01", "name_02", etc. or "name1", "name2")
func get_animation_frames(base_name: String, frame_count: int = 0) -> Array[AtlasTexture]:
	var result: Array[AtlasTexture] = []

	if frame_count > 0:
		# Try numbered format
		for i in range(1, frame_count + 1):
			var names_to_try := [
				"%s_%02d" % [base_name, i],  # name_01
				"%s%d" % [base_name, i],      # name1
				"%s_%d" % [base_name, i],     # name_1
			]

			for sprite_name in names_to_try:
				if _sprite_data.has(sprite_name):
					var tex := get_sprite(sprite_name)
					if tex != null:
						result.append(tex)
					break
	else:
		# Auto-detect frames
		var i := 1
		while true:
			var found := false
			var names_to_try := [
				"%s_%02d" % [base_name, i],
				"%s%d" % [base_name, i],
				"%s_%d" % [base_name, i],
			]

			for sprite_name in names_to_try:
				if _sprite_data.has(sprite_name):
					var tex := get_sprite(sprite_name)
					if tex != null:
						result.append(tex)
						found = true
					break

			if not found:
				break
			i += 1

	return result

## Check if a sprite exists
func has_sprite(sprite_name: String) -> bool:
	return _sprite_data.has(sprite_name)

## Get all sprite names
func get_all_sprite_names() -> Array:
	return _sprite_data.keys()

## Get sprite names matching a prefix
func get_sprites_with_prefix(prefix: String) -> Array:
	var result := []
	for sprite_name in _sprite_data.keys():
		if sprite_name.begins_with(prefix):
			result.append(sprite_name)
	return result

## Get the raw SubTextureData for a sprite
func get_sprite_data(sprite_name: String) -> SubTextureData:
	return _sprite_data.get(sprite_name)

## Check if atlases are loaded
func is_loaded() -> bool:
	return _loaded

## Get sprite size (accounting for rotation)
func get_sprite_size(sprite_name: String) -> Vector2:
	if not _sprite_data.has(sprite_name):
		return Vector2.ZERO

	var data: SubTextureData = _sprite_data[sprite_name]
	if data.rotated:
		return Vector2(data.height, data.width)
	else:
		return Vector2(data.width, data.height)
