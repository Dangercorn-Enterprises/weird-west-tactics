# =============================================================================
# DUSTFALL — PAUSE MENU + SETTINGS TEST (headless)
# 1) GameState settings: get/set roundtrip + persisted to user://settings.json
#    (the path audio.gd's mute persistence silently no-op'd on before this —
#    get_setting/set_setting never existed on GameState).
# 2) Audio volumes: setters clamp + persist, live music volume_db tracks the
#    user volume, zero volume never crashes.
# 3) Mute: persists, stops music, and RESUMES the scene mood on unmute.
# 4) PauseMenu autoload: open pauses the tree + shows the overlay with synced
#    sliders, close unpauses, quit-to-title lands on the Title scene unpaused.
# Run: godot --headless --path godot --script res://tests/pause_test.gd
# =============================================================================
extends SceneTree

var fails: Array = []
var stage := 0
var stage_start_ms := 0
var gs: Node
var audio: Node
var pm: Node

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _init() -> void:
	stage = -1 # autoloads mount after _init — start work on frame 1
	stage_start_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - stage_start_ms) / 1000.0

func _next() -> void:
	stage += 1
	stage_start_ms = Time.get_ticks_msec()

func _finish() -> void:
	if fails.is_empty():
		print("PAUSE TEST: ALL PASS")
		quit(0)
	else:
		print("PAUSE TEST: %d FAILURES" % fails.size())
		quit(1)

func _tick() -> void:
	match stage:
		-1:
			gs = root.get_node_or_null("GameState")
			audio = root.get_node_or_null("Audio")
			pm = root.get_node_or_null("PauseMenu")
			if gs == null or audio == null or pm == null:
				_fail("autoload missing: gs=%s audio=%s pause=%s" % [gs, audio, pm])
				_finish()
				return
			_test_settings()
			_test_volumes()
			_test_mute()
			_test_menu()
			_test_posse()
			# quit-to-title from a paused menu, then let change_scene settle
			pm.open_menu()
			pm._quit_to_title()
			_next()
		0:
			if _elapsed() < 0.5:
				return
			if current_scene == null or String(current_scene.name) != "Title":
				var got := String(current_scene.name) if current_scene != null else "null"
				_fail("quit-to-title did not land on Title (scene=%s)" % got)
			if paused:
				_fail("quit-to-title left the tree paused")
			_finish()

func _test_settings() -> void:
	print("== settings persistence ==")
	gs.set_setting("pause_test_key", 42)
	if int(gs.get_setting("pause_test_key", -1)) != 42:
		_fail("set/get_setting roundtrip failed")
	if String(gs.get_setting("missing_key", "dflt")) != "dflt":
		_fail("get_setting default not honored")
	var f := FileAccess.open("user://settings.json", FileAccess.READ)
	if f == null:
		_fail("settings.json not written")
	else:
		var s = JSON.parse_string(f.get_as_text())
		if not (s is Dictionary) or int(s.get("pause_test_key", -1)) != 42:
			_fail("settings.json does not contain the persisted key")

func _test_volumes() -> void:
	print("== audio volumes ==")
	if audio.is_muted():
		audio.toggle_mute() # normalize: tests assume unmuted baseline
	audio.set_music_volume(2.0)
	if absf(float(audio.get_music_volume()) - 1.0) > 0.001:
		_fail("music volume not clamped to 1.0")
	audio.play_music("title")
	audio.set_music_volume(0.25)
	var want: float = linear_to_db(0.14 * 0.25) # title mood vol * user vol
	var got: float = audio._music_player.volume_db
	if absf(got - want) > 0.1:
		_fail("live music volume_db %f != expected %f" % [got, want])
	if absf(float(gs.get_setting("music_vol", -1.0)) - 0.25) > 0.001:
		_fail("music volume not persisted")
	audio.set_sfx_volume(0.0)
	audio.sfx("click") # zero volume must not crash (floors at -80dB)
	if absf(float(gs.get_setting("sfx_vol", -1.0)) - 0.0) > 0.001:
		_fail("sfx volume not persisted")
	audio.set_music_volume(1.0)
	audio.set_sfx_volume(1.0)

func _test_mute() -> void:
	print("== mute persistence + mood resume ==")
	audio.play_music("map")
	audio.toggle_mute() # -> muted
	if bool(gs.get_setting("audio_muted", false)) != true:
		_fail("mute=true not persisted")
	if audio._music_player.playing:
		_fail("music still playing while muted")
	audio.toggle_mute() # -> unmuted; the map mood must come back
	if bool(gs.get_setting("audio_muted", true)) != false:
		_fail("mute=false not persisted")
	if String(audio._mood) != "map":
		_fail("mood lost across mute/unmute: %s" % audio._mood)
	if not audio._music_player.playing:
		_fail("music did not resume on unmute")

# Posse sheet (2i): injected IN-MEMORY roster only — state is swapped back and
# never saved (_swap is deliberately untested here; it writes user://save.json).
func _test_posse() -> void:
	print("== posse sheet ==")
	var saved_state = gs.state
	gs.state = {"party": [
		{"uid": "t0", "name": "Test Rider", "archetype": "gunslinger", "level": 2,
			"xp": 40, "hpDamage": 4, "gear": {"weapon": "rifle"}, "god": "vulcan",
			"stats": {"vigor": 6, "quickness": 7, "strength": 4, "deftness": 8,
				"nimbleness": 5, "cognition": 4, "knowledge": 3, "mien": 4, "spirit": 5}},
		{"uid": "t1", "name": "Bench Hand", "archetype": "preacher", "level": 1,
			"xp": 0, "hpDamage": 0, "gear": {},
			"stats": {"vigor": 5, "quickness": 4, "strength": 5, "deftness": 4}},
	]}
	pm.open_menu()
	if pm.posse_btn.disabled:
		_fail("posse button disabled with a live party")
	pm._open_posse()
	if not pm.posse_box.visible or pm.main_box.visible:
		_fail("posse view did not swap in")
	if pm.posse_box.get_child_count() != 5: # head + hint + 2 rider rows + back
		_fail("posse row count wrong: %d" % pm.posse_box.get_child_count())
	pm._back_to_main()
	if pm.posse_box.visible or not pm.main_box.visible:
		_fail("back did not restore the main menu")
	pm.close()
	gs.state = saved_state

func _test_menu() -> void:
	print("== pause menu ==")
	audio.set_music_volume(0.6)
	audio.set_sfx_volume(0.3)
	pm.open_menu()
	if not paused:
		_fail("open_menu did not pause the tree")
	if not pm.ui_root.visible:
		_fail("open_menu did not show the overlay")
	if absf(float(pm.music_slider.value) - 0.6) > 0.001:
		_fail("music slider not synced on open: %s" % pm.music_slider.value)
	if absf(float(pm.sfx_slider.value) - 0.3) > 0.001:
		_fail("sfx slider not synced on open: %s" % pm.sfx_slider.value)
	# slider handler drives the audio engine
	pm._on_music_changed(0.9)
	if absf(float(audio.get_music_volume()) - 0.9) > 0.001:
		_fail("music slider change did not reach Audio")
	pm.close()
	if paused:
		_fail("close did not unpause the tree")
	if pm.ui_root.visible:
		_fail("close left the overlay visible")
	audio.set_music_volume(1.0)
	audio.set_sfx_volume(1.0)
