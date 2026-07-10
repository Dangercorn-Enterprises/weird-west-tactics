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
var on_cover_hit: Callable = Callable() # UI hook (q, r, chp_left) — cover chip/shatter

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
			# cover: current bonus (0..0.4). cover0: original (for FX/repair ref).
			# chp: cover durability. -1 = heavy/indestructible-by-bullets; >0 =
			# light, decays toward 0. heavy: material flag for explosive rules.
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0, "heavy": false})
		grid.append(row)
	for p in [[3, 2], [6, 7], [2, 6], [7, 3]]:
		grid[p[1]][p[0]]["h"] = 1
	for p in [[4, 4], [5, 5]]:
		grid[p[1]][p[0]]["h"] = 2
	# heavy cover (rock/wall): 0.4 bonus, bullet-immune (chp -1)
	for p in [[2, 3], [7, 6], [4, 7], [5, 2], [1, 5], [8, 4]]:
		var c: Dictionary = grid[p[1]][p[0]]
		c["cover"] = 0.4; c["cover0"] = 0.4; c["chp"] = -1; c["heavy"] = true
	# light cover (wagon/table/cactus): 0.2 bonus, decays over ~3 absorbed hits
	for p in [[3, 5], [6, 4], [2, 8], [7, 8], [4, 1], [5, 8]]:
		var c: Dictionary = grid[p[1]][p[0]]
		c["cover"] = 0.2; c["cover0"] = 0.2; c["chp"] = LIGHT_COVER_HP; c["heavy"] = false
	return grid

const LIGHT_COVER_HP := 3  # absorbed would-be-hits before light cover is gone
const HUNKER_BONUS := 0.20  # hunker adds to cover bonus (was a flat -20 to-hit)

# Bresenham supercover line between two tiles (exclusive of endpoints).
func _line_tiles(aq: int, ar: int, bq: int, br: int) -> Array:
	var tiles: Array = []
	var dq: int = absi(bq - aq)
	var dr: int = absi(br - ar)
	var sq: int = 1 if aq < bq else -1
	var sr: int = 1 if ar < br else -1
	var err: int = dq - dr
	var q: int = aq
	var r: int = ar
	while q != bq or r != br:
		var e2: int = 2 * err
		if e2 > -dr:
			err -= dr; q += sq
		if e2 < dq:
			err += dq; r += sr
		if q == bq and r == br:
			break
		tiles.append([q, r])
	return tiles

# Direct-fire line of sight: a full-height (h>=2) tile between shooter and target
# blocks the shot. High ground shooting DOWN sees over one intervening wall
# (skylined target below the muzzle line) — the "I have the high ground" rule.
func has_los(grid: Array, att: Dictionary, def: Dictionary) -> bool:
	var att_h: int = int(grid[att["r"]][att["q"]]["h"])
	var def_h: int = int(grid[def["r"]][def["q"]]["h"])
	for t in _line_tiles(int(att["q"]), int(att["r"]), int(def["q"]), int(def["r"])):
		if int(grid[t[1]][t[0]]["h"]) >= 2:
			# elevation advantage lets you see over a wall lower than your perch
			if att_h > def_h and int(grid[t[1]][t[0]]["h"]) <= att_h:
				continue
			return false
	return true

