extends Node
## Game Constants - Ported from Game.as
## These are the core physics and gameplay constants from the original Astroflux

class_name GameConstantsClass

# =============================================================================
# PHYSICS CONSTANTS (from Game.as)
# =============================================================================

## Milliseconds per physics tick (original: 33ms = ~30 FPS physics)
const TICK_LENGTH: int = 33

## Tick length in seconds for Godot's delta calculations
const TICK_SEC: float = 0.033333

## Player ship friction coefficient (applied per tick)
const FRICTION: float = 0.009

## Enemy ship friction when not accelerating
const FRICTION_ENEMY_IDLE: float = 0.1  # 1 - 0.9 = 0.1 (10% speed loss per tick)

## Roll/strafe friction
const FRICTION_ROLL: float = 0.02

## Sound audibility distance squared
const SOUND_DISTANCE: int = 250000

## Maximum player level
const MAX_LEVEL: int = 150

## Safe zone full regeneration time in seconds
const SAFEZONEFULLREGENTIME: int = 10

## Defense bonus per upgrade level
const DEFENSEBONUS: int = 8

## Damage bonus per upgrade level
const DMGBONUS: int = 8

## Regeneration bonus per upgrade level
const REGENBONUS: int = 1

## Server sync frequency in milliseconds
const SYNC_FREQUENCY: float = 50000.0

# =============================================================================
# CONVERGER CONSTANTS (from Converger.as)
# =============================================================================

## PI / 8 - used for angle snapping threshold
const PI_DIVIDED_BY_8: float = 0.39269908169872414

## Blip offset for convergence calculations
const BLIP_OFFSET: float = 30.0

## Default convergence time in milliseconds
const CONVERGE_TIME: float = 1000.0

## Position error threshold before instant snap
const POSITION_SNAP_THRESHOLD: float = 30.0

## Angle error threshold before instant snap (PI/8)
const ANGLE_SNAP_THRESHOLD: float = 0.39269908169872414

# =============================================================================
# COMBAT CONSTANTS
# =============================================================================

## Maximum resistance cap (75%)
const MAX_RESISTANCE: float = 0.75

## Respawn time in milliseconds
const RESPAWN_TIME: float = 10000.0

## PvP respawn time in milliseconds
const RESPAWN_TIME_PVP: float = 3000.0

# =============================================================================
# DAMAGE TYPES (from Damage.as)
# =============================================================================

enum DamageType {
	KINETIC = 0,
	ENERGY = 1,
	CORROSIVE = 2,
	KINETIC_ENERGY = 3,  # 50/50 split
	KINETIC_CORROSIVE = 4,
	ENERGY_CORROSIVE = 5,
	HEAL = 6,
	ALL_TYPES = 7,
	DONT_SCALE = 8,
	PURE = 9  # Ignores resistances
}

# =============================================================================
# COMMAND TYPES (from Command.as)
# =============================================================================

enum CommandType {
	ACCELERATE = 0,
	ROTATE_LEFT = 1,
	ROTATE_RIGHT = 2,
	FIRE = 3,
	SPEED_BOOST = 4,
	HARDENED_SHIELD = 5,
	SHIELD_CONVERT = 6,
	DAMAGE_BOOST = 7,
	DEACCELERATE = 8
}

# =============================================================================
# AI STATES (from EnemyShip.as)
# =============================================================================

enum AIState {
	IDLE,
	CHASE,
	FOLLOW,
	MELEE,
	FLEE,
	ORBIT,
	OBSERVE,
	BOSS
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Clamp angle to -PI to PI range (matches Util.clampRadians from AS3)
static func clamp_radians(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle

## Calculate angle difference (matches Util.angleDifference from AS3)
static func angle_difference(from_angle: float, to_angle: float) -> float:
	var diff := to_angle - from_angle
	return clamp_radians(diff)

## Format decimal for debug output
static func format_decimal(value: float, decimals: int = 1) -> String:
	return str(snapped(value, pow(10, -decimals)))
