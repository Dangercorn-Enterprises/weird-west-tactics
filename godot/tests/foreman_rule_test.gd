# =============================================================================
# DUSTFALL — IRON FOREMAN "CONDUCTING COVER" TEST (Session #3, 2026-10-08)
# Tim's pick (Astra B2 contract): when the Foreman's shot is absorbed by terrain
# cover, that tile heats — a fuse-delay charge owned by the Foreman that blows
# at the start of the next enemy phase. Contract checks:
#   forced hit / miss never arm; a cover strike arms exactly one charge with
#   owner + source; hunker-only cover does not arm; point-blank (no cover) does
#   not arm; no stacking on a marked tile; maxPending cap; preEnrageOnly;
#   heavyOnly variant; ordinary bomber sticks carry no owner; the player
#   phase in between leaves it lit; it detonates on the enemy tick; the hook
#   draws no RNG; units without a bossRule never arm anything.
# Run: godot --headless --path godot --script res://tests/foreman_rule_test.gd
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
	var u := {"id": id, "name": id, "side": side, "q": q, "r": r, "alive": true, "hp": 40, "maxHp": 40,
		"aim": 70, "rng": 6, "str": 8, "quick": 1, "wmin": 6, "wmax": 10, "ap": 3, "maxAp": 3,
		"armorDef": 0, "status": {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}}
	u.merge(extra, true)
	return u

func _grid(core) -> Array:
	var grid: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0, "heavy": false, "rough": false})
		grid.append(row)
	return grid

func _rock(grid: Array, q: int, r: int) -> void:
	grid[r][q]["cover"] = 0.4; grid[r][q]["cover0"] = 0.4; grid[r][q]["chp"] = -1; grid[r][q]["heavy"] = true

func _wagon(grid: Array, q: int, r: int, core) -> void:
	grid[r][q]["cover"] = 0.2; grid[r][q]["cover0"] = 0.2; grid[r][q]["chp"] = core.LIGHT_COVER_HP; grid[r][q]["heavy"] = false

func _foreman(q: int, r: int, rule := {"id": "conducting_cover", "maxPending": 1, "preEnrageOnly": true, "heavyOnly": false}) -> Dictionary:
	return _u("boss", "e", q, r, {"boss": true, "bossRule": rule.duplicate(true)})

func _battle(core, grid: Array, units: Array) -> Dictionary:
	return {"grid": grid, "players": units.filter(func(x): return x["side"] == "p"),
		"enemies": units.filter(func(x): return x["side"] == "e"), "units": units,
		"kills": 0, "xpKills": 0, "playerDeaths": 0, "charges": [], "favorPool": {}}

