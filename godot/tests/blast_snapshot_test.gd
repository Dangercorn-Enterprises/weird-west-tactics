# =============================================================================
# DUSTFALL, do_blast snapshot test (Node-parity guard)
# A blast that drops an un-enraged boss to <= 50% raises Risen Dead onto free
# SPAWNS tiles mid-blast. The Node harness (doBlast) filters the caught units
# BEFORE applying damage, so the fresh adds are never hit and never cost a
# randint. Godot must match draw for draw: the caught set is snapshotted first.
# Deterministic, pure core. NEVER touches user://save.json.
# Run:  godot --headless --path godot --script res://tests/blast_snapshot_test.gd
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
		push_error("design.json missing, run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	const SEED := 20260904
	core.seed_rng(SEED)

	var spec := {}
	for e in core.design["enemies"]:
		if e.get("id", "") == "iron_foreman":
			spec = e
			break
	var boss := core.enemy_to_unit(spec, 0)
	# boss at (8,7): the 3x3 blast radius covers SPAWNS (8,8), (9,6) and (9,8),
	# so the enrage adds land INSIDE the blast. 51% HP: any blast tick enrages.
	boss["q"] = 8; boss["r"] = 7
	boss["hp"] = int(ceil(float(boss["maxHp"]) * 0.51))
	ok("boss starts un-enraged above half",
		bool(boss.get("boss", false)) and not bool(boss.get("enraged", false))
		and float(boss["hp"]) > float(boss["maxHp"]) / 2.0)
	# one player caught too, so the blast draws twice (boss + player), no more
	var pl: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	pl["q"] = 7; pl["r"] = 7
	pl["hp"] = 999; pl["maxHp"] = 999
	var b := _mk_battle(core, [pl], [boss])
	ok("spawn tiles (8,8) and (9,6) start free", b["units"].size() == 2)

	var state0: int = core._rng_state
	core.do_blast(b, {"q": 8, "r": 7})

	ok("blast enraged the boss", bool(boss.get("enraged", false)))
	var raised: Array = []
	for u in b["units"]:
		if u.get("name", "") == "Risen Dead":
			raised.append(u)
	ok("enrage raised two Risen Dead into the radius", raised.size() == 2
		and int(raised[0]["q"]) == 8 and int(raised[0]["r"]) == 8
		and int(raised[1]["q"]) == 9 and int(raised[1]["r"]) == 6)
	var untouched := raised.size() == 2
	for m in raised:
		if int(m["hp"]) != int(m["maxHp"]) or not bool(m["alive"]):
			untouched = false
	ok("freshly raised units took NO blast damage (full HP)", untouched)

	# Node-equivalent draw count: exactly one randint per unit caught at the
	# moment the blast resolves (boss + player = 2), none for the adds.
	var ref := CombatCoreScript.new()
	ref.seed_rng(SEED)
	ok("rng state moved from the pre-blast snapshot", core._rng_state != state0)
	ref.rnd()
	ref.rnd()
	ok("RNG advanced exactly 2 draws (caught units only, adds cost nothing)",
		core._rng_state == ref._rng_state)
	ref.rnd()
	ok("...and not 3 or 4 (the old live-array walk)", core._rng_state != ref._rng_state)

	print("blast_snapshot_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
