class_name Minimap
extends Control
## Minimap - Radar showing bodies, player, and enemies
## Ported from core/hud/components/map/Map.as

# =============================================================================
# CONFIGURATION
# =============================================================================

@export var map_scale: float = 0.02  ## World to minimap scale
@export var map_radius: float = 100.0  ## Visible radius in pixels

# =============================================================================
# COLORS
# =============================================================================

const COLOR_PLAYER := Color(0.2, 0.8, 1.0, 1.0)  # Cyan
const COLOR_SUN := Color(1.0, 0.9, 0.3, 1.0)  # Yellow
const COLOR_PLANET := Color(0.4, 0.7, 0.4, 1.0)  # Green
const COLOR_STATION := Color(0.3, 0.5, 1.0, 1.0)  # Blue
const COLOR_WARP_GATE := Color(0.2, 0.9, 0.5, 1.0)  # Teal
const COLOR_ENEMY := Color(1.0, 0.3, 0.3, 0.8)  # Red
const COLOR_SPAWNER := Color(0.8, 0.4, 0.1, 0.6)  # Orange

# =============================================================================
# STATE
# =============================================================================

var player_ship: Node = null
var _background_texture: AtlasTexture = null
var _frame_texture: AtlasTexture = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Load minimap frame texture
	if TextureManager.is_loaded():
		_load_textures()
	else:
		TextureManager.atlases_loaded.connect(_load_textures)

func _load_textures() -> void:
	_frame_texture = TextureManager.get_sprite("hud_radar")

func _process(_delta: float) -> void:
	queue_redraw()

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	var center := size / 2

	# Draw dark background circle
	draw_circle(center, map_radius + 5, Color(0.05, 0.05, 0.1, 0.85))

	# Draw frame if available
	if _frame_texture != null:
		var frame_size := Vector2(_frame_texture.get_width(), _frame_texture.get_height())
		var frame_pos := center - frame_size / 2
		draw_texture(_frame_texture, frame_pos)
	else:
		# Fallback: draw circle border
		draw_arc(center, map_radius, 0, TAU, 64, Color(0.3, 0.4, 0.5, 0.8), 2.0)

	# Get player position for centering
	var player_pos := Vector2.ZERO
	if player_ship != null and is_instance_valid(player_ship):
		player_pos = player_ship.global_position

	# Draw bodies
	_draw_bodies(center, player_pos)

	# Draw spawners
	_draw_spawners(center, player_pos)

	# Draw enemies
	_draw_enemies(center, player_pos)

	# Draw player (always at center)
	_draw_player(center)

	# Draw border circle
	draw_arc(center, map_radius, 0, TAU, 64, Color(0.4, 0.5, 0.6, 0.6), 1.5)

func _draw_bodies(center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		var body_pos: Vector2 = body.global_position
		var relative := (body_pos - player_pos) * map_scale

		# Skip if outside radar range
		if relative.length() > map_radius - 5:
			# Draw at edge for distant bodies
			relative = relative.normalized() * (map_radius - 8)

		var draw_pos := center + relative

		# Determine color and size based on body type
		var color := COLOR_PLANET
		var radius := 3.0

		match body.body_type:
			0:  # SUN
				color = COLOR_SUN
				radius = 8.0
			1:  # PLANET
				color = COLOR_PLANET
				radius = 5.0
			2:  # WARP_GATE
				color = COLOR_WARP_GATE
				radius = 4.0
			3, 4, 5, 9, 10, 11:  # SHOP, RESEARCH, JUNK, HANGAR, CANTINA, PAINT
				color = COLOR_STATION
				radius = 4.0

		# Draw body
		draw_circle(draw_pos, radius, color)

		# Draw orbit ring for planets
		if body.orbit_radius > 0 and body.parent_body != null:
			var parent_pos_world: Vector2 = body.parent_body.global_position
			var parent_relative: Vector2 = (parent_pos_world - player_pos) * map_scale
			if parent_relative.length() < map_radius:
				var orbit_scaled: float = body.orbit_radius * map_scale
				if orbit_scaled < map_radius * 1.5:
					draw_arc(center + parent_relative, orbit_scaled, 0, TAU, 32,
						Color(0.3, 0.3, 0.4, 0.3), 1.0)

func _draw_spawners(center: Vector2, player_pos: Vector2) -> void:
	# Get all spawners from bodies
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		if not body.get("spawners"):
			continue

		for spawner in body.spawners:
			if not is_instance_valid(spawner):
				continue

			var spawner_pos: Vector2 = spawner.global_position
			var relative := (spawner_pos - player_pos) * map_scale

			if relative.length() > map_radius - 5:
				continue

			var draw_pos := center + relative

			# Draw spawner as small dot
			draw_circle(draw_pos, 2.0, COLOR_SPAWNER)

func _draw_enemies(center: Vector2, player_pos: Vector2) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var enemy_pos: Vector2 = enemy.global_position
		var relative := (enemy_pos - player_pos) * map_scale

		if relative.length() > map_radius - 5:
			continue

		var draw_pos := center + relative

		# Draw enemy as small red dot
		draw_circle(draw_pos, 2.5, COLOR_ENEMY)

func _draw_player(center: Vector2) -> void:
	# Draw player triangle pointing in movement direction
	var player_rot := 0.0
	if player_ship != null and is_instance_valid(player_ship):
		player_rot = player_ship.rotation

	var triangle_size := 6.0
	var points := PackedVector2Array([
		center + Vector2(triangle_size, 0).rotated(player_rot),
		center + Vector2(-triangle_size * 0.6, triangle_size * 0.5).rotated(player_rot),
		center + Vector2(-triangle_size * 0.6, -triangle_size * 0.5).rotated(player_rot),
	])

	draw_colored_polygon(points, COLOR_PLAYER)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.0)

# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(ship: Node) -> void:
	player_ship = ship
