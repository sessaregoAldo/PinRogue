extends Node
## Sound effects (autoload "Sfx").
## The sounds are synthesized at startup, so the project needs no audio files.
## To use real samples, put an AudioStream into `_streams` under the same name.
## Also owns the audio volume settings (saved to user://settings.cfg).

const MIX_RATE := 22050
const VOICES := 12
const SETTINGS_PATH := "user://settings.cfg"
const SFX_BUS := "SFX"

var master_volume: float = 0.8
var sfx_volume: float = 0.8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_play_ms: Dictionary = {}
var _sfx_bus_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # UI clicks still play while paused
	_sfx_bus_index = AudioServer.get_bus_index(SFX_BUS)
	if _sfx_bus_index == -1:
		AudioServer.add_bus()
		_sfx_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_sfx_bus_index, SFX_BUS)
		AudioServer.set_bus_send(_sfx_bus_index, "Master")
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	_build_sounds()
	load_settings()


## Play a sound by name. `min_interval_ms` stops the same sound from stacking up.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, min_interval_ms: int = 30) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		push_warning("Sfx: unknown sound '%s'" % sound)
		return
	var now := Time.get_ticks_msec()
	if min_interval_ms > 0 and now - int(_last_play_ms.get(sound, -100000)) < min_interval_ms:
		return
	_last_play_ms[sound] = now
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.play()


# --- Settings -----------------------------------------------------------------

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_bus(0, master_volume)


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus(_sfx_bus_index, sfx_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep other sections if they exist
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = float(cfg.get_value("audio", "master", master_volume))
		sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	set_master_volume(master_volume)
	set_sfx_volume(sfx_volume)


func _apply_bus(index: int, linear: float) -> void:
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


# --- Synthesis ----------------------------------------------------------------
# Each sound is a function f(t, p) -> sample in [-1, 1], where t is seconds and
# p is progress from 0 to 1.

func _build_sounds() -> void:
	_streams["flipper_up"] = _synth(0.09, func(t: float, _p: float) -> float:
		return sin(TAU * 90.0 * t) * 0.7 * exp(-t * 40.0) + _noise() * 0.5 * exp(-t * 90.0))
	_streams["flipper_down"] = _synth(0.06, func(t: float, _p: float) -> float:
		return sin(TAU * 70.0 * t) * 0.5 * exp(-t * 60.0) + _noise() * 0.2 * exp(-t * 120.0))
	_streams["bumper"] = _synth(0.25, func(t: float, _p: float) -> float:
		var tone := sin(TAU * 660.0 * t) + 0.6 * sin(TAU * 990.0 * t) + 0.3 * sin(TAU * 1320.0 * t)
		return tone / 1.9 * 0.8 * exp(-t * 14.0) + _noise() * 0.4 * exp(-t * 300.0))
	_streams["slingshot"] = _synth(0.08, func(t: float, _p: float) -> float:
		return _noise() * 0.6 * exp(-t * 60.0) + sin(TAU * 320.0 * t) * 0.6 * exp(-t * 45.0))
	_streams["bounce"] = _synth(0.04, func(t: float, _p: float) -> float:
		return sin(TAU * 1800.0 * t) * 0.5 * exp(-t * 150.0) + _noise() * 0.4 * exp(-t * 250.0))
	_streams["launch"] = _synth(0.22, func(t: float, _p: float) -> float:
		return sin(TAU * (150.0 * t + 600.0 * t * t)) * 0.5 * exp(-t * 10.0) + _noise() * 0.4 * exp(-t * 20.0))
	_streams["ramp_enter"] = _synth(0.3, func(t: float, p: float) -> float:
		return sin(TAU * (250.0 * t + 900.0 * t * t)) * 0.45 * (1.0 - p) + _noise() * 0.15 * (1.0 - p))
	_streams["ramp_land"] = _synth(0.12, func(t: float, _p: float) -> float:
		return sin(TAU * 85.0 * t) * 0.8 * exp(-t * 30.0) + _noise() * 0.35 * exp(-t * 80.0))
	_streams["ramp_complete"] = _synth(0.36, func(t: float, _p: float) -> float:
		var note := [523.25, 659.25, 783.99][mini(int(t / 0.09), 2)] as float
		var local := fmod(t, 0.09) if t < 0.18 else t - 0.18
		return sin(TAU * note * t) * 0.4 * exp(-local * 12.0))
	_streams["drain"] = _synth(0.6, func(t: float, p: float) -> float:
		return signf(sin(TAU * (300.0 * t - 150.0 * t * t))) * 0.25 * (1.0 - p))
	_streams["tilt"] = _synth(0.5, func(t: float, p: float) -> float:
		return signf(sin(TAU * 110.0 * t)) * 0.3 * (1.0 - p * 0.5))
	_streams["warning"] = _synth(0.15, func(t: float, p: float) -> float:
		return signf(sin(TAU * 440.0 * t)) * 0.2 * (1.0 - p))
	_streams["rollover"] = _synth(0.07, func(t: float, _p: float) -> float:
		return sin(TAU * 1500.0 * t) * 0.35 * exp(-t * 50.0) + sin(TAU * 2250.0 * t) * 0.15 * exp(-t * 70.0))
	_streams["victory"] = _synth(1.3, func(t: float, _p: float) -> float:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var i := mini(int(t / 0.16), 3)
		var local := t - i * 0.16
		var decay := 3.0 if i == 3 else 10.0
		var f: float = notes[i]
		return (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)) / 1.4 * 0.45 * exp(-local * decay))
	_streams["powerup"] = _synth(0.5, func(t: float, _p: float) -> float:
		var notes := [659.25, 880.0, 1174.66, 1318.5]
		var i := mini(int(t / 0.07), 3)
		var f: float = notes[i]
		return sin(TAU * f * t) * 0.35 * exp(-(t - i * 0.07) * (4.0 if i == 3 else 14.0)))
	_streams["multiplier"] = _synth(0.35, func(t: float, p: float) -> float:
		return (sin(TAU * (300.0 * t + 1400.0 * t * t)) + 0.5 * signf(sin(TAU * (600.0 * t + 2800.0 * t * t)))) / 1.5 * 0.4 * (1.0 - p))
	_streams["guard_hit"] = _synth(0.15, func(t: float, _p: float) -> float:
		return (sin(TAU * 420.0 * t) + 0.6 * sin(TAU * 1130.0 * t)) / 1.6 * 0.6 * exp(-t * 25.0))
	_streams["guard_break"] = _synth(0.45, func(t: float, p: float) -> float:
		return _noise() * 0.5 * exp(-t * 9.0) + sin(TAU * (900.0 * t - 700.0 * t * t)) * 0.3 * (1.0 - p))
	_streams["booster"] = _synth(0.3, func(t: float, p: float) -> float:
		return (sin(TAU * (200.0 * t + 1500.0 * t * t)) * 0.4 + _noise() * 0.25) * sin(PI * p))
	_streams["click"] = _synth(0.03, func(t: float, _p: float) -> float:
		return sin(TAU * 1200.0 * t) * 0.4 * exp(-t * 200.0))


func _synth(duration: float, sample: Callable) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / MIX_RATE
		var v := clampf(float(sample.call(t, t / duration)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _noise() -> float:
	return randf_range(-1.0, 1.0)
