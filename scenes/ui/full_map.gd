class_name FullMap
extends Control
## FullMap - Full screen solar system map (press M to open)
## Ported from core/hud/components/map/Map.as

# =============================================================================
# SIGNALS
# =============================================================================

signal closed

# =============================================================================
# CONFIGURATION (from original Map.as)
# =============================================================================

var SCALE: float = 0.1  ## Dynamic scale based on orbit sizes

# Background texture is 760x600, inner drawing area is padded
const BG_WIDTH: float = 760.0
const BG_HEIGHT: float = 600.0
const PADDING: float = 31.0
const WIDTH: float = 698.0   # BG_WIDTH - PADDING*2
const HEIGHT: float = 538.0  # BG_HEIGHT - PADDING*2

# =============================================================================
# COLORS (from Style.as)
# =============================================================================

const COLOR_MAP_PLANET: int = 0xFF6663  # Red-ish for planets
const COLOR_FRIENDLY: int = 0x22FF66  # Green
const COLOR_HOSTILE: int = 0xFF4444  # Red
const COLOR_WARP_GATE: int = 0x22A966  # Teal
const COLOR_SHOP: int = 0x4444FF  # Blue
const COLOR_RESEARCH: int = 0x662222  # Dark red
const COLOR_BYLINE: int = 0x888888  # Gray
const COLOR_ORBIT: int = 0x00BFFF  # Cyan orbit lines

# =============================================================================
# STATE
# =============================================================================

var player_ship: Node = null
var _is_open: bool = false
var _map_offset: Vector2 = Vector2.ZERO  # Offset to center on player

# Textures
var _tex_background: AtlasTexture = null
var _tex_sun: AtlasTexture = null
var _tex_spawner: AtlasTexture = null
var _tex_warpgate: AtlasTexture = null
var _tex_shop: AtlasTexture = null
var _tex_research: AtlasTexture = null

# =============================================================================
# NODES
# =============================================================================

@onready var system_name_label: Label = $MapContainer/SystemName
@onready var coords_label: Label = $MapContainer/Coordinates
@onready var close_button: Button = $MapContainer/CloseButton

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false

	# Load textures
	if TextureManager.is_loaded():
		_load_textures()
	else:
		TextureManager.atlases_loaded.connect(_load_textures)

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _load_textures() -> void:
	_tex_background = TextureManager.get_sprite("map_bgr")
	_tex_sun = TextureManager.get_sprite("map_sun")
	_tex_spawner = TextureManager.get_sprite("map_spawner")
	_tex_warpgate = TextureManager.get_sprite("map_warpgate")
	_tex_shop = TextureManager.get_sprite("map_shop")
	_tex_research = TextureManager.get_sprite("map_research")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _is_open:
			close_map()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _is_open:
		_update_map()
		queue_redraw()

# =============================================================================
# MAP CONTROL
# =============================================================================

func toggle_map() -> void:
	if _is_open:
		close_map()
	else:
		open_map()

func open_map() -> void:
	_is_open = true
	visible = true
	_calculate_scale()
	get_tree().paused = true

func close_map() -> void:
	_is_open = false
	visible = false
	closed.emit()
	get_tree().paused = false

func _on_close_pressed() -> void:
	close_map()

func _calculate_scale() -> void:
	# Find the maximum orbit radius to scale the map (like original)
	var max_radius: float = 200.0
	SCALE = 0.1

	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		# Skip comets
		if body.body_type == 6:  # COMET
			continue
		if body.get("orbit_radius") != null and body.orbit_radius > 0:
			if body.orbit_radius * SCALE > max_radius:
				SCALE = max_radius / body.orbit_radius

