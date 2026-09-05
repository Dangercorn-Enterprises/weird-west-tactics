# =============================================================================
# DUSTFALL — shrine god-swearing regression test (2026-07-09 audit, clusters 4+5)
# Run:  godot --headless --path godot --script res://tests/god_swear_test.gd
# party_to_unit must carry p['god'] onto the battle unit so the divine favor
# pool (battle.gd godId), favor-on-win (game_state.gd), and blessing alignment
# all honor the shrine Swear choice. Web parity: scene_battle.js god: p.god||null.
# The parity harness can never catch this (mk_party has no god field) — hence
# this dedicated test.
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

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing — run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	var arch_god: Dictionary = (load("res://scripts/game_state.gd") as GDScript) \
		.get_script_constant_map()["ARCH_GOD"]

	# the resolver carries its own copy of the map (favor purse per god); the two
	# must never drift, or the bot and the live battle would pay different gods
	ok("combat_core.ARCH_GOD matches game_state.ARCH_GOD exactly",
		CombatCoreScript.ARCH_GOD == arch_god)

	# unsworn rider: god is null, resolution falls back to the archetype god
	var plain: Dictionary = core.mk_party(["gunslinger"])[0]
	var u0: Dictionary = core.party_to_unit(plain, 0)
	ok("unsworn unit has null god", u0.get("god") == null)
	var g0 = u0.get("god") if u0.get("god") else arch_god.get(u0.get("archetype", ""))
	ok("unsworn resolves to archetype god (coyote)", g0 == "coyote")

	# sworn rider: the shrine god must survive party_to_unit
	var sworn: Dictionary = core.mk_party(["gunslinger"])[0]
	sworn["god"] = "vulcan"
	var u1: Dictionary = core.party_to_unit(sworn, 0)
	ok("sworn unit carries god", u1.get("god") == "vulcan")
	var g1 = u1.get("god") if u1.get("god") else arch_god.get(u1.get("archetype", ""))
	ok("sworn resolves to sworn god over archetype", g1 == "vulcan")

	# swearing must not touch combat math (parity guard)
	ok("swearing changes no combat stats",
		u0["hp"] == u1["hp"] and u0["aim"] == u1["aim"] and u0["maxAp"] == u1["maxAp"]
		and u0["rng"] == u1["rng"] and u0["wmin"] == u1["wmin"] and u0["wmax"] == u1["wmax"])

	print("god_swear_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
