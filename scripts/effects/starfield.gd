class_name Starfield
extends Node2D
## Starfield - Procedural parallax starfield with nebula background
## Ported from core/parallax/ParallaxManager.as

# =============================================================================
# CONFIGURATION
# =============================================================================

@export_group("Stars")
@export var star_count_per_layer: int = 200
@export var field_size: Vector2 = Vector2(4000, 4000)
@export var layers: int = 3
@export var layer_colors: Array[Color] = [
	Color(0.3, 0.3, 0.4, 0.5),   # Far stars (dim)
	Color(0.5, 0.5, 0.6, 0.7),   # Mid stars
	Color(0.8, 0.8, 1.0, 1.0),   # Near stars (bright)
]
@export var layer_sizes: Array[float] = [1.0, 2.0, 3.0]
@export var layer_speeds: Array[float] = [0.1, 0.3, 0.6]  # Parallax speeds

@export_group("Nebula")
@export var nebula_texture_path: String = "res://assets/backgrounds/space_bg.jpg"
@export var nebula_count: int = 8
@export var nebula_alpha: float = 0.25
@export var nebula_parallax_speed: float = 0.05
@export var nebula_tint: Color = Color(0.1, 0.15, 0.25, 1.0)  # Antor blue tint

# =============================================================================
# STATE
# =============================================================================

var _star_layers: Array[Array] = []
var _nebula_positions: Array[Vector2] = []
var _nebula_rotations: Array[float] = []
var _nebula_texture: Texture2D = null
var _camera: Camera2D = null
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Use deterministic seed for consistent nebula placement
	_rng.seed = 12345

	# Load nebula texture
	if ResourceLoader.exists(nebula_texture_path):
		_nebula_texture = load(nebula_texture_path)

	# Generate nebula positions
	for i in range(nebula_count):
		var pos := Vector2(
			_rng.randf_range(-1500, 1500),
			_rng.randf_range(-1500, 1500)
		)
		_nebula_positions.append(pos)
		_nebula_rotations.append(_rng.randf() * TAU)

	# Generate star positions for each layer
	for i in range(layers):
		var layer_stars: Array = []
		for j in range(star_count_per_layer):
			layer_stars.append(Vector2(
				randf_range(-field_size.x / 2, field_size.x / 2),
				randf_range(-field_size.y / 2, field_size.y / 2)
			))
		_star_layers.append(layer_stars)

	_initialized = true
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	if not _initialized:
		return

	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	var cam_pos := _camera.global_position
	var viewport_size := get_viewport_rect().size / _camera.zoom

	# Draw solid dark background first
	var bg_rect := Rect2(
		cam_pos - viewport_size,
		viewport_size * 2
	)
	draw_rect(bg_rect, nebula_tint)

	# Draw nebulas (slowest parallax - far background)
	_draw_nebulas(cam_pos, viewport_size)

	# Draw each star layer with parallax offset
	for layer_idx in range(layers):
		var color: Color = layer_colors[layer_idx] if layer_idx < layer_colors.size() else Color.WHITE
		var size: float = layer_sizes[layer_idx] if layer_idx < layer_sizes.size() else 2.0
		var speed: float = layer_speeds[layer_idx] if layer_idx < layer_speeds.size() else 0.5

		var parallax_offset := cam_pos * (1.0 - speed)

		for star_pos in _star_layers[layer_idx]:
			var draw_pos: Vector2 = star_pos - parallax_offset

			# Wrap stars to create infinite field effect
			draw_pos.x = fmod(draw_pos.x - cam_pos.x + field_size.x / 2, field_size.x) - field_size.x / 2 + cam_pos.x
			draw_pos.y = fmod(draw_pos.y - cam_pos.y + field_size.y / 2, field_size.y) - field_size.y / 2 + cam_pos.y

			# Only draw if on screen
			var screen_pos := draw_pos - cam_pos
			if abs(screen_pos.x) < viewport_size.x and abs(screen_pos.y) < viewport_size.y:
				draw_circle(draw_pos, size, color)

func _draw_nebulas(cam_pos: Vector2, viewport_size: Vector2) -> void:
	if _nebula_texture == null:
		return

	var tex_size := _nebula_texture.get_size()
	var parallax_offset := cam_pos * (1.0 - nebula_parallax_speed)

	for i in range(_nebula_positions.size()):
		var base_pos := _nebula_positions[i]
		var rot := _nebula_rotations[i]

		# Apply parallax
		var draw_pos := base_pos - parallax_offset * (float(i) / _nebula_positions.size() * 0.5 + 0.5)

		# Wrap position for infinite tiling
		var wrap_size := 3000.0
		draw_pos.x = fmod(draw_pos.x - cam_pos.x + wrap_size, wrap_size * 2) - wrap_size + cam_pos.x
		draw_pos.y = fmod(draw_pos.y - cam_pos.y + wrap_size, wrap_size * 2) - wrap_size + cam_pos.y

		# Only draw if potentially visible
		var dist_to_cam := draw_pos.distance_to(cam_pos)
		if dist_to_cam < viewport_size.length() + tex_size.length():
			# Draw with additive blending effect (simulated with alpha)
			draw_set_transform(draw_pos, rot, Vector2.ONE)
			var tinted := Color(1, 1, 1, nebula_alpha)
			draw_texture(_nebula_texture, -tex_size / 2, tinted)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

# =============================================================================
# PUBLIC API
# =============================================================================

## Set nebula tint color (from solar system data)
func set_nebula_tint(color: Color) -> void:
	nebula_tint = color
	queue_redraw()

## Set nebula alpha
func set_nebula_alpha(alpha: float) -> void:
	nebula_alpha = clampf(alpha, 0.0, 1.0)
	queue_redraw()
