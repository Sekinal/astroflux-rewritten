extends Node
## SoundManager - Handles all game audio
## Ported from sound/SoundManager.as

# =============================================================================
# AUDIO BUS NAMES
# =============================================================================

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

# =============================================================================
# VOLUME
# =============================================================================

var music_volume: float = 0.5:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		_update_music_volume()

var sfx_volume: float = 0.5:
	set(value):
		sfx_volume = clampf(value, 0.0, 1.0)
		_update_sfx_volume()

# =============================================================================
# AUDIO POOLS
# =============================================================================

const SFX_POOL_SIZE := 16
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

var _music_player: AudioStreamPlayer = null
var _music_crossfade_player: AudioStreamPlayer = null

# =============================================================================
# SOUND CACHE
# =============================================================================

var _sound_cache: Dictionary = {}  # path -> AudioStream
var _sound_volumes: Dictionary = {}  # Original volumes from game data

# =============================================================================
# SOUND CONSTANTS (from original SoundConst.as)
# =============================================================================

# Music
const MUSIC_HYPERION := "res://assets/audio/music/theme_hyperion.mp3"
const MUSIC_ACTION := "res://assets/audio/music/action_loop.mp3"
const MUSIC_VAST_SPACE := "res://assets/audio/music/theme_vast_space.mp3"
const MUSIC_DEATH := "res://assets/audio/music/theme_death.mp3"

# Weapons
const SFX_LASER1 := "res://assets/audio/weapons/laser1.mp3"
const SFX_LASER2 := "res://assets/audio/weapons/laser2.mp3"
const SFX_LASER3 := "res://assets/audio/weapons/laser3.mp3"
const SFX_LASER4 := "res://assets/audio/weapons/laser4.mp3"
const SFX_LASER5 := "res://assets/audio/weapons/laser5.mp3"
const SFX_LASER6 := "res://assets/audio/weapons/laser6.mp3"
const SFX_LASER7 := "res://assets/audio/weapons/laser7.mp3"
const SFX_BEAM := "res://assets/audio/weapons/beam.mp3"
const SFX_MISSILE := "res://assets/audio/weapons/rocket1.mp3"
const SFX_FIRE2 := "res://assets/audio/weapons/fire2.mp3"
const SFX_FIRE3 := "res://assets/audio/weapons/fire3.mp3"

# Explosions
const SFX_EXPLOSION_SMALL := "res://assets/audio/explosions/explosion2.mp3"
const SFX_EXPLOSION_MEDIUM := "res://assets/audio/explosions/explosion13.mp3"
const SFX_EXPLOSION_BIG := "res://assets/audio/explosions/explosion_big.mp3"
const SFX_EXPLOSION_HUGE := "res://assets/audio/explosions/explosion_huge.mp3"

# Effects
const SFX_PICKUP := "res://assets/audio/effects/pickup.mp3"
const SFX_LEVEL_UP := "res://assets/audio/effects/effect_level_up.mp3"
const SFX_WARP := "res://assets/audio/effects/warp.mp3"
const SFX_SHIELD_DOWN := "res://assets/audio/effects/effect_energy_field_down.mp3"

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	# Create SFX pool
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)

	# Create music players
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)

	_music_crossfade_player = AudioStreamPlayer.new()
	_music_crossfade_player.bus = BUS_MUSIC
	add_child(_music_crossfade_player)

	# Load original volume data
	_load_sound_volumes()

	print("[SoundManager] Initialized with %d SFX players" % SFX_POOL_SIZE)

func _load_sound_volumes() -> void:
	# Default volumes from the original game
	_sound_volumes = {
		"laser1.mp3": 0.6,
		"laser2.mp3": 0.6,
		"laser3.mp3": 0.6,
		"laser4.mp3": 0.6,
		"laser5.mp3": 0.6,
		"laser6.mp3": 0.6,
		"laser7.mp3": 0.6,
		"beam.mp3": 0.74,
		"rocket1.mp3": 0.7,
		"fire2.mp3": 0.6,
		"fire3.mp3": 0.6,
		"explosion2.mp3": 0.7,
		"explosion13.mp3": 0.7,
		"explosion_big.mp3": 0.8,
		"explosion_huge.mp3": 0.9,
		"pickup.mp3": 0.8,
		"warp.mp3": 0.9,
	}

# =============================================================================
# SFX PLAYBACK
# =============================================================================

## Play a sound effect
func play_sfx(path: String, volume_mult: float = 1.0, pitch_variance: float = 0.0) -> void:
	var stream := _get_or_load_sound(path)
	if stream == null:
		return

	# Get pooled player
	var player := _get_sfx_player()
	if player == null:
		return

	# Set stream and volume
	player.stream = stream
	var base_volume := _get_sound_volume(path)
	player.volume_db = linear_to_db(base_volume * volume_mult * sfx_volume)

	# Apply pitch variance
	if pitch_variance > 0:
		player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	else:
		player.pitch_scale = 1.0

	player.play()

## Play a random laser sound
func play_laser() -> void:
	var lasers := [SFX_LASER1, SFX_LASER2, SFX_LASER3, SFX_LASER4, SFX_LASER5]
	play_sfx(lasers[randi() % lasers.size()], 1.0, 0.1)

