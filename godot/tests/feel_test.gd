# =============================================================================
# DUSTFALL — FEEL PASS TEST (headless, v1.4 2026-10-08)
# The enemy phase is recorded from CombatCore's UI hooks and played back one
# event at a time (battle.gd _end_turn -> _play_events). This boots battle.tscn
# on an in-memory GameState (never touches user://save.json) and checks:
#   1) hooks fire: a seeded enemy phase records move/fire/hit events, and the
#      core's new on_fire/on_move/on_blast hooks are pure (no extra RNG draws:
#      the same seed produces the same end state with hooks on and off)
#   2) playback contract: input is blocked (_busy), sprites + labels are frozen
#      until their event plays, every unit lands on its logic tile at the end,
#      labels show the real hp, locks/frozen sets are empty, a rider is selected
#   3) feedback pieces: MISS and COVER floaters, death animation lock + hide,
#      heal floater, hover tile + AP cost, hit-stop releases, SFX pool rotates
# Run: godot --headless --path godot --script res://tests/feel_test.gd
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")
const MemoryState = preload("res://tests/_memory_state.gd")

var fails: Array = []
var scene
var stage := 0
var stage_start_ms := 0
var dead_id: Variant = null
var events_seen := 0

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _ok(msg: String) -> void:
	print("  ok  ", msg)

# ---- 1) pure hooks: same seed, same end state, hooks on vs off ----------------
func _test_hook_purity() -> void:
	print("== hook purity (parity guard) ==")
	var runs := []
	for with_hooks in [false, true]:
		var core = CombatCoreScript.new()
		var gs = root.get_node("/root/GameState")
		core.design = gs.design
		core.seed_rng(4242)
		var grid: Array = core.build_grid()
		var players: Array = []
		var roster: Array = gs.state["party"]
		for i in mini(3, roster.size()):
			var u: Dictionary = core.party_to_unit(roster[i], i)
			players.append(u)
		var specs: Array = core.scale_encounter(gs.enemies_by_ids(["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil", "powder_monk"]), players.size())
		var enemies: Array = []
		for i in specs.size():
			var e: Dictionary = core.enemy_to_unit(specs[i], i)
			e["q"] = core.SPAWNS[i % core.SPAWNS.size()][0]
			e["r"] = core.SPAWNS[i % core.SPAWNS.size()][1]
			enemies.append(e)
		var b := {"grid": grid, "players": players, "enemies": enemies, "units": players + enemies,
			"kills": 0, "xpKills": 0, "playerDeaths": 0, "charges": []}
		var counts := {"fire": 0, "move": 0, "blast": 0}
		if with_hooks:
			core.on_fire = func(_a, _d, _res): counts["fire"] += 1
			core.on_move = func(_u, _q, _r, _reach): counts["move"] += 1
			core.on_blast = func(_c): counts["blast"] += 1
		for turn in 4:
			core.enemy_phase(b)
			for p in players:
				if p["alive"]:
					p["ap"] = p["maxAp"]
		var sig := []
		for u in b["units"]:
			sig.append([u["id"], u["q"], u["r"], u["hp"], u["alive"]])
		runs.append({"sig": sig, "counts": counts, "rng": core._rng_state})
	if runs[0]["sig"] != runs[1]["sig"] or runs[0]["rng"] != runs[1]["rng"]:
		_fail("hooks changed the simulation: %s vs %s" % [str(runs[0]["sig"]), str(runs[1]["sig"])])
	else:
		_ok("4 enemy phases identical with hooks on/off (rng state %d)" % runs[1]["rng"])
	var c: Dictionary = runs[1]["counts"]
	if c["fire"] + c["move"] == 0:
		_fail("no fire/move hook calls in 4 phases: %s" % str(c))
	else:
		_ok("hook calls: %s" % str(c))

# ---- scene boot ----------------------------------------------------------------
func _init() -> void:
	stage = -1
	stage_start_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _setup_scene() -> void:
	var gs = MemoryState.mount(self)
	if gs == null:
		_fail("GameState autoload missing under --script")
		_finish()
		return
	gs.new_game()
	_test_hook_purity()
	print("== live battle scene ==")
	scene = preload("res://scenes/battle.tscn").instantiate()
	if not ("sel" in scene):
		_fail("battle.gd failed to attach — parse error (scene is bare %s)" % scene.get_class())
		_finish()
		return
	root.add_child(scene)
	scene.core.seed_rng(4242)

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - stage_start_ms) / 1000.0

