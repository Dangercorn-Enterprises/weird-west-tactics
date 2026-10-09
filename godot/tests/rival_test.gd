# =============================================================================
# DUSTFALL — WANTED-POSTER RIVALS TEST (Session #3 Lane D, 2026-10-08)
# Tim's picks: mint on (downs a rider | survives a fight you lost | random
# named spawn at tier 2+ | `wanted` hindrance doubles odds); scars cosmetic +
# mechanical; rivals on the marshal board AND trail ambushes near last-seen.
# Pure-dictionary tests over scripts/rivals.gd + the combat_core hooks it
# depends on (lastHitBy, grudge targeting, rival temperaments).
# Run: godot --headless --path godot --script res://tests/rival_test.gd
# =============================================================================
extends SceneTree

const RivalsLib = preload("res://scripts/rivals.gd")
const CombatCoreScript = preload("res://scripts/combat_core.gd")

var fails := 0
var passes := 0
var design: Dictionary = {}

func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("  PASS  " + name)
	else:
		fails += 1
		print("  FAIL  " + name + ("  (" + detail + ")" if detail != "" else ""))

func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

func _state() -> Dictionary:
	return {"party": [{"uid": "p0", "name": "Silas", "archetype": "gunslinger", "stats": {}},
		{"uid": "p1", "name": "Mae", "archetype": "hexslinger", "stats": {}}],
		"gold": 100, "day": 5, "location": "tucson", "rivals": []}

