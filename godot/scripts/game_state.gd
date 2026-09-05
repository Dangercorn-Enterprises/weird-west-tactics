# =============================================================================
# DUSTFALL — GAME STATE (autoload singleton)
# Campaign state, save/load, and battle-result bookkeeping. Mirrors the web
# game's DF.state shape (src/engine.js) so saves stay conceptually portable.
# =============================================================================
extends Node

const DT = preload("res://scripts/ui_theme.gd")
const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"

var design: Dictionary = {}
var sprites_data: Dictionary = {}
var settings: Dictionary = {}
var state: Dictionary = {}
# handoff: worldmap/town set this before switching to the battle scene
var pending_battle: Dictionary = {}
var last_result: Dictionary = {}

func apply_theme(c: Control) -> void:
	c.theme = DT.get_theme()

func headline(l: Label, size: int) -> void:
	DT.headline(l, size)

func _ready() -> void:
	# autopilot must keep ticking while the PauseMenu holds the tree paused
	# (_process here is autopilot-only, so ALWAYS changes no gameplay behavior)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	design = JSON.parse_string(f.get_as_text())
	var sf := FileAccess.open("res://data/sprites.json", FileAccess.READ)
	sprites_data = JSON.parse_string(sf.get_as_text())

# ---- settings (user://settings.json — audio prefs; audio.gd reads via get_setting)
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var s = JSON.parse_string(f.get_as_text())
	if s is Dictionary:
		settings = s

func get_setting(key: String, default = null):
	return settings.get(key, default)

func set_setting(key: String, value) -> void:
	settings[key] = value
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings))

# ---- dev autopilot (DUSTFALL_AUTOPILOT=1): tour scenes, screenshot each ----------
# Stage order (tests/autopilot_test.gd asserts it): a scene that owns an intro
# card is never shot by the timer below; its representative shot is an explicit
# stage AFTER the card is dismissed. The 2026-07-09 capture took shot_battle at
# the battle stage with the card still up (docs/steam_screens/shot_battle.png).
# The tour's new_game()/save_game() calls land on the real user://save.json, so
# the campaign save is copied to AP_BACKUP before the tour and put back at the
# end. A backup left by a tour that crashed mid-way is the campaign: it is kept,
# never overwritten, and restored when the next tour completes.
const AP_BACKUP := "user://save.json.autopilot-bak"
const AP_STAGE_CREATOR := 1
const AP_STAGE_WORLDMAP := 2        # new_game() here writes the save (backed up)
const AP_STAGE_TOWN := 3
const AP_STAGE_BATTLE := 4          # go_battle, intro card up while the board settles
const AP_STAGE_INTRO_DISMISS := 5   # shot_battle_intro.png, then close the card
const AP_STAGE_BATTLE_SHOT := 6     # shot_battle.png (card gone), then turn 180
const AP_STAGE_ROTATED_SHOT := 7    # shot_battle_rotated.png
const AP_STAGE_PAUSE_OPEN := 8
const AP_STAGE_PAUSE_SHOT := 9      # shot_pause.png, restore the save, quit
var _ap_stage := 0
var _ap_t := 0.0
var _ap_started := false
var _shot_done := {}

# true for scenes whose first frames are covered by an intro card (battle):
# the timer shot skips them, an explicit stage shoots them after the card closes
static func ap_has_intro(scene: Object) -> bool:
	return scene != null and "intro_open" in scene

func _process(delta: float) -> void:
	if OS.get_environment("DUSTFALL_AUTOPILOT") != "1":
		return
	if not _ap_started:
		_ap_started = true
		_ap_backup_save()
	_ap_t += delta
	var scene := get_tree().current_scene
	if scene == null:
		return
	var sname := String(scene.name)
	if _ap_t > 2.2 and not _shot_done.has(sname) and not ap_has_intro(scene):
		_shot_done[sname] = true
		_ap_shot("shot_%s" % sname.to_lower(), scene)
	if _ap_t > 3.0:
		_ap_t = 0.0
		_ap_stage += 1
		match _ap_stage:
			AP_STAGE_CREATOR:
				get_tree().change_scene_to_file("res://scenes/creator.tscn")
			AP_STAGE_WORLDMAP:
				new_game()
				get_tree().change_scene_to_file("res://scenes/worldmap.tscn")
			AP_STAGE_TOWN:
				get_tree().change_scene_to_file("res://scenes/town.tscn")
			AP_STAGE_BATTLE:
				go_battle({"title": "The Deacon's Reckoning", "biome": "boneyard",
					"enemies": enemies_by_ids(["the_deacon", "walkin_dead", "coyote_beast", "dust_devil"]),
					"intro": "Death Valley earns its name tonight. The Deacon stands in a church with no roof, preaching to graves that empty themselves. End the sermon.",
					"context": {}})
			AP_STAGE_INTRO_DISMISS:
				if ap_has_intro(scene) and scene.intro_open:
					_ap_shot("shot_battle_intro", scene)
					scene.intro_open = false
					scene.intro_panel.queue_free()
			AP_STAGE_BATTLE_SHOT:
				_ap_shot("shot_battle", scene)
				if "cam_target_azimuth" in scene:
					scene.cam_target_azimuth += PI # 180 degrees, should show unit BACKS
			AP_STAGE_ROTATED_SHOT:
				_ap_shot("shot_battle_rotated", scene)
			AP_STAGE_PAUSE_OPEN:
				var pm := get_node_or_null("/root/PauseMenu")
				if pm:
					pm.open_menu()
			AP_STAGE_PAUSE_SHOT:
				_ap_shot("shot_pause", scene)
				var pm2 := get_node_or_null("/root/PauseMenu")
				if pm2:
					pm2.close()
				_ap_restore_save()
				print("AUTOPILOT done")
				get_tree().quit()

