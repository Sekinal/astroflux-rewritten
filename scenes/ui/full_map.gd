class_name FullMap
extends Control
## FullMap - Full screen solar system map (press M to open)
## Ported from core/hud/components/map/Map.as

# =============================================================================
# SIGNALS
# =============================================================================

signal closed

# =============================================================================
# CONFIGURATION
# =============================================================================

const MAP_SCALE_BASE: float = 0.08  ## Base scale for world to map
const MAP_WIDTH: float = 760.0
const MAP_HEIGHT: float = 600.0
const PADDING: float = 31.0

# =============================================================================
# COLORS
# =============================================================================

const COLOR_PLAYER := Color(0.2, 0.9, 1.0, 1.0)  # Cyan
const COLOR_SUN := Color(1.0, 0.85, 0.2, 1.0)  # Yellow
const COLOR_PLANET := Color(1.0, 0.4, 0.4, 1.0)  # Red-ish (like original)
const COLOR_STATION := Color(0.3, 0.5, 1.0, 1.0)  # Blue
const COLOR_WARP_GATE := Color(0.13, 0.66, 0.4, 1.0)  # Teal green
const COLOR_ENEMY := Color(1.0, 0.3, 0.3, 0.8)  # Red
const COLOR_SPAWNER := Color(0.9, 0.5, 0.1, 0.7)  # Orange
const COLOR_ORBIT := Color(0.3, 0.35, 0.4, 0.4)  # Gray
const COLOR_TEXT := Color(0.99, 0.85, 0.53, 0.8)  # Gold
const COLOR_COORDS := Color(0.55, 0.55, 0.55, 1.0)  # Gray

# =============================================================================
# STATE
# =============================================================================

var player_ship: Node = null
var map_scale: float = MAP_SCALE_BASE
var _background_texture: AtlasTexture = null
var _is_open: bool = false

# =============================================================================
# NODES
# =============================================================================

@onready var map_container: Control = $MapContainer
@onready var system_name_label: Label = $MapContainer/SystemName
@onready var coords_label: Label = $MapContainer/Coordinates
@onready var close_button: Button = $MapContainer/CloseButton

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	visible = false

	# Load map background texture
	if TextureManager.is_loaded():
		_load_textures()
	else:
		TextureManager.atlases_loaded.connect(_load_textures)

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func _load_textures() -> void:
	_background_texture = TextureManager.get_sprite("map_bgr")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _is_open:
			close_map()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _is_open:
		queue_redraw()
		_update_labels()

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

	# Pause game while map is open
	get_tree().paused = true

func close_map() -> void:
	_is_open = false
	visible = false
	closed.emit()

	# Unpause game
	get_tree().paused = false

func _on_close_pressed() -> void:
	close_map()

func _calculate_scale() -> void:
	# Find the maximum orbit radius to scale the map
	var max_radius: float = 200.0

	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if body.get("orbit_radius") != null and body.orbit_radius > 0:
			if body.orbit_radius * MAP_SCALE_BASE > max_radius:
				map_scale = max_radius / body.orbit_radius

	# Clamp scale
	map_scale = clampf(map_scale, 0.01, 0.2)

func _update_labels() -> void:
	# Update system name
	if system_name_label:
		system_name_label.text = BodyManager.current_system_name

	# Update player coordinates
	if coords_label and player_ship != null and is_instance_valid(player_ship):
		var pos: Vector2 = player_ship.global_position
		coords_label.text = "Position: %d, %d" % [int(pos.x), int(pos.y)]

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	if not _is_open:
		return

	var map_center := size / 2

	# Draw dark overlay
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.85))

	# Draw map background
	if _background_texture != null:
		var bg_size := Vector2(_background_texture.get_width(), _background_texture.get_height())
		var bg_pos := map_center - bg_size / 2
		draw_texture(_background_texture, bg_pos)
	else:
		# Fallback: draw rectangle
		var map_rect := Rect2(map_center - Vector2(MAP_WIDTH, MAP_HEIGHT) / 2, Vector2(MAP_WIDTH, MAP_HEIGHT))
		draw_rect(map_rect, Color(0.05, 0.08, 0.12, 0.95))
		draw_rect(map_rect, Color(0.3, 0.4, 0.5, 0.5), false, 2.0)

	# Get player position for centering
	var player_pos := Vector2.ZERO
	if player_ship != null and is_instance_valid(player_ship):
		player_pos = player_ship.global_position

	# Draw orbit rings first (behind everything)
	_draw_orbits(map_center, player_pos)

	# Draw spawners
	_draw_spawners(map_center, player_pos)

	# Draw bodies
	_draw_bodies(map_center, player_pos)

	# Draw enemies
	_draw_enemies(map_center, player_pos)

	# Draw player
	_draw_player(map_center, player_pos)

