# =============================================================================
# DUSTFALL — COMBAT CORE (Godot port, v1.3)
# Faithful GDScript port of the battle math in tools/balance_harness.js, which
# itself mirrors the shipped web game (src/scene_battle.js). The parity test
# (tests/parity_test.gd) proves this port produces the same encounter win
# rates as the Node harness — the balance work carries over exactly.
# Pure logic: no nodes, no rendering. Units are Dictionaries, same field names
# as the JS so the two codebases stay diffable.
# =============================================================================
class_name CombatCore
extends RefCounted

const COLS := 10
const ROWS := 10
const SPAWNS := [[8, 8], [9, 6], [8, 2], [9, 3], [7, 9], [9, 8], [8, 5]]

# per-archetype kits (mirror of partyToUnit's maps)
const ABIL := {
	"gunslinger": "Fan the Hammer", "hexslinger": "Hex Bolt",
	"tinkerer": "Ashfall Grenade", "preacher": "Lay on Hands",
	"lawdog": "Called Shot", "drifter": "Aimed Shot",
}
const ABIL2 := {
	"gunslinger": "Gut Shot", "hexslinger": "Soul Drain",
	"tinkerer": "Arc Shock", "preacher": "Holy Smite",
	"lawdog": "Pistol Whip", "drifter": "Both Barrels",
}
const DIVINE := {
	"gunslinger": "Coyote's Gambit", "hexslinger": "Samedi's Embrace",
	"tinkerer": "Vulcan's Forgefire", "preacher": "Perun's Thunder",
	"lawdog": "Iron Verdict", "drifter": "Anansi's Trick",
}
# ability model (mirror of ABIL_FX)
const ABIL_FX := {
	"Fan the Hammer": {"cost": 3, "kind": "multi", "shots": 3, "aimMod": -10},
	"Gut Shot": {"cost": 2, "kind": "atk", "mult": 1.8, "status": "bleed", "statusN": 3},
	"Both Barrels": {"cost": 2, "kind": "atk", "mult": 1.8, "status": "bleed", "statusN": 3},
	"Pistol Whip": {"cost": 2, "kind": "atk", "mult": 1.8},
	"Holy Smite": {"cost": 2, "kind": "atk", "mult": 1.6},
	"Arc Shock": {"cost": 2, "kind": "atk", "mult": 1.4, "ic": true},
	"Hex Bolt": {"cost": 2, "kind": "atk", "ic": true, "status": "hex", "statusN": 2},
	"Called Shot": {"cost": 3, "kind": "atk", "guaranteed": true, "status": "marked", "statusN": 2},
	"Aimed Shot": {"cost": 2, "kind": "atk", "mult": 1.5},
	"Ashfall Grenade": {"cost": 2, "kind": "blast"},
	"Lay on Hands": {"cost": 2, "kind": "heal", "any": true},
	"Soul Drain": {"cost": 2, "kind": "heal", "self": true},
}
const DIVINE_BLAST := ["Vulcan's Forgefire", "Perun's Thunder"]

var design: Dictionary = {} # design.json (enemies/weapons/armor/mods/pregen...)
var favor := 1 # divine favor snapshot per unit (New Game seeds 1)
var scale_enabled := true
var on_damage: Callable = Callable() # optional UI hook (dmg floaters/flash)

# ---- seeded RNG: exact mulberry32 port so runs are reproducible -------------
var _rng_state: int = 0

static func _to_i32(v: int) -> int:
	v = v & 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v

static func _imul(a: int, b: int) -> int:
	return _to_i32((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF))

static func _ushr(v: int, n: int) -> int:
	return (v & 0xFFFFFFFF) >> n

func seed_rng(s: int) -> void:
	_rng_state = _to_i32(s)

func rnd() -> float:
	_rng_state = _to_i32(_rng_state + 0x6D2B79F5)
	var a := _rng_state
	var t := _imul(a ^ _ushr(a, 15), _to_i32(1 | a))
	t = _to_i32(_to_i32(t + _imul(t ^ _ushr(t, 7), _to_i32(61 | t))) ^ t)
	return float(_ushr(t ^ _ushr(t, 14), 0)) / 4294967296.0

