class_name AIState
extends RefCounted
## AIState - Base class for AI state machine states
## Ported from AI state classes in core/ship/ai/

# =============================================================================
# STATE INTERFACE
# =============================================================================

var ship = null  # EnemyShip reference (untyped to avoid load order)
var target: Node = null

func _init(enemy_ship, initial_target: Node = null) -> void:
	ship = enemy_ship
	target = initial_target

## Called when entering this state
func enter() -> void:
	pass

## Called when exiting this state
func exit() -> void:
	pass

## Called every physics frame, returns next state name or empty string to stay
func execute(delta: float) -> String:
	return ""

## Get state name for debugging
func get_state_name() -> String:
	return "AIState"
