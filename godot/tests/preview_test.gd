# =============================================================================
# DUSTFALL, ATTACK PREVIEW TEST (headless)
# combat_preview must describe what do_fire / _cast_divine will actually
# resolve. Boots battle.tscn (like anim_test), swaps in a flat synthetic grid
# and drives combat_preview with fixture units:
#   1) divine: aim 999 + ignore cover reads 95, damage is x2.5 (x3.5 empowered)
#   2) blast divine: AoE damage range times the blast count, no hit chance
#   3) ability on a wIC weapon: weapon ignore-cover OR'd in (cover ignored)
#   4) marked target: two-step rounding exactly like do_fire
# Run: godot --headless --path godot --script res://tests/preview_test.gd
# =============================================================================
extends SceneTree

var fails: Array = []
var stage := 0
var stage_start_ms := 0
var battle_scene

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _init() -> void:
	stage = -1 # autoloads mount after _init
	stage_start_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _finish() -> void:
	if fails.is_empty():
		print("PREVIEW TEST: ALL PASS")
		quit(0)
	else:
		print("PREVIEW TEST: %d FAILURES" % fails.size())
		quit(1)

func _tick() -> void:
	match stage:
		-1:
			var gs = root.get_node_or_null("GameState")
			if gs == null:
				_fail("GameState autoload missing under --script")
				_finish()
				return
			gs.new_game()
			battle_scene = preload("res://scenes/battle.tscn").instantiate()
			if not ("sel" in battle_scene):
				_fail("battle.gd failed to attach (parse error)")
				_finish()
				return
			root.add_child(battle_scene)
			stage = 0
		0:
			if float(Time.get_ticks_msec() - stage_start_ms) / 1000.0 < 0.3:
				return
			_run()
			_finish()

func _flat_grid(core) -> Array:
	var g: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0,
				"heavy": false, "rough": false, "deco": null})
		g.append(row)
	return g

func _status() -> Dictionary:
	return {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}

func _attacker(divine, favor: int, wic: bool) -> Dictionary:
	return {"id": "t_att", "side": "p", "alive": true, "q": 0, "r": 0,
		"aim": 60, "rng": 4, "str": 6, "wmin": 3, "wmax": 6, "wIC": wic,
		"jinx": 0, "status": _status(), "divine": divine, "divineFavor": favor}

func _target(armor: int) -> Dictionary:
	return {"id": "t_tgt", "side": "e", "alive": true, "q": 3, "r": 0,
		"armorDef": armor, "status": _status()}

