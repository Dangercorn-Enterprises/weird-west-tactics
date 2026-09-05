# =============================================================================
# DUSTFALL — persistent wound regression test (Phase 2 audit C1, 2026-09-04)
# Bug: mk_unit set maxHp = hp with hp already reduced by hpDamage, and
# apply_battle_result stores hpDamage = maxHp - hp, so any wound older than the
# last battle was silently healed and a fallen rider with prior wounds came
# back above 1 HP. Fix: maxHp is the TRUE max (10 + vigor*2) in both engines.
# Tim's picks (2026-09-04): Fork A1 — in-battle heals cure campaign wounds;
# Fork B2 — a fallen rider who levels returns at 1 HP plus the vigor headroom
# (no 1-HP pin loop), symmetric with surviving riders.
# Uses a MemoryState subclass so apply_battle_result NEVER touches user://save.json.
# Run:  godot --headless --path godot --script res://tests/wound_test.gd
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

class MemoryState:
	extends "res://scripts/game_state.gd"
	func save_game() -> void:
		pass

var passed := 0
var failed := 0

func eq(name: String, actual, expected) -> void:
	if actual == expected:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name, "  (got ", actual, ", want ", expected, ")")

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing — run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	var gs := MemoryState.new()

	# Pregen gunslinger: vigor 5 → true max 20. Carry an 8-point wound in (start 12).
	# Each case: fight one battle ending at `hp`/`alive`, then a second battle with
	# no new damage — the stored wound must be stable across both.
	# gunslinger FAVORED = deftness/quickness, so a level adds exactly +1 vigor
	# (+2 max HP) with no RNG in the HP path.
	for case in [
		{"name": "damage",          "hp": 10, "alive": true,  "xp": 0,  "kills": 0, "next": 10},
		{"name": "unchanged",       "hp": 12, "alive": true,  "xp": 0,  "kills": 0, "next": 12},
		{"name": "healed (A1)",     "hp": 16, "alive": true,  "xp": 0,  "kills": 0, "next": 16},
		{"name": "fallen",          "hp": -4, "alive": false, "xp": 0,  "kills": 0, "next": 1},
		{"name": "fallen+level (B2)", "hp": -4, "alive": false, "xp": 99, "kills": 1, "next": 3},
	]:
		var label: String = case["name"]
		var member: Dictionary = core.mk_party(["gunslinger"])[0]
		member["hpDamage"] = 8
		member["xp"] = case["xp"]
		var unit: Dictionary = core.party_to_unit(member, 0)
		eq(label + ": max HP is the true max", unit["maxHp"], 20)
		eq(label + ": start HP carries the wound", unit["hp"], 12)
		unit["hp"] = case["hp"]
		unit["alive"] = case["alive"]
		gs.state = {"party": [member], "favor": {}}
		gs.apply_battle_result({"players": [unit]}, false, case["kills"])
		var next: Dictionary = core.party_to_unit(member, 0)
		eq(label + ": next battle HP", next["hp"], case["next"])
		if label.begins_with("fallen+level"):
			eq(label + ": rider reached Lv 2", member["level"], 2)
			eq(label + ": max HP grew with vigor", next["maxHp"], 22)
		# A battle with no new damage (and no XP) must not move the wound.
		gs.apply_battle_result({"players": [next]}, false, 0)
		eq(label + ": third battle HP", core.party_to_unit(member, 0)["hp"], case["next"])

	# Rest/Doc clear hpDamage; a cleared rider spawns at full.
	var rested: Dictionary = core.mk_party(["gunslinger"])[0]
	rested["hpDamage"] = 0
	eq("rest clears wounds", core.party_to_unit(rested, 0)["hp"], 20)

	# Enemies and summons never pass maxHp — mk_unit must still default it to hp.
	var foe: Dictionary = core.mk_unit({"hp": 14, "quick": 4})
	eq("mk_unit without maxHp defaults to hp", foe["maxHp"], 14)

	gs.free()
	print("wound_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
