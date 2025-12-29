class_name HUD
extends CanvasLayer
## HUD - Heads Up Display
## Shows health, shield, and weapon info

# =============================================================================
# NODES
# =============================================================================

@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var shield_bar: ProgressBar = $MarginContainer/VBoxContainer/ShieldBar
@onready var heat_bar: ProgressBar = $MarginContainer/VBoxContainer/HeatBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/Label
@onready var shield_label: Label = $MarginContainer/VBoxContainer/ShieldBar/Label
@onready var heat_label: Label = $MarginContainer/VBoxContainer/HeatBar/Label
@onready var weapon_label: Label = $MarginContainer/VBoxContainer/WeaponInfo

# =============================================================================
# STATE
# =============================================================================

var _player: CharacterBody2D = null

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Wait a frame for scene to be ready
	await get_tree().process_frame
	_find_player()

func _find_player() -> void:
	# Find player ship in scene
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		set_player(players[0])
	else:
		# Try to find by class
		var game := get_parent()
		if game and game.has_node("PlayerShip"):
			set_player(game.get_node("PlayerShip"))

func set_player(player: Node) -> void:
	if _player:
		# Disconnect old signals using duck typing
		if _player.has_signal("health_changed"):
			if _player.health_changed.is_connected(_on_health_changed):
				_player.health_changed.disconnect(_on_health_changed)
		if _player.has_signal("shield_changed"):
			if _player.shield_changed.is_connected(_on_shield_changed):
				_player.shield_changed.disconnect(_on_shield_changed)

	_player = player

	if _player:
		if _player.has_signal("health_changed"):
			_player.health_changed.connect(_on_health_changed)
		if _player.has_signal("shield_changed"):
			_player.shield_changed.connect(_on_shield_changed)

		# Initialize bars
		var hp = _player.get("hp") if _player.get("hp") != null else 100.0
		var hp_max = _player.get("hp_max") if _player.get("hp_max") != null else 100.0
		var shield = _player.get("shield") if _player.get("shield") != null else 100.0
		var shield_max = _player.get("shield_max") if _player.get("shield_max") != null else 100.0
		_on_health_changed(hp, hp_max)
		_on_shield_changed(shield, shield_max)

func _process(_delta: float) -> void:
	if _player == null:
		return

	# Update weapon info
	var weapon = _player.get_active_weapon()
	if weapon and weapon_label:
		var reload_pct: float = weapon.get_reload_progress(NetworkManager.server_time) * 100
		weapon_label.text = "%s [%.0f%%]" % [weapon.weapon_type.to_upper(), reload_pct]

	# Update heat bar
	var player_heat = _player.get("heat")
	if player_heat and heat_bar:
		var heat_pct: float = player_heat.get_heat_percent()
		heat_bar.value = heat_pct
		if heat_label:
			# Show lockout status if applicable
			var current_time: float = NetworkManager.server_time
			if player_heat.is_locked_out(current_time):
				var remaining: float = player_heat.get_lockout_remaining(current_time)
				heat_label.text = "LOCKED [%.1fs]" % remaining
				heat_label.modulate = Color.RED
			else:
				heat_label.text = "ENERGY: %d%%" % int(heat_pct * 100)
				# Color based on energy level
				if heat_pct < 0.25:
					heat_label.modulate = Color.ORANGE
				else:
					heat_label.modulate = Color.WHITE

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_health_changed(current: float, maximum: float) -> void:
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current
	if health_label:
		health_label.text = "HP: %d / %d" % [int(current), int(maximum)]

func _on_shield_changed(current: float, maximum: float) -> void:
	if shield_bar:
		shield_bar.max_value = maximum
		shield_bar.value = current
	if shield_label:
		shield_label.text = "SHIELD: %d / %d" % [int(current), int(maximum)]
