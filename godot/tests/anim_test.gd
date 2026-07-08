# =============================================================================
# DUSTFALL — ANIMATION LAYER TEST (headless)
# 1) path_from_reach: BFS cost-map path reconstruction (hand maps + every
#    reachable tile of a real CombatCore.reach() map must yield a contiguous
#    in-reach path ending on the destination).
# 2) Live scene: boot battle.tscn with a manually-mounted GameState (autoloads
#    are absent under --script), drive _do_move and _animate_lunge, pump real
#    frames — sprites must land exactly on their logic tiles and every
#    animation lock must clear. Catches tween/bookkeeping regressions that a
#    pure unit test can't.
# Run: godot --headless --path godot --script res://tests/anim_test.gd
# =============================================================================
extends SceneTree

const BattleScript = preload("res://scenes/battle.gd")
const CombatCoreScript = preload("res://scripts/combat_core.gd")

var fails: Array = []
var battle_scene
var stage := 0
var stage_start_ms := 0
var move_dest := []
var lunge_origin := Vector3.ZERO

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _adjacent(a: Array, b: Array) -> bool:
	return absi(int(a[0]) - int(b[0])) + absi(int(a[1]) - int(b[1])) == 1

# ---- part 1: pure path reconstruction --------------------------------------
func _test_paths() -> void:
	print("== path_from_reach ==")
	var straight := {"0,0": 0, "1,0": 1, "2,0": 2, "3,0": 3}
	if BattleScript.path_from_reach(straight, 0, 0, 3, 0) != [[1, 0], [2, 0], [3, 0]]:
		_fail("straight-line path wrong")
	var climb := {"0,0": 0, "1,0": 2, "2,0": 3} # climb step costs 2
	if BattleScript.path_from_reach(climb, 0, 0, 2, 0) != [[1, 0], [2, 0]]:
		_fail("climb-cost path wrong")
	if BattleScript.path_from_reach(straight, 0, 0, 0, 0) != []:
		_fail("dest==start should be empty")
	if BattleScript.path_from_reach(straight, 0, 0, 9, 9) != []:
		_fail("unreachable dest should be empty")

	# real BFS map: heights, a blocker unit, every reachable tile reconstructs
	var core = CombatCoreScript.new()
	var grid: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0})
		grid.append(row)
	grid[4][6]["h"] = 1  # climb tile
	grid[3][5]["h"] = 2  # wall — impassable
	var u := {"q": 4, "r": 4, "ap": 5, "alive": true}
	var blocker := {"q": 5, "r": 4, "ap": 0, "alive": true}
	var reach: Dictionary = core.reach(grid, [u, blocker], u)
	if reach.size() < 10:
		_fail("real reach map suspiciously small: %d" % reach.size())
	var checked := 0
	for key in reach.keys():
		var parts: PackedStringArray = key.split(",")
		var tq := int(parts[0])
		var tr := int(parts[1])
		if tq == 4 and tr == 4:
			continue
		var path: Array = BattleScript.path_from_reach(reach, 4, 4, tq, tr)
		checked += 1
		if path.is_empty():
			_fail("no path to reachable %s" % key)
			continue
		if path[-1][0] != tq or path[-1][1] != tr:
			_fail("path to %s ends at %s" % [key, str(path[-1])])
		if not _adjacent([4, 4], path[0]):
			_fail("path to %s does not start adjacent to unit" % key)
		if path.size() > int(reach[key]):
			_fail("path to %s longer than its cost" % key)
		for i in path.size():
			if not reach.has("%d,%d" % [path[i][0], path[i][1]]):
				_fail("path to %s leaves the reach map" % key)
			if i > 0 and not _adjacent(path[i - 1], path[i]):
				_fail("path to %s is not contiguous" % key)
	print("reconstructed %d real paths" % checked)

# ---- part 2: live scene ------------------------------------------------------
func _init() -> void:
	_test_paths()
	stage = -1 # autoloads mount after _init — set the scene up on frame 1
	stage_start_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _setup_scene() -> void:
	print("== live battle scene ==")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_fail("GameState autoload missing under --script")
		_finish()
		return
	gs.new_game()
	battle_scene = preload("res://scenes/battle.tscn").instantiate()
	# fail fast if battle.gd didn't compile (bare Node3D has no `sel`) rather
	# than spinning the frame loop forever on a parse error
	if not ("sel" in battle_scene):
		_fail("battle.gd failed to attach — parse error (scene is bare %s)" % battle_scene.get_class())
		_finish()
		return
	root.add_child(battle_scene)

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - stage_start_ms) / 1000.0

func _next_stage() -> void:
	stage += 1
	stage_start_ms = Time.get_ticks_msec()

func _finish() -> void:
	if fails.is_empty():
		print("ANIM TEST: ALL PASS")
		quit(0)
	else:
		print("ANIM TEST: %d FAILURES" % fails.size())
		quit(1)