func randint(lo: int, hi: int) -> int: # inclusive, mirror of JS randint
	return lo + int(rnd() * float(hi - lo + 1))

func chance(pct: float) -> bool:
	return rnd() * 100.0 < pct

# ---- grid (canonical mesa map, mirror of harness buildGrid) ------------------
func build_grid() -> Array:
	var grid: Array = []
	for r in ROWS:
		var row: Array = []
		for q in COLS:
			row.append({"h": 0, "cover": 0.0})
		grid.append(row)
	for p in [[3, 2], [6, 7], [2, 6], [7, 3]]:
		grid[p[1]][p[0]]["h"] = 1
	for p in [[4, 4], [5, 5]]:
		grid[p[1]][p[0]]["h"] = 2
	for p in [[2, 3], [7, 6], [4, 7], [5, 2], [1, 5], [8, 4]]:
		grid[p[1]][p[0]]["cover"] = 0.4
	for p in [[3, 5], [6, 4], [2, 8], [7, 8], [4, 1], [5, 8]]:
		grid[p[1]][p[0]]["cover"] = 0.2
	return grid

# ---- unit construction --------------------------------------------------------
func mk_unit(o: Dictionary) -> Dictionary:
	o["maxHp"] = o["hp"]
	o["alive"] = true
	o["maxAp"] = 3 + int(float(o["quick"]) / 4.0)
	o["ap"] = o["maxAp"]
	o["jinx"] = 0
	o["status"] = {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}
	return o

func _find(arr: Array, id: String) -> Dictionary:
	for it in arr:
		if it.get("id", "") == id:
			return it
	return {}

func party_to_unit(p: Dictionary, i: int) -> Dictionary:
	var arch := _find(design["archetypes"], p.get("archetype", ""))
	var gear: Dictionary = p.get("gear", {})
	var gw := _find(design["weapons"], gear.get("weapon", "") if gear.get("weapon") else "")
	var ga := _find(design["armor"], gear.get("armor", "") if gear.get("armor") else "")
	var w: Dictionary
	if not gw.is_empty():
		w = {"damage": gw["dmg"], "range": gw["range"], "accuracy": gw["accuracy"]}
	elif not arch.is_empty() and arch.get("weapons", []).size() > 0:
		w = arch["weapons"][0]
	else:
		w = {"damage": [4, 8], "range": 5, "accuracy": 72}
	var s: Dictionary = p.get("stats", {})
	var vigor: int = s.get("vigor", 5)
	var quick: int = s.get("quickness", 5)
	var strn: int = s.get("strength", 4)
	var deft: int = s.get("deftness", 5)
	var aid: String = p.get("archetype", "")
	var u := mk_unit({
		"id": p.get("uid", "p%d" % i),
		"name": p.get("name", "Rider"),
		"archetype": aid,
		"side": "p",
		"q": 1,
		"r": [1, 4, 7, 2][i] if i < 4 else 1,
		"hp": max(1, 10 + vigor * 2 - int(p.get("hpDamage", 0))),
		"str": strn,
		"quick": quick,
		"aim": int(w["accuracy"]) + (deft - 5) * 2,
		"rng": int(w["range"]),
		"wmin": int(w["damage"][0]),
		"wmax": int(w["damage"][1]),
		"abilities": [ABIL.get(aid), ABIL2.get(aid)].filter(func(x): return x != null),
		"divine": DIVINE.get(aid),
		"divineFavor": favor,
		"divineUsed": false,
		"wIC": not gw.is_empty() and gw.get("ignoreCover", false),
		"armorDef": int(ga.get("def", 0)) if not ga.is_empty() else 0,
		"boss": false,
	})
	if not ga.is_empty() and int(ga.get("speed", 0)) != 0:
		u["maxAp"] = max(2, u["maxAp"] + int(ga["speed"]))
		u["ap"] = u["maxAp"]
	var gm := _find(design["weapon_mods"], gear.get("mod", "") if gear.get("mod") else "")
	if not gm.is_empty():
		var fx: Dictionary = gm.get("effect", {})
		u["aim"] += int(fx.get("accuracy", 0))
		u["rng"] = max(1, u["rng"] + int(fx.get("range", 0)))
		u["wmin"] = max(1, u["wmin"] + int(fx.get("wmin", 0)))
		u["wmax"] = max(u["wmin"], u["wmax"] + int(fx.get("wmax", 0)))
	return u