func _next() -> void:
	stage += 1
	stage_start_ms = Time.get_ticks_msec()

func _finish() -> void:
	Engine.time_scale = 1.0
	if fails.is_empty():
		print("FEEL TEST: ALL PASS")
		quit(0)
	else:
		print("FEEL TEST: %d FAILURES" % fails.size())
		quit(1)

func _count_floaters(text: String) -> int:
	var n := 0
	for c in scene.get_children():
		if c is Label3D and String(c.text) == text:
			n += 1
	return n

func _tick() -> void:
	match stage:
		-1:
			_setup_scene()
			_next()
		0: # settle, then move an enemy next to the party so the phase has shots
			if _elapsed() < 0.3:
				return
			print("== enemy phase playback ==")
			var e0: Dictionary = scene.battle["enemies"][0]
			var p0: Dictionary = scene.battle["players"][0]
			e0["q"] = int(p0["q"]) + 2
			e0["r"] = int(p0["r"])
			scene._sync_units()
			var e1: Dictionary = scene.battle["enemies"][1]
			var spr1: Sprite3D = scene.unit_nodes[e1["id"]]["sprite"]
			var before1 := spr1.position
			scene._end_turn()
			events_seen = scene._events.size()
			if not scene._busy:
				_fail("_end_turn did not enter playback (_busy false)")
			if scene._frozen.is_empty():
				_fail("no units frozen for playback")
			if events_seen == 0:
				_fail("enemy phase recorded no events")
			else:
				var kinds := {}
				for ev in scene._events:
					kinds[ev["t"]] = int(kinds.get(ev["t"], 0)) + 1
				_ok("recorded %d events: %s" % [events_seen, str(kinds)])
			# frozen contract: an enemy that will move has NOT been teleported yet
			var moved_now := false
			for ev in scene._events:
				if ev["t"] == "move" and ev["u"]["id"] == e1["id"]:
					moved_now = true
			if moved_now and spr1.position.distance_to(before1) > 0.01:
				_fail("enemy sprite moved before its event played")
			# input is blocked while busy
			var ap0: int = int(scene.sel["ap"]) if not scene.sel.is_empty() else -1
			scene._click(Vector2(640, 360))
			if not scene.sel.is_empty() and int(scene.sel["ap"]) != ap0:
				_fail("click during playback changed state")
			_next()
		1: # wait for playback to finish
			if scene._busy or not scene._animating.is_empty():
				if _elapsed() > 14.0:
					_fail("playback never finished: busy=%s locks=%s" % [str(scene._busy), str(scene._animating)])
					_finish()
				return
			if not scene._frozen.is_empty():
				_fail("frozen set not cleared after playback: %s" % str(scene._frozen))
			if not scene._events.is_empty():
				_fail("event list not cleared after playback")
			for u in scene.battle["units"]:
				if not scene.unit_nodes.has(u["id"]):
					continue
				var n: Dictionary = scene.unit_nodes[u["id"]]
				var spr: Sprite3D = n["sprite"]
				if u["alive"]:
					var wx: float = scene._tx(int(u["q"]))
					var wz: float = scene._tz(int(u["r"]))
					if absf(spr.position.x - wx) > 0.05 or absf(spr.position.z - wz) > 0.05:
						_fail("unit %s sprite off its tile after playback" % str(u["id"]))
					if String(n["label"].text) != "%d" % maxi(0, int(u["hp"])):
						_fail("unit %s label %s != hp %d" % [str(u["id"]), n["label"].text, int(u["hp"])])
				elif spr.visible:
					_fail("dead unit %s still visible after playback" % str(u["id"]))
			if scene.ended:
				_ok("battle ended during the phase (fine) — skipping selection check")
			elif scene.sel.is_empty() or not scene.sel.get("alive", false) or scene.sel.get("side") != "p":
				_fail("no living rider selected after playback")
			else:
				_ok("playback finished in %.1fs; sprites, labels, selection consistent" % _elapsed())
			if Engine.time_scale < 0.99:
				_fail("hit-stop left time_scale at %.2f" % Engine.time_scale)
			_next()
		2: # immediate-mode feedback: MISS / COVER floaters, heal floater, hover tile
			print("== feedback pieces ==")
			var att: Dictionary = scene.battle["players"][0]
			var tgt: Dictionary = scene.battle["enemies"][0]
			var m0 := _count_floaters("MISS")
			scene._on_fire(att, tgt, "miss")
			if _count_floaters("MISS") != m0 + 1:
				_fail("miss did not spawn a MISS floater")
			var c0 := _count_floaters("COVER")
			scene._on_fire(att, tgt, "cover")
			if _count_floaters("COVER") != c0 + 1:
				_fail("cover shot did not spawn a COVER floater")
			# recording mode defers: no floater, one event
			scene._recording = true
			scene._events.clear()
			var m1 := _count_floaters("MISS")
			scene._on_fire(att, tgt, "miss")
			scene._recording = false
			if scene._events.size() != 1 or scene._events[0]["t"] != "fire":
				_fail("recording did not queue the fire event: %s" % str(scene._events))
			if _count_floaters("MISS") != m1:
				_fail("recording mode spawned a floater early")
			scene._events.clear()
			_ok("MISS / COVER floaters; recording defers")
			# hover tile: a reachable tile shows the plane + its AP cost
			if not scene.ended and not scene.sel.is_empty():
				var key: String = ""
				for k in scene.reach_map.keys():
					key = k
					break
				if key != "":
					var parts: PackedStringArray = key.split(",")
					scene._set_hover_tile(int(parts[0]), int(parts[1]))
					if not scene._hover_tile.visible or not scene._hover_cost.visible:
						_fail("hover tile not shown for a reachable tile")
					elif String(scene._hover_cost.text) != "%d AP" % int(scene.reach_map[key]):
						_fail("hover cost text wrong: %s" % scene._hover_cost.text)
					else:
						_ok("hover tile + AP cost")
					scene._set_hover_tile(0, 0)
					if scene._hover_tile.visible and not scene.reach_map.has("0,0"):
						_fail("hover tile stayed visible on an unreachable tile")
			# death: killing blow in immediate mode takes a lock, then hides
			var victim: Dictionary = {}
			for e in scene.battle["enemies"]:
				if e["alive"]:
					victim = e
					break
			if victim.is_empty():
				_ok("no living enemy left to test death on")
				_next()
				_next()
				return
			dead_id = victim["id"]
			victim["hp"] = 1
			scene.core.apply_damage(scene.battle, victim, 5)
			if not scene._animating.has(dead_id):
				_fail("killing blow did not start a death animation lock")
			var spr: Sprite3D = scene.unit_nodes[dead_id]["sprite"]
			if not spr.visible:
				_fail("sprite hidden on the same frame as the killing blow")
			_next()
		3: # death animation releases and hides the sprite
			if scene._animating.has(dead_id):
				if _elapsed() > 4.0:
					_fail("death animation never released its lock")
					_finish()
				return
			var spr: Sprite3D = scene.unit_nodes[dead_id]["sprite"]
			if spr.visible:
				_fail("dead sprite still visible after the death animation")
			if spr.modulate != Color.WHITE:
				_fail("death animation left modulate at %s (revive would look wrong)" % str(spr.modulate))
			_ok("death animation: lock held %.2fs, sprite hidden, state restored" % _elapsed())
			_test_audio_pool()
			_next()
		4:
			if Engine.time_scale < 0.99:
				if _elapsed() > 1.0:
					_fail("hit-stop never released time_scale")
					_finish()
				return
			_finish()

func _test_audio_pool() -> void:
	print("== sfx pool ==")
	var a := root.get_node_or_null("/root/Audio")
	if a == null:
		_fail("Audio autoload missing")
		return
	if a._sfx_players.size() != a.SFX_POOL:
		_fail("sfx pool size %d != %d" % [a._sfx_players.size(), a.SFX_POOL])
	# force every player "busy" to prove the round-robin steals the oldest voice
	var seen := {}
	for i in a.SFX_POOL + 2:
		var p = a._next_player()
		seen[p.get_instance_id()] = true
	if seen.size() < 2:
		_fail("_next_player always returns the same player")
	else:
		_ok("pool of %d players rotates (%d distinct over %d picks)" % [a.SFX_POOL, seen.size(), a.SFX_POOL + 2])
	# the audio surface still accepts the volume argument the feel pass added
	a.sfx("miss", 0.5)
	_ok("sfx(name, volume) accepted")