# Effective cover bonus (0..~0.6) the defender enjoys vs THIS attacker.
# High ground on the shooter halves it (sees over); a defender on high ground
# gets NONE (beacon — skylined); hunker adds to it. Directional flanking:
# point-blank (adjacent) attacks bypass cover in v1 (full edge-facing = v2).
func cover_bonus(grid: Array, att: Dictionary, def: Dictionary) -> float:
	if int(grid[def["r"]][def["q"]]["h"]) >= 1:
		return HUNKER_BONUS if def["status"]["hunker"] > 0 else 0.0  # beacon
	var cb: float = float(grid[def["r"]][def["q"]]["cover"])
	if dist(att, def) <= 1:
		cb = 0.0  # point-blank flank negates cover (v1 directional proxy)
	elif int(grid[att["r"]][att["q"]]["h"]) > int(grid[def["r"]][def["q"]]["h"]):
		cb *= 0.5  # shooting down over low cover — half, not erased (Njord fix)
	if def["status"]["hunker"] > 0:
		cb += HUNKER_BONUS
	return minf(cb, 0.60)  # cap so hunker can't fully erase the hit band

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
		# sworn shrine god fuels this unit's divine (JS parity: god: p.god || null)
		"god": p.get("god") if p.get("god") else null,
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

# Bare-target hit % — everything EXCEPT cover/hunker (those live in cover_bonus).
# Unclamped so the banded roll can compute the "would-hit-bare" ceiling.
func base_hit(grid: Array, att: Dictionary, def: Dictionary) -> float:
	var c: float = float(att["aim"])
	c += float(grid[att["r"]][att["q"]]["h"] - grid[def["r"]][def["q"]]["h"]) * 10.0
	c -= float(maxi(0, dist(att, def) - att["rng"])) * 15.0
	if att.get("jinx", 0):
		c -= 15.0
	if att["status"]["hex"] > 0:
		c -= 15.0
	return c

# Effective chance to hit the UNIT (through cover). Used by AI EV + hover preview.
# = base_hit - cover_bonus, clamped. Identical value to the pre-banded formula
# for the plain cover+hunker case, so unit win-rate parity is preserved.
func hit_chance(grid: Array, att: Dictionary, def: Dictionary, ignore_cover := false) -> int:
	var base: float = base_hit(grid, att, def)
	var cb: float = 0.0 if ignore_cover else cover_bonus(grid, att, def)
	return clampi(roundi(base - cb * 100.0), 5, 95)

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
	var ic: bool = opts.get("ignoreCover", false) or att.get("wIC", false)
	# Direct fire needs line of sight (h>=2 terrain blocks the shot). Abilities
	# can waive it via opts.no_los (e.g. supernatural / thrown effects).
	if not opts.get("no_los", false) and not has_los(b["grid"], att, def):
		return false
	# Banded single roll (BT cover model): one draw split into hit / strikes-cover
	# / miss. The HIT threshold == the old effective hit_chance and consumes the
	# same single rnd() as the former chance(), so unit-hit parity is exact; the
	# strikes-cover band is carved out of the former miss space.
	var hit_thru: int = hit_chance(b["grid"], att, def, ic)
	var bare: int = clampi(roundi(base_hit(b["grid"], att, def)), 5, 95)
	var r: float = rnd() * 100.0
	if r < float(hit_thru):
		# HIT UNIT — RNG order preserved: roll_dmg() then crit chance().
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
	elif not ic and r < float(bare):
		# STRIKES COVER — the would-have-hit-bare band. Cover eats the shot and
		# degrades (light only); the unit is untouched. Misses (r>=bare) touch
		# nothing, so accuracy-spam can never strip cover.
		strike_cover(b, def["q"], def["r"])
	return false