func enemy_to_unit(spec: Dictionary, i: int) -> Dictionary:
	var beh: String = spec.get("behavior", "")
	return mk_unit({
		"id": "e%d" % i,
		"archetype": spec.get("id", ""),
		"name": spec.get("name", ""),
		"side": "e",
		"q": 8,
		"r": 1,
		"hp": int(spec["hp"]),
		"str": int(spec["str"]),
		"quick": int(spec["quick"]),
		"aim": int(spec["aim"]) + (8 if beh == "sentry" else 0), # braced sentries
		"rng": int(spec["rng"]),
		"wmin": int(spec["wmin"]),
		"wmax": int(spec["wmax"]),
		"hexer": beh == "hexer",
		"blinker": beh == "teleport",
		"bomber": beh == "bomber",
		"slammer": beh == "tank",
		"sentry": beh == "sentry",
		"zealot": beh == "zealot",
		"swarmer": beh == "swarm",
		"coverer": beh == "cover",
		"flanker": beh == "flank",
		"berserk": false,
		"boss": spec.get("boss", false),
		"divine": null,
		"abilities": [],
	})

# ---- combat math (verbatim mirror) -------------------------------------------
static func dist(a: Dictionary, b: Dictionary) -> int:
	return absi(a["q"] - b["q"]) + absi(a["r"] - b["r"])

func hit_chance(grid: Array, att: Dictionary, def: Dictionary, ignore_cover := false) -> int:
	var c: float = float(att["aim"])
	var cover: float = 0.0 if ignore_cover else float(grid[def["r"]][def["q"]]["cover"])
	c -= cover * 100.0
	c += float(grid[att["r"]][att["q"]]["h"] - grid[def["r"]][def["q"]]["h"]) * 10.0
	c -= float(maxi(0, dist(att, def) - att["rng"])) * 15.0
	if att.get("jinx", 0):
		c -= 15.0
	if att["status"]["hex"] > 0:
		c -= 15.0
	if def["status"]["hunker"] > 0:
		c -= 20.0
	return clampi(roundi(c), 5, 95)

func roll_dmg(att: Dictionary) -> int:
	return randint(att["wmin"], att["wmax"]) + int(float(att["str"]) / 3.0)

# BFS movement reachability (mirror of reach())
func reach(grid: Array, units: Array, u: Dictionary) -> Dictionary:
	var res := {}
	var start := "%d,%d" % [u["q"], u["r"]]
	res[start] = 0
	var fr := [[u["q"], u["r"], 0]]
	while fr.size() > 0:
		var cur: Array = fr.pop_front()
		var q: int = cur[0]
		var r: int = cur[1]
		var c: int = cur[2]
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nq: int = q + d[0]
			var nr: int = r + d[1]
			if nq < 0 or nr < 0 or nq >= COLS or nr >= ROWS:
				continue
			var cell: Dictionary = grid[nr][nq]
			if int(cell["h"]) >= 2:
				continue
			var occupied := false
			for x in units:
				if x["alive"] and x != u and x["q"] == nq and x["r"] == nr:
					occupied = true
					break
			if occupied:
				continue
			var step := 1 + (1 if int(cell["h"]) > int(grid[r][q]["h"]) else 0)
			var nc := c + step
			var key := "%d,%d" % [nq, nr]
			if nc <= int(u["ap"]) and (not res.has(key) or nc < int(res[key])):
				res[key] = nc
				fr.append([nq, nr, nc])
	res.erase(start)
	return res

