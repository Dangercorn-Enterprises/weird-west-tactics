# =============================================================================
# DUSTFALL — Session #2 combat rules test (fuse charges, Deacon kit, rough
# terrain, end-turn hunker, re-routed level-ups). Deterministic, pure core —
# NEVER touches user://save.json (no new_game/save_game/apply_battle_result).
# Run:  godot --headless --path godot --script res://tests/combat_rules_test.gd
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

var passed := 0
var failed := 0

func ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)

func _mk_battle(core: CombatCore, players: Array, enemies: Array) -> Dictionary:
	return {"grid": core.build_grid(), "players": players, "enemies": enemies,
		"units": players + enemies, "kills": 0, "playerDeaths": 0, "charges": []}

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing — run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	core.seed_rng(42)

	# ---- fuse-delay charges (2c) ------------------------------------------------
	var pl: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	pl["q"] = 4; pl["r"] = 2
	var b := _mk_battle(core, [pl], [])
	core.plant_charge(b, "e", {"q": 4, "r": 2})
	ok("plant: one lit charge, fuse 1",
		b["charges"].size() == 1 and int(b["charges"][0]["fuse"]) == 1)
	core.tick_charges(b, "p")
	ok("player-phase tick leaves an enemy stick lit", b["charges"].size() == 1)
	var hp0: int = pl["hp"]
	var heavy0: float = b["grid"][2][5]["cover"]  # heavy at (5,2), in radius
	core.tick_charges(b, "e")
	ok("thrower-phase tick detonates (charge gone)", b["charges"].is_empty())
	ok("blast hurt the unit on the tile (4-7)",
		hp0 - int(pl["hp"]) >= 4 and hp0 - int(pl["hp"]) <= 7)
	ok("blast cleared light cover at (4,1)",
		float(b["grid"][1][4]["cover"]) == 0.0 and int(b["grid"][1][4]["chp"]) == 0)
	ok("blast cracked heavy cover at (5,2) one tier",
		absf(float(b["grid"][2][5]["cover"]) - (heavy0 - 0.2)) < 0.0001)

	# charge danger pricing (bot panic instinct)
	var b2 := _mk_battle(core, [], [])
	core.plant_charge(b2, "e", {"q": 5, "r": 5})
	ok("danger 5.5 on the charge tile", absf(core._charge_danger(b2, 5, 5) - 5.5) < 0.0001)
	ok("danger 5.5 one tile diagonal", absf(core._charge_danger(b2, 6, 6) - 5.5) < 0.0001)
	ok("no danger two tiles out", core._charge_danger(b2, 7, 5) == 0.0)

	# ---- Deacon kit (2h): free raise every other activation, cap 2 ---------------
	var deacon_spec := {}
	for e in core.design["enemies"]:
		if e.get("id", "") == "the_deacon":
			deacon_spec = e
			break
	var deacon := core.enemy_to_unit(deacon_spec, 0)
	deacon["q"] = 8; deacon["r"] = 1
	var far: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	far["q"] = 0; far["r"] = 9
	far["hp"] = 999; far["maxHp"] = 999
	var bd := _mk_battle(core, [far], [deacon])
	ok("the_deacon maps boss-summon -> summoner", deacon.get("summoner", false) == true)
	core.enemy_phase(bd)
	ok("activation 1 raises one Risen Dead",
		bd["enemies"].size() == 2 and bd["enemies"][1].get("raisedBy", "") == deacon["id"])
	core.enemy_phase(bd)
	ok("activation 2 (off-beat) raises none", bd["enemies"].size() == 2)
	core.enemy_phase(bd)
	ok("activation 3 raises the second", bd["enemies"].size() == 3)
	core.enemy_phase(bd)
	core.enemy_phase(bd)
	ok("cap: never more than 2 kit adds alive", bd["enemies"].size() == 3)
	for x in bd["enemies"]:
		if x.get("raisedBy", "") != "":
			x["alive"] = false
	deacon["enraged"] = true
	core.enemy_phase(bd)
	core.enemy_phase(bd)
	var raised_alive := 0
	for x in bd["enemies"]:
		if x.get("raisedBy", "") != "" and x["alive"]:
			raised_alive += 1
	ok("enraged Deacon stops kit raises", raised_alive == 0)

	# ---- rough terrain (2e): soft tiles cost double to enter ---------------------
	var walker := {"q": 2, "r": 5, "ap": 4, "alive": true, "side": "p",
		"status": {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}}
	var grid := core.build_grid()
	var rc: Dictionary = core.reach(grid, [walker], walker)
	ok("entering brush (3,5) costs 2 MP", int(rc.get("3,5", -1)) == 2)
	ok("plain neighbor (2,4) costs 1 MP", int(rc.get("2,4", -1)) == 1)
	ok("rough flag persists on the soft tile", bool(grid[5][3].get("rough", false)))

	# ---- hunker ends turn (2b): bot banks leftover AP as a brace ------------------
	var brawler: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	brawler["q"] = 1; brawler["r"] = 1
	brawler["ap"] = 3; brawler["maxAp"] = 3
	brawler["abilities"] = []          # basic attacks only -> 2 AP spent, 1 left
	brawler["divineFavor"] = 0         # keep the once-per-fight ult out of it
	var tank := core.enemy_to_unit(core.design["enemies"][0], 0)
	tank["q"] = 1; tank["r"] = 2
	tank["hp"] = 999; tank["maxHp"] = 999
	var bh := _mk_battle(core, [brawler], [tank])
	core.player_phase(bh)
	ok("leftover AP became a brace (hunker 2)", int(brawler["status"]["hunker"]) == 2)
	ok("brace ended the turn (AP 0)", int(brawler["ap"]) == 0)

	# ---- FAVORED re-route (2f): every level-up grows LIVE stats only --------------
	var gss: GDScript = load("res://scripts/game_state.gd")
	var gsi: Node = gss.new()  # NOT in tree: _ready never runs, nothing saves
	var live: Array = gss.get_script_constant_map()["LIVE_STATS"]
	for aid in ["hexslinger", "tinkerer", "preacher", "lawdog", "drifter", "gunslinger"]:
		var pre: Dictionary = core.design["pregen"][aid]["stats"]
		var member := {"name": aid, "archetype": aid, "level": 1, "xp": 0,
			"stats": pre.duplicate(true)}
		seed(1337)
		gsi.gain_xp(member, 100)  # exactly one level
		var live_gain := 0
		var dead_gain := 0
		for s in member["stats"].keys():
			var d: int = int(member["stats"][s]) - int(pre.get(s, 0))
			if s in live:
				live_gain += d
			else:
				dead_gain += d
		ok("%s level-up grows +2 live, +0 dormant" % aid,
			int(member["level"]) == 2 and live_gain == 2 and dead_gain == 0)
	gsi.free()

	print("combat_rules_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
