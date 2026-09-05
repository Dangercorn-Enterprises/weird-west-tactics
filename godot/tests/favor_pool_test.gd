# =============================================================================
# DUSTFALL: shared favor purse regression test (2026-09-04 port-regression fix)
# Run:  godot --headless --path godot --script res://tests/favor_pool_test.gd
# Divine favor is ONE purse per god (web: DF.state.favor[god], read live at
# cast time). Two riders sworn to the same god (the default full party's
# preacher and lawdog both draw on Perun) share it: the second cannot cast on
# an empty purse, and empowerment (>= 3) is judged BEFORE the debit. The
# resolver models this as b.favorPool; battle.gd reads GS.state.favor live.
# Pure core, no scene. The parity harness mirrors b.favorPool draw for draw.
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

var passed := 0
var failed := 0
var hits := 0  # damage events landed on the enemy (on_damage hook)

func ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)

# open field: no cover, no height, so LOS/range never gate the divine
func _open_grid(core: CombatCore) -> Array:
	var g: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0,
				"heavy": false, "rough": false})
		g.append(row)
	return g

func _mk_battle(core: CombatCore, players: Array, enemies: Array, pool) -> Dictionary:
	var b := {"grid": _open_grid(core), "players": players, "enemies": enemies,
		"units": players + enemies, "kills": 0, "xpKills": 0, "playerDeaths": 0,
		"charges": []}
	if pool != null:
		b["favorPool"] = pool
	return b

func _rider(core: CombatCore, aid: String, i: int, q: int, r: int, quick: int) -> Dictionary:
	var u: Dictionary = core.party_to_unit(core.mk_party([aid])[0], i)
	u["id"] = "p%d" % i
	u["q"] = q
	u["r"] = r
	u["quick"] = quick  # fixes activation order (player_phase sorts by quick)
	return u

# a big, visible, unkillable threat: the bot spends its ult only on hp >= 18
func _wall(core: CombatCore) -> Dictionary:
	var e: Dictionary = core.enemy_to_unit(core.design["enemies"][0], 0)
	e["q"] = 3
	e["r"] = 3
	e["hp"] = 999
	e["maxHp"] = 999
	return e

func _casts(players: Array) -> int:
	var n := 0
	for p in players:
		if p.get("divineUsed", false):
			n += 1
	return n

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing, run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	core.seed_rng(1337)
	core.on_damage = func(def, _dmg, _crit):
		if def["side"] == "e":
			hits += 1

	# ---- god resolution -----------------------------------------------------------
	var pr: Dictionary = _rider(core, "preacher", 0, 1, 1, 9)
	var ld: Dictionary = _rider(core, "lawdog", 1, 1, 5, 1)
	ok("preacher and lawdog both draw on Perun (ARCH_GOD)",
		core.unit_god(pr) == "perun" and core.unit_god(ld) == "perun")
	var sworn: Dictionary = _rider(core, "lawdog", 2, 1, 7, 1)
	sworn["god"] = "vulcan"
	ok("a sworn rider draws on the shrine god instead", core.unit_god(sworn) == "vulcan")
	var all_seeded := true
	for g in core.ARCH_GOD.values():
		if not core.GODS.has(g):
			all_seeded = false
	ok("every archetype god gets a purse seed (GODS covers ARCH_GOD)", all_seeded)

	# ---- perun 1, two Perun riders: exactly ONE cast, purse empty ---------------
	var b1 := _mk_battle(core, [pr, ld], [_wall(core)], {"perun": 1, "coyote": 1})
	core.player_phase(b1)
	ok("perun 1: exactly one of two Perun riders casts", _casts([pr, ld]) == 1)
	ok("perun 1: the purse is spent to 0", int(b1["favorPool"]["perun"]) == 0)
	ok("perun 1: the Coyote purse is untouched", int(b1["favorPool"]["coyote"]) == 1)

	# ---- perun 3, two Perun riders (both Thunder, blast count = empowerment) ------
	# Riders sit outside the blast radius, so every damage event is one blast on
	# the wall: first cast empowered (3 blasts, judged on 3 before the debit),
	# second cast plain (2 blasts, purse at 2), purse ends at 1.
	var pa: Dictionary = _rider(core, "preacher", 0, 1, 1, 9)
	var pb: Dictionary = _rider(core, "preacher", 1, 1, 5, 1)
	hits = 0
	var b3 := _mk_battle(core, [pa, pb], [_wall(core)], {"perun": 3})
	core.player_phase(b3)
	ok("perun 3: both Perun riders cast", _casts([pa, pb]) == 2)
	ok("perun 3: first cast empowered, second plain (3 + 2 blasts)", hits == 5)
	ok("perun 3: the purse is debited once per cast (ends at 1)", int(b3["favorPool"]["perun"]) == 1)

	# ---- perun 2: a lone caster is NOT empowered (2 blasts) -----------------------
	var pc: Dictionary = _rider(core, "preacher", 0, 1, 1, 9)
	hits = 0
	var b2 := _mk_battle(core, [pc], [_wall(core)], {"perun": 2})
	core.player_phase(b2)
	ok("perun 2: plain cast (2 blasts)", pc.get("divineUsed", false) and hits == 2)
	ok("perun 2: purse ends at 1", int(b2["favorPool"]["perun"]) == 1)

	# ---- perun 0, coyote 1: a Coyote rider is unaffected by the Perun purse ------
	var gs: Dictionary = _rider(core, "gunslinger", 0, 1, 1, 9)
	var pd: Dictionary = _rider(core, "preacher", 1, 1, 5, 1)
	var b0 := _mk_battle(core, [gs, pd], [_wall(core)], {"perun": 0, "coyote": 1})
	core.player_phase(b0)
	ok("perun 0: the Perun rider stays silent", not pd.get("divineUsed", false))
	ok("coyote 1: the Coyote rider casts anyway", gs.get("divineUsed", false))
	ok("coyote purse spent, perun purse still 0",
		int(b0["favorPool"]["coyote"]) == 0 and int(b0["favorPool"]["perun"]) == 0)

	# ---- no purse at all (rules tests build battles without one): no cast --------
	var pe: Dictionary = _rider(core, "preacher", 0, 1, 1, 9)
	var bn := _mk_battle(core, [pe], [_wall(core)], null)
	core.player_phase(bn)
	ok("no favorPool: the god is silent", not pe.get("divineUsed", false))

	print("favor_pool_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