## Play beam sound (looping)
func play_beam() -> AudioStreamPlayer:
	var stream := _get_or_load_sound(SFX_BEAM)
	if stream == null:
		return null

	var player := _get_sfx_player()
	if player == null:
		return null

	player.stream = stream
	player.volume_db = linear_to_db(0.74 * sfx_volume)
	# Note: For looping, caller should handle the loop
	player.play()
	return player

## Play explosion based on size
func play_explosion(size: float = 1.0) -> void:
	var path: String
	if size < 0.5:
		path = SFX_EXPLOSION_SMALL
	elif size < 1.0:
		path = SFX_EXPLOSION_MEDIUM
	elif size < 2.0:
		path = SFX_EXPLOSION_BIG
	else:
		path = SFX_EXPLOSION_HUGE

	play_sfx(path, clampf(size, 0.5, 1.5), 0.15)

## Play missile launch sound
func play_missile() -> void:
	play_sfx(SFX_MISSILE, 1.0, 0.1)

## Play pickup sound
func play_pickup() -> void:
	play_sfx(SFX_PICKUP, 1.0, 0.05)

## Play level up sound
func play_level_up() -> void:
	play_sfx(SFX_LEVEL_UP)

## Play warp sound
func play_warp() -> void:
	play_sfx(SFX_WARP)

## Play shield down sound
func play_shield_down() -> void:
	play_sfx(SFX_SHIELD_DOWN)

# =============================================================================
# MUSIC PLAYBACK
# =============================================================================

## Play background music with optional crossfade
func play_music(path: String, crossfade: bool = true, loop: bool = true) -> void:
	var stream := _get_or_load_sound(path)
	if stream == null:
		push_warning("[SoundManager] Failed to load music: " + path)
		return

	if crossfade and _music_player.playing:
		_crossfade_to(stream, loop)
	else:
		_music_player.stream = stream
		_music_player.volume_db = linear_to_db(music_volume)
		_music_player.play()

		if loop:
			_music_player.finished.connect(_on_music_finished.bind(path), CONNECT_ONE_SHOT)

## Stop music with optional fade out
func stop_music(fade_out: bool = true) -> void:
	if fade_out:
		var tween := create_tween()
		tween.tween_property(_music_player, "volume_db", -40.0, 1.0)
		tween.tween_callback(_music_player.stop)
	else:
		_music_player.stop()

## Play theme for solar system
func play_system_theme(system_key: String) -> void:
	var music_path: String
	match system_key.to_lower():
		"hyperion", "antor":
			music_path = MUSIC_HYPERION
		"arrenius":
			music_path = "res://assets/audio/music/theme_arrenius.mp3"
		"kapello":
			music_path = "res://assets/audio/music/theme_kapello.mp3"
		_:
			music_path = MUSIC_VAST_SPACE

	play_music(music_path)

func _crossfade_to(new_stream: AudioStream, loop: bool) -> void:
	# Swap players
	var old_player := _music_player
	_music_player = _music_crossfade_player
	_music_crossfade_player = old_player

	# Start new music
	_music_player.stream = new_stream
	_music_player.volume_db = -40.0
	_music_player.play()

	# Crossfade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_music_player, "volume_db", linear_to_db(music_volume), 1.5)
	tween.tween_property(_music_crossfade_player, "volume_db", -40.0, 1.5)
	tween.chain().tween_callback(_music_crossfade_player.stop)

	if loop:
		_music_player.finished.connect(func(): play_music(new_stream.resource_path, false, true), CONNECT_ONE_SHOT)

func _on_music_finished(path: String) -> void:
	# Loop music
	play_music(path, false, true)

# =============================================================================
# INTERNAL
# =============================================================================

func _get_sfx_player() -> AudioStreamPlayer:
	# Find a free player or use round-robin
	for i in range(SFX_POOL_SIZE):
		var idx := (_sfx_pool_index + i) % SFX_POOL_SIZE
		if not _sfx_players[idx].playing:
			_sfx_pool_index = (idx + 1) % SFX_POOL_SIZE
			return _sfx_players[idx]

	# All players busy - steal the oldest one
	var player := _sfx_players[_sfx_pool_index]
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE
	return player

func _get_or_load_sound(path: String) -> AudioStream:
	if _sound_cache.has(path):
		return _sound_cache[path]

	if not FileAccess.file_exists(path):
		push_warning("[SoundManager] Sound file not found: " + path)
		return null

	var stream := load(path) as AudioStream
	if stream:
		_sound_cache[path] = stream

	return stream

func _get_sound_volume(path: String) -> float:
	var filename := path.get_file()
	if _sound_volumes.has(filename):
		return _sound_volumes[filename]
	return 0.7  # Default volume

func _update_music_volume() -> void:
	if _music_player and _music_player.playing:
		_music_player.volume_db = linear_to_db(music_volume)

func _update_sfx_volume() -> void:
	# Volume is applied per-play, no need to update playing sounds
	pass

# =============================================================================
# UTILITY
# =============================================================================

## Preload commonly used sounds
func preload_common_sounds() -> void:
	var sounds := [
		SFX_LASER1, SFX_LASER2, SFX_LASER3, SFX_LASER4, SFX_LASER5,
		SFX_EXPLOSION_SMALL, SFX_EXPLOSION_MEDIUM, SFX_EXPLOSION_BIG,
		SFX_PICKUP, SFX_MISSILE, SFX_BEAM,
	]
	for path in sounds:
		_get_or_load_sound(path)

	print("[SoundManager] Preloaded %d common sounds" % sounds.size())
