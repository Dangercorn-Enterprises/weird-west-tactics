# =============================================================================
# DUSTFALL, summoned unit id test. Enrage adds and Deacon kit raises used to
# mint fixed ids (e90/e91 and e80+raisedN), so two bosses in one fight, or a
# Deacon that raised 10+ times, aliased sprites in battle.gd (unit_nodes and the
# pre-phase facing map are keyed by id). Deterministic, pure core, NEVER
# touches user://save.json.
# Run:  godot --headless --path godot --script res://tests/summon_id_test.gd
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

func _spec(core: CombatCore, id: String) -> Dictionary:
	for e in core.design["enemies"]:
		if e.get("id", "") == id:
			return e
	return {}

func _all_ids_distinct(units: Array) -> bool:
	var seen := {}
	for u in units:
		var id := str(u["id"])
		if seen.has(id):
			return false
		seen[id] = true
	return true

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing, run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	core.seed_rng(42)

	# ---- two bosses enrage in one battle (finale: hollow_man + coyotes_shadow) ----
	var hollow_spec := _spec(core, "hollow_man")
	var coyote_spec := _spec(core, "coyotes_shadow")
	ok("finale bosses exist in design", not hollow_spec.is_empty() and not coyote_spec.is_empty())
	var hollow := core.enemy_to_unit(hollow_spec, 0)
	var coyote := core.enemy_to_unit(coyote_spec, 1)
	hollow["q"] = 5; hollow["r"] = 1
	coyote["q"] = 5; coyote["r"] = 8
	var pl: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	pl["q"] = 0; pl["r"] = 5
	var b := _mk_battle(core, [pl], [hollow, coyote])
	ok("both are bosses", hollow.get("boss", false) == true and coyote.get("boss", false) == true)
	hollow["hp"] = int(hollow["maxHp"]) / 2
	core.check_boss_phase(b, hollow)
	ok("first boss enraged and added 2", hollow.get("enraged", false) == true and b["enemies"].size() == 4)
	coyote["hp"] = int(coyote["maxHp"]) / 2
	core.check_boss_phase(b, coyote)
	ok("second boss enraged and added 2 more", coyote.get("enraged", false) == true and b["enemies"].size() == 6)
	ok("all unit ids distinct after two enrages", _all_ids_distinct(b["units"]))
	ok("enrage add ids are owner-scoped",
		str(b["enemies"][2]["id"]) == "e0_phase0" and str(b["enemies"][3]["id"]) == "e0_phase1"
		and str(b["enemies"][4]["id"]) == "e1_phase0" and str(b["enemies"][5]["id"]) == "e1_phase1")
	ok("enrage adds still named Risen Dead on both sides",
		str(b["enemies"][2]["name"]) == "Risen Dead" and str(b["enemies"][5]["name"]) == "Risen Dead")

	# ---- Deacon raises 12 times over a stalled fight, never repeats an id ----------
	var deacon := core.enemy_to_unit(_spec(core, "the_deacon"), 0)
	deacon["q"] = 8; deacon["r"] = 1
	var far: Dictionary = core.party_to_unit(core.mk_party(["gunslinger"])[0], 0)
	far["q"] = 0; far["r"] = 9
	far["hp"] = 99999; far["maxHp"] = 99999  # stalled fight: nobody dies for 24+ activations
	var bd := _mk_battle(core, [far], [deacon])
	ok("the_deacon is a summoner", deacon.get("summoner", false) == true)
	var raises := 0
	var guard := 0
	while raises < 12 and guard < 60:
		guard += 1
		var before: int = bd["enemies"].size()
		core.enemy_phase(bd)
		if bd["enemies"].size() > before:
			raises += 1
			# the posse cleans up each raise so the cap-2 resets and the fight stalls
			for x in bd["enemies"]:
				if x.get("raisedBy", "") != "":
					x["alive"] = false
	ok("Deacon raised 12 times", raises == 12 and int(deacon.get("raisedN", 0)) == 12)
	ok("all 13 enemy ids distinct after 12 raises", bd["enemies"].size() == 13 and _all_ids_distinct(bd["enemies"]))
	ok("raise ids are owner-scoped and per-raise",
		str(bd["enemies"][1]["id"]) == "e0_raise0" and str(bd["enemies"][12]["id"]) == "e0_raise11")
	var all_raised_by_deacon := true
	for x in bd["enemies"]:
		if x != deacon and x.get("raisedBy", "") != deacon["id"]:
			all_raised_by_deacon = false
	ok("every raise still records raisedBy = Deacon id", all_raised_by_deacon)
	# a Deacon who then enrages mints phase ids that cannot collide with raise ids
	deacon["hp"] = int(deacon["maxHp"]) / 2
	core.check_boss_phase(bd, deacon)
	ok("Deacon enrage after 12 raises keeps every id distinct",
		deacon.get("enraged", false) == true and bd["enemies"].size() == 15 and _all_ids_distinct(bd["enemies"]))
	# a second Deacon in the same fight (hypothetical) never shares raise ids
	var deacon2 := core.enemy_to_unit(_spec(core, "the_deacon"), 1)
	deacon2["q"] = 8; deacon2["r"] = 4
	bd["enemies"].append(deacon2)
	bd["units"].append(deacon2)
	core.enemy_phase(bd)
	ok("second summoner raise id is scoped to its own id",
		bd["enemies"].size() == 17 and str(bd["enemies"][16]["id"]) == "e1_raise0" and _all_ids_distinct(bd["enemies"]))

	print("\nsummon_id_test: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
