# =============================================================================
# DUSTFALL — MELEE SNAP TEST (Session #3, 2026-10-08)
# Tim's overwatch pick: "free melee hit adjacent unless they have some sort of
# gunslinger / John Wick type perk".
#   - ending a move adjacent to an enemy eats one punch per adjacent enemy
#   - punch = 1 + str/3, armor-soaked, deterministic (no RNG draw)
#   - cqc perk (gunslinger archetype) is immune
#   - each reactor punches once per phase; begin_phase resets the other side
#   - stunned reactors do not react
#   - the bots price the punch (melee_tax) and avoid needless adjacency
#   - the enemy AI stops acting once a punch kills the mover
# Run: godot --headless --path godot --script res://tests/melee_snap_test.gd
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

var fails := 0
var passes := 0

func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("  PASS  " + name)
	else:
		fails += 1
		print("  FAIL  " + name + ("  (" + detail + ")" if detail != "" else ""))

func _u(id: String, side: String, q: int, r: int, extra := {}) -> Dictionary:
	var u := {"id": id, "name": id, "side": side, "q": q, "r": r, "alive": true, "hp": 20, "maxHp": 20,
		"aim": 70, "rng": 5, "str": 6, "quick": 4, "wmin": 4, "wmax": 8, "ap": 3, "maxAp": 3,
		"armorDef": 0, "status": {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}}
	u.merge(extra, true)
	return u

func _battle(core, units: Array) -> Dictionary:
	var grid: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0, "heavy": false, "rough": false})
		grid.append(row)
	var players: Array = units.filter(func(x): return x["side"] == "p")
	var enemies: Array = units.filter(func(x): return x["side"] == "e")
	return {"grid": grid, "players": players, "enemies": enemies, "units": units,
		"kills": 0, "xpKills": 0, "playerDeaths": 0, "charges": [], "favorPool": {}}

