# =============================================================================
# DUSTFALL — AUDIO ENGINE (Godot port of src/audio.js)
# Fully synthesized: SFX + a sparse generative western ambient layer.
# Zero assets, zero network — procedurally rendered 16-bit PCM only.
# Autoload singleton "Audio". Mute: Audio.toggle_mute(); persisted in GameState.
#
# Design parity with the web engine (src/audio.js):
#   SFX  : shot hit miss blast divine heal stun click win lose
#   MOODS: title map town battle boss  (drone bed + sparse pentatonic plucks)
# The web engine used WebAudio oscillators + biquad filters live; Godot has no
# per-node biquad on generated PCM, so we bake each SFX to an AudioStreamWAV at
# startup with a tiny in-GDScript synth (one-pole filtered noise + decaying
# tones). Character matches; cost is a few ms of buffer generation on boot.
# =============================================================================
extends Node

const SR := 44100                      # sample rate
const MASTER_SFX := 0.5
const MASTER_MUSIC := 0.14

var _muted := false
var music_vol := 1.0                   # 0..1 user volume (persisted in settings)
var sfx_vol := 1.0
var _sfx: Dictionary = {}              # name -> AudioStreamWAV
var _sfx_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _pluck_timer: Timer
var _mood := ""

# mood = root(Hz), pentatonic-ish scale (semitones), pluck pace range ms, drone vol
const MOODS := {
	"title":  {"root": 55.0,  "scale": [0, 3, 5, 7, 10], "pace": [4.0, 9.0],  "vol": 0.14},
	"map":    {"root": 65.4,  "scale": [0, 3, 5, 7, 10], "pace": [5.0, 11.0], "vol": 0.12},
	"town":   {"root": 82.4,  "scale": [0, 2, 5, 7, 9],  "pace": [4.5, 9.0],  "vol": 0.10},
	"battle": {"root": 49.0,  "scale": [0, 3, 6, 7, 10], "pace": [2.5, 6.0],  "vol": 0.16},
	"boss":   {"root": 41.2,  "scale": [0, 1, 3, 6, 7],  "pace": [1.8, 4.2],  "vol": 0.20},
}


# Autoloads aren't registered as global identifiers under `godot --script`
# headless runs, so look GameState up by node path at runtime (never as a
# compile-time global) — lets the synth tests instantiate this script directly.
func _gamestate() -> Node:
	return get_node_or_null("/root/GameState")

func _ready() -> void:
	# keep audio (and the pause-menu's slider feedback) alive while the tree
	# is paused — the PauseMenu autoload pauses everything else
	process_mode = Node.PROCESS_MODE_ALWAYS
	var gs := _gamestate()
	if gs and gs.has_method("get_setting"):
		_muted = bool(gs.get_setting("audio_muted", false))
		music_vol = clampf(float(gs.get_setting("music_vol", 1.0)), 0.0, 1.0)
		sfx_vol = clampf(float(gs.get_setting("sfx_vol", 1.0)), 0.0, 1.0)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "Master"
	add_child(_sfx_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = _db(MASTER_MUSIC * music_vol)
	add_child(_music_player)
	_pluck_timer = Timer.new()
	_pluck_timer.one_shot = true
	_pluck_timer.timeout.connect(_on_pluck)
	add_child(_pluck_timer)
	_build_sfx()


# ---- tiny synth toolkit: writes into a Float array buffer (mono, -1..1) ----

func _rng() -> float:
	return randf() * 2.0 - 1.0

# one-pole lowpass on a white-noise burst with exponential amplitude decay;
# sweep>0 glides the cutoff (approx of the web engine's biquad sweep).
func _burst(buf: PackedFloat32Array, start: float, dur: float, cutoff: float, gain: float, sweep: float, highpass := false) -> void:
	var n := int(dur * SR)
	var s0 := int(start * SR)
	var prev := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / float(n)
		var fc: float = cutoff if sweep <= 0.0 else cutoff * pow(sweep / cutoff, t)
		var alpha: float = clampf(fc / float(SR) * 6.283, 0.001, 0.999)
		var white := _rng()
		prev = prev + alpha * (white - prev)          # one-pole LP
		var sample: float = (white - prev) if highpass else prev
		var env := gain * exp(-5.0 * t)               # exp decay
		buf[idx] += sample * env

# one decaying oscillator tone; type: sine/square/saw/triangle; f1>0 glides pitch
func _tone(buf: PackedFloat32Array, start: float, freq: float, dur: float, gain: float, wave := "sine", f1 := 0.0) -> void:
	var n := int(dur * SR)
	var s0 := int(start * SR)
	var phase := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / float(n)
		var f: float = freq if f1 <= 0.0 else freq * pow(f1 / freq, t)
		phase += 6.283185 * f / float(SR)
		var s := 0.0
		match wave:
			"square":   s = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":      s = fmod(phase / 6.283185, 1.0) * 2.0 - 1.0
			"triangle": s = asin(sin(phase)) * 0.6366
			_:          s = sin(phase)
		# fast attack (15ms), exp decay — mirrors the web gain envelope
		var atk: float = minf(1.0, (float(i) / float(SR)) / 0.015)
		var env := gain * atk * exp(-4.0 * t)
		buf[idx] += s * env

func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in range(buf.size()):
		var v := int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	return wav

func _blank(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * SR))
	b.fill(0.0)
	return b


