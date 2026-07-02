# =============================================================================
# DUSTFALL — BATTLE SCENE PROTOTYPE (Godot port, v1.3)
# Interactive HD-2D battle driven by the parity-tested CombatCore: 3D tile
# board, orthographic FFT camera with Q/E quarter-turns, billboard pixel
# sprites generated from the shared sprites.json, click to select/move/attack,
# Enter ends the turn (CombatCore runs the enemy phase).
# Prototype scope: canonical mesa map, flat-color tiles (generated textures
# come with the art pass), Label3D HP readouts.
# =============================================================================
extends Node3D

const CombatCoreScript = preload("res://scripts/combat_core.gd")

const TILE := 1.0
const STEP := 0.55
const BASE := 0.32

var core
var battle: Dictionary
var grid: Array
var sel: Dictionary = {}
var reach_map: Dictionary = {}
var sprites_data: Dictionary = {}
var cam: Camera3D
var cam_azimuth := PI / 4
var cam_target_azimuth := PI / 4
var unit_nodes := {} # unit id -> {sprite, label, ring}
var highlight_nodes: Array = []
var log_label: Label
var floors := ["#3a2c18", "#4a3820", "#5a4428"]

func _tx(q: int) -> float: return (float(q) - 4.5) * TILE
func _tz(r: int) -> float: return (float(r) - 4.5) * TILE
func _top_y(h: int) -> float: return BASE + float(h) * STEP

func _ready() -> void:
	core = CombatCoreScript.new()
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	core.design = JSON.parse_string(f.get_as_text())
	var sf := FileAccess.open("res://data/sprites.json", FileAccess.READ)
	sprites_data = JSON.parse_string(sf.get_as_text())
	core.seed_rng(int(Time.get_ticks_usec()) & 0x7FFFFFFF)
	floors = core.design["biomes"]["mesa"]["floors"]
	_setup_battle()
	_build_camera_and_light()
	_build_board()
	_build_units()
	_build_hud()
	_select(battle["players"][0])
	_log("— Your move —  (click: select/move/attack · Q/E rotate · Enter end turn)")

# ---- battle state ------------------------------------------------------------
func _setup_battle() -> void:
	grid = core.build_grid()
	var party: Array = core.mk_party(["gunslinger", "hexslinger"])
	var players: Array = []
	for i in party.size():
		players.append(core.party_to_unit(party[i], i))
	var ids := ["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"]
	var raw: Array = []
	for id in ids:
		raw.append(core._find(core.design["enemies"], id))
	var specs: Array = core.scale_encounter(raw, players.size())
	var enemies: Array = []
	for i in specs.size():
		var u: Dictionary = core.enemy_to_unit(specs[i], i)
		var sp: Array = core.SPAWNS[i]
		u["q"] = sp[0]
		u["r"] = sp[1]
		enemies.append(u)
	battle = {
		"grid": grid, "players": players, "enemies": enemies,
		"units": players + enemies, "kills": 0, "playerDeaths": 0,
	}

# ---- world construction --------------------------------------------------------
func _build_camera_and_light() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.6
	add_child(cam)
	_place_camera()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 30, 0)
	sun.light_color = Color(1.0, 0.88, 0.69)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.05, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.75, 0.62)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

func _place_camera() -> void:
	var dist := 26.0
	var elev := 0.62
	cam.position = Vector3(
		sin(cam_azimuth) * cos(elev) * dist,
		sin(elev) * dist,
		cos(cam_azimuth) * cos(elev) * dist
	)
	cam.look_at(Vector3(0, 0.8, 0))

func _hexc(hex: String) -> Color:
	return Color(hex)

func _build_board() -> void:
	for r in core.ROWS:
		for q in core.COLS:
			var cell: Dictionary = grid[r][q]
			var h := _top_y(int(cell["h"]))
			var mesh := BoxMesh.new()
			mesh.size = Vector3(TILE * 0.98, h, TILE * 0.98)
			var mat := StandardMaterial3D.new()
			var vary := 0.94 + float((q * 7 + r * 13) % 5) * 0.03
			mat.albedo_color = _hexc(floors[mini(2, int(cell["h"]))]) * vary
			mesh.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(_tx(q), h / 2.0, _tz(r))
			add_child(mi)
			# pickable collider carrying the tile coords
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = mesh.size
			shape.shape = box
			body.add_child(shape)
			body.set_meta("q", q)
			body.set_meta("r", r)
			mi.add_child(body)
			# soft cover markers (visual placeholder until the art pass)
			if float(cell["cover"]) > 0.0:
				var deco := BoxMesh.new()
				var big := float(cell["cover"]) > 0.3
				deco.size = Vector3(0.34, 0.5 if big else 0.3, 0.34)
				var dmat := StandardMaterial3D.new()
				dmat.albedo_color = _hexc("#6b4a26") if big else _hexc("#5a7a4a")
				deco.material = dmat
				var dmi := MeshInstance3D.new()
				dmi.mesh = deco
				dmi.position = Vector3(_tx(q), h + deco.size.y / 2.0, _tz(r))
				add_child(dmi)

func _sprite_texture(archetype: String) -> ImageTexture:
	var pal: Dictionary = sprites_data["palette"]
	var rows: Array = sprites_data["sprites"].get(archetype, sprites_data["sprites"]["gunslinger"])
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, (row as String).length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in row.length(): # rows can be ragged in the source data
			var col = pal.get(row[x])
			if col != null:
				img.set_pixel(x, y, Color(col))
	return ImageTexture.create_from_image(img)

