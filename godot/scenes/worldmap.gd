# =============================================================================
# DUSTFALL — WORLDMAP (Godot port)
# RDR2-flavored hand-drawn map (assets/scenes/worldmap.png) with the real
# US-Southwest node graph, trail risk, mount-aware travel, the 3-act story
# spine (ported from src/scene_worldmap.js), ambushes and boss reckonings.
# =============================================================================
extends Control

var GS
var nodes: Array = []
var edges: Array = []
var adj: Dictionary = {}
var hover: Dictionary = {}
var map_rect := Rect2()

@onready var info_name: Label = $Panel/VBox/NodeName
@onready var info_lore: Label = $Panel/VBox/Lore
@onready var info_status: Label = $Panel/VBox/Status
@onready var objective: Label = $Panel/VBox/Objective
@onready var enter_btn: Button = $Panel/VBox/EnterBtn
@onready var overlay: Control = $Overlay

const ACT1_OBJ := [
	"Act I — Make for Los Angeles. The Deacon's revenants raid the coast.",
	"Act I — Into the Boneyard. Hunt the Deacon at Death Valley.",
	"Act I complete — the Deacon is broken. The frontier lies open.",
]
const ACT2_OBJ := [
	"Act II — The Forgeworks rise from the ash. Make for Los Alamos.",
	"Act II — Storm the foundry. Break the Iron Foreman.",
	"Act II complete — the Foreman is scrap. Something older stirs.",
]
const ACT3_OBJ := [
	"Act III — The Hollow Court wakes. Make for Groom Lake.",
	"Act III — End it. Face the Hollow Man before the Sleeper rises.",
	"The frontier is saved — for now.",
]

func _ready() -> void:
	GS = get_node("/root/GameState")
	GS.apply_theme(self)
	GS.headline(info_name, 26)
	if GS.state.is_empty():
		if not GS.load_game():
			GS.new_game()
	nodes = GS.design["world_nodes"]
	edges = GS.design["world_edges"]
	for n in nodes:
		adj[n["id"]] = []
	for e in edges:
		if adj.has(e[0]) and adj.has(e[1]):
			adj[e[0]].append(e[1])
			adj[e[1]].append(e[0])
	var bg: TextureRect = $MapArt
	if ResourceLoader.exists("res://assets/scenes/worldmap.png"):
		bg.texture = load("res://assets/scenes/worldmap.png")
	enter_btn.pressed.connect(_enter_town)
	$Panel/VBox/TitleBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	overlay.draw.connect(_draw_overlay)
	overlay.gui_input.connect(_overlay_input)
	_process_battle_result()
	_refresh()

# ---- act spine -------------------------------------------------------------------
func _step(act: String) -> int:
	return int(GS.state.get(act, {}).get("step", 0))

func _objective_text() -> String:
	if _step("act2") >= 2:
		return ACT3_OBJ[_step("act3")]
	if _step("act1") >= 2:
		return ACT2_OBJ[_step("act2")]
	return ACT1_OBJ[_step("act1")]

func _objective_node() -> String:
	if _step("act2") >= 2:
		return "" if _step("act3") >= 2 else "area51"
	if _step("act1") >= 2:
		return "losalamos"
	return "losangeles" if _step("act1") == 0 else "deathvalley"

# story beats: returns non-empty battle params if a beat fires on arrival at `to`
func _story_beat(to: Dictionary) -> Dictionary:
	var s1 := _step("act1")
	if to["id"] == "losangeles" and s1 == 0:
		return {"title": "The Revenant Vanguard", "biome": "boneyard",
			"enemies": GS.enemies_by_ids(["revenant_gun", "walkin_dead", "dynamite_bandit", "dynamite_bandit"]),
			"context": {"advance": "act1", "to": 1}}
	if to["id"] == "deathvalley" and s1 == 1:
		GS.state["flags"]["boss_deathvalley"] = true
		return {"title": "The Deacon's Reckoning", "biome": "boneyard",
			"enemies": GS.enemies_by_ids(["the_deacon", "walkin_dead", "walkin_dead", "coyote_beast"]),
			"context": {"advance": "act1", "to": 2}}
	if s1 >= 2 and _step("act2") == 0:
		return {"title": "The Forgeworks Vanguard", "biome": "foundry",
			"enemies": GS.enemies_by_ids(["forge_sentry", "forge_sentry", "ashfall_golem", "dynamite_bandit"]),
			"context": {"advance": "act2", "to": 1}}
	if _step("act2") == 1 and to["id"] == "losalamos":
		GS.state["flags"]["boss_losalamos"] = true
		return {"title": "The Iron Foreman", "biome": "foundry",
			"enemies": GS.enemies_by_ids(["iron_foreman", "ashfall_golem", "forge_sentry"]),
			"context": {"advance": "act2", "to": 2}}
	if _step("act2") >= 2 and _step("act3") == 0:
		return {"title": "Heralds of the Hollow Court", "biome": "canyon",
			"enemies": GS.enemies_by_ids(["the_weaver", "dust_witch", "revenant_gun"]),
			"context": {"advance": "act3", "to": 1}}
	if _step("act3") == 1 and to["id"] == "area51":
		GS.state["flags"]["boss_area51"] = true
		return {"title": "The Hollow Man", "biome": "hollow",
			"enemies": GS.enemies_by_ids(["hollow_man", "coyotes_shadow", "dust_devil"]),
			"context": {"advance": "act3", "to": 2, "finale": true}}
	return {}

