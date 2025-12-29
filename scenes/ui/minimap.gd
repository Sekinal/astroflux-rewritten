class_name Minimap
extends Control
## Minimap - Radar showing bodies, player, and enemies
## Ported from core/hud/components/radar/Radar.as

# =============================================================================
# CONFIGURATION (from original Radar.as)
# =============================================================================

const RADAR_RADIUS: float = 60.0  ## Radius from center in pixels
const INNER_DETECTION: float = 2500.0  ## Full visibility range
const OUTER_DETECTION: float = 5000.0  ## Max detection range (fades)

# =============================================================================
# COLORS (from original Style.as / Blip class)
# =============================================================================

const COLOR_PLAYER := Color(0.13, 1.0, 0.4)  # Light green (0x22FF66)
const COLOR_SUN := Color(1.0, 0.94, 0.53)  # Yellow-ish (0xFFEF88)
const COLOR_PLANET := Color(0.13, 0.55, 0.25)  # Green (0x228B42 / 2263074)
const COLOR_STATION := Color(0.67, 0.67, 0.67)  # Gray (0xAAAAAA / 11184810)
const COLOR_ENEMY := Color(1.0, 0.35, 0.35)  # Red (0xFF5A5A / 16729156)
const COLOR_SPAWNER := Color(1.0, 0.35, 0.35)  # Red (hostile spawners)
const COLOR_FRIENDLY := Color(0.13, 1.0, 0.4)  # Light green
const COLOR_COMET := Color(0.67, 0.67, 1.0)  # Blue-ish (0xAAAAFF / 11184895)

# =============================================================================
# STATE
# =============================================================================

var player_ship: Node = null

# Textures
var _tex_bg: AtlasTexture = null
var _tex_player: AtlasTexture = null
var _tex_enemy: AtlasTexture = null
var _tex_spawner: AtlasTexture = null
var _tex_planet: AtlasTexture = null
var _tex_station: AtlasTexture = null
var _tex_sun: AtlasTexture = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Set size to match radar background (120x120)
	custom_minimum_size = Vector2(120, 120)
	size = Vector2(120, 120)

	if TextureManager.is_loaded():
		_load_textures()
	else:
		TextureManager.atlases_loaded.connect(_load_textures)

func _load_textures() -> void:
	_tex_bg = TextureManager.get_sprite("radar_bg")
	_tex_player = TextureManager.get_sprite("radar_player")
	_tex_enemy = TextureManager.get_sprite("radar_enemy")
	_tex_spawner = TextureManager.get_sprite("radar_spawner")
	_tex_planet = TextureManager.get_sprite("radar_planet")
	_tex_station = TextureManager.get_sprite("radar_station")
	_tex_sun = TextureManager.get_sprite("radar_sun")

func _process(_delta: float) -> void:
	queue_redraw()

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	var center := Vector2(RADAR_RADIUS, RADAR_RADIUS)  # 60, 60

	# Draw radar background texture
	if _tex_bg != null:
		draw_texture(_tex_bg, Vector2.ZERO)
	else:
		# Fallback: dark circle
		draw_circle(center, RADAR_RADIUS, Color(0.05, 0.05, 0.1, 0.85))
		draw_arc(center, RADAR_RADIUS, 0, TAU, 64, Color(0.3, 0.4, 0.5, 0.8), 2.0)

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

	# Draw player marker at center
	_draw_player(center)

