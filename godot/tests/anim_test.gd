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
			_finish()