# ---- SFX catalog (parity with DF.sfx) ----

func _build_sfx() -> void:
	var b: PackedFloat32Array

	b = _blank(0.2);  _burst(b, 0, 0.14, 900, 0.7, 200); _burst(b, 0, 0.05, 2500, 0.25, 0, true)
	_sfx["shot"] = _to_wav(b)

	b = _blank(0.15); _tone(b, 0, 220, 0.10, 0.25, "square", 90); _burst(b, 0, 0.08, 500, 0.3, 0)
	_sfx["hit"] = _to_wav(b)

	b = _blank(0.22); _burst(b, 0, 0.18, 1800, 0.12, 3200)
	_sfx["miss"] = _to_wav(b)

	b = _blank(0.55); _burst(b, 0, 0.5, 500, 0.9, 60); _tone(b, 0, 70, 0.45, 0.5, "sine", 40)
	_sfx["blast"] = _to_wav(b)

	b = _blank(0.8)
	var i := 0
	for f in [220.0, 277.0, 330.0, 440.0]:
		_tone(b, i * 0.05, f, 0.7, 0.12, "saw", f * 1.5); i += 1
	_burst(b, 0, 0.6, 4000, 0.1, 0, true)
	_sfx["divine"] = _to_wav(b)

	b = _blank(0.4);  _tone(b, 0, 392, 0.16, 0.2, "sine"); _tone(b, 0.1, 523, 0.28, 0.2, "sine")
	_sfx["heal"] = _to_wav(b)

	b = _blank(0.25); _tone(b, 0, 660, 0.08, 0.15, "square"); _tone(b, 0.12, 660, 0.08, 0.12, "square")
	_sfx["stun"] = _to_wav(b)

	b = _blank(0.06); _tone(b, 0, 900, 0.03, 0.08, "square", 500)
	_sfx["click"] = _to_wav(b)

	b = _blank(0.9); i = 0
	for f in [262.0, 330.0, 392.0, 523.0]:
		_tone(b, i * 0.13, f, 0.35, 0.22, "triangle"); i += 1
	_sfx["win"] = _to_wav(b)

	b = _blank(1.3); i = 0
	for f in [330.0, 294.0, 262.0, 196.0]:
		_tone(b, i * 0.22, f, 0.5, 0.16, "saw", f * 0.97); i += 1
	_sfx["lose"] = _to_wav(b)


# ---- public SFX API (Audio.sfx("shot")) ----

func sfx(name: String) -> void:
	if _muted or not _sfx.has(name):
		return
	_sfx_player.stream = _sfx[name]
	_sfx_player.volume_db = _db(MASTER_SFX * sfx_vol)
	_sfx_player.play()


# ---- generative ambient music: looping drone bed + timed plucks ----