func _draw_orbits(map_center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		if body.get("orbit_radius") == null or body.orbit_radius <= 0:
			continue
		if body.get("parent_body") == null:
			continue

		var parent_world_pos: Vector2 = body.parent_body.global_position
		var parent_map_pos: Vector2 = _world_to_map(parent_world_pos, map_center, player_pos)
		var orbit_radius_scaled: float = body.orbit_radius * map_scale

		# Only draw if orbit is visible
		if orbit_radius_scaled > 5 and orbit_radius_scaled < 400:
			draw_arc(parent_map_pos, orbit_radius_scaled, 0, TAU, 64, COLOR_ORBIT, 1.0)

func _draw_bodies(map_center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		var body_pos: Vector2 = body.global_position
		var map_pos := _world_to_map(body_pos, map_center, player_pos)

		# Skip if way off screen
		if map_pos.x < -50 or map_pos.x > size.x + 50:
			continue
		if map_pos.y < -50 or map_pos.y > size.y + 50:
			continue

		var color := COLOR_PLANET
		var radius := 6.0
		var draw_name := true

		match body.body_type:
			0:  # SUN
				color = COLOR_SUN
				radius = 15.0
			1:  # PLANET
				color = COLOR_PLANET
				radius = 8.0
			2:  # WARP_GATE
				color = COLOR_WARP_GATE
				radius = 6.0
			3, 4, 5, 9, 10, 11:  # Stations
				color = COLOR_STATION
				radius = 5.0
			_:
				draw_name = false
				radius = 4.0

		# Draw glow
		draw_circle(map_pos, radius + 3, Color(color.r, color.g, color.b, 0.3))
		# Draw body
		draw_circle(map_pos, radius, color)

		# Draw name
		if draw_name and body.get("body_name") != null:
			var font := ThemeDB.fallback_font
			var font_size := 12
			var text_pos := map_pos + Vector2(-30, radius + 14)
			draw_string(font, text_pos, body.body_name, HORIZONTAL_ALIGNMENT_CENTER, 60, font_size, COLOR_TEXT)

func _draw_spawners(map_center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue
		if not body.get("spawners"):
			continue

		for spawner in body.spawners:
			if not is_instance_valid(spawner):
				continue

			var spawner_pos: Vector2 = spawner.global_position
			var map_pos := _world_to_map(spawner_pos, map_center, player_pos)

			# Draw spawner indicator
			draw_circle(map_pos, 3.0, COLOR_SPAWNER)

func _draw_enemies(map_center: Vector2, player_pos: Vector2) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var enemy_pos: Vector2 = enemy.global_position
		var map_pos := _world_to_map(enemy_pos, map_center, player_pos)

		# Draw enemy dot
		draw_circle(map_pos, 3.0, COLOR_ENEMY)

func _draw_player(map_center: Vector2, player_pos: Vector2) -> void:
	var map_pos := _world_to_map(player_pos, map_center, player_pos)

	# Get rotation
	var player_rot := 0.0
	if player_ship != null and is_instance_valid(player_ship):
		player_rot = player_ship.rotation

	# Draw player glow
	draw_circle(map_pos, 10, Color(COLOR_PLAYER.r, COLOR_PLAYER.g, COLOR_PLAYER.b, 0.3))

	# Draw player triangle
	var tri_size := 8.0
	var points := PackedVector2Array([
		map_pos + Vector2(tri_size, 0).rotated(player_rot),
		map_pos + Vector2(-tri_size * 0.7, tri_size * 0.6).rotated(player_rot),
		map_pos + Vector2(-tri_size * 0.7, -tri_size * 0.6).rotated(player_rot),
	])

	draw_colored_polygon(points, COLOR_PLAYER)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.5)

func _world_to_map(world_pos: Vector2, map_center: Vector2, player_pos: Vector2) -> Vector2:
	# Center map on player
	var relative := (world_pos - player_pos) * map_scale
	return map_center + relative

# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(ship: Node) -> void:
	player_ship = ship

func is_map_open() -> bool:
	return _is_open