func _process_battle_result() -> void:
	var res: Dictionary = GS.last_result
	if res.is_empty():
		return
	GS.last_result = {}
	var ctx: Dictionary = res.get("context", {})
	if res.get("win", false) and ctx.has("advance"):
		GS.state[ctx["advance"]] = {"step": int(ctx["to"])}
		if ctx.get("finale", false):
			GS.state["flags"]["campaign_complete"] = true
			GS.save_game()
			get_tree().change_scene_to_file.call_deferred("res://scenes/ending.tscn")
			return
	if res.get("win", false) and ctx.has("bounty"):
		GS.state["gold"] = int(GS.state["gold"]) + int(ctx["bounty"])
	GS.save_game()

# ---- geometry ---------------------------------------------------------------------
func _node_pos(n: Dictionary) -> Vector2:
	var r := _map_rect()
	# MUST match tools/compose_map.py — the art is drawn from these same coords
	return r.position + Vector2(
		(0.06 + float(n["x"]) * 0.88) * r.size.x,
		(0.08 + float(n["y"]) * 0.84) * r.size.y)

func _map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, overlay.size)

func _current() -> Dictionary:
	var n: Dictionary = GS.node_by_id(str(GS.state["location"]))
	return n if not n.is_empty() else nodes[0]

func _god_color(id) -> Color:
	var g: Dictionary = GS.god_by_id(id)
	return Color(g["color"]) if not g.is_empty() else Color("#9a8a6a")

# ---- drawing -----------------------------------------------------------------------
func _draw_overlay() -> void:
	var cur := _current()
	for e in edges:
		var a: Dictionary = GS.node_by_id(e[0])
		var b: Dictionary = GS.node_by_id(e[1])
		if a.is_empty() or b.is_empty():
			continue
		var risk: int = e[2] if e.size() > 2 else 2
		var col := Color(0.25, 0.16, 0.08, 0.55 if risk < 3 else 0.4)
		overlay.draw_dashed_line(_node_pos(a), _node_pos(b), col, 2.0 if risk == 1 else 1.5, 8.0 if risk >= 2 else 2.0)
	var obj := _objective_node()
	for n in nodes:
		var p := _node_pos(n)
		var reachable: bool = adj[cur["id"]].has(n["id"])
		var visited: bool = GS.state["visited"].has(n["id"]) or n["id"] == cur["id"]
		var r := 8.0 if n["id"] == cur["id"] else 5.5 # art carries the glyphs now
		overlay.draw_circle(p, r + 3, Color("#2a1d0f"))
		var c := _god_color(n.get("god"))
		c.a = 1.0 if visited else 0.55
		overlay.draw_circle(p, r, c)
		if n["id"] == cur["id"]:
			overlay.draw_arc(p, r + 2, 0, TAU, 24, Color.WHITE, 2.5)
		elif reachable:
			overlay.draw_arc(p, r + 2, 0, TAU, 24, Color("#f4e7c8"), 2.0)
		if not hover.is_empty() and hover["id"] == n["id"]:
			overlay.draw_arc(p, r + 6, 0, TAU, 24, Color("#d4a843"), 1.5)
		if obj != "" and n["id"] == obj:
			var pulse := 3.0 + sin(Time.get_ticks_msec() / 260.0) * 2.0
			overlay.draw_arc(p, r + 6 + pulse, 0, TAU, 28, Color("#d4a843"), 2.0)

func _process(_d: float) -> void:
	overlay.queue_redraw()