func _build_drone(mood_id: String) -> AudioStreamWAV:
	var m: Dictionary = MOODS.get(mood_id, MOODS["title"])
	var root: float = m["root"]
	var secs := 4.0                                  # seamless-ish loop bed
	var buf := _blank(secs)
	# two detuned saws through a dark lowpass = desert-wind organ
	var prev := 0.0
	for i in range(buf.size()):
		var ph := 6.283185 * root * float(i) / float(SR)
		var ph2 := 6.283185 * (root + 0.7) * float(i) / float(SR)
		var raw := (fmod(ph / 6.283185, 1.0) * 2.0 - 1.0) + (fmod(ph2 / 6.283185, 1.0) * 2.0 - 1.0)
		raw *= 0.25
		prev = prev + 0.02 * (raw - prev)            # ~220Hz one-pole lowpass
		buf[i] = prev
	var wav := _to_wav(buf)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	return wav

func play_music(mood_id: String) -> void:
	if _music_player == null:
		return # headless / _ready not yet run — scenes may still request music
	if _mood == mood_id and _music_player.playing:
		return
	_mood = mood_id
	if _muted:
		return
	var m: Dictionary = MOODS.get(mood_id, MOODS["title"])
	_music_player.stream = _build_drone(mood_id)
	_music_player.volume_db = _db(float(m["vol"]) * music_vol)
	_music_player.play()
	_schedule_pluck()

func stop_music() -> void:
	_mood = ""
	_music_player.stop()
	_pluck_timer.stop()

func _schedule_pluck() -> void:
	if _mood == "":
		return
	var m: Dictionary = MOODS[_mood]
	var lo: float = m["pace"][0]
	var hi: float = m["pace"][1]
	_pluck_timer.start(lo + randf() * (hi - lo))

func _on_pluck() -> void:
	if _mood == "" or _muted:
		return
	var m: Dictionary = MOODS[_mood]
	var root: float = m["root"]
	var scale: Array = m["scale"]
	var notes := 1 + (randi() % 3)
	var buf := _blank(1.4)
	for i in range(notes):
		var semi: float = float(scale[randi() % scale.size()])
		var octv := 2 + (randi() % 2)
		var f := root * pow(2.0, octv + semi / 12.0)
		_tone(buf, i * 0.28, f, 0.9, 0.1, "triangle", f * 0.995)
	# fire the pluck through a transient one-shot player so the drone keeps looping
	var p := AudioStreamPlayer.new()
	p.stream = _to_wav(buf)
	p.bus = "Master"
	p.volume_db = _db(MASTER_MUSIC * music_vol)
	add_child(p)
	p.finished.connect(func(): p.queue_free())
	p.play()
	_schedule_pluck()

# engine hook: called on every scene switch (mirrors DF.music.onScene)
func on_scene(name: String) -> void:
	match name:
		"title", "creator": play_music("title")
		"worldmap":         play_music("map")
		"town":             play_music("town")
		"results", "ending": play_music("map")
		# battle picks its own mood (boss-aware) in the battle scene


# ---- mute / volumes ----

func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 1.0)) # 0 -> -80dB silence, never -inf

func set_music_volume(v: float) -> void:
	music_vol = clampf(v, 0.0, 1.0)
	if _music_player != null and _mood != "":
		var m: Dictionary = MOODS.get(_mood, MOODS["title"])
		_music_player.volume_db = _db(float(m["vol"]) * music_vol)
	_persist("music_vol", music_vol)

func set_sfx_volume(v: float) -> void:
	sfx_vol = clampf(v, 0.0, 1.0)
	_persist("sfx_vol", sfx_vol)

func get_music_volume() -> float:
	return music_vol

func get_sfx_volume() -> float:
	return sfx_vol

func _persist(key: String, value) -> void:
	var gs := _gamestate()
	if gs and gs.has_method("set_setting"):
		gs.set_setting(key, value)

func toggle_mute() -> bool:
	_muted = not _muted
	_persist("audio_muted", _muted)
	if _muted:
		var keep := _mood
		stop_music()
		_mood = keep   # remember the scene's mood so unmute can resume it
	elif _mood != "":
		play_music(_mood)
	return _muted

func is_muted() -> bool:
	return _muted