# save the viewport and log the capture context (one JSON line per shot, so a
# sidecar can be rebuilt from the Godot log): scene, stage, biome/title, the
# core's current mulberry32 state (battle seeds from the clock and keeps no
# seed), camera heading in degrees, intro card state, campaign location/day.
func _ap_shot(shot: String, scene: Node) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null: # null under --headless (no renderer): the tour still walks
		img.save_png("user://%s.png" % shot)
	var ctx := _ap_shot_context(scene)
	ctx["saved"] = img != null
	print("AUTOPILOT shot: %s %s" % [shot, JSON.stringify(ctx)])

func _ap_shot_context(scene: Node) -> Dictionary:
	var ctx := {"scene": String(scene.name), "stage": _ap_stage}
	if "params" in scene and scene.params is Dictionary:
		ctx["biome"] = String(scene.params.get("biome", ""))
		ctx["title"] = String(scene.params.get("title", ""))
	if "core" in scene and scene.core != null and "_rng_state" in scene.core:
		ctx["rng_state"] = int(scene.core._rng_state)
	if "cam_azimuth" in scene:
		ctx["camera_heading_deg"] = int(round(rad_to_deg(float(scene.cam_azimuth)))) % 360
	if ap_has_intro(scene):
		ctx["intro_open"] = bool(scene.intro_open)
	if not state.is_empty():
		ctx["location"] = String(state.get("location", ""))
		ctx["day"] = int(state.get("day", 0))
	return ctx

# The backup is the campaign save verbatim; an empty backup means "there was no
# save", so the restore deletes whatever the tour wrote. Paths are parameters
# so tests/autopilot_test.gd can round-trip on scratch files.
func _ap_backup_save(save_path := SAVE_PATH, backup_path := AP_BACKUP) -> void:
	if FileAccess.file_exists(backup_path):
		print("AUTOPILOT: leftover ", backup_path, " kept as the campaign save")
		return
	var text := ""
	if FileAccess.file_exists(save_path):
		text = FileAccess.open(save_path, FileAccess.READ).get_as_text()
	var f := FileAccess.open(backup_path, FileAccess.WRITE)
	f.store_string(text)
	print("AUTOPILOT: campaign save backed up (%d bytes)" % text.length())

func _ap_restore_save(save_path := SAVE_PATH, backup_path := AP_BACKUP) -> void:
	if not FileAccess.file_exists(backup_path):
		print("AUTOPILOT: no backup to restore")
		return
	var text := FileAccess.open(backup_path, FileAccess.READ).get_as_text()
	if text.is_empty():
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	else:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		f.store_string(text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	print("AUTOPILOT: campaign save restored (%d bytes)" % text.length())

# ---- lifecycle -----------------------------------------------------------------
func new_game(lead_archetype := "gunslinger", lead_name := "") -> void:
	var comp := "hexslinger" if lead_archetype == "gunslinger" else "gunslinger"
	state = {
		"party": [_mk_member(lead_archetype, "p0", lead_name), _mk_member(comp, "p1", "")],
		"gold": 300, "day": 1, "location": "catalina", # Act I opens off the coast
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

# Riders must exist before a scene runs outside the campaign flow (title Quick
# Skirmish, battle/worldmap direct launch — all three call this). The save on
# disk is the campaign — load it FIRST. new_game() ends in save_game(), so
# falling straight to it from an empty state overwrote a real campaign with a
# fresh 2-rider/300g/day-1 party, no prompt (Quick Skirmish clobber, 2026-09-04
# audit). Only a missing/unreadable save starts a new game.
func ensure_party() -> void:
	if not state.is_empty():
		return
	if has_save() and load_game():
		return
	new_game()

# ---- progression -----------------------------------------------------------------
# Combat reads exactly these four stats (party_to_unit); everything else is
# dead data until the stat-wiring design session. UI that shows stats grays
# anything not in LIVE_STATS — the sheet must not print dead numbers as live.
const LIVE_STATS := ["vigor", "quickness", "strength", "deftness"]
# Session #2 decision 2f (Tim, 2026-07-10): FAVORED re-routed onto LIVE stats
# so every archetype levels something real (hexslinger/tinkerer used to level
# NOTHING — both favored stats were dead; audit cluster 4). Old pairs kept in
# the design log; full stat wiring is a future design session.
const FAVORED := {
	"gunslinger": ["deftness", "quickness"], "hexslinger": ["deftness", "vigor"],
	"tinkerer": ["deftness", "quickness"], "preacher": ["vigor", "strength"],
	"lawdog": ["vigor", "quickness"], "drifter": ["quickness", "deftness"],
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
	# XP — Session #2 decision 2i (Tim, 2026-07-10): only DEPLOYED riders earn.
	# The bench is free storage, not an XP tax (audit: slots 5-6 were strictly
	# negative — never fought, diluted every share).
	var xp := kills * 10 + (25 if win else 0)
	var deployed: Array = []
	for u in battle["players"]:
		for m in state["party"]:
			if m["uid"] == u["id"]:
				deployed.append(m)
	var ups: Array = []
	var gains: Array = []  # per-rider breakdown for the results banner
	if deployed.size() > 0:
		var share := roundi(float(xp) / float(deployed.size()))
		for m in deployed:
			var reached := gain_xp(m, share)
			if reached.size() > 0:
				ups.append("%s → Lv %d" % [m["name"], m["level"]])
			gains.append({"name": m["name"], "xp": share, "level": int(m["level"]),
				"into": int(m["xp"]), "next": xp_for_level(int(m["level"]))})
	save_game()
	return {"xp": xp, "levelUps": ups, "gains": gains}

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