func _init() -> void:
	var core = CombatCoreScript.new()
	core.seed_rng(7)

	print("== the hook itself ==")
	var grid := _grid(core)
	_rock(grid, 6, 4)
	var fm := _foreman(2, 4)
	var rider := _u("r", "p", 6, 4)
	var b := _battle(core, grid, [rider, fm])
	var rng0: int = core._rng_state
	core.boss_on_cover_strike(b, fm, rider)
	_check("cover strike arms one charge", b["charges"].size() == 1)
	_check("hook draws no RNG", core._rng_state == rng0)
	if b["charges"].size() == 1:
		var c: Dictionary = b["charges"][0]
		_check("charge sits on the target tile, enemy side, fuse 1", int(c["q"]) == 6 and int(c["r"]) == 4 and c["side"] == "e" and int(c["fuse"]) == 1)
		_check("charge carries owner + source", str(c.get("owner", "")) == "boss" and str(c.get("source", "")) == "foreman_heat")
	core.boss_on_cover_strike(b, fm, rider)
	_check("no stacking on an already marked tile", b["charges"].size() == 1)
	# second rider on another rock: maxPending 1 blocks a second heat
	_rock(grid, 6, 7)
	var rider2 := _u("r2", "p", 6, 7)
	b["players"].append(rider2); b["units"].append(rider2)
	core.boss_on_cover_strike(b, fm, rider2)
	_check("maxPending caps at one pending heat per Foreman", b["charges"].size() == 1)
	b["charges"].clear()
	# hunker-only cover on bare ground does not arm
	var bare := _u("b", "p", 7, 2)
	bare["status"]["hunker"] = 2
	core.boss_on_cover_strike(b, fm, bare)
	_check("hunker on bare terrain does not arm", b["charges"].is_empty())
	# point-blank: adjacency negates the rock, so no terrain cover contributes
	var fm_adj := _foreman(5, 4)
	core.boss_on_cover_strike(b, fm_adj, rider)
	_check("point-blank (cover negated) does not arm", b["charges"].is_empty())
	# enraged Foreman with preEnrageOnly stops arming
	fm["enraged"] = true
	core.boss_on_cover_strike(b, fm, rider)
	_check("preEnrageOnly: enraged Foreman arms nothing", b["charges"].is_empty())
	fm["enraged"] = false
	var fm_all := _foreman(2, 4, {"id": "conducting_cover", "maxPending": 1, "preEnrageOnly": false})
	fm_all["enraged"] = true
	core.boss_on_cover_strike(b, fm_all, rider)
	_check("preEnrageOnly=false arms while enraged", b["charges"].size() == 1)
	b["charges"].clear()
	# heavyOnly: a wagon does not arm, a rock does
	var fm_heavy := _foreman(2, 1, {"id": "conducting_cover", "maxPending": 1, "preEnrageOnly": true, "heavyOnly": true})
	_wagon(grid, 6, 1, core)
	var on_wagon := _u("w", "p", 6, 1)
	core.boss_on_cover_strike(b, fm_heavy, on_wagon)
	_check("heavyOnly ignores light cover", b["charges"].is_empty())
	core.boss_on_cover_strike(b, fm_heavy, rider)
	_check("heavyOnly arms on a rock", b["charges"].size() == 1)
	b["charges"].clear()
	# a unit without a rule never arms
	var plain := _u("e9", "e", 2, 4)
	core.boss_on_cover_strike(b, plain, rider)
	_check("no bossRule -> never arms", b["charges"].is_empty())

	print("== through do_fire: only the cover band arms ==")
	# force each band by seeding: scan seeds until we see each outcome once
	var seen := {"hit": 0, "cover": 0, "miss": 0}
	var armed_on := {"hit": 0, "cover": 0, "miss": 0}
	for s in 400:
		var g := _grid(core)
		_rock(g, 6, 4)
		var f2 := _foreman(2, 4)
		var t2 := _u("t", "p", 6, 4)
		var b2 := _battle(core, g, [t2, f2])
		var res := {"r": ""}
		core.on_fire = func(_a, _d, result): res["r"] = result
		core.seed_rng(1000 + s)
		core.do_fire(b2, f2, t2)
		if res["r"] == "":
			continue
		seen[res["r"]] += 1
		if b2["charges"].size() > 0:
			armed_on[res["r"]] += 1
	core.on_fire = Callable()
	_check("saw all three bands (%s)" % str(seen), seen["hit"] > 0 and seen["cover"] > 0 and seen["miss"] > 0)
	_check("every cover strike armed heat", armed_on["cover"] == seen["cover"])
	_check("hits never arm", armed_on["hit"] == 0)
	_check("misses never arm", armed_on["miss"] == 0)

	print("== lifecycle: lit through the player phase, blows on the enemy tick ==")
	var g3 := _grid(core)
	_rock(g3, 6, 4)
	var f3 := _foreman(2, 4)
	var t3 := _u("t3", "p", 6, 4)
	var b3 := _battle(core, g3, [t3, f3])
	core.boss_on_cover_strike(b3, f3, t3)
	core.tick_charges(b3, "p")
	_check("player-phase tick leaves the heat lit", b3["charges"].size() == 1 and int(b3["charges"][0]["fuse"]) == 1)
	var hp0: int = int(t3["hp"])
	core.tick_charges(b3, "e")
	_check("enemy tick detonates (charge gone)", b3["charges"].is_empty())
	_check("rider standing in the heat took blast damage (4-7)", hp0 - int(t3["hp"]) >= 4 and hp0 - int(t3["hp"]) <= 7, "took %d" % (hp0 - int(t3["hp"])))
	_check("blast cracked the rock a tier (0.4 -> 0.2)", is_equal_approx(float(g3[4][6]["cover"]), 0.2))
	# an ordinary bomber stick has no owner/source
	var g4 := _grid(core)
	var b4 := _battle(core, g4, [_u("x", "p", 5, 5), _u("bm", "e", 1, 1, {"bomber": true})])
	core.plant_charge(b4, "e", {"q": 5, "r": 5})
	_check("ordinary stick has no owner/source", not b4["charges"][0].has("owner") and not b4["charges"][0].has("source"))
	_check("last_charge_source is empty for a plain stick", core.last_charge_source == "")
	core.plant_charge(b4, "e", {"q": 6, "r": 6}, {"owner": "boss", "source": "foreman_heat"})
	_check("last_charge_source reports foreman_heat", core.last_charge_source == "foreman_heat")
	# metadata can never override timing/side/position
	core.plant_charge(b4, "e", {"q": 7, "r": 7}, {"fuse": 9, "side": "p", "q": 0})
	var last: Dictionary = b4["charges"][b4["charges"].size() - 1]
	_check("meta cannot override fuse/side/position", int(last["fuse"]) == 1 and last["side"] == "e" and int(last["q"]) == 7)

	print("== design data wiring ==")
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	core.design = JSON.parse_string(f.get_as_text())
	var spec: Dictionary = core._find(core.design["enemies"], "iron_foreman")
	_check("iron_foreman carries bossRule conducting_cover in design.json", str(spec.get("bossRule", {}).get("id", "")) == "conducting_cover")
	var unit: Dictionary = core.enemy_to_unit(spec, 0)
	_check("enemy_to_unit maps bossRule", str(unit.get("bossRule", {}).get("id", "")) == "conducting_cover")
	var other: Dictionary = core.enemy_to_unit(core._find(core.design["enemies"], "the_deacon"), 1)
	_check("other bosses carry an empty rule", (other.get("bossRule", {}) as Dictionary).is_empty())

	print("")
	print("foreman_rule_test: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
