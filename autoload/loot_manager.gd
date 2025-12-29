extends Node
## LootManager - Handles loot drop spawning and management
## Autoload singleton

# =============================================================================
# LOOT SCENE
# =============================================================================

var _loot_scene: PackedScene = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_loot_scene = load("res://scenes/entities/loot/loot.tscn")

# =============================================================================
# PUBLIC API
# =============================================================================

func spawn_loot(position: Vector2, loot_items: Array) -> void:
	"""Spawn loot items at the given position."""
	for item in loot_items:
		if item is Dictionary:
			_spawn_loot_item(position, item)

func spawn_xp(position: Vector2, amount: int) -> void:
	"""Spawn XP orbs at position."""
	# Split into multiple orbs for larger amounts
	var orb_count := 1
	var per_orb := amount

	if amount > 50:
		orb_count = mini(amount / 25, 5)
		per_orb = amount / orb_count

	for i in range(orb_count):
		var loot = _create_loot(0, {"amount": per_orb})  # Type.XP = 0
		if loot != null:
			loot.global_position = position
			_add_to_scene(loot)

func spawn_artifact(position: Vector2, artifact_id: String, data: Dictionary = {}) -> void:
	"""Spawn an artifact drop."""
	data["id"] = artifact_id
	var loot = _create_loot(1, data)  # Type.ARTIFACT = 1
	if loot != null:
		loot.global_position = position
		_add_to_scene(loot)

# =============================================================================
# INTERNAL
# =============================================================================

func _spawn_loot_item(position: Vector2, item: Dictionary) -> void:
	var loot_type: int = 0  # Default to XP

	match item.get("type", "xp"):
		"xp":
			loot_type = 0
		"artifact":
			loot_type = 1
		"resource":
			loot_type = 2
		"weapon":
			loot_type = 3
		"ship_part":
			loot_type = 4

	var loot = _create_loot(loot_type, item)
	if loot != null:
		loot.global_position = position
		_add_to_scene(loot)

func _create_loot(type: int, data: Dictionary):
	if _loot_scene == null:
		return null

	var loot = _loot_scene.instantiate()
	loot.loot_type = type
	loot.loot_data = data
	return loot

func _add_to_scene(loot: Node) -> void:
	var scene_root = get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(loot)