func _update_map() -> void:
	# Update labels
	if system_name_label:
		system_name_label.text = BodyManager.current_system_name

	# Update coordinates based on player position
	if coords_label and player_ship != null and is_instance_valid(player_ship):
		var pos: Vector2 = player_ship.global_position
		coords_label.text = "Current position: %d, %d" % [int(pos.x), int(pos.y)]

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	if not _is_open:
		return

	var screen_center := size / 2

	# Draw dark overlay behind everything
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9))

	# Calculate background position (centered on screen)
	var bg_pos := screen_center - Vector2(BG_WIDTH, BG_HEIGHT) / 2

	# Draw map background texture
	if _tex_background != null:
		draw_texture(_tex_background, bg_pos)
	else:
		# Fallback rectangle
		draw_rect(Rect2(bg_pos, Vector2(BG_WIDTH, BG_HEIGHT)), Color(0.02, 0.04, 0.08, 0.95))
		draw_rect(Rect2(bg_pos, Vector2(BG_WIDTH, BG_HEIGHT)), Color(0.2, 0.3, 0.4, 0.5), false, 2.0)

	# The map center is the center of the background
	var map_center := screen_center

	# Get player world position
	var player_world_pos := Vector2.ZERO
	if player_ship != null and is_instance_valid(player_ship):
		player_world_pos = player_ship.global_position

	# Calculate map offset to center on player (like original: mapContainer.x = WIDTH/2 - player.x)
	_map_offset = map_center - player_world_pos * SCALE

	# Create clipping rect (inner area of background, excluding padding)
	var clip_rect := Rect2(
		bg_pos + Vector2(PADDING, PADDING),
		Vector2(WIDTH, HEIGHT)
	)

	# Draw orbit rings first (suns draw their children's orbits)
	_draw_orbits(clip_rect)

	# Draw suns
	_draw_suns(clip_rect)

	# Draw stations (warp gates, shops, research)
	_draw_stations(clip_rect)

	# Draw planets
	_draw_planets(clip_rect)

	# Draw spawners
	_draw_spawners(clip_rect)

	# Draw player
	_draw_player(clip_rect)

func _world_to_map(world_pos: Vector2) -> Vector2:
	return _map_offset + world_pos * SCALE

func _is_in_clip_rect(pos: Vector2, clip_rect: Rect2, tex_size: float = 0.0) -> bool:
	## Check if position is inside clip rect, accounting for texture size
	## Allows textures whose center is near the edge but partially visible
	var expanded := clip_rect.grow(tex_size / 2)
	return expanded.has_point(pos)

func _draw_orbits(clip_rect: Rect2) -> void:
	# Draw orbit circles for each body's children
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if not body.get("children"):
			continue

		var body_map_pos := _world_to_map(body.global_position)

		for child in body.children:
			if not is_instance_valid(child):
				continue
			# Skip comets, hidden, boss, warning
			if child.body_type in [6, 8, 13, 14]:  # COMET, BOSS, HIDDEN, WARNING
				continue

			var orbit_radius_scaled: float = child.orbit_radius * SCALE
			if orbit_radius_scaled > 3 and orbit_radius_scaled < 500:
				draw_arc(body_map_pos, orbit_radius_scaled, 0, TAU, 64,
					Color(0.0, 0.75, 1.0, 0.3), 1.5)