# Degrade cover on an absorbed hit. Heavy (chp<0) shrugs off small arms; light
# decays its bonus as its durability drops, so coverage weakens as it breaks.
func strike_cover(b: Dictionary, q: int, r: int) -> void:
	var cell: Dictionary = b["grid"][r][q]
	if int(cell["chp"]) <= 0:
		return  # heavy/indestructible or already gone
	cell["chp"] = int(cell["chp"]) - 1
	cell["cover"] = float(cell["cover0"]) * (float(cell["chp"]) / float(LIGHT_COVER_HP))
	if int(cell["chp"]) <= 0:
		cell["cover"] = 0.0
	if on_cover_hit.is_valid():
		on_cover_hit.call(q, r, int(cell["chp"]))

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
	# Explosives are the answer to cover: delete light in the radius, crack heavy.
	# This is the whole reason to lob (and why hunkering behind a wagon is finite).
	for dr in range(-1, 2):
		for dq in range(-1, 2):
			var q: int = int(center["q"]) + dq
			var r: int = int(center["r"]) + dr
			if q < 0 or r < 0 or q >= COLS or r >= ROWS:
				continue
			var cell: Dictionary = b["grid"][r][q]
			if float(cell["cover"]) <= 0.0:
				continue
			if bool(cell["heavy"]):
				# crack heavy down a tier rather than vaporize it
				cell["cover"] = maxf(0.0, float(cell["cover"]) - 0.2)
				if cell["cover"] <= 0.0:
					cell["heavy"] = false
			else:
				cell["cover"] = 0.0
				cell["chp"] = 0
			if on_cover_hit.is_valid():
				on_cover_hit.call(q, r, -1)  # -1 flags a blast (shatter FX)

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
				var cluster := 0
				for p in alive:
					if absi(p["q"] - tgt["q"]) <= 1 and absi(p["r"] - tgt["r"]) <= 1:
						cluster += 1
				var is_blast: bool = e.get("bomber", false) or (e.get("slammer", false) and cluster >= 2)
				# Direct fire needs LOS; blasts lob over terrain. No clear shot ->
				# fall through to reposition instead of wasting the turn on a wall.
				if is_blast or has_los(b["grid"], e, tgt):
					e["ap"] -= 2
					if is_blast:
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
	# No line of sight -> no shot: EV 0 so the policy never fires through a wall.
	# Only thrown/blast effects (no_los) are exempt — even a guaranteed Called
	# Shot needs to see the target.
	if not fx.get("no_los", false):
		if not has_los(grid, att, def):
			return 0.0
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

# ---- positional bot (sim measuring instrument, 2026-07-09) ----------------------
# The pre-v1 bot was positionally blind: it never sought LOS, high ground, or
# flanks, so Positioning v1 win rates understated human play (DESIGN_LOG caveat).
# These helpers price tiles with the REAL hit_chance, so height bonus, cover
# halving, beacon, and point-blank flanking are all valued without hand-tuned
# weights. Linear scans only (no sorts): sort stability differs between GDScript
# and JS, and the harness must stay draw-for-draw identical.

# Best basic-attack EV from tile (q,r): lowest-HP enemy visible and in range
# from there, priced by hit_chance. 0.0 when no shot exists from that tile.
func _best_shot_ev_from(b: Dictionary, p: Dictionary, q: int, r: int) -> float:
	var sq: int = p["q"]
	var sr: int = p["r"]
	p["q"] = q
	p["r"] = r
	var focus: Dictionary = {}
	for e in b["enemies"]:
		if not e["alive"]:
			continue
		if dist(p, e) > int(p["rng"]) + 1:
			continue
		if not has_los(b["grid"], p, e):
			continue
		if focus.is_empty() or int(e["hp"]) < int(focus["hp"]):
			focus = e
	var ev := 0.0
	if not focus.is_empty():
		ev = float(hit_chance(b["grid"], p, focus, p.get("wIC", false))) / 100.0 * _avg_roll(p, 1.0)
	p["q"] = sq
	p["r"] = sr
	return ev

# Tile cover for the defensive tiebreak — beacon-aware: high tiles protect nothing.
func _tile_cov(grid: Array, q: int, r: int) -> float:
	return 0.0 if int(grid[r][q]["h"]) >= 1 else float(grid[r][q]["cover"])