# ---- damage / statuses / boss phase -------------------------------------------
func apply_damage(b: Dictionary, def: Dictionary, dmg: int, crit := false) -> void:
	def["hp"] -= dmg
	if on_damage.is_valid():
		on_damage.call(def, dmg, crit)
	if def["hp"] <= 0:
		def["alive"] = false
		if def["side"] == "e":
			b["kills"] += 1
		else:
			b["playerDeaths"] += 1
	else:
		check_boss_phase(b, def)

func do_fire(b: Dictionary, att: Dictionary, def: Dictionary, opts := {}) -> bool:
	var ch := hit_chance(b["grid"], att, def, opts.get("ignoreCover", false) or att.get("wIC", false))
	if chance(float(ch)):
		# flat 10% crit at 1.5x, both sides (Pass 19). RNG order preserved
		# exactly: roll_dmg() first, then the crit chance() — matching the
		# original inline expression so win-rate parity is untouched.
		var base_dmg := roll_dmg(att)
		var is_crit := chance(10.0)
		var dmg := roundi(float(base_dmg) * float(opts.get("mult", 1.0)) * (1.5 if is_crit else 1.0))
		if def["status"]["marked"] > 0:
			dmg = roundi(float(dmg) * 1.3)
		if int(def.get("armorDef", 0)) > 0:
			dmg = maxi(1, dmg - int(def["armorDef"]))
		apply_damage(b, def, dmg, is_crit)
		if opts.get("status") and def["alive"]:
			var k: String = opts["status"]
			def["status"][k] = maxi(int(def["status"].get(k, 0)), int(opts.get("statusN", 2)))
		if att.get("hexer", false) and def["alive"]:
			def["status"]["hex"] = maxi(int(def["status"]["hex"]), 2)
		return true
	return false

const STATUS_DOT := {"burn": 3, "bleed": 2}

func tick_status(b: Dictionary, u: Dictionary) -> void:
	if not u["alive"]:
		return
	if u["status"]["burn"] > 0:
		apply_damage(b, u, STATUS_DOT["burn"])
		u["status"]["burn"] -= 1
	for k in ["hex", "marked", "hunker"]:
		if u["status"][k] > 0:
			u["status"][k] -= 1

func do_blast(b: Dictionary, center: Dictionary) -> void:
	for u in b["units"]:
		if u["alive"] and absi(u["q"] - center["q"]) <= 1 and absi(u["r"] - center["r"]) <= 1:
			var dmg := randint(4, 7)
			if int(u.get("armorDef", 0)) > 0:
				dmg = maxi(1, dmg - int(u["armorDef"]))
			apply_damage(b, u, dmg)

func trigger_boss_phase(b: Dictionary, boss: Dictionary) -> void:
	boss["enraged"] = true
	boss["str"] += 3
	boss["aim"] += 12
	boss["wmax"] += 4
	boss["quick"] += 2
	boss["hp"] = mini(int(boss["maxHp"]), int(boss["hp"]) + roundi(float(boss["maxHp"]) * 0.25))
	var tmpl := _find(design["enemies"], "walkin_dead")
	if not tmpl.is_empty():
		var taken := {}
		for u in b["units"]:
			if u["alive"]:
				taken["%d,%d" % [u["q"], u["r"]]] = true
		var added := 0
		for sp in SPAWNS:
			if added >= 2:
				break
			var key := "%d,%d" % [sp[0], sp[1]]
			if taken.has(key):
				continue
			var m := enemy_to_unit(tmpl, 90 + added)
			m["name"] = "Risen Dead"
			m["q"] = sp[0]
			m["r"] = sp[1]
			b["enemies"].append(m)
			b["units"].append(m)
			taken[key] = true
			added += 1

func check_boss_phase(b: Dictionary, u: Dictionary) -> void:
	if u.get("boss", false) and u["alive"] and not u.get("enraged", false) and float(u["hp"]) <= float(u["maxHp"]) / 2.0:
		trigger_boss_phase(b, u)