# ---- input / travel ------------------------------------------------------------------
func _node_at(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := 24.0 * 24.0
	for n in nodes:
		var d := _node_pos(n).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = n
	return best

func _overlay_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover = _node_at(ev.position)
		_refresh()
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var n := _node_at(ev.position)
		if n.is_empty():
			return
		var cur := _current()
		if n["id"] == cur["id"]:
			_enter_town()
		elif adj[cur["id"]].has(n["id"]):
			_travel(cur, n)

func _mount() -> Dictionary:
	if GS.state.get("mount") == null:
		return {}
	for m in GS.design["mounts"]:
		if m["id"] == GS.state["mount"]:
			return m
	return {}

func _travel_days(a: Dictionary, b: Dictionary) -> int:
	var dx := float(a["x"]) - float(b["x"])
	var dy := float(a["y"]) - float(b["y"])
	var days := maxi(1, roundi(sqrt(dx * dx + dy * dy) * 22.0))
	var mt := _mount()
	if not mt.is_empty():
		days = maxi(1, roundi(float(days) * float(mt["travelF"])))
	return days

func _risk_of(a: Dictionary, b: Dictionary) -> int:
	for e in edges:
		if (e[0] == a["id"] and e[1] == b["id"]) or (e[0] == b["id"] and e[1] == a["id"]):
			return e[2] if e.size() > 2 else 2
	return 2

func _travel(from: Dictionary, to: Dictionary) -> void:
	GS.state["day"] = int(GS.state["day"]) + _travel_days(from, to)
	GS.state["location"] = to["id"]
	GS.state["visited"][to["id"]] = true
	GS.save_game()
	var beat := _story_beat(to)
	if not beat.is_empty():
		GS.save_game()
		GS.go_battle(beat)
		return
	# first arrival at a tier-3 node = boss reckoning
	if int(to.get("tier", 1)) >= 3 and not GS.state["flags"].has("boss_" + str(to["id"])):
		GS.state["flags"]["boss_" + str(to["id"])] = true
		GS.save_game()
		var boss := {}
		for e in GS.design["enemies"]:
			if e.get("boss", false) and e.get("faction") == to.get("god"):
				boss = e
				break
		if boss.is_empty():
			for e in GS.design["enemies"]:
				if e.get("boss", false):
					boss = e
					break
		var minions: Array = GS.design["enemies"].filter(
			func(e): return int(e.get("tier", 1)) <= 2 and not e.get("boss", false)).slice(0, 2)
		GS.go_battle({"title": "Reckoning at " + str(to["name"]),
			"biome": GS.biome_for(to.get("god")), "enemies": [boss] + minions, "context": {}})
		return
	var risk := _risk_of(from, to)
	var ch := 0.6 if risk >= 3 else (0.3 if risk == 2 else 0.0)
	var mt := _mount()
	if not mt.is_empty() and ch > 0.0:
		ch = maxf(0.05, ch + float(mt["ambushMod"]))
	if randf() < ch:
		var pool: Array = GS.design["enemies"].filter(
			func(e): return int(e.get("tier", 1)) <= maxi(1, int(to.get("tier", 1))) and not e.get("boss", false))
		var count := 2 + (randi() % 2) + (1 if int(to.get("tier", 1)) > 1 else 0)
		var enemies: Array = []
		for i in count:
			enemies.append(pool[randi() % pool.size()])
		GS.go_battle({"title": "Ambush on the " + ("wilderness" if risk == 3 else "trail"),
			"biome": GS.biome_for(to.get("god")), "enemies": enemies, "context": {}})
		return
	_refresh()

func _enter_town() -> void:
	get_tree().change_scene_to_file("res://scenes/town.tscn")

# ---- HUD --------------------------------------------------------------------------
func _refresh() -> void:
	var cur := _current()
	var shown := hover if (not hover.is_empty() and hover["id"] != cur["id"]) else cur
	info_name.text = str(shown["name"])
	var lore := str(shown.get("lore", ""))
	if shown["id"] != cur["id"]:
		if adj[cur["id"]].has(shown["id"]):
			var days := _travel_days(cur, shown)
			var risk := _risk_of(cur, shown)
			var risk_txt := "wilderness (wild)" if risk >= 3 else ("trail (risky)" if risk == 2 else "road (safe)")
			lore = "Ride: %d day%s · %s\n%s" % [days, "" if days == 1 else "s", risk_txt, lore]
		else:
			lore = "No trail from %s.\n%s" % [cur["name"], lore]
	info_lore.text = lore
	var mt := _mount()
	info_status.text = "Gold %d · Day %d%s" % [int(GS.state["gold"]), int(GS.state["day"]),
		("  ·  " + str(mt["name"])) if not mt.is_empty() else ""]
	objective.text = _objective_text()