# Move to the best SHOT tile (EV>0 required) reachable while keeping >=2 AP to
# fire. Score = shot EV + 2.0*cover (cover ~tiebreak: 0.4 heavy ≈ a 10%-hit
# swing on a typical gun). Baseline = current tile's score when it has a shot,
# else 0 — any reachable shot beats standing blind, and the bot never cover-
# shuffles without gaining a shot. min_gain gates Rule B so it won't move for
# crumbs. Returns true if it moved (consumes move AP, ticks bleed).
func positional_move(b: Dictionary, p: Dictionary, min_gain: float) -> bool:
	var rc := reach(b["grid"], b["units"], p)
	var cur_ev := _best_shot_ev_from(b, p, int(p["q"]), int(p["r"]))
	var cur_score: float = cur_ev + 2.0 * _tile_cov(b["grid"], int(p["q"]), int(p["r"])) if cur_ev > 0.0 else 0.0
	var best_q := -1
	var best_r := -1
	var best_cost := 0
	var best_score := cur_score
	for key in rc.keys():
		var cost: int = int(rc[key])
		if int(p["ap"]) - cost < 2:
			continue
		var parts: PackedStringArray = key.split(",")
		var q := int(parts[0])
		var r := int(parts[1])
		var ev := _best_shot_ev_from(b, p, q, r)
		if ev <= 0.0:
			continue
		var s: float = ev + 2.0 * _tile_cov(b["grid"], q, r)
		if s > best_score:
			best_score = s
			best_q = q
			best_r = r
			best_cost = cost
	if best_q >= 0 and best_score > cur_score + min_gain:
		p["ap"] -= best_cost
		p["q"] = best_q
		p["r"] = best_r
		if int(p["status"]["bleed"]) > 0:
			apply_damage(b, p, STATUS_DOT["bleed"])
			p["status"]["bleed"] -= 1
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
			# 2) find a firing position (positional bot): a target only counts when
			# it's VISIBLE. No visible target -> hunt a reachable shot tile (Rule A);
			# none reachable -> close distance the old way.
			var in_range: Array = live_enemies.filter(func(e): return dist(p, e) <= int(p["rng"]) + 1)
			var visible: Array = in_range.filter(func(e): return has_los(b["grid"], p, e))
			if visible.is_empty():
				if positional_move(b, p, 0.0):
					continue
				var nearest := live_enemies.duplicate()
				nearest.sort_custom(func(a, c): return dist(p, a) < dist(p, c))
				if int(p["ap"]) > 0 and move_unit_toward(b, p, nearest[0]):
					continue
				break
			# 3) divine: once per fight on the biggest eligible threat. Blast divines
			# lob (any in-range threat); single-target divines need LOS or the once-
			# per-fight ult whiffs on do_fire's gate. Linear scan, no sorts.
			if p.get("divine") and not p.get("divineUsed", false) and int(p.get("divineFavor", 0)) >= 1:
				var pool: Array = in_range if DIVINE_BLAST.has(p["divine"]) else visible
				var threat: Dictionary = {}
				for e in pool:
					if threat.is_empty() or int(e["hp"]) > int(threat["hp"]):
						threat = e
				if not threat.is_empty() and (threat.get("boss", false) or int(threat["hp"]) >= 18):
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
			# 4) focus the lowest-HP VISIBLE target (linear scan). Rule B: when the
			# shot is poor (<50%) and AP allows move+shoot, take a better perch
			# first — high ground / flank / decayed-cover angles all price in via
			# hit_chance inside positional_move.
			var focus: Dictionary = {}
			for e in visible:
				if focus.is_empty() or int(e["hp"]) < int(focus["hp"]):
					focus = e
			if int(p["ap"]) >= 3 and hit_chance(b["grid"], p, focus, p.get("wIC", false)) < 50:
				if positional_move(b, p, 0.15 * _avg_roll(p, 1.0)):
					continue
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
		# 2b (hunker ends turn): a competent player banks leftover AP as a brace —
		# the activation was over anyway, so this is strictly-correct defense and
		# finally prices hunker into the baselines.
		if p["alive"] and int(p["ap"]) >= 1:
			p["status"]["hunker"] = maxi(int(p["status"]["hunker"]), 2)
			p["ap"] = 0
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