# ---- movement -----------------------------------------------------------------
func move_unit_toward(b: Dictionary, u: Dictionary, tgt: Dictionary) -> bool:
	var rc := reach(b["grid"], b["units"], u)
	var cover_w := 1.0
	if u["side"] == "e":
		if u.get("coverer", false):
			cover_w = 2.5
		elif u.get("berserk", false) or u.get("swarmer", false):
			cover_w = 0.0
	var best := []
	var best_score := float(dist(u, tgt)) * 2.0 - cover_w * float(b["grid"][u["r"]][u["q"]]["cover"])
	for key in rc.keys():
		var parts: PackedStringArray = key.split(",")
		var q := int(parts[0])
		var r := int(parts[1])
		var d := absi(q - tgt["q"]) + absi(r - tgt["r"])
		var score := float(d) * 2.0 - cover_w * float(b["grid"][r][q]["cover"])
		if score < best_score:
			best_score = score
			best = [q, r]
	if best.size() == 2:
		u["ap"] -= int(rc["%d,%d" % [best[0], best[1]]])
		u["q"] = best[0]
		u["r"] = best[1]
		if u["status"]["bleed"] > 0:
			apply_damage(b, u, STATUS_DOT["bleed"])
			u["status"]["bleed"] -= 1
		return true
	return false

# ---- ENEMY phase (mirror of enemyPhase) ----------------------------------------
func enemy_phase(b: Dictionary) -> void:
	var queue: Array = b["enemies"].filter(func(e): return e["alive"])
	queue.sort_custom(func(a, c): return int(a["quick"]) > int(c["quick"]))
	for e in queue:
		if not e["alive"]:
			continue
		e["ap"] = e["maxAp"]
		tick_status(b, e)
		if not e["alive"]:
			continue
		if int(e["status"].get("stun", 0)) > 0: # Perun's stun
			e["status"]["stun"] -= 1
			continue
		var guard := 0
		while guard < 12:
			guard += 1
			var alive: Array = b["players"].filter(func(p): return p["alive"])
			if alive.is_empty():
				return
			# Anansi's confusion: lash out at whoever's nearest, any side
			if int(e["status"].get("conf", 0)) > 0 and int(e["ap"]) >= 2:
				e["status"]["conf"] -= 1
				var others: Array = b["units"].filter(func(u): return u["alive"] and u != e)
				others.sort_custom(func(a, c): return dist(e, a) < dist(e, c))
				if others.size() > 0 and dist(e, others[0]) <= int(e["rng"]) + 1:
					e["ap"] -= 2
					do_fire(b, e, others[0])
					continue
			# zealots berserk once bloodied
			if e.get("zealot", false) and not e.get("berserk", false) and float(e["hp"]) <= float(e["maxHp"]) / 2.0:
				e["berserk"] = true
				e["aim"] += 10
				e["wmax"] += 2
			# behavior-driven target selection
			var tgt: Dictionary
			if e.get("flanker", false):
				var sorted_hp := alive.duplicate()
				sorted_hp.sort_custom(func(a, c): return int(a["hp"]) < int(c["hp"]))
				tgt = sorted_hp[0]
			elif e.get("swarmer", false):
				var sorted_d := alive.duplicate()
				sorted_d.sort_custom(func(a, c): return dist(e, a) < dist(e, c))
				tgt = sorted_d[0]
			else:
				var in_rng: Array = alive.filter(func(p): return dist(e, p) <= int(e["rng"]) + 1)
				if in_rng.size() > 0:
					in_rng.sort_custom(func(a, c): return int(a["hp"]) < int(c["hp"]))
					tgt = in_rng[0]
				else:
					var sorted_d2 := alive.duplicate()
					sorted_d2.sort_custom(func(a, c): return dist(e, a) < dist(e, c))
					tgt = sorted_d2[0]
			if tgt.is_empty():
				break
			if e.get("sentry", false) and dist(e, tgt) > int(e["rng"]) + 1:
				break # emplacements never chase
			if dist(e, tgt) <= int(e["rng"]) + 1 and int(e["ap"]) >= 2:
				e["ap"] -= 2
				var cluster := 0
				for p in alive:
					if absi(p["q"] - tgt["q"]) <= 1 and absi(p["r"] - tgt["r"]) <= 1:
						cluster += 1
				if e.get("bomber", false) or (e.get("slammer", false) and cluster >= 2):
					do_blast(b, tgt)
				else:
					do_fire(b, e, tgt)
				var any_alive := false
				for p in b["players"]:
					if p["alive"]:
						any_alive = true
						break
				if not any_alive:
					return
				continue
			if e.get("blinker", false) and int(e["ap"]) >= 1 and dist(e, tgt) > int(e["rng"]):
				var spots: Array = []
				for r in ROWS:
					for q in COLS:
						if int(b["grid"][r][q]["h"]) >= 2:
							continue
						var occ := false
						for x in b["units"]:
							if x["alive"] and x["q"] == q and x["r"] == r:
								occ = true
								break
						if occ:
							continue
						var d := absi(q - tgt["q"]) + absi(r - tgt["r"])
						if d >= 1 and d <= int(e["rng"]):
							spots.append([q, r])
				if spots.size() > 0:
					var s: Array = spots[int(rnd() * spots.size())]
					e["q"] = s[0]
					e["r"] = s[1]
					e["ap"] -= 1
					continue
			if int(e["ap"]) > 0 and move_unit_toward(b, e, tgt):
				continue
			break