func _tick() -> void:
	match stage:
		-1:
			_setup_scene()
			_next_stage()
		0: # settle one beat, then start a multi-tile move
			if _elapsed() < 0.3:
				return
			var sel: Dictionary = battle_scene.sel
			if sel.is_empty():
				_fail("no unit selected after boot")
				_finish()
				return
			for key in battle_scene.reach_map.keys():
				if int(battle_scene.reach_map[key]) >= 2:
					var parts: PackedStringArray = (key as String).split(",")
					move_dest = [int(parts[0]), int(parts[1])]
					break
			if move_dest.is_empty():
				_fail("no multi-tile destination in reach")
				_finish()
				return
			battle_scene._do_move(move_dest[0], move_dest[1])
			if not battle_scene._animating.has(sel["id"]):
				_fail("move did not take an animation lock")
			_next_stage()
		1: # wait for the walk to finish, then check landing
			if not battle_scene._animating.is_empty():
				if _elapsed() > 4.0:
					_fail("move animation never released its lock")
					_finish()
				return
			var sel: Dictionary = battle_scene.sel
			if int(sel["q"]) != move_dest[0] or int(sel["r"]) != move_dest[1]:
				_fail("logic position not at destination")
			var spr: Sprite3D = battle_scene.unit_nodes[sel["id"]]["sprite"]
			var want := Vector3(battle_scene._tx(move_dest[0]), 0.0, battle_scene._tz(move_dest[1]))
			if absf(spr.position.x - want.x) > 0.05 or absf(spr.position.z - want.z) > 0.05:
				_fail("sprite did not land on destination tile: %s vs %s" % [spr.position, want])
			_next_stage()
		2: # attack lunge must return to origin and release its lock
			var sel: Dictionary = battle_scene.sel
			var spr: Sprite3D = battle_scene.unit_nodes[sel["id"]]["sprite"]
			lunge_origin = spr.position
			lunge_origin.y = float(battle_scene.unit_nodes[sel["id"]]["base_y"])
			battle_scene._animate_lunge(sel, battle_scene.battle["enemies"][0])
			if not battle_scene._animating.has(sel["id"]):
				_fail("lunge did not take an animation lock")
			_next_stage()
		3:
			if not battle_scene._animating.is_empty():
				if _elapsed() > 3.0:
					_fail("lunge never released its lock")
					_finish()
				return
			var sel: Dictionary = battle_scene.sel
			var spr: Sprite3D = battle_scene.unit_nodes[sel["id"]]["sprite"]
			if spr.position.distance_to(lunge_origin) > 0.06:
				_fail("lunge did not return to origin: %s vs %s" % [spr.position, lunge_origin])
			_next_stage()
		4: # enemy phase: slides must all resolve and every sprite match logic
			battle_scene._end_turn()
			_next_stage()
		5:
			if not battle_scene._animating.is_empty():
				if _elapsed() > 5.0:
					_fail("enemy slide locks never cleared: %s" % str(battle_scene._animating))
					_finish()
				return
			for u in battle_scene.battle["units"]:
				if not u["alive"] or not battle_scene.unit_nodes.has(u["id"]):
					continue
				var spr: Sprite3D = battle_scene.unit_nodes[u["id"]]["sprite"]
				var wx: float = battle_scene._tx(int(u["q"]))
				var wz: float = battle_scene._tz(int(u["r"]))
				if absf(spr.position.x - wx) > 0.05 or absf(spr.position.z - wz) > 0.05:
					_fail("unit %s sprite off its tile after enemy phase" % str(u["id"]))
			_test_preview()
			_test_crit()
			_test_status()
			_finish()

# status readout: active statuses render codes above the unit, marked sets
# the amber priority colour, no statuses => hidden
func _test_status() -> void:
	print("== status readout ==")
	var u: Dictionary = battle_scene.battle["players"][0]
	# clean slate
	u["status"] = {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}
	var d0: Dictionary = battle_scene._status_display(u)
	if d0["text"] != "":
		_fail("no-status unit should show empty readout, got %s" % d0["text"])
	# marked + burn: marked (higher priority) sets the colour, both codes shown
	u["status"]["marked"] = 2
	u["status"]["burn"] = 1
	var d1: Dictionary = battle_scene._status_display(u)
	if not ("MRK2" in d1["text"] and "BRN1" in d1["text"]):
		_fail("status codes missing: %s" % d1["text"])
	if d1["color"] != Color("#ffcf3f"):
		_fail("marked should drive the amber priority colour, got %s" % str(d1["color"]))
	# the live label reflects it after a sync
	battle_scene._sync_units()
	var slbl: Label3D = battle_scene.unit_nodes[u["id"]]["status"]
	if not slbl.visible or "MRK2" not in String(slbl.text):
		_fail("status label not rendered after sync: vis=%s text=%s" % [slbl.visible, slbl.text])
	# clearing hides it
	u["status"]["marked"] = 0
	u["status"]["burn"] = 0
	battle_scene._sync_units()
	if slbl.visible:
		_fail("status label should hide when no statuses active")
	print("status readout renders codes + priority colour, hides when clear")

