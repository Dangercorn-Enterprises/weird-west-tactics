# =============================================================================
# DUSTFALL — GAME STATE (autoload singleton)
# Campaign state, save/load, and battle-result bookkeeping. Mirrors the web
# game's DF.state shape (src/engine.js) so saves stay conceptually portable.
# =============================================================================
extends Node

const SAVE_PATH := "user://save.json"

var design: Dictionary = {}
var sprites_data: Dictionary = {}
var state: Dictionary = {}
# handoff: worldmap/town set this before switching to the battle scene
var pending_battle: Dictionary = {}
var last_result: Dictionary = {}

func _ready() -> void:
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	design = JSON.parse_string(f.get_as_text())
	var sf := FileAccess.open("res://data/sprites.json", FileAccess.READ)
	sprites_data = JSON.parse_string(sf.get_as_text())

# ---- dev autopilot (DUSTFALL_AUTOPILOT=1): tour scenes, screenshot each ----------
var _ap_stage := 0
var _ap_t := 0.0
var _shot_done := {}

func _process(delta: float) -> void:
	if OS.get_environment("DUSTFALL_AUTOPILOT") != "1":
		return
	_ap_t += delta
	var scene := get_tree().current_scene
	if scene == null:
		return
	var sname := String(scene.name)
	if _ap_t > 2.2 and not _shot_done.has(sname):
		_shot_done[sname] = true
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://shot_%s.png" % sname.to_lower())
		print("AUTOPILOT shot: ", sname)
	if _ap_t > 3.0:
		_ap_t = 0.0
		_ap_stage += 1
		match _ap_stage:
			1:
				new_game()
				get_tree().change_scene_to_file("res://scenes/worldmap.tscn")
			2:
				get_tree().change_scene_to_file("res://scenes/town.tscn")
			3:
				go_battle({"title": "Autopilot Skirmish", "biome": "boneyard",
					"enemies": enemies_by_ids(["the_deacon", "walkin_dead", "coyote_beast", "dust_devil"]),
					"context": {}})
			4:
				pass # linger one beat on the battle for its screenshot
			5:
				print("AUTOPILOT done")
				get_tree().quit()

# ---- lifecycle -----------------------------------------------------------------
func new_game(lead_archetype := "gunslinger", lead_name := "") -> void:
	var comp := "hexslinger" if lead_archetype == "gunslinger" else "gunslinger"
	state = {
		"party": [_mk_member(lead_archetype, "p0", lead_name), _mk_member(comp, "p1", "")],
		"gold": 300, "day": 1, "location": "rustwater",
		"visited": {}, "inventory": {}, "mount": null,
		"favor": {"coyote": 1, "samedi": 1, "vulcan": 1, "perun": 1, "anansi": 1, "sleeper": 0},
		"flags": {}, "act1": {"step": 0}, "act2": {"step": 0}, "act3": {"step": 0},
		"version": 1,
	}
	save_game()

func _mk_member(aid: String, uid: String, nm: String) -> Dictionary:
	var pg: Dictionary = design["pregen"].get(aid, {})
	return {
		"uid": uid, "archetype": aid,
		"name": nm if nm != "" else pg.get("name", aid.capitalize()),
		"stats": pg.get("stats", {}).duplicate(),
		"level": 1, "xp": 0, "god": null,
		"gear": {"weapon": null, "armor": null, "mod": null},
		"hpDamage": 0, "alive": true,
	}

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var s = JSON.parse_string(f.get_as_text())
	if s is Dictionary and s.has("version"):
		state = s
		return true
	return false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# ---- progression (mirror of DF.gainXP) ------------------------------------------
const FAVORED := {
	"gunslinger": ["deftness", "quickness"], "hexslinger": ["cognition", "spirit"],
	"tinkerer": ["knowledge", "cognition"], "preacher": ["spirit", "vigor"],
	"lawdog": ["vigor", "mien"], "drifter": ["nimbleness", "quickness"],
}

func xp_for_level(lvl: int) -> int:
	return maxi(1, lvl) * 100

func gain_xp(member: Dictionary, amount: int) -> Array:
	member["xp"] = int(member.get("xp", 0)) + amount
	member["level"] = int(member.get("level", 1))
	var reached: Array = []
	while int(member["xp"]) >= xp_for_level(int(member["level"])):
		member["xp"] = int(member["xp"]) - xp_for_level(int(member["level"]))
		member["level"] = int(member["level"]) + 1
		var fav: Array = FAVORED.get(member["archetype"], ["vigor", "quickness"])
		var s1: String = fav[randi() % fav.size()]
		member["stats"][s1] = int(member["stats"].get(s1, 3)) + 1
		member["stats"]["vigor"] = int(member["stats"].get("vigor", 3)) + 1
		reached.append(member["level"])
	return reached

# ---- battle bookkeeping (wounds/favor/XP — mirrors finish() + results scene) ----
const ARCH_GOD := {
	"gunslinger": "coyote", "hexslinger": "samedi", "tinkerer": "vulcan",
	"preacher": "perun", "lawdog": "perun", "drifter": "anansi",
}

func apply_battle_result(battle: Dictionary, win: bool, kills: int) -> Dictionary:
	# wounds persist; the fallen cling on at 1 HP
	for u in battle["players"]:
		for m in state["party"]:
			if m["uid"] == u["id"]:
				m["hpDamage"] = maxi(0, int(u["maxHp"]) - (int(u["hp"]) if u["alive"] else 1))
	# victory pleases the party's gods
	if win:
		var gods := {}
		for u in battle["players"]:
			var g = u.get("god") if u.get("god") else ARCH_GOD.get(u.get("archetype", ""))
			if g:
				gods[g] = true
		for g in gods.keys():
			state["favor"][g] = int(state["favor"].get(g, 0)) + 1
	# XP share + level-ups
	var xp := kills * 10 + (25 if win else 0)
	var ups: Array = []
	if state["party"].size() > 0:
		var share := roundi(float(xp) / float(state["party"].size()))
		for m in state["party"]:
			var reached := gain_xp(m, share)
			if reached.size() > 0:
				ups.append("%s → Lv %d" % [m["name"], m["level"]])
	save_game()
	return {"xp": xp, "levelUps": ups}

# ---- helpers ---------------------------------------------------------------------
func node_by_id(id: String) -> Dictionary:
	for n in design["world_nodes"]:
		if n["id"] == id:
			return n
	return {}

func god_by_id(id) -> Dictionary:
	if id == null:
		return {}
	for g in design["gods"]:
		if g["id"] == id:
			return g
	return {}

func enemies_by_ids(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		for e in design["enemies"]:
			if e["id"] == id:
				out.append(e)
	return out

const GOD_BIOME := {
	"coyote": "mesa", "vulcan": "foundry", "samedi": "boneyard",
	"anansi": "canyon", "perun": "town", "sleeper": "hollow",
}

func biome_for(god) -> String:
	return GOD_BIOME.get(god, "mesa") if god else "mesa"

func go_battle(params: Dictionary) -> void:
	pending_battle = params
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