# ---- PLAYER phase (ability-aware policy, mirror of playerPhaseAbilities) -------
func _avg_roll(u: Dictionary, mult: float) -> float:
	return (float(u["wmin"] + u["wmax"]) / 2.0 + float(int(float(u["str"]) / 3.0))) * mult

func _exp_atk_dmg(grid: Array, att: Dictionary, def: Dictionary, fx: Dictionary) -> float:
	var saved: int = att["aim"]
	if fx.has("aimMod"):
		att["aim"] += int(fx["aimMod"])
	var ch := 95 if fx.get("guaranteed", false) else hit_chance(grid, att, def, fx.get("ic", false))
	att["aim"] = saved
	return float(fx.get("shots", 1)) * float(ch) / 100.0 * _avg_roll(att, float(fx.get("mult", 1.0)))

func _is_healer(p: Dictionary) -> bool:
	for a in p.get("abilities", []):
		if a == "Lay on Hands" or a == "Soul Drain":
			return true
	return false

func _exec_atk(b: Dictionary, p: Dictionary, def: Dictionary, fx: Dictionary) -> void:
	var st := {"status": fx.get("status"), "statusN": fx.get("statusN")}
	if fx.get("kind") == "multi":
		var sv: int = p["aim"]
		p["aim"] += int(fx.get("aimMod", 0))
		for i in int(fx.get("shots", 1)):
			if not def["alive"]:
				break
			do_fire(b, p, def, st)
		p["aim"] = sv
	elif fx.get("guaranteed", false):
		var sv2: int = p["aim"]
		p["aim"] = 999
		do_fire(b, p, def, st)
		p["aim"] = sv2
	elif fx.get("kind") == "blast":
		do_blast(b, def)
	else:
		do_fire(b, p, def, {
			"mult": fx.get("mult", 1.0), "ignoreCover": fx.get("ic", false),
			"status": fx.get("status"), "statusN": fx.get("statusN"),
		})