func _draw_bodies(center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		var body_pos: Vector2 = body.global_position
		var relative := body_pos - player_pos
		var distance := relative.length()

		# Skip if outside outer detection range
		if distance >= OUTER_DETECTION:
			continue

		# Calculate radar position (like original Blip.setRadarPos)
		var radar_pos := _world_to_radar(relative, distance)
		if radar_pos == Vector2.INF:
			continue

		var draw_pos := center + radar_pos - Vector2(2, 2)  # Center blip (4x4 textures)

		# Calculate alpha for fading at edge
		var alpha := _get_radar_alpha(distance)

		# Determine texture and color based on body type
		var tex: AtlasTexture = null
		var color := COLOR_PLANET

		match body.body_type:
			0:  # SUN
				tex = _tex_sun
				color = COLOR_SUN
			1:  # PLANET
				tex = _tex_planet
				color = COLOR_PLANET
			2:  # WARP_GATE
				tex = _tex_station
				color = COLOR_STATION
			3, 4, 5, 9, 10, 11:  # SHOP, RESEARCH, JUNK, HANGAR, CANTINA, PAINT
				tex = _tex_station
				color = COLOR_STATION

		# Draw blip
		if tex != null:
			draw_texture(tex, draw_pos, Color(color.r, color.g, color.b, alpha))
		else:
			draw_circle(center + radar_pos, 2.0, Color(color.r, color.g, color.b, alpha))

func _draw_spawners(center: Vector2, player_pos: Vector2) -> void:
	for body in BodyManager.bodies:
		if not is_instance_valid(body):
			continue

		if not body.get("spawners"):
			continue

		for spawner in body.spawners:
			if not is_instance_valid(spawner):
				continue

			var spawner_pos: Vector2 = spawner.global_position
			var relative := spawner_pos - player_pos
			var distance := relative.length()

			if distance >= OUTER_DETECTION:
				continue

			var radar_pos := _world_to_radar(relative, distance)
			if radar_pos == Vector2.INF:
				continue

			var draw_pos := center + radar_pos - Vector2(2, 2)
			var alpha := _get_radar_alpha(distance)

			if _tex_spawner != null:
				draw_texture(_tex_spawner, draw_pos, Color(COLOR_SPAWNER.r, COLOR_SPAWNER.g, COLOR_SPAWNER.b, alpha))
			else:
				draw_circle(center + radar_pos, 2.0, Color(COLOR_SPAWNER.r, COLOR_SPAWNER.g, COLOR_SPAWNER.b, alpha))

func _draw_enemies(center: Vector2, player_pos: Vector2) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var enemy_pos: Vector2 = enemy.global_position
		var relative := enemy_pos - player_pos
		var distance := relative.length()

		if distance >= OUTER_DETECTION:
			continue

		var radar_pos := _world_to_radar(relative, distance)
		if radar_pos == Vector2.INF:
			continue

		var draw_pos := center + radar_pos - Vector2(1.5, 1.5)  # 3x3 texture
		var alpha := _get_radar_alpha(distance)

		if _tex_enemy != null:
			draw_texture(_tex_enemy, draw_pos, Color(COLOR_ENEMY.r, COLOR_ENEMY.g, COLOR_ENEMY.b, alpha))
		else:
			draw_circle(center + radar_pos, 1.5, Color(COLOR_ENEMY.r, COLOR_ENEMY.g, COLOR_ENEMY.b, alpha))

func _draw_player(center: Vector2) -> void:
	# Draw player marker texture at center
	if _tex_player != null:
		var tex_size := Vector2(_tex_player.get_width(), _tex_player.get_height())
		draw_texture(_tex_player, center - tex_size / 2, COLOR_PLAYER)
	else:
		# Fallback: draw small triangle
		var player_rot := 0.0
		if player_ship != null and is_instance_valid(player_ship):
			player_rot = player_ship.rotation

		var triangle_size := 4.0
		var points := PackedVector2Array([
			center + Vector2(triangle_size, 0).rotated(player_rot),
			center + Vector2(-triangle_size * 0.6, triangle_size * 0.5).rotated(player_rot),
			center + Vector2(-triangle_size * 0.6, -triangle_size * 0.5).rotated(player_rot),
		])
		draw_colored_polygon(points, COLOR_PLAYER)

# =============================================================================
# HELPER FUNCTIONS (ported from Blip.setRadarPos / getRadarAlphaIndex)
# =============================================================================

func _world_to_radar(relative: Vector2, distance: float) -> Vector2:
	## Convert world-space relative position to radar position
	## Returns Vector2.INF if outside detection range

	if distance >= OUTER_DETECTION:
		return Vector2.INF

	if distance < INNER_DETECTION:
		# Inside inner detection: direct scale
		return relative / INNER_DETECTION * RADAR_RADIUS
	else:
		# Between inner and outer: clamp to edge, normalized direction
		var dir := relative.normalized()
		return dir * (RADAR_RADIUS - 2)  # Slight margin from edge

func _get_radar_alpha(distance: float) -> float:
	## Calculate alpha based on distance (fade out between inner and outer detection)
	if distance < INNER_DETECTION:
		return 1.0
	elif distance < OUTER_DETECTION:
		return 1.0 - (distance - INNER_DETECTION) / (OUTER_DETECTION - INNER_DETECTION)
	return 0.0

# =============================================================================
# PUBLIC API
# =============================================================================

func set_player(ship: Node) -> void:
	player_ship = ship
