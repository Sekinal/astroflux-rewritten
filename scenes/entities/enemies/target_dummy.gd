class_name TargetDummy
extends CharacterBody2D
## TargetDummy - A stationary target for testing weapons

# =============================================================================
# SIGNALS
# =============================================================================

signal health_changed(current: float, maximum: float)
signal destroyed

# =============================================================================
# PROPERTIES
# =============================================================================

@export var hp_max: float = 100.0
@export var show_damage_numbers: bool = true

var hp: float = 100.0
var resistances: Array[float] = [0.0, 0.0, 0.0]
var _is_destroyed: bool = false

# =============================================================================
# NODES
# =============================================================================

@onready var body_sprite: Polygon2D = $Body
@onready var health_bar: ProgressBar = $HealthBar
@onready var collision: CollisionShape2D = $CollisionShape2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	hp = hp_max
	_update_health_bar()
	add_to_group("enemies")

# =============================================================================
# COMBAT
# =============================================================================

func take_damage(dmg: Variant, attacker: Node = null) -> void:
	if _is_destroyed:
		return

	var damage_amount: float = 0.0

	# Handle both Damage object and raw float (duck typing)
	if dmg != null and dmg is Object and dmg.has_method("calculate_resisted"):
		damage_amount = dmg.calculate_resisted(resistances)
	elif dmg is float or dmg is int:
		damage_amount = float(dmg)
	else:
		damage_amount = 10.0  # Default damage

	hp -= damage_amount
	health_changed.emit(hp, hp_max)
	_update_health_bar()

	# Visual feedback - flash red
	_flash_damage()

	# Show damage number
	if show_damage_numbers:
		_spawn_damage_number(damage_amount)

	if hp <= 0:
		_destroy()

func _flash_damage() -> void:
	if body_sprite:
		var original_color: Color = body_sprite.color
		body_sprite.color = Color.RED

		await get_tree().create_timer(0.1).timeout

		if is_instance_valid(body_sprite):
			body_sprite.color = original_color

func _spawn_damage_number(amount: float) -> void:
	# Create floating damage text
	var label := Label.new()
	label.text = str(int(amount))
	label.add_theme_font_size_override("font_size", 20)
	label.modulate = Color.YELLOW
	label.position = Vector2(-20, -50)
	add_child(label)

	# Animate upward and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = hp_max
		health_bar.value = hp

func _destroy() -> void:
	_is_destroyed = true
	destroyed.emit()

	# Respawn after delay
	if body_sprite:
		body_sprite.visible = false
	if collision:
		collision.disabled = true

	await get_tree().create_timer(3.0).timeout

	# Respawn
	hp = hp_max
	_is_destroyed = false
	_update_health_bar()
	if body_sprite:
		body_sprite.visible = true
	if collision:
		collision.disabled = false

# =============================================================================
# DEBUFFS
# =============================================================================

func apply_debuff(debuff: Variant) -> void:
	# Simple debuff handling using duck typing
	if debuff != null and debuff.get("type") == 2:  # DOT type = 2
		_apply_dot(debuff)

func _apply_dot(debuff: Variant) -> void:
	if debuff == null:
		return
	# Apply damage over time
	var duration: float = debuff.get("duration") if debuff.get("duration") else 1000.0
	var ticks: int = int(duration / 500.0)  # Tick every 500ms
	for i in range(ticks):
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(self) and not _is_destroyed:
			var tick_dmg: float = debuff.get_tick_damage() if debuff.has_method("get_tick_damage") else 5.0
			take_damage(tick_dmg)