func player_phase(b: Dictionary) -> void:
	var order: Array = b["players"].filter(func(p): return p["alive"])
	order.sort_custom(func(a, c): return int(a["quick"]) > int(c["quick"]))
	for p in order:
		if not p["alive"]:
			continue
		p["ap"] = p["maxAp"]
		tick_status(b, p)
		if not p["alive"]:
			continue
		var guard := 0
		while guard < 12 and int(p["ap"]) >= 2:
			guard += 1
			var live_enemies: Array = b["enemies"].filter(func(e): return e["alive"])
			if live_enemies.is_empty():
				break
			# 1) heal a badly hurt ally/self
			if _is_healer(p):
				var self_only: bool = p.get("abilities", []).has("Soul Drain")
				var pool: Array = [p] if self_only else b["players"].filter(func(a): return a["alive"])
				var hurt: Array = pool.filter(func(a): return float(a["hp"]) / float(a["maxHp"]) < 0.4)
				hurt.sort_custom(func(a, c): return float(a["hp"]) / float(a["maxHp"]) < float(c["hp"]) / float(c["maxHp"]))
				if hurt.size() > 0:
					hurt[0]["hp"] = mini(int(hurt[0]["maxHp"]), int(hurt[0]["hp"]) + randint(6, 10))
					p["ap"] -= 2
					continue
			# 2) move into range if nothing is in range
			var in_range: Array = live_enemies.filter(func(e): return dist(p, e) <= int(p["rng"]) + 1)
			if in_range.is_empty():
				var nearest := live_enemies.duplicate()
				nearest.sort_custom(func(a, c): return dist(p, a) < dist(p, c))
				if int(p["ap"]) > 0 and move_unit_toward(b, p, nearest[0]):
					continue
				break
			# 3) divine: once per fight on the biggest in-range threat
			if p.get("divine") and not p.get("divineUsed", false) and int(p.get("divineFavor", 0)) >= 1:
				var threats := in_range.duplicate()
				threats.sort_custom(func(a, c): return int(a["hp"]) > int(c["hp"]))
				var threat: Dictionary = threats[0]
				if threat.get("boss", false) or int(threat["hp"]) >= 18:
					var emp: bool = int(p["divineFavor"]) >= 3
					p["divineFavor"] = maxi(0, int(p["divineFavor"]) - 1)
					p["divineUsed"] = true
					if DIVINE_BLAST.has(p["divine"]):
						do_blast(b, threat)
						do_blast(b, threat)
						if emp:
							do_blast(b, threat)
						# Pass 11: Vulcan burns, Perun stuns the survivors
						var rk: String = "burn" if p["divine"] == "Vulcan's Forgefire" else "stun"
						for x in b["enemies"]:
							if x["alive"] and absi(x["q"] - threat["q"]) <= 1 and absi(x["r"] - threat["r"]) <= 1:
								x["status"][rk] = maxi(int(x["status"].get(rk, 0)), 2 if rk == "burn" else 1)
					else:
						var sv: int = p["aim"]
						p["aim"] = 999
						do_fire(b, p, threat, {
							"ignoreCover": true, "mult": 3.5 if emp else 2.5,
							"status": "marked" if emp else null, "statusN": 2,
						})
						p["aim"] = sv
						if p["divine"] == "Samedi's Embrace":
							p["hp"] = mini(int(p["maxHp"]), int(p["hp"]) + (9 if emp else 6))
						elif p["divine"] == "Coyote's Gambit":
							p["status"]["hunker"] = maxi(int(p["status"]["hunker"]), 2)
						elif p["divine"] == "Iron Verdict" and threat["alive"]:
							threat["status"]["marked"] = maxi(int(threat["status"]["marked"]), 2)
						elif p["divine"] == "Anansi's Trick" and threat["alive"]:
							threat["status"]["conf"] = maxi(int(threat["status"].get("conf", 0)), 1)
					p["ap"] = 0
					continue
			# 4) best damage-per-AP action on the lowest-HP focus target
			var focus_list := in_range.duplicate()
			focus_list.sort_custom(func(a, c): return int(a["hp"]) < int(c["hp"]))
			var focus: Dictionary = focus_list[0]
			var opts: Array = [{"cost": 2, "kind": "atk", "mult": 1.0}]
			for aname in p.get("abilities", []):
				var fx: Dictionary = ABIL_FX.get(aname, {})
				if not fx.is_empty() and fx.get("kind") != "heal" and int(fx["cost"]) <= int(p["ap"]):
					opts.append(fx)
			var aff: Array = opts.filter(func(o): return int(o["cost"]) <= int(p["ap"]))
			aff.sort_custom(func(a, c):
				return _exp_atk_dmg(b["grid"], p, focus, a) / float(a["cost"]) > _exp_atk_dmg(b["grid"], p, focus, c) / float(c["cost"]))
			var choice: Dictionary = aff[0]
			_exec_atk(b, p, focus, choice)
			p["ap"] -= int(choice["cost"])
			var any_e := false
			for e in b["enemies"]:
				if e["alive"]:
					any_e = true
					break
			if not any_e:
				return
	for p in b["players"]:
		p["jinx"] = 0