# crit must propagate core -> apply_damage -> on_damage(crit) -> CRIT floater
func _test_crit() -> void:
	print("== crit feedback ==")
	var core = battle_scene.core
	# 1. propagation: apply_damage forwards the crit flag to the on_damage hook
	var got := {"crit": null, "dmg": 0}
	core.on_damage = func(u, dmg, crit):
		got["crit"] = crit
		got["dmg"] = dmg
	var tgt: Dictionary = battle_scene.battle["enemies"][0]
	core.apply_damage(battle_scene.battle, tgt, 7, true)
	if got["crit"] != true or got["dmg"] != 7:
		_fail("apply_damage did not forward crit flag: %s" % str(got))
	# restore the real UI hook
	core.on_damage = battle_scene._on_unit_damaged

	# 2. visual: a crit spawns an amber "CRIT -N" Label3D floater
	var before := _count_crit_floaters()
	battle_scene._on_unit_damaged(tgt, 9, true)
	var after := _count_crit_floaters()
	if after <= before:
		_fail("crit did not spawn a CRIT floater (%d -> %d)" % [before, after])
	# 3. a normal hit must NOT read as a crit
	var n0 := _count_crit_floaters()
	battle_scene._on_unit_damaged(tgt, 4, false)
	if _count_crit_floaters() != n0:
		_fail("normal hit spawned a CRIT floater")
	print("crit propagates core -> UI, floater rendered")

func _count_crit_floaters() -> int:
	var n := 0
	for c in battle_scene.get_children():
		if c is Label3D and "CRIT" in String(c.text):
			n += 1
	return n

# combat_preview must equal the parity-tested CombatCore math exactly
func _test_preview() -> void:
	print("== combat preview ==")
	var core = battle_scene.core
	var grid: Array = battle_scene.grid
	var players: Array = battle_scene.battle["players"]
	var enemies: Array = battle_scene.battle["enemies"]
	if players.is_empty() or enemies.is_empty():
		_fail("no units to preview")
		return
	var att: Dictionary = players[0]
	var tgt: Dictionary = enemies[0]

	# basic attack: hit% must match hit_chance(); dmg range must match the formula
	var p: Dictionary = battle_scene.combat_preview(att, tgt, "")
	var expect_hit: int = core.hit_chance(grid, att, tgt, bool(att.get("wIC", false)))
	if int(p["hit"]) != expect_hit:
		_fail("preview hit %d != hit_chance %d" % [int(p["hit"]), expect_hit])
	var base: int = int(att["str"]) / 3
	var mf := 1.3 if int(tgt.get("status", {}).get("marked", 0)) > 0 else 1.0
	var armor: int = int(tgt.get("armorDef", 0))
	var elo: int = maxi(1, int(round(float(int(att["wmin"]) + base) * mf)) - armor) if armor > 0 else int(round(float(int(att["wmin"]) + base) * mf))
	var ehi: int = maxi(1, int(round(float(int(att["wmax"]) + base) * mf)) - armor) if armor > 0 else int(round(float(int(att["wmax"]) + base) * mf))
	if int(p["lo"]) != elo or int(p["hi"]) != ehi:
		_fail("preview dmg %d-%d != expected %d-%d" % [int(p["lo"]), int(p["hi"]), elo, ehi])

	# ability preview: guaranteed hit reads 95, multiplier scales damage up
	var g: Dictionary = battle_scene.combat_preview(att, tgt, "Called Shot")
	if int(g["hit"]) != 95:
		_fail("Called Shot preview should be 95%% (guaranteed), got %d" % int(g["hit"]))
	var aimed: Dictionary = battle_scene.combat_preview(att, tgt, "Aimed Shot") # mult 1.5
	if int(aimed["hi"]) <= int(p["hi"]):
		_fail("Aimed Shot (x1.5) should exceed basic damage: %d vs %d" % [int(aimed["hi"]), int(p["hi"])])

	# purity: previewing must not mutate the attacker's aim (Fan the Hammer aimMod -10)
	var aim0: int = int(att["aim"])
	battle_scene.combat_preview(att, tgt, "Fan the Hammer")
	if int(att["aim"]) != aim0:
		_fail("preview mutated attacker aim: %d -> %d" % [aim0, int(att["aim"])])

	# HUD wiring: panel + label live under the THEMED hud Control (which is
	# under the CanvasLayer), and the panel renders real text.
	if battle_scene.preview_panel == null or battle_scene.preview_label == null:
		_fail("preview HUD nodes not built")
	else:
		var parent: Node = battle_scene.preview_panel.get_parent()
		if not (parent is Control) or (parent as Control).theme == null:
			_fail("preview panel not under a themed HUD Control")
		elif not (parent.get_parent() is CanvasLayer):
			_fail("themed HUD Control not under the CanvasLayer")
		else:
			var txt: String = battle_scene._preview_text(p)
			if not ("% to hit" in txt and "dmg" in txt):
				_fail("preview text missing hit/dmg lines: %s" % txt)
	print("preview matches CombatCore, no state mutation, HUD themed + wired")
