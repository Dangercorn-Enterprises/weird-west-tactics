# =============================================================================
# DUSTFALL — WANTED-POSTER RIVALS (Session #3 Lane D, Tim's picks 2026-10-08)
# Pillar P3: the frontier remembers. Named outlaws MINTED by events, ranked
# 1-3, scarred, holding a grudge against one rider, posted on the marshal
# board and hunting on trails near where they were last seen. A loss against
# them escalates them; a win is permanent and pays the bounty.
#
# Mint triggers (all four picked): an enemy that DOWNS a rider and survives
# the fight; the last enemy standing when the posse is wiped; a random named
# spawn in tier-2+ ambushes and bounties; the `wanted` hindrance doubles the
# random odds (the hook is wired; the Godot creator does not offer hindrances
# yet, so it reads member["hindrances"] when present).
#
# NOT a Nemesis system: no hierarchy, no promotion among enemies, no enemy-vs-
# enemy power struggle (that structure is WB's patent). A rank number only the
# player's fights can change, on a wanted poster. Keep it that way.
#
# Pure static functions over GameState.state / design dictionaries so
# tests/rival_test.gd can drive them without a scene. Data: design.rivals
# (src/data.js RIVALS). Campaign-layer only (Godot); the combat hooks it
# relies on (lastHitBy, grudge targeting, rival temperaments) live in BOTH
# engines (combat_core.gd / balance_harness.js).
# =============================================================================
class_name Rivals
extends RefCounted

static func _cfg(design: Dictionary) -> Dictionary:
	return design.get("rivals", {})

static func all(state: Dictionary) -> Array:
	if not state.has("rivals") or not (state["rivals"] is Array):
		state["rivals"] = []
	return state["rivals"]

static func live(state: Dictionary) -> Array:
	return all(state).filter(func(r): return bool(r.get("alive", true)))

static func by_id(state: Dictionary, id: String) -> Dictionary:
	for r in all(state):
		if str(r["id"]) == id:
			return r
	return {}

static func max_live(design: Dictionary) -> int:
	return int(_cfg(design).get("maxLive", 3))

static func bounty_for(r: Dictionary) -> int:
	return 60 + 60 * int(r.get("rank", 1))

static func stars(r: Dictionary) -> String:
	return "★".repeat(int(r.get("rank", 1)))

static func display_name(r: Dictionary) -> String:
	return "%s %s" % [str(r.get("name", "Nobody")), str(r.get("epithet", ""))] if str(r.get("epithet", "")) != "" else str(r.get("name", "Nobody"))

# A rider with the `wanted` hindrance doubles the random mint odds.
static func wanted_mult(state: Dictionary) -> float:
	for m in state.get("party", []):
		for h in m.get("hindrances", []):
			if str(h) == "wanted":
				return 2.0
	return 1.0

# ---- minting --------------------------------------------------------------------
# Create a rival from an enemy template. Returns {} when the live cap is hit or
# the template is not a regular enemy (bosses never become rivals).
static func mint(state: Dictionary, design: Dictionary, template_id: String, grudge_uid: String,
		node_id: String, rng: RandomNumberGenerator, reason: String) -> Dictionary:
	if live(state).size() >= max_live(design):
		return {}
	var tmpl := {}
	for e in design.get("enemies", []):
		if str(e.get("id", "")) == template_id:
			tmpl = e
			break
	if tmpl.is_empty() or bool(tmpl.get("boss", false)):
		return {}
	var cfg := _cfg(design)
	var names: Array = cfg.get("names", ["Nobody"])
	var epithets: Array = cfg.get("epithets", [""])
	var used := {}
	for r in all(state):
		used[str(r.get("name", ""))] = true
	var nm: String = str(names[rng.randi() % names.size()])
	var guard := 0
	while used.has(nm) and guard < 20:
		nm = str(names[rng.randi() % names.size()])
		guard += 1
	var r := {
		"id": "rv%d_%d" % [int(state.get("day", 0)), all(state).size()],
		"name": nm,
		"epithet": str(epithets[rng.randi() % epithets.size()]),
		"template": template_id,
		"rank": 1,
		"scars": [],
		"grudge": grudge_uid,
		"lastNode": node_id,
		"alive": true,
		"mintedDay": int(state.get("day", 0)),
		"mintedBy": reason,
		"kills": 0,
		"fights": 0,
	}
	all(state).append(r)
	return r

