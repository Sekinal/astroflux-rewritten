class_name Starfield
extends Node2D
## Starfield - Procedural parallax starfield background
## Creates multiple layers of stars at different depths

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

var _star_layers: Array[Array] = []
var _camera: Camera2D = null
var _initialized: bool = false

func _ready() -> void:
	# Generate star positions for each layer immediately
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
	# Redraw when camera moves for parallax effect
	queue_redraw()

func _draw() -> void:
	if not _initialized:
		return

	if _camera == null:
		_camera = get_viewport().get_camera_2d()
		if _camera == null:
			return

	var cam_pos := _camera.global_position
	var viewport_size := get_viewport_rect().size / _camera.zoom

	# Draw each layer with parallax offset
	for layer_idx in range(layers):
		var color: Color = layer_colors[layer_idx] if layer_idx < layer_colors.size() else Color.WHITE
		var size: float = layer_sizes[layer_idx] if layer_idx < layer_sizes.size() else 2.0
		var speed: float = layer_speeds[layer_idx] if layer_idx < layer_speeds.size() else 0.5

		var parallax_offset := cam_pos * (1.0 - speed)

		for star_pos in _star_layers[layer_idx]:
			# Calculate wrapped position
			var draw_pos: Vector2 = star_pos - parallax_offset

			# Wrap stars to create infinite field effect
			draw_pos.x = fmod(draw_pos.x - cam_pos.x + field_size.x / 2, field_size.x) - field_size.x / 2 + cam_pos.x
			draw_pos.y = fmod(draw_pos.y - cam_pos.y + field_size.y / 2, field_size.y) - field_size.y / 2 + cam_pos.y

			# Only draw if on screen (with margin)
			var screen_pos := draw_pos - cam_pos
			if abs(screen_pos.x) < viewport_size.x and abs(screen_pos.y) < viewport_size.y:
				draw_circle(draw_pos, size, color)