func _init() -> void:
	var core = CombatCoreScript.new()
	core.seed_rng(1)

	print("== punch mechanics ==")
	var p := _u("p0", "p", 4, 4)
	var e1 := _u("e1", "e", 5, 4, {"str": 6})   # 1 + 2 = 3 dmg
	var e2 := _u("e2", "e", 4, 5, {"str": 9})   # 1 + 3 = 4 dmg
	var far := _u("e3", "e", 8, 8)
	var b := _battle(core, [p, e1, e2, far])
	_check("melee_dmg = 1 + str/3", core.melee_dmg(e1, p) == 3 and core.melee_dmg(e2, p) == 4)
	var armored := _u("pa", "p", 0, 0, {"armorDef": 2})
	_check("armor soaks the punch (min 1)", core.melee_dmg(e1, armored) == 1 and core.melee_dmg(_u("w", "e", 0, 0, {"str": 1}), armored) == 1)
	var rng_before: int = core._rng_state
	var landed: int = core.resolve_melee_snap(b, p)
	_check("two adjacent enemies punch once each", landed == 2 and int(p["hp"]) == 13, "landed %d hp %d" % [landed, int(p["hp"])])
	_check("no RNG draw for punches", core._rng_state == rng_before)
	_check("reactors are spent for the phase", e1.get("snapped", false) and e2.get("snapped", false) and not far.get("snapped", false))
	_check("a second move this phase is free", core.resolve_melee_snap(b, p) == 0)
	core.begin_phase(b, "p")  # player phase begins -> enemies (the reactors) reset
	_check("begin_phase('p') resets enemy reactors", not e1.get("snapped", false))
	_check("...and punches land again", core.resolve_melee_snap(b, p) == 2)
	core.begin_phase(b, "p")
	e1["status"]["stun"] = 1
	_check("a stunned reactor does not punch", core.resolve_melee_snap(b, p) == 1)
	e1["status"]["stun"] = 0
	core.begin_phase(b, "p")
	var wick := _u("gs", "p", 4, 4, {"cqc": true})
	b["units"].append(wick); b["players"].append(wick)
	_check("cqc mover is immune", core.resolve_melee_snap(b, wick) == 0 and int(wick["hp"]) == 20)
	_check("melee_tax prices the punch for a plain mover", core.melee_tax(b, p, 4, 4) == 7)
	_check("melee_tax is 0 for a cqc mover", core.melee_tax(b, wick, 4, 4) == 0)
	_check("melee_tax is 0 away from enemies", core.melee_tax(b, p, 0, 0) == 0)

	print("== party_to_unit carries the perk from design ==")
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		# autoloads mount after _init under --script; load design directly
		var f := FileAccess.open("res://data/design.json", FileAccess.READ)
		core.design = JSON.parse_string(f.get_as_text())
	else:
		core.design = gs.design
	var gun: Dictionary = core.party_to_unit({"uid": "g", "archetype": "gunslinger", "stats": {}}, 0)
	var hex: Dictionary = core.party_to_unit({"uid": "h", "archetype": "hexslinger", "stats": {}}, 1)
	_check("gunslinger has cqc", gun.get("cqc", false) == true)
	_check("hexslinger does not", hex.get("cqc", false) == false)
	var dead: Dictionary = core.enemy_to_unit(core._find(core.design["enemies"], "walkin_dead"), 0)
	_check("enemies default to no cqc", dead.get("cqc", false) == false)

	print("== bots price the punch ==")
	# enemy approaching a rider: with 3 AP it could end adjacent (dist 1) or 2 away.
	# Target in range from 2 tiles (rng 5), so the punch tax should keep it at dist 2.
	var rider := _u("r", "p", 5, 5, {"str": 9})  # punch 4
	var walker := _u("w", "e", 1, 5, {"ap": 4, "maxAp": 4, "rng": 5})
	var b2 := _battle(core, [rider, walker])
	core.move_unit_toward(b2, walker, rider)
	_check("enemy stops short of adjacency when it can shoot anyway (dist %d)" % core.dist(walker, rider), core.dist(walker, rider) >= 2)
	_check("...and took no punch", int(walker["hp"]) == 20)
	# a melee-range swarmer must still close: rng 1 lets it attack from dist 2, so it stops at 2 as well
	var beast := _u("bst", "e", 1, 5, {"ap": 4, "maxAp": 4, "rng": 1, "swarmer": true})
	var b3 := _battle(core, [_u("r2", "p", 5, 5, {"str": 9}), beast])
	core.move_unit_toward(b3, beast, b3["players"][0])
	_check("swarmer closes to attack distance without eating the punch (dist %d)" % core.dist(beast, b3["players"][0]), core.dist(beast, b3["players"][0]) == 2)

	print("== a punch can kill, and a dead mover acts no further ==")
	# (a) the punch itself is lethal and counts as a kill
	var frail := _u("fr", "e", 3, 4, {"hp": 2, "maxHp": 2})
	var brawler := _u("br", "p", 4, 4, {"str": 9})  # punch 4 >= 2 hp
	var b4 := _battle(core, [brawler, frail])
	core.resolve_melee_snap(b4, frail)
	_check("frail enemy died to the punch", not frail["alive"])
	_check("the kill counts", int(b4["kills"]) == 1)
	# (b) a rational mover never ends adjacent when it can avoid it: with rng 0 it
	# would rather stand 2 tiles out than eat a punch it can't survive
	var cautious := _u("ca", "e", 1, 4, {"hp": 2, "maxHp": 2, "ap": 3, "maxAp": 3, "rng": 0})
	var b5 := _battle(core, [_u("br2", "p", 4, 4, {"str": 9}), cautious])
	core.enemy_phase(b5)
	_check("a doomed approach is refused (stops at dist %d)" % core.dist(cautious, b5["players"][0]), cautious["alive"] and core.dist(cautious, b5["players"][0]) >= 2)
	# (c) the activation guard: a mover that dies ON the move (bleed-out) fires no shot
	var bleeder := _u("bl", "e", 1, 4, {"hp": 2, "maxHp": 2, "ap": 3, "maxAp": 3, "rng": 1, "quick": 9})
	bleeder["status"]["bleed"] = 1
	var b6 := _battle(core, [_u("br3", "p", 4, 4, {"str": 1}), bleeder])
	var shots := {"n": 0}
	core.on_fire = func(att, _def, res): if res != "melee" and att["id"] == "bl": shots["n"] += 1
	core.enemy_phase(b6)
	core.on_fire = Callable()
	_check("bleeder died on the move", not bleeder["alive"])
	_check("...and fired no shot after dying", shots["n"] == 0, "%d shots" % shots["n"])

	print("")
	print("melee_snap_test: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
