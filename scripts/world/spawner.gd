class_name Spawner
extends Node2D
## Spawner - Manages enemy spawning at bodies
## Ported from core/spawn/Spawner.as and SpawnManager.as

# =============================================================================
# SIGNALS
# =============================================================================

signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal all_waves_cleared
signal enemy_spawned(enemy: Node)
signal enemy_died(enemy: Node)

# =============================================================================
# CONFIGURATION
# =============================================================================

@export_group("Spawner Config")
@export var spawner_key: String = ""  ## Unique identifier
@export var max_enemies: int = 5  ## Max enemies alive at once
@export var spawn_delay: float = 2.0  ## Delay between spawns
@export var wave_delay: float = 5.0  ## Delay between waves
@export var total_waves: int = 1  ## Number of waves (0 = infinite)
@export var respawn: bool = true  ## Respawn enemies when killed
@export var respawn_delay: float = 10.0  ## Time before respawn after all killed

@export_group("Enemy Config")
@export var enemy_scene: PackedScene = null  ## Enemy scene to spawn
@export var enemy_config: Dictionary = {}  ## Config to apply to enemies
@export var min_level: int = 1
@export var max_level: int = 10

@export_group("Orbit Config")
@export var orbit_radius: float = 100.0  ## Distance from spawner
@export var orbit_speed: float = 0.5  ## Radians per second

@export_group("Boss")
@export var boss_scene: PackedScene = null  ## Boss to spawn after waves
@export var boss_config: Dictionary = {}

# =============================================================================
# STATE
# =============================================================================

var current_wave: int = 0
var enemies_alive: Array = []  # Active enemy nodes
var enemies_killed: int = 0
var is_active: bool = true
var boss_spawned: bool = false
var parent_body = null  # Body this spawner belongs to

var _spawn_timer: float = 0.0
var _wave_timer: float = 0.0
var _respawn_timer: float = 0.0
var _enemies_to_spawn: int = 0
var _wave_complete: bool = false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Load default enemy scene if not set
	if enemy_scene == null:
		enemy_scene = load("res://scenes/entities/enemies/enemy_ship.tscn")

	# Start first wave
	_start_wave(1)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Handle respawn timer
	if _respawn_timer > 0:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_restart_spawner()
		return

	# Handle wave delay
	if _wave_complete:
		_wave_timer -= delta
		if _wave_timer <= 0:
			_wave_complete = false
			if total_waves == 0 or current_wave < total_waves:
				_start_wave(current_wave + 1)
			elif boss_scene != null and not boss_spawned:
				_spawn_boss()
			else:
				all_waves_cleared.emit()
				is_active = false
		return

	# Handle spawn timer
	if _enemies_to_spawn > 0 and enemies_alive.size() < max_enemies:
		_spawn_timer -= delta
		if _spawn_timer <= 0:
			_spawn_enemy()
			_spawn_timer = spawn_delay
			_enemies_to_spawn -= 1

# =============================================================================
# WAVE MANAGEMENT
# =============================================================================

func _start_wave(wave_num: int) -> void:
	current_wave = wave_num
	_enemies_to_spawn = max_enemies
	_spawn_timer = 0.0  # Spawn first immediately
	_wave_complete = false
	wave_started.emit(wave_num)

func _check_wave_complete() -> void:
	if _enemies_to_spawn <= 0 and enemies_alive.is_empty():
		_wave_complete = true
		_wave_timer = wave_delay
		wave_cleared.emit(current_wave)

func _restart_spawner() -> void:
	current_wave = 0
	enemies_killed = 0
	boss_spawned = false
	_start_wave(1)

# =============================================================================
# SPAWNING
# =============================================================================

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemy = enemy_scene.instantiate()

	# Calculate spawn position in orbit
	var angle: float = randf() * TAU
	var spawn_pos: Vector2 = global_position + Vector2(
		cos(angle) * orbit_radius,
		sin(angle) * orbit_radius
	)

	enemy.global_position = spawn_pos

	# Configure enemy
	if enemy.has_method("init_from_config") and not enemy_config.is_empty():
		enemy.init_from_config(enemy_config)

	# Set orbit parameters
	if enemy.get("orbit_angle") != null:
		enemy.orbit_angle = angle
	if enemy.get("orbit_radius") != null:
		enemy.orbit_radius = orbit_radius
	if enemy.get("angle_velocity") != null:
		enemy.angle_velocity = orbit_speed

	# Set spawner reference
	if enemy.has_method("set_spawner"):
		enemy.set_spawner(self)

	# Connect death signal
	if enemy.has_signal("destroyed"):
		enemy.destroyed.connect(_on_enemy_destroyed.bind(enemy))

	# Add to scene
	get_tree().current_scene.add_child(enemy)
	enemies_alive.append(enemy)

	enemy_spawned.emit(enemy)

func _spawn_boss() -> void:
	if boss_scene == null:
		return

	boss_spawned = true

	var boss = boss_scene.instantiate()
	boss.global_position = global_position

	if boss.has_method("init_from_config") and not boss_config.is_empty():
		boss.init_from_config(boss_config)

	if boss.has_method("set_spawner"):
		boss.set_spawner(self)

	if boss.has_signal("destroyed"):
		boss.destroyed.connect(_on_boss_destroyed.bind(boss))

	get_tree().current_scene.add_child(boss)
	enemies_alive.append(boss)

# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_enemy_destroyed(enemy: Node) -> void:
	enemies_alive.erase(enemy)
	enemies_killed += 1
	enemy_died.emit(enemy)

	_check_wave_complete()

	# Handle respawn
	if respawn and enemies_alive.is_empty() and _enemies_to_spawn <= 0:
		if total_waves == 0 or current_wave >= total_waves:
			_respawn_timer = respawn_delay

func _on_boss_destroyed(boss: Node) -> void:
	enemies_alive.erase(boss)
	all_waves_cleared.emit()

	# Notify parent body
	if parent_body != null and parent_body.has_method("on_spawner_cleared"):
		parent_body.on_spawner_cleared(self)

	if respawn:
		_respawn_timer = respawn_delay * 2  # Longer respawn for boss

func on_enemy_died(enemy: Node) -> void:
	# Called directly by EnemyShip
	_on_enemy_destroyed(enemy)

# =============================================================================
# PUBLIC API
# =============================================================================

func set_parent_body(body) -> void:
	parent_body = body

func get_enemies_alive() -> int:
	return enemies_alive.size()

func get_total_killed() -> int:
	return enemies_killed

func is_cleared() -> bool:
	return not is_active or (enemies_alive.is_empty() and _enemies_to_spawn <= 0 and boss_spawned)

func stop() -> void:
	is_active = false
	for enemy in enemies_alive:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies_alive.clear()

func restart() -> void:
	stop()
	is_active = true
	_restart_spawner()