func _sprite_for(u: Dictionary) -> String:
	var raw: String = str(u.get("archetype", "")).to_lower()
	if sprites_data["sprites"].has(raw):
		return raw
	if raw.contains("dead") or raw.contains("risen"):
		return "walkin_dead"
	if raw.contains("hex") or raw.contains("witch") or raw.contains("weaver"):
		return "hexslinger"
	return "gunslinger"

func _build_units() -> void:
	for u in battle["units"]:
		var spr := Sprite3D.new()
		spr.texture = _sprite_texture(_sprite_for(u))
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.pixel_size = 0.068
		spr.shaded = false
		add_child(spr)
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.modulate = Color("#4ecdc4") if u["side"] == "p" else Color("#c0392b")
		add_child(lbl)
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = 0.34
		rm.outer_radius = 0.44
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("#d4a843")
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.material = rmat
		ring.mesh = rm
		ring.scale = Vector3(1, 0.08, 1)
		ring.visible = false
		add_child(ring)
		unit_nodes[u["id"]] = {"sprite": spr, "label": lbl, "ring": ring}
	_sync_units()

func _sync_units() -> void:
	for u in battle["units"]:
		var n: Dictionary = unit_nodes.get(u["id"], {})
		if n.is_empty():
			continue
		var y := _top_y(int(grid[u["r"]][u["q"]]["h"]))
		n["sprite"].position = Vector3(_tx(u["q"]), y + 0.68, _tz(u["r"]))
		n["sprite"].visible = u["alive"]
		n["label"].position = Vector3(_tx(u["q"]), y + 1.5, _tz(u["r"]))
		n["label"].text = "%d/%d" % [maxi(0, int(u["hp"])), int(u["maxHp"])]
		n["label"].visible = u["alive"]
		n["ring"].position = Vector3(_tx(u["q"]), y + 0.03, _tz(u["r"]))
		n["ring"].visible = u["alive"] and not sel.is_empty() and u["id"] == sel.get("id")

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	log_label = Label.new()
	log_label.position = Vector2(16, 16)
	log_label.add_theme_font_size_override("font_size", 18)
	cl.add_child(log_label)

var _log_lines: Array = []
func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > 6:
		_log_lines.pop_front()
	log_label.text = "\n".join(_log_lines)

# ---- selection / highlights -----------------------------------------------------
func _select(u: Dictionary) -> void:
	sel = u
	reach_map = core.reach(grid, battle["units"], u) if not u.is_empty() else {}
	_refresh_highlights()
	_sync_units()

func _refresh_highlights() -> void:
	for n in highlight_nodes:
		n.queue_free()
	highlight_nodes.clear()
	for key in reach_map.keys():
		var parts: PackedStringArray = key.split(",")
		var q := int(parts[0])
		var r := int(parts[1])
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.92, 0.92)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.31, 0.80, 0.77, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.position = Vector3(_tx(q), _top_y(int(grid[r][q]["h"])) + 0.015, _tz(r))
		add_child(mi)
		highlight_nodes.append(mi)

# ---- input -----------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				cam_target_azimuth -= PI / 2
			KEY_E:
				cam_target_azimuth += PI / 2
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_end_turn()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)

func _process(_delta: float) -> void:
	var d := cam_target_azimuth - cam_azimuth
	if absf(d) > 0.0005:
		cam_azimuth += d * 0.14
		_place_camera()

func _click(screen_pos: Vector2) -> void:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"].has_meta("q"):
		return
	var q: int = hit["collider"].get_meta("q")
	var r: int = hit["collider"].get_meta("r")
	var occ := {}
	for u in battle["units"]:
		if u["alive"] and u["q"] == q and u["r"] == r:
			occ = u
			break
	if not occ.is_empty() and occ["side"] == "p":
		_select(occ)
		return
	if not occ.is_empty() and occ["side"] == "e" and not sel.is_empty():
		if core.dist(sel, occ) <= int(sel["rng"]) + 1 and int(sel["ap"]) >= 2:
			sel["ap"] -= 2
			var hp_before: int = occ["hp"]
			var landed: bool = core.do_fire(battle, sel, occ)
			_log("%s %s %s%s" % [
				sel["name"], "hits" if landed else "misses", occ["name"],
				" for %d" % (hp_before - int(occ["hp"])) if landed else "",
			])
			_after_action()
		else:
			_log("Out of range or no AP.")
		return
	var key := "%d,%d" % [q, r]
	if not sel.is_empty() and reach_map.has(key):
		sel["ap"] -= int(reach_map[key])
		sel["q"] = q
		sel["r"] = r
		_select(sel)

func _end_turn() -> void:
	_log("Enemies stir...")
	core.enemy_phase(battle)
	for p in battle["players"]:
		if p["alive"]:
			p["ap"] = p["maxAp"]
			core.tick_status(battle, p)
	_sync_units()
	_check_end()
	var alive_players: Array = battle["players"].filter(func(p): return p["alive"])
	if alive_players.size() > 0:
		_select(alive_players[0])
		_log("— Your move —")

func _after_action() -> void:
	_sync_units()
	_refresh_highlights()
	_check_end()

func _check_end() -> void:
	if battle["enemies"].filter(func(e): return e["alive"]).is_empty():
		_log("THE DUST SETTLES — victory. (Enter restarts)")
	elif battle["players"].filter(func(p): return p["alive"]).is_empty():
		_log("WIPED OUT. (Enter restarts)")