func _draw_suns(clip_rect: Rect2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if body.body_type != 0:  # Not SUN
			continue

		var map_pos := _world_to_map(body.global_position)
		var tex_size_check := 44.0 if _tex_sun != null else 40.0  # map_sun is 44x44
		if not _is_in_clip_rect(map_pos, clip_rect, tex_size_check):
			continue

		if _tex_sun != null:
			var tex_size := Vector2(_tex_sun.get_width(), _tex_sun.get_height())
			# Check for black hole (special color)
			var color := Color.WHITE
			if body.body_name == "Black Hole":
				color = Color(0.4, 0.4, 0.6)
			draw_texture(_tex_sun, map_pos - tex_size / 2, color)
		else:
			# Fallback: draw circle
			draw_circle(map_pos, 20.0, Color(1.0, 0.85, 0.2))

func _draw_stations(clip_rect: Rect2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		# Skip non-station types
		if body.body_type not in [2, 3, 4, 5, 9, 10, 11]:  # WARP, SHOP, RESEARCH, JUNK, HANGAR, CANTINA, PAINT
			continue

		var map_pos := _world_to_map(body.global_position)
		if not _is_in_clip_rect(map_pos, clip_rect, 20.0):  # Station textures are 20x20
			continue

		var tex: AtlasTexture = null
		var color := Color.WHITE

		match body.body_type:
			2:  # WARP_GATE
				tex = _tex_warpgate
				color = Color.from_string("#22A966", Color.GREEN)
			3:  # SHOP
				tex = _tex_shop
				color = Color.from_string("#4444FF", Color.BLUE)
			4:  # RESEARCH
				tex = _tex_research
				color = Color.from_string("#662222", Color.DARK_RED)
			_:
				tex = _tex_shop
				color = Color.from_string("#88AA66", Color.OLIVE)

		if tex != null:
			var tex_size := Vector2(tex.get_width(), tex.get_height())
			draw_texture(tex, map_pos - tex_size / 2, color)
		else:
			draw_circle(map_pos, 8.0, color)

		# Draw name
		if body.get("body_name"):
			var font := ThemeDB.fallback_font
			var text_pos := map_pos + Vector2(-30, 12)
			draw_string(font, text_pos, body.body_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, color)

func _draw_planets(clip_rect: Rect2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if body.body_type != 1:  # Not PLANET
			continue

		# Draw planet as colored circle (scaled from original texture)
		var planet_scale: float = SCALE * 1.5
		var radius: float = max(4.0, body.radius * planet_scale * 0.5)

		var map_pos := _world_to_map(body.global_position)
		if not _is_in_clip_rect(map_pos, clip_rect, radius * 2 + 6):  # Planet size + glow
			continue

		# Planet color
		var color := Color.from_string("#FF6663", Color.RED)

		# Draw glow
		draw_circle(map_pos, radius + 3, Color(color.r, color.g, color.b, 0.3))
		draw_circle(map_pos, radius, color)

		# Draw name
		if body.get("body_name") and body.get("landable"):
			var font := ThemeDB.fallback_font
			var text_pos := map_pos + Vector2(-30, radius + 12)
			draw_string(font, text_pos, body.body_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, color)

func _draw_spawners(clip_rect: Rect2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if not body.get("spawners"):
			continue

		for spawner in body.spawners:
			if not is_instance_valid(spawner):
				continue

			var map_pos := _world_to_map(spawner.global_position)
			if not _is_in_clip_rect(map_pos, clip_rect, 4.0):  # Spawner texture is 4x4
				continue

			# Color: orange for hostile spawners
			var color := Color.from_string("#C83444", Color.ORANGE_RED)

			if _tex_spawner != null:
				var tex_size := Vector2(_tex_spawner.get_width(), _tex_spawner.get_height())
				draw_texture(_tex_spawner, map_pos - tex_size / 2, color)
			else:
				draw_circle(map_pos, 3.0, color)

func _draw_player(clip_rect: Rect2) -> void:
	if player_ship == null or not is_instance_valid(player_ship):
		return

	var map_pos := _world_to_map(player_ship.global_position)
	var player_rot: float = player_ship.rotation

	# Draw player ship (scaled sprite or triangle)
	var ship_scale: float = 0.35

	# Draw glow
	draw_circle(map_pos, 15, Color(1.0, 1.0, 1.0, 0.2))

	# Draw ship as rotated triangle
	var tri_size: float = 12.0
	var points := PackedVector2Array([
		map_pos + Vector2(tri_size, 0).rotated(player_rot),
		map_pos + Vector2(-tri_size * 0.7, tri_size * 0.6).rotated(player_rot),
		map_pos + Vector2(-tri_size * 0.7, -tri_size * 0.6).rotated(player_rot),
	])

	draw_colored_polygon(points, Color.WHITE)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.2, 0.8, 1.0), 2.0)

# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(ship: Node) -> void:
	player_ship = ship

func is_map_open() -> bool:
	return _is_open