func _u(id: String, side: String, q: int, r: int, extra := {}) -> Dictionary:
	var u := {"id": id, "name": id, "side": side, "q": q, "r": r, "alive": true, "hp": 20, "maxHp": 20,
		"aim": 70, "rng": 5, "str": 6, "quick": 4, "wmin": 4, "wmax": 8, "ap": 3, "maxAp": 3, "archetype": "walkin_dead",
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
	return {"grid": grid, "players": units.filter(func(x): return x["side"] == "p"),
		"enemies": units.filter(func(x): return x["side"] == "e"), "units": units,
		"kills": 0, "xpKills": 0, "playerDeaths": 0, "charges": [], "favorPool": {}}

func _init() -> void:
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	design = JSON.parse_string(f.get_as_text())
	_check("design.json carries the rivals table", design.has("rivals") and (design["rivals"]["names"] as Array).size() >= 10)

	print("== minting ==")
	var st := _state()
	var r1 := RivalsLib.mint(st, design, "walkin_dead", "p0", "tucson", _rng(1), "test")
	_check("mint creates a live rank-1 rival with a grudge", not r1.is_empty() and r1["rank"] == 1 and r1["grudge"] == "p0" and r1["alive"])
	_check("display name = name + epithet", RivalsLib.display_name(r1).begins_with(str(r1["name"])) and RivalsLib.display_name(r1).length() > str(r1["name"]).length())
	var boss := RivalsLib.mint(st, design, "the_deacon", "p0", "tucson", _rng(2), "test")
	_check("bosses never become rivals", boss.is_empty())
	RivalsLib.mint(st, design, "coyote_beast", "p1", "tucson", _rng(3), "test")
	RivalsLib.mint(st, design, "forge_sentry", "p1", "tucson", _rng(4), "test")
	var r4 := RivalsLib.mint(st, design, "walkin_dead", "p1", "tucson", _rng(5), "test")
	_check("live cap (3) refuses a fourth", r4.is_empty() and RivalsLib.live(st).size() == 3)
	_check("bounty = 60 + 60 x rank", RivalsLib.bounty_for(r1) == 120 and RivalsLib.bounty_for({"rank": 3}) == 240)
	_check("stars render the rank", RivalsLib.stars({"rank": 2}) == "★★")
	var old := {"party": [], "day": 1}
	_check("older saves get a rivals list lazily", RivalsLib.live(old).is_empty() and old.has("rivals"))

	print("== spec_for: rank + scars ==")
	var tmpl := {}
	for e in design["enemies"]:
		if e["id"] == "walkin_dead":
			tmpl = e
	var s1 := RivalsLib.spec_for(design, r1)
	_check("rank 1: base stats, rival flags, grudge carried", int(s1["hp"]) == int(tmpl["hp"]) and int(s1["aim"]) == int(tmpl["aim"]) and s1["rival"] and s1["grudge"] == "p0" and not s1["rivalFlank"])
	r1["rank"] = 2
	r1["scars"] = ["eye"]
	var s2 := RivalsLib.spec_for(design, r1)
	_check("rank 2 + 1 scar: +25%% hp, +4-2 aim, flank temperament", int(s2["hp"]) == roundi(float(tmpl["hp"]) * 1.25) and int(s2["aim"]) == int(tmpl["aim"]) + 2 and s2["rivalFlank"] and not s2["rivalZealot"])
	r1["rank"] = 3
	var s3 := RivalsLib.spec_for(design, r1)
	_check("rank 3: zealot too", s3["rivalZealot"] and s3["rivalFlank"])
	r1["rank"] = 1
	r1["scars"] = []

	print("== combat hooks ==")
	var core = CombatCoreScript.new()
	core.design = design
	var unit: Dictionary = core.enemy_to_unit(s2, 0)
	_check("enemy_to_unit maps rival/grudge/flank", unit["rival"] and unit["rivalId"] == str(r1["id"]) and unit["grudge"] == "p0" and unit["flanker"])
	# grudge targeting: the rival shoots p0 even when p1 is weaker and closer
	core.seed_rng(11)
	var p0 := _u("p0", "p", 4, 4, {"hp": 20})
	var p1 := _u("p1", "p", 6, 5, {"hp": 3})
	var rv := _u("e0", "e", 7, 4, {"grudge": "p0", "rng": 6})
	var b := _battle(core, [p0, p1, rv])
	var shot_at := {"id": ""}
	core.on_fire = func(_a, d, _res): if shot_at["id"] == "": shot_at["id"] = str(d["id"])
	core.enemy_phase(b)
	core.on_fire = Callable()
	_check("grudge rival targets its rider (shot at %s)" % shot_at["id"], shot_at["id"] == "p0")
	# lastHitBy: do_fire marks the defender, melee snap marks the mover, blast credits its source
	core.seed_rng(3)
	var a := _u("att", "e", 2, 2, {"aim": 999})
	var d := _u("def", "p", 4, 2)
	var b2 := _battle(core, [d, a])
	core.do_fire(b2, a, d)
	_check("do_fire records lastHitBy", str(d.get("lastHitBy", "")) == "att")
	var mover := _u("mv", "p", 3, 3)
	var puncher := _u("pn", "e", 3, 4)
	var b3 := _battle(core, [mover, puncher])
	core.resolve_melee_snap(b3, mover)
	_check("melee snap records lastHitBy", str(mover.get("lastHitBy", "")) == "pn")
	var v := _u("v", "p", 5, 5)
	var b4 := _battle(core, [v, _u("sl", "e", 1, 1)])
	core.do_blast(b4, {"q": 5, "r": 5}, "sl")
	_check("blast credits its source", str(v.get("lastHitBy", "")) == "sl")
	var v2 := _u("v2", "p", 5, 5)
	var b5 := _battle(core, [v2])
	core.do_blast(b5, {"q": 5, "r": 5})
	_check("player/anonymous blast credits nobody", not v2.has("lastHitBy"))

	print("== after_battle ==")
	# LOSS: enemy e9 downed p0 and is still standing -> minted with the grudge on p0
	var st2 := _state()
	var dead_p0 := _u("p0", "p", 1, 1, {"alive": false, "hp": 0, "lastHitBy": "e9", "name": "Silas"})
	var dead_p1 := _u("p1", "p", 1, 2, {"alive": false, "hp": 0, "lastHitBy": "e8"})
	var e9 := _u("e9", "e", 5, 5, {"hp": 9, "archetype": "coyote_beast"})
	var e8 := _u("e8", "e", 6, 6, {"hp": 15, "archetype": "walkin_dead"})
	var lossb := _battle(core, [dead_p0, dead_p1, e9, e8])
	var rec := RivalsLib.after_battle(st2, design, lossb, false, "tucson", _rng(7))
	_check("loss: exactly one rival minted", (rec["minted"] as Array).size() == 1 and RivalsLib.live(st2).size() == 1)
	if (rec["minted"] as Array).size() == 1:
		var m: Dictionary = rec["minted"][0]
		_check("...the one who downed a rider, grudge on that rider", m["template"] == "coyote_beast" and m["grudge"] == "p0" and m["kills"] == 1)
		_check("...last seen where the fight was", m["lastNode"] == "tucson")
	_check("loss receipt has a banner line", (rec["lines"] as Array).size() >= 1)
	# LOSS with no rider-down credit: the last one standing (highest hp) is minted
	var st3 := _state()
	var lossb2 := _battle(core, [_u("p0", "p", 1, 1, {"alive": false, "hp": 0}), _u("e1", "e", 5, 5, {"hp": 4, "archetype": "walkin_dead", "lastHitBy": "p0"}), _u("e2", "e", 6, 6, {"hp": 14, "archetype": "coyote_beast"})])
	var rec2 := RivalsLib.after_battle(st3, design, lossb2, false, "carson", _rng(8))
	_check("loss w/o credit: highest-hp survivor minted", (rec2["minted"] as Array).size() == 1 and rec2["minted"][0]["template"] == "coyote_beast")
	# WIN: nobody minted, and a rival present + dead pays the bounty and is retired
	var st4 := _state()
	var rr := RivalsLib.mint(st4, design, "walkin_dead", "p0", "tucson", _rng(9), "test")
	var rspec := RivalsLib.spec_for(design, rr)
	var runit: Dictionary = core.enemy_to_unit(rspec, 0)
	runit["alive"] = false
	runit["hp"] = 0
	var winb := _battle(core, [_u("p0", "p", 1, 1), runit])
	var rec3 := RivalsLib.after_battle(st4, design, winb, true, "tucson", _rng(10))
	_check("win: no mint", (rec3["minted"] as Array).is_empty())
	_check("win: dead rival retired + bounty paid", not rr["alive"] and int(rec3["gold"]) == 120 and (rec3["killed"] as Array).size() == 1)
	_check("win: a dead rival drops off the board", RivalsLib.live(st4).is_empty())
	# LOSS with the rival surviving: escalates, scars, remembers the node, grudge follows last hitter
	var st5 := _state()
	var r5 := RivalsLib.mint(st5, design, "walkin_dead", "p0", "tucson", _rng(12), "test")
	var u5: Dictionary = core.enemy_to_unit(RivalsLib.spec_for(design, r5), 0)
	u5["lastHitBy"] = "p1"
	var lossb3 := _battle(core, [_u("p0", "p", 1, 1, {"alive": false, "hp": 0}), _u("p1", "p", 1, 2, {"alive": false, "hp": 0}), u5])
	var rec4 := RivalsLib.after_battle(st5, design, lossb3, false, "saltlake", _rng(13))
	_check("loss: surviving rival ranks up and scars", r5["rank"] == 2 and (r5["scars"] as Array).size() == 1 and (rec4["escalated"] as Array).size() == 1)
	_check("...moves its last-seen node and re-aims its grudge", r5["lastNode"] == "saltlake" and r5["grudge"] == "p1")
	_check("...and no second rival is minted off the same fight", (rec4["minted"] as Array).is_empty() or RivalsLib.live(st5).size() <= 2)
	RivalsLib.after_battle(st5, design, lossb3, false, "saltlake", _rng(14))
	RivalsLib.after_battle(st5, design, lossb3, false, "saltlake", _rng(15))
	_check("rank caps at 3", r5["rank"] == 3)

	print("== spawning ==")
	var node_t2 := {"id": "saltlake", "tier": 2}
	var node_t1 := {"id": "carson", "tier": 1}
	# rivals_near: at the node and one trail away (clean state)
	var st6 := _state()
	var r6 := RivalsLib.mint(st6, design, "walkin_dead", "p0", "saltlake", _rng(20), "test")
	var near := RivalsLib.rivals_near(st6, design, "saltlake")
	_check("rivals_near finds the rival at its node", near.size() == 1)
	var adj_found := false
	for e in design["world_edges"]:
		if str(e[0]) == "saltlake" or str(e[1]) == "saltlake":
			var other: String = str(e[1]) if str(e[0]) == "saltlake" else str(e[0])
			adj_found = RivalsLib.rivals_near(st6, design, other).size() == 1
			break
	_check("rivals_near finds it one trail away", adj_found)
	_check("rivals_near ignores a far node", RivalsLib.rivals_near(st6, design, "sandiego").is_empty())
	# a rival nearby leads with rivalLeadsChance (fresh state per draw so a
	# named spawn from a miss can't pollute the next draw)
	var led := 0
	for s in 200:
		var st_l := _state()
		var rl := RivalsLib.mint(st_l, design, "walkin_dead", "p0", "saltlake", _rng(20), "test")
		var spec := RivalsLib.pick_leader(st_l, design, node_t2, "coyote_beast", _rng(100 + s))
		if not spec.is_empty() and spec["rivalId"] == str(rl["id"]):
			led += 1
	_check("a rival last seen here leads ~half the fights (%d/200)" % led, led > 60 and led < 140)
	# random named spawn: tier 1 never, tier 2 ~namedSpawnChance, wanted doubles it
	var st7 := _state()
	var t1 := 0
	for s in 200:
		var st_t := _state()
		if not RivalsLib.pick_leader(st_t, design, node_t1, "coyote_beast", _rng(300 + s)).is_empty():
			t1 += 1
	_check("tier 1: no random named spawns", t1 == 0)
	var t2 := 0
	for s in 400:
		var st_t := _state()
		if not RivalsLib.pick_leader(st_t, design, node_t2, "coyote_beast", _rng(500 + s)).is_empty():
			t2 += 1
	_check("tier 2: random named spawns near the configured chance (%d/400)" % t2, t2 > 60 and t2 < 140)
	var t2w := 0
	for s in 400:
		var st_w := _state()
		st_w["party"][0]["hindrances"] = ["wanted"]
		if not RivalsLib.pick_leader(st_w, design, node_t2, "coyote_beast", _rng(500 + s)).is_empty():
			t2w += 1
	_check("`wanted` hindrance doubles the odds (%d vs %d)" % [t2w, t2], t2w > t2 + 40)
	_check("wanted_mult reads member hindrances", RivalsLib.wanted_mult(st7) == 1.0)
	# a named spawn is a real minted rival with a grudge on a party member
	var st8 := _state()
	var spec8 := {}
	var s_i := 0
	while spec8.is_empty() and s_i < 200:
		spec8 = RivalsLib.pick_leader(st8, design, node_t2, "coyote_beast", _rng(900 + s_i))
		s_i += 1
	_check("named spawn mints a live rival with a party grudge", not spec8.is_empty() and RivalsLib.live(st8).size() == 1 and spec8["grudge"] in ["p0", "p1"])

	print("== rumors ==")
	var st9 := _state()
	var r9 := RivalsLib.mint(st9, design, "walkin_dead", "p0", "tucson", _rng(40), "test")
	var lines := RivalsLib.rumors(st9, design)
	_check("a live rival makes a rumor naming the town", lines.size() == 1 and "Tucson" in lines[0] and RivalsLib.display_name(r9) in lines[0])
	r9["alive"] = false
	r9["diedNode"] = "tucson"
	_check("a dead rival makes a burial rumor", "buried" in RivalsLib.rumors(st9, design)[0])

	print("")
	print("rival_test: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