# ---- encounter scaling (mirror of DF.scaleEncounter) ---------------------------
func scale_encounter(specs: Array, party_size: int) -> Array:
	var hp_f: float = clampf(0.6 + 0.25 * float(party_size - 2), 0.6, 1.35)
	var dmg_f: float = clampf(0.8 + 0.1 * float(party_size - 2), 0.8, 1.2)
	if hp_f == 1.0 and dmg_f == 1.0:
		return specs
	var out: Array = []
	for s in specs:
		var c: Dictionary = s.duplicate()
		c["hp"] = maxi(4, roundi(float(s["hp"]) * hp_f))
		c["wmin"] = maxi(1, roundi(float(s["wmin"]) * dmg_f))
		c["wmax"] = maxi(2, roundi(float(s["wmax"]) * dmg_f))
		out.append(c)
	return out

# ---- one battle / aggregate ----------------------------------------------------
func run_battle(party_specs: Array, enemy_specs: Array, max_rounds: int) -> Dictionary:
	var grid := build_grid()
	var players: Array = []
	for i in mini(4, party_specs.size()):
		players.append(party_to_unit(party_specs[i], i))
	var enemies: Array = []
	for i in enemy_specs.size():
		var u := enemy_to_unit(enemy_specs[i], i)
		var sp: Array = SPAWNS[i] if i < SPAWNS.size() else SPAWNS[i % SPAWNS.size()]
		u["q"] = sp[0]
		u["r"] = sp[1]
		enemies.append(u)
	var b := {
		"grid": grid, "players": players, "enemies": enemies,
		"units": players + enemies, "kills": 0, "playerDeaths": 0,
	}
	var round_n := 0
	var timed_out := false
	while round_n < max_rounds:
		round_n += 1
		player_phase(b)
		if b["enemies"].filter(func(e): return e["alive"]).is_empty():
			break
		enemy_phase(b)
		if b["players"].filter(func(p): return p["alive"]).is_empty():
			break
		if round_n == max_rounds:
			timed_out = true
	var win: bool = (
		not b["players"].filter(func(p): return p["alive"]).is_empty()
		and b["enemies"].filter(func(e): return e["alive"]).is_empty()
	)
	return {"win": win, "rounds": round_n, "timedOut": timed_out}

func eval_encounter(party: Array, enemy_ids: Array, runs: int) -> Dictionary:
	var raw: Array = []
	for id in enemy_ids:
		var spec := _find(design["enemies"], id)
		if not spec.is_empty():
			raw.append(spec)
	var specs := scale_encounter(raw, party.size()) if scale_enabled else raw
	var wins := 0
	for i in runs:
		if run_battle(party, specs, 60)["win"]:
			wins += 1
	return {"winRate": float(wins) / float(runs), "n": runs}

func mk_party(ids: Array) -> Array:
	var out: Array = []
	for i in ids.size():
		var aid: String = ids[i]
		var pg: Dictionary = design["pregen"].get(aid, {})
		out.append({
			"uid": "p%d" % i, "archetype": aid,
			"name": pg.get("name", aid),
			"stats": pg.get("stats", {}).duplicate(),
			"hpDamage": 0,
		})
	return out