func _run() -> void:
	print("== combat preview vs resolver ==")
	var core = battle_scene.core
	var grid: Array = _flat_grid(core)
	grid[0][3]["cover"] = 0.4 # target stands in heavy cover
	grid[0][3]["cover0"] = 0.4
	battle_scene.grid = grid
	var tgt := _target(0)

	# 1) single-target divine: aim 999 + ignore cover reads the 95 clamp,
	#    damage is x2.5 ((3+2)*2.5=12.5->13, (6+2)*2.5=20), 1 shot
	var att := _attacker("Iron Verdict", 1, false)
	var cover_hit: int = core.hit_chance(grid, att, tgt, false)
	if cover_hit >= 95:
		_fail("fixture broken: cover-respecting hit should be below 95, got %d" % cover_hit)
	var d: Dictionary = battle_scene.combat_preview(att, tgt, "Iron Verdict")
	if int(d["hit"]) != 95:
		_fail("divine preview hit should be 95, got %d" % int(d["hit"]))
	if int(d["lo"]) != 13 or int(d["hi"]) != 20:
		_fail("divine preview dmg should be 13-20 (x2.5), got %d-%d" % [int(d["lo"]), int(d["hi"])])
	if int(d.get("shots", 1)) != 1:
		_fail("divine preview should be a single shot")
	if int(att["aim"]) != 60:
		_fail("divine preview mutated attacker aim")
	# empowered (favor >= 3): x3.5 -> (5*3.5=17.5->18, 8*3.5=28)
	var att_e := _attacker("Iron Verdict", 3, false)
	var de: Dictionary = battle_scene.combat_preview(att_e, tgt, "Iron Verdict")
	if int(de["lo"]) != 18 or int(de["hi"]) != 28:
		_fail("empowered divine dmg should be 18-28 (x3.5), got %d-%d" % [int(de["lo"]), int(de["hi"])])
	var dtxt: String = battle_scene._preview_text(d)
	if not ("95% to hit" in dtxt and "13-20 dmg" in dtxt):
		_fail("divine preview text wrong: %s" % dtxt.replace("\n", " | "))

	# 2) blast divine: 2 blasts of 4-7 (3 when empowered), armor per blast, no hit%
	var attb := _attacker("Perun's Thunder", 1, false)
	var b: Dictionary = battle_scene.combat_preview(attb, tgt, "Perun's Thunder")
	if b.get("kind") != "blast" or b.has("hit"):
		_fail("blast divine preview should be kind blast without a hit chance: %s" % str(b))
	if int(b.get("blasts", 0)) != 2 or int(b["lo"]) != 8 or int(b["hi"]) != 14:
		_fail("blast divine should read x2 8-14, got x%d %d-%d" % [int(b.get("blasts", 0)), int(b["lo"]), int(b["hi"])])
	var attb_e := _attacker("Perun's Thunder", 3, false)
	var be: Dictionary = battle_scene.combat_preview(attb_e, _target(2), "Perun's Thunder")
	if int(be.get("blasts", 0)) != 3 or int(be["lo"]) != 6 or int(be["hi"]) != 15:
		_fail("empowered blast vs armor 2 should read x3 6-15, got x%d %d-%d" % [int(be.get("blasts", 0)), int(be["lo"]), int(be["hi"])])
	var btxt: String = battle_scene._preview_text(b)
	if not ("AoE strike x2" in btxt and "8-14 dmg" in btxt) or "to hit" in btxt:
		_fail("blast divine preview text wrong: %s" % btxt.replace("\n", " | "))

	# 3) ordinary ability on a wIC weapon: cover is ignored like do_fire does
	var att_w := _attacker(null, 0, true)
	var ic_hit: int = core.hit_chance(grid, att_w, tgt, true)
	var a: Dictionary = battle_scene.combat_preview(att_w, tgt, "Aimed Shot")
	if int(a["hit"]) != ic_hit:
		_fail("wIC ability preview should ignore cover (%d), got %d" % [ic_hit, int(a["hit"])])
	if ic_hit == cover_hit:
		_fail("fixture broken: ignore-cover hit equals cover hit (%d)" % ic_hit)
	# and without wIC the same ability still respects cover
	var att_n := _attacker(null, 0, false)
	var n: Dictionary = battle_scene.combat_preview(att_n, tgt, "Aimed Shot")
	if int(n["hit"]) != cover_hit:
		_fail("non-wIC ability preview should respect cover (%d), got %d" % [cover_hit, int(n["hit"])])

	# 4) marked target: do_fire rounds round(base*mult) then round(dmg*1.3).
	#    Gut Shot x1.8, str 6 (+2): lo (3+2)*1.8=9 -> 11.7->12,
	#    hi (6+2)*1.8=14.4->14 -> 18.2->18. Single-step rounding would say
	#    hi 14.4*1.3=18.72->19, so 18 proves the resolver's two-step path.
	var tgt_m := _target(0)
	tgt_m["status"]["marked"] = 2
	var m: Dictionary = battle_scene.combat_preview(att_n, tgt_m, "Gut Shot")
	if int(m["lo"]) != 12 or int(m["hi"]) != 18:
		_fail("marked preview should double-round to 12-18, got %d-%d" % [int(m["lo"]), int(m["hi"])])
	# marked + armor: armor applies after both roundings (18-2=16)
	var tgt_ma := _target(2)
	tgt_ma["status"]["marked"] = 2
	var ma: Dictionary = battle_scene.combat_preview(att_n, tgt_ma, "Gut Shot")
	if int(ma["lo"]) != 10 or int(ma["hi"]) != 16:
		_fail("marked+armor preview should read 10-16, got %d-%d" % [int(ma["lo"]), int(ma["hi"])])

	# 5) basic attack unchanged: hit_chance with the weapon flag, plain 1.0x range
	var p: Dictionary = battle_scene.combat_preview(att_n, tgt, "")
	if int(p["hit"]) != cover_hit or int(p["lo"]) != 5 or int(p["hi"]) != 8:
		_fail("basic preview should read %d%% 5-8, got %d%% %d-%d" % [cover_hit, int(p["hit"]), int(p["lo"]), int(p["hi"])])
	print("divine 95/x2.5/x3.5, blast x2/x3 ranges, wIC ignore-cover, marked double-rounding")
