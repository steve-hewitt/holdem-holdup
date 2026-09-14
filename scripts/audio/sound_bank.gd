extends Node

## Procedurally synthesised sound effects. No asset files needed.
## Autoloaded as `SoundBank`.

const RATE := 22050
const POOL_SIZE := 12

var muted := false
var _players: Array = []
var _cache: Dictionary = {}
var _next := 0


func _ready() -> void:
	for _i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)
	_build_sounds()


func toggle_mute() -> bool:
	muted = not muted
	return muted


func stop_all() -> void:
	for p in _players:
		if p.playing:
			p.stop()
		p.stream = null


func play(sound: String, pitch: float = 1.0, volume_db: float = -6.0) -> void:
	if muted:
		return
	if not _cache.has(sound):
		push_warning("SoundBank.play: unknown sound '%s'" % sound)
		return
	var player: AudioStreamPlayer = _idle_player()
	player.stream = _cache[sound]
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


## Prefer a player that is not currently playing so rapid bursts (raise →
## chip → win) do not truncate each other; fall back to round-robin steal.
func _idle_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	return player


func _build_sounds() -> void:
	# Card sliding off the deck.
	_cache["deal"] = _render(0.09, func(t: float) -> float:
		var env: float = exp(-t * 45.0)
		var noise: float = sin(t * 9000.0) * 0.4 + sin(t * 6400.0) * 0.3
		var tone: float = sin(TAU * (1400.0 - t * 4000.0) * t)
		return (noise * 0.5 + tone * 0.5) * env)

	# Clay chip clink.
	_cache["chip"] = _render(0.10, func(t: float) -> float:
		var env: float = exp(-t * 40.0)
		var a: float = sin(TAU * 2600.0 * t)
		var b: float = sin(TAU * 3900.0 * t) * 0.6
		return (a + b) * env * 0.7)

	# Soft table knock for a check.
	_cache["check"] = _render(0.12, func(t: float) -> float:
		var env: float = exp(-t * 30.0)
		return sin(TAU * (240.0 - t * 300.0) * t) * env * 0.8)

	# Low descending tone for a fold.
	_cache["fold"] = _render(0.16, func(t: float) -> float:
		var env: float = exp(-t * 18.0)
		return sin(TAU * (360.0 - t * 900.0) * t) * env * 0.6)

	# Rising double blip for a raise.
	_cache["raise"] = _render(0.18, func(t: float) -> float:
		var env: float = exp(-t * 12.0)
		var step: float = 520.0 if t < 0.07 else 760.0
		return sin(TAU * step * t) * env * 0.6)

	# Victory arpeggio.
	_cache["win"] = _render(0.5, func(t: float) -> float:
		var env: float = exp(-t * 5.0)
		var f: float = 523.25
		if t > 0.12:
			f = 659.25
		if t > 0.24:
			f = 783.99
		if t > 0.36:
			f = 1046.5
		return sin(TAU * f * t) * env * 0.5)

	# Defeat slide.
	_cache["lose"] = _render(0.5, func(t: float) -> float:
		var env: float = exp(-t * 4.0)
		return sin(TAU * (392.0 - t * 300.0) * t) * env * 0.5)

	# UI tick.
	_cache["click"] = _render(0.05, func(t: float) -> float:
		var env: float = exp(-t * 90.0)
		return sin(TAU * 1200.0 * t) * env * 0.5)

	# Big win fanfare.
	_cache["jackpot"] = _render(0.8, func(t: float) -> float:
		var env: float = exp(-t * 3.0)
		var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
		var idx: int = mini(int(t / 0.12), notes.size() - 1)
		return sin(TAU * notes[idx] * t) * env * 0.45)


func _render(duration: float, fn: Callable) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / RATE
		var sample: float = clampf(fn.call(t), -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream
