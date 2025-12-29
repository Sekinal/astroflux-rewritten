extends Node
## ProjectileManager - Handles projectile pooling and management
## Ported from core/projectile/ProjectileManager.as

# =============================================================================
# CONFIGURATION
# =============================================================================

const POOL_SIZE: int = 200
const PROJECTILE_SCENE_PATH: String = "res://scenes/entities/projectiles/projectile.tscn"

# =============================================================================
# STATE
# =============================================================================

# Use untyped arrays to avoid class loading order issues
var _pool: Array = []
var _active: Array = []
var _projectile_scene: PackedScene = null
var _container: Node2D = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Scene will be loaded on demand
	pass

## Initialize the projectile pool (call from game scene)
func initialize(container: Node2D) -> void:
	_container = container

	# Load projectile scene
	if ResourceLoader.exists(PROJECTILE_SCENE_PATH):
		_projectile_scene = load(PROJECTILE_SCENE_PATH)
	else:
		push_warning("[ProjectileManager] Projectile scene not found, will create basic projectiles")

	# Pre-populate pool
	for i in range(POOL_SIZE):
		var proj := _create_projectile()
		proj.deactivate()
		_pool.append(proj)

	print("[ProjectileManager] Initialized with pool size: %d" % POOL_SIZE)

func _create_projectile() -> Node:
	var proj: Node

	if _projectile_scene:
		proj = _projectile_scene.instantiate()
	else:
		push_error("[ProjectileManager] No projectile scene loaded!")
		return null

	if _container:
		_container.add_child(proj)

	# Connect destroyed signal
	if proj.has_signal("destroyed"):
		proj.destroyed.connect(_on_projectile_destroyed.bind(proj))

	return proj

# =============================================================================
# SPAWNING
# =============================================================================

## Spawn a projectile from weapon fire data
func spawn(data: Dictionary) -> Node:
	var proj: Node = _get_from_pool()

	if proj == null:
		# Pool exhausted, create new one
		proj = _create_projectile()
		if proj == null:
			return null
		push_warning("[ProjectileManager] Pool exhausted, created new projectile")

	if proj.has_method("activate"):
		proj.activate(data)
	_active.append(proj)

	return proj

## Spawn multiple projectiles from weapon fire
func spawn_multiple(projectile_array: Array) -> Array:
	var spawned: Array = []
	for data in projectile_array:
		var proj := spawn(data)
		if proj:
			spawned.append(proj)
	return spawned

func _get_from_pool() -> Node:
	if _pool.is_empty():
		return null

	return _pool.pop_back()

# =============================================================================
# CLEANUP
# =============================================================================

func _on_projectile_destroyed(proj: Node) -> void:
	# Remove from active list
	var idx := _active.find(proj)
	if idx >= 0:
		_active.remove_at(idx)

	# Return to pool
	_pool.append(proj)

## Destroy all active projectiles
func clear_all() -> void:
	for proj in _active:
		if proj.has_method("deactivate"):
			proj.deactivate()
		_pool.append(proj)
	_active.clear()

## Destroy projectiles owned by a specific node
func clear_for_owner(owner: Node) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var proj: Node = _active[i]
		if proj.get("owner_node") == owner:
			if proj.has_method("destroy"):
				proj.destroy(false)

# =============================================================================
# QUERIES
# =============================================================================

func get_active_count() -> int:
	return _active.size()

func get_pool_count() -> int:
	return _pool.size()

func get_projectiles_near(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	var radius_sq := radius * radius

	for proj in _active:
		if proj.get("alive") and proj.position.distance_squared_to(pos) <= radius_sq:
			result.append(proj)

	return result
