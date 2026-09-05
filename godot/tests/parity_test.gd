# =============================================================================
# DUSTFALL — PARITY TEST (headless)
# Proves the Godot combat core produces the same balance as the Node harness.
# Run:  godot --headless --path godot --script res://tests/parity_test.gd
# Prints JSON: {"unit": {...exact derivations...}, "encounters": {...win rates}}
# tools/parity_check.js compares against the Node harness exactly (shared seed
# 1337, same draws, delta 0.0). Aggregates are snapped to 4 decimals here and
# the Node side rounds to the same 4 decimals before comparing.
# =============================================================================
extends SceneTree

const CombatCoreScript = preload("res://scripts/combat_core.gd")

func _init() -> void:
	var core := CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing — run: node tools/export_data.js")
		quit(1)
		return
	core.design = JSON.parse_string(f.get_as_text())
	core.seed_rng(1337)

	# ---- exact unit-derivation checks (must match JS partyToUnit bit-for-bit)
	var starter := core.mk_party(["gunslinger", "hexslinger"])
	var u0 := core.party_to_unit(starter[0], 0)
	var geared := core.party_to_unit({
		"uid": "g0", "archetype": "gunslinger",
		"stats": core.design["pregen"]["gunslinger"]["stats"],
		"gear": {"weapon": "rifle", "armor": "reinforced_vest", "mod": "ashfall_chamber"},
	}, 0)
	var grid := core.build_grid()
	var e0 := core.enemy_to_unit(core.design["enemies"][0], 0)
	e0["q"] = 8
	e0["r"] = 8
	var lo_att := u0.duplicate(true)
	lo_att["aim"] = -500
	var hi_att := u0.duplicate(true)
	hi_att["aim"] = 999
	var unit_report := {
		"gunslinger_hp": u0["hp"], "gunslinger_aim": u0["aim"],
		"gunslinger_maxAp": u0["maxAp"], "gunslinger_rng": u0["rng"],
		"geared_rng": geared["rng"], "geared_wmin": geared["wmin"],
		"geared_wmax": geared["wmax"], "geared_maxAp": geared["maxAp"],
		"geared_armorDef": geared["armorDef"],
		"hit_clamp_lo": core.hit_chance(grid, lo_att, e0),
		"hit_clamp_hi": core.hit_chance(grid, hi_att, e0),
	}

	# ---- statistical parity on the key tuned encounters
	var runs := 2000
	var full := core.mk_party(["gunslinger", "hexslinger", "preacher", "lawdog"])
	var encounters := {
		"skirmish": core.eval_encounter(starter, ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"], runs),
		"vanguard": core.eval_encounter(starter, ["revenant_gun", "walkin_dead", "dynamite_bandit", "dynamite_bandit"], runs),
		"deacon": core.eval_encounter(starter, ["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"], runs),
		"foreman": core.eval_encounter(starter, ["iron_foreman", "forge_sentry", "forge_sentry"], runs),
		"weaver": core.eval_encounter(starter, ["the_weaver", "dust_witch", "dust_witch"], runs),
		"hollow": core.eval_encounter(starter, ["hollow_man", "dust_devil", "dust_devil"], runs),
		"finale4": core.eval_encounter(full, ["hollow_man", "coyotes_shadow", "dust_devil"], runs),
	}
	var results := {}
	for k in encounters:
		results[k] = {
			"wr": snappedf(encounters[k]["winRate"], 0.0001),
			"rounds": snappedf(encounters[k]["avgRounds"], 0.0001),
			"kills": snappedf(encounters[k]["avgKills"], 0.0001),
		}

	print(JSON.stringify({"unit": unit_report, "encounters": results}))
	quit(0)
