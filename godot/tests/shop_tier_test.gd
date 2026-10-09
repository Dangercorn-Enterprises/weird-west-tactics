# =============================================================================
# DUSTFALL — SHOP TIER TEST (Session #3, 2026-10-08)
# Tim's economy pick C: tier-unlock the catalog tail now (drops later).
#   - every weapon / armor / consumable in design.json carries a tier 1..3
#   - tier-1 towns still sell everything the old fixed slices sold (no regression)
#   - the previously unobtainable tail appears by tier 3
#   - unimplemented consumables never reach a shelf
#   - every world node has a tier the shelf can key on
# Run: godot --headless --path godot --script res://tests/shop_tier_test.gd
# =============================================================================
extends SceneTree

const GameStateScript = preload("res://scripts/game_state.gd")

var fails := 0
var passes := 0

func _check(name: String, cond: bool, detail := "") -> void:
	if cond:
		passes += 1
		print("  PASS  " + name)
	else:
		fails += 1
		print("  FAIL  " + name + ("  (" + detail + ")" if detail != "" else ""))

func _ids(list: Array) -> Array:
	var out: Array = []
	for it in list:
		out.append(str(it["id"]))
	return out

func _init() -> void:
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	var design: Dictionary = JSON.parse_string(f.get_as_text())
	var weapons: Array = design["weapons"]
	var armor: Array = design["armor"]
	var cons: Array = design["consumables"]

	print("== data ==")
	var missing := 0
	for list in [weapons, armor, cons]:
		for it in list:
			var t := int(it.get("tier", 0))
			if t < 1 or t > 3:
				missing += 1
	_check("every shop item has a tier in 1..3", missing == 0, "%d without" % missing)
	var unimpl: Array = _ids(cons.filter(func(c): return bool(c.get("unimplemented", false))))
	_check("the three unimplemented consumables are flagged", unimpl == ["tonic_vigor", "holy_water", "coyote_dust"], str(unimpl))

	print("== shelves by town tier ==")
	var t1w := _ids(GameStateScript.shop_goods(weapons, 1))
	var t1a := _ids(GameStateScript.shop_goods(armor, 1))
	var t1c := _ids(GameStateScript.shop_goods(cons, 1))
	# the old fixed slices: weapons[0:4], armor[0:3], consumables[0:3]
	_check("tier 1 keeps the old weapon slice", t1w == ["revolver", "rifle", "shotgun", "repeater"], str(t1w))
	_check("tier 1 keeps the old armor slice", t1a == ["leather_duster", "reinforced_vest", "ashfall_plating"], str(t1a))
	_check("tier 1 keeps the old consumable slice", t1c == ["bandages", "ashfall_charge", "smelling_salts"], str(t1c))
	var t2w := _ids(GameStateScript.shop_goods(weapons, 2))
	var t2a := _ids(GameStateScript.shop_goods(armor, 2))
	_check("tier 2 opens the Hex Focus", "hex_focus" in t2w and not ("steam_cannon" in t2w))
	_check("tier 2 opens Blessed Vestments", "blessed_vestments" in t2a and not ("clockwork_exo" in t2a))
	var t3w := _ids(GameStateScript.shop_goods(weapons, 3))
	var t3a := _ids(GameStateScript.shop_goods(armor, 3))
	var t3c := _ids(GameStateScript.shop_goods(cons, 3))
	_check("tier 3 sells every weapon", t3w.size() == weapons.size())
	_check("tier 3 sells every armor", t3a.size() == armor.size())
	_check("unimplemented consumables never reach a shelf", t3c == ["bandages", "ashfall_charge", "smelling_salts"], str(t3c))
	_check("tier 0 / missing tier behaves as tier 1", _ids(GameStateScript.shop_goods(weapons, 0)) == t1w)
	# the formerly unobtainable tail is now reachable somewhere
	for id in ["ashfall_pistol", "steam_cannon", "hex_focus", "blessed_vestments", "clockwork_exo"]:
		_check("tail item %s is purchasable by tier 3" % id, id in t3w or id in t3a)

	print("== world ==")
	var nodes: Array = design["world_nodes"]
	var bad := 0
	var tiers := {}
	for n in nodes:
		var t := int(n.get("tier", 0))
		if t < 1 or t > 3:
			bad += 1
		tiers[t] = int(tiers.get(t, 0)) + 1
	_check("every world node has a tier 1..3 (%s)" % str(tiers), bad == 0, "%d bad" % bad)

	print("")
	print("shop_tier_test: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