# ---- in-battle spec --------------------------------------------------------------
# The enemy spec the battle builds the rival from: template stats + rank bonus
# (+25% hp, +4 aim per rank above 1), scar penalties (-2 aim each), rank 2 adds
# the flank temperament, rank 3 adds zealot. Carries rival/rivalId/grudge for
# the core (grudge targeting) and the scene (name tag).
static func spec_for(design: Dictionary, r: Dictionary) -> Dictionary:
	var tmpl := {}
	for e in design.get("enemies", []):
		if str(e.get("id", "")) == str(r.get("template", "")):
			tmpl = e
			break
	if tmpl.is_empty():
		return {}
	var cfg := _cfg(design)
	var rank := int(r.get("rank", 1))
	var scars: int = (r.get("scars", []) as Array).size()
	var spec: Dictionary = tmpl.duplicate(true)
	spec["name"] = display_name(r)
	spec["hp"] = maxi(4, roundi(float(tmpl["hp"]) * (1.0 + float(cfg.get("rankHp", 0.25)) * float(rank - 1))))
	spec["aim"] = int(tmpl["aim"]) + int(cfg.get("rankAim", 4)) * (rank - 1) + int(cfg.get("scarAim", -2)) * scars
	spec["rival"] = true
	spec["rivalId"] = str(r["id"])
	spec["grudge"] = str(r.get("grudge", ""))
	spec["rivalFlank"] = rank >= 2
	spec["rivalZealot"] = rank >= 3
	return spec

# ---- after a battle -----------------------------------------------------------------
# Applies the fight's consequences and returns a receipt for the banner:
#   {"minted": [rival], "killed": [rival], "escalated": [rival], "gold": int, "lines": [String]}
static func after_battle(state: Dictionary, design: Dictionary, battle: Dictionary, win: bool,
		node_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"minted": [], "killed": [], "escalated": [], "gold": 0, "lines": []}
	var cfg := _cfg(design)
	var scars: Array = cfg.get("scars", [])
	# 1) rivals that were IN this fight
	for e in battle.get("enemies", []):
		if not bool(e.get("rival", false)):
			continue
		var r := by_id(state, str(e.get("rivalId", "")))
		if r.is_empty():
			continue
		r["fights"] = int(r.get("fights", 0)) + 1
		if not bool(e["alive"]):
			r["alive"] = false
			r["diedNode"] = node_id
			r["diedDay"] = int(state.get("day", 0))
			var g := bounty_for(r)
			out["gold"] += g
			out["killed"].append(r)
			out["lines"].append("WANTED no more: %s — bounty %dg" % [display_name(r), g])
		elif not win:
			# survived the fight that broke the posse: escalate + scar + remember where
			r["rank"] = mini(3, int(r.get("rank", 1)) + 1)
			if not scars.is_empty() and (r["scars"] as Array).size() < scars.size():
				var pool: Array = scars.filter(func(s): return not (r["scars"] as Array).has(str(s["id"])))
				if not pool.is_empty():
					var s: Dictionary = pool[rng.randi() % pool.size()]
					(r["scars"] as Array).append(str(s["id"]))
					out["lines"].append("%s rides off with %s. Rank %s." % [display_name(r), str(s["name"]), stars(r)])
				else:
					out["lines"].append("%s rides off. Rank %s." % [display_name(r), stars(r)])
			else:
				out["lines"].append("%s rides off. Rank %s." % [display_name(r), stars(r)])
			r["lastNode"] = node_id
			out["escalated"].append(r)
			# the grudge follows whoever hurt them last
			if str(e.get("lastHitBy", "")) != "":
				r["grudge"] = str(e["lastHitBy"])
	# 2) minting (one per fight, Calder interpretation: readable)
	if not win and live(state).size() < max_live(design):
		var minted := {}
		# a) an enemy that downed a rider AND is still standing
		for p in battle.get("players", []):
			if bool(p["alive"]):
				continue
			var killer_id := str(p.get("lastHitBy", ""))
			if killer_id == "":
				continue
			for e in battle.get("enemies", []):
				if str(e["id"]) == killer_id and bool(e["alive"]) and not bool(e.get("rival", false)) and not bool(e.get("boss", false)):
					minted = mint(state, design, str(e.get("archetype", "")), str(p["id"]), node_id, rng, "downed " + str(p.get("name", "a rider")))
					if not minted.is_empty():
						minted["kills"] = 1
						out["lines"].append("%s put %s in the dirt and rode off. A name is going around." % [display_name(minted), str(p.get("name", "a rider"))])
					break
			if not minted.is_empty():
				break
		# b) else the last enemy standing (highest hp), grudge = whoever hurt it last
		if minted.is_empty():
			var best := {}
			for e in battle.get("enemies", []):
				if bool(e["alive"]) and not bool(e.get("rival", false)) and not bool(e.get("boss", false)):
					if best.is_empty() or int(e["hp"]) > int(best["hp"]):
						best = e
			if not best.is_empty():
				var grudge := str(best.get("lastHitBy", ""))
				if grudge == "" and not battle.get("players", []).is_empty():
					grudge = str(battle["players"][0]["id"])
				minted = mint(state, design, str(best.get("archetype", "")), grudge, node_id, rng, "survived the wipe")
				if not minted.is_empty():
					out["lines"].append("%s walked away from it. Folks will remember the name." % display_name(minted))
		if not minted.is_empty():
			out["minted"].append(minted)
	return out

