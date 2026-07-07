# =============================================================================
# DUSTFALL — AUDIO SYNTH TEST (headless)
# Verifies the procedural audio engine without an audio device: every SFX and
# drone bed must generate a non-empty, in-range, non-silent 16-bit PCM buffer
# of the expected length. Catches synth regressions (silent buffers, clipping,
# wrong sample rate) that you can't hear in CI.
# Run: godot --headless --path godot --script res://tests/audio_test.gd
# =============================================================================
extends SceneTree

const AudioScript = preload("res://scripts/audio.gd")

func _rms(wav: AudioStreamWAV) -> float:
	var d := wav.data
	var n := d.size() / 2
	if n == 0:
		return 0.0
	var acc := 0.0
	var peak := 0
	for i in range(n):
		var v := d.decode_s16(i * 2)
		acc += float(v) * float(v)
		peak = max(peak, abs(v))
	return sqrt(acc / float(n))

func _init() -> void:
	var a := AudioScript.new()
	# build the SFX table directly (no _ready / no autoload deps)
	a._build_sfx()

	var fails: Array = []
	var sfx_names := ["shot", "hit", "miss", "blast", "divine", "heal", "stun", "click", "win", "lose"]
	print("== SFX ==")
	for nm in sfx_names:
		if not a._sfx.has(nm):
			fails.append("missing sfx: " + nm); continue
		var wav: AudioStreamWAV = a._sfx[nm]
		var samples := wav.data.size() / 2
		var rms := _rms(wav)
		var ms := int(1000.0 * samples / float(a.SR))
		var ok := samples > 0 and rms > 1.0 and wav.mix_rate == a.SR
		print("  %-7s samples=%6d  %4dms  rms=%8.1f  %s" % [nm, samples, ms, rms, "OK" if ok else "FAIL"])
		if not ok:
			fails.append("sfx %s rms=%.1f samples=%d" % [nm, rms, samples])

	print("== MUSIC DRONE BEDS ==")
	for mood in a.MOODS.keys():
		var wav := a._build_drone(mood)
		var samples := wav.data.size() / 2
		var rms := _rms(wav)
		var looped := wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == samples
		var ok := samples > 0 and rms > 1.0 and looped
		print("  %-7s samples=%6d  rms=%8.1f  loop=%s  %s" % [mood, samples, rms, str(looped), "OK" if ok else "FAIL"])
		if not ok:
			fails.append("drone %s rms=%.1f looped=%s" % [mood, rms, str(looped)])

	# clipping sanity: no SFX should be a wall of full-scale samples (bad synth)
	for nm in sfx_names:
		var wav: AudioStreamWAV = a._sfx[nm]
		var d := wav.data
		var clipped := 0
		var n := d.size() / 2
		for i in range(n):
			if abs(d.decode_s16(i * 2)) >= 32767:
				clipped += 1
		if n > 0 and float(clipped) / float(n) > 0.05:
			fails.append("sfx %s over-clipped (%.0f%%)" % [nm, 100.0 * clipped / n])

	print("")
	if fails.is_empty():
		print("AUDIO TEST: PASS (%d SFX + %d moods)" % [sfx_names.size(), a.MOODS.size()])
		quit(0)
	else:
		for f in fails:
			push_error("AUDIO FAIL: " + f)
		print("AUDIO TEST: FAIL (%d issues)" % fails.size())
		quit(1)