# ---- spawning -------------------------------------------------------------------------
# Rivals near a node: last seen there or one trail away.
static func rivals_near(state: Dictionary, design: Dictionary, node_id: String) -> Array:
	var near: Array = []
	var adj := {}
	for e in design.get("world_edges", []):
		if str(e[0]) == node_id:
			adj[str(e[1])] = true
		elif str(e[1]) == node_id:
			adj[str(e[0])] = true
	for r in live(state):
		var ln := str(r.get("lastNode", ""))
		if ln == node_id or adj.has(ln):
			near.append(r)
	return near

# Pick who leads an ambush / bounty at this node. Returns a rival spec, or {}.
# Order: a live rival lurking nearby (rivalLeadsChance), else a fresh random
# named spawn at tier 2+ (namedSpawnChance x wanted multiplier) minted from
# the given template. Deterministic for a seeded rng.
static func pick_leader(state: Dictionary, design: Dictionary, node: Dictionary, template_id: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var cfg := _cfg(design)
	var near := rivals_near(state, design, str(node.get("id", "")))
	if not near.is_empty() and rng.randf() < float(cfg.get("rivalLeadsChance", 0.5)):
		var r: Dictionary = near[rng.randi() % near.size()]
		return spec_for(design, r)
	if int(node.get("tier", 1)) >= 2 and live(state).size() < max_live(design):
		var chance := float(cfg.get("namedSpawnChance", 0.25)) * wanted_mult(state)
		if rng.randf() < chance:
			var grudge := ""
			if not state.get("party", []).is_empty():
				grudge = str(state["party"][rng.randi() % state["party"].size()]["uid"])
			var r := mint(state, design, template_id, grudge, str(node.get("id", "")), rng, "named spawn")
			if not r.is_empty():
				return spec_for(design, r)
	return {}

# Saloon rumor lines about rivals, newest first.
static func rumors(state: Dictionary, design: Dictionary) -> Array:
	var out: Array = []
	var nodes := {}
	for n in design.get("world_nodes", []):
		nodes[str(n["id"])] = str(n.get("name", n["id"]))
	var rs: Array = all(state).duplicate()
	rs.reverse()
	for r in rs:
		if bool(r.get("alive", true)):
			out.append("\"%s was seen near %s. Rank %s. There's paper on them.\"" % [display_name(r), nodes.get(str(r.get("lastNode", "")), "the badlands"), stars(r)])
		else:
			out.append("\"They buried %s at %s. The posse that did it drinks free here.\"" % [display_name(r), nodes.get(str(r.get("diedNode", "")), "the badlands")])
	return out
