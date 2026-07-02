# =============================================================================
# DUSTFALL — BATTLE SCENE (Godot port, v1.3 art pass)
# HD-2D battle driven by the parity-tested CombatCore. Reads GameState.
# pending_battle {title, biome, enemies, context}; on completion applies
# XP/wounds/favor via GameState and returns to the worldmap with the result
# context (act advancement handled there).
# Art: AI-generated tile textures per biome (assets/tiles), character sprites
# (assets/sprites) with pixel-data fallback, shrine blessing, abilities/items.
# =============================================================================
extends Node3D

const CombatCoreScript = preload("res://scripts/combat_core.gd")

const TILE := 1.0
const STEP := 0.55
const BASE := 0.32

var GS
var core
var battle: Dictionary
var grid: Array
var params: Dictionary = {}
var sel: Dictionary = {}
var reach_map: Dictionary = {}
var pending_ability := "" # ability awaiting a target click
var pending_item := ""
var ended := false
var cam: Camera3D
var cam_azimuth := PI / 4
var cam_target_azimuth := PI / 4
var unit_nodes := {}
var highlight_nodes: Array = []
var log_label: Label
var ability_bar: HBoxContainer
var banner: PanelContainer
var banner_label: Label

func _tx(q: int) -> float: return (float(q) - 4.5) * TILE
func _tz(r: int) -> float: return (float(r) - 4.5) * TILE
func _top_y(h: int) -> float: return BASE + float(h) * STEP

func _ready() -> void:
	GS = get_node("/root/GameState")
	core = CombatCoreScript.new()
	core.design = GS.design
	core.seed_rng(int(Time.get_ticks_usec()) & 0x7FFFFFFF)
	core.on_damage = _on_unit_damaged
	params = GS.pending_battle if not GS.pending_battle.is_empty() else {
		"title": "Skirmish at the Crossing", "biome": "mesa",
		"enemies": GS.enemies_by_ids(["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"]),
		"context": {}}
	GS.pending_battle = {}
	if GS.state.is_empty():
		if not GS.load_game():
			GS.new_game()
	_setup_battle()
	_build_camera_and_light()
	_build_board()
	_build_units()
	_build_hud()
	_apply_blessing()
	_select(battle["players"][0])
	_log("— Your move — (Q/E rotate · Enter end turn)")

# ---- battle state ------------------------------------------------------------
func _setup_battle() -> void:
	var biome: Dictionary = GS.design["biomes"].get(params.get("biome", "mesa"), GS.design["biomes"]["mesa"])
	grid = _build_biome_grid(biome)
	var players: Array = []
	var roster: Array = GS.state["party"]
	for i in mini(4, roster.size()):
		players.append(core.party_to_unit(roster[i], i))
	# favor snapshot per unit (Phase 1b)
	for u in players:
		var g = u.get("god") if u.get("god") else GS.ARCH_GOD.get(u.get("archetype", ""))
		u["divineFavor"] = int(GS.state["favor"].get(g, 0)) if g else 0
		u["godId"] = g
	var specs: Array = core.scale_encounter(params["enemies"], players.size())
	var enemies: Array = []
	for i in specs.size():
		var u: Dictionary = core.enemy_to_unit(specs[i], i)
		var sp: Array = core.SPAWNS[i] if i < core.SPAWNS.size() else core.SPAWNS[i % core.SPAWNS.size()]
		u["q"] = sp[0]
		u["r"] = sp[1]
		enemies.append(u)
	battle = {"grid": grid, "players": players, "enemies": enemies,
		"units": players + enemies, "kills": 0, "playerDeaths": 0}

func _build_biome_grid(biome: Dictionary) -> Array:
	var g: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			row.append({"h": 0, "cover": 0.0, "deco": null})
		g.append(row)
	for p in biome.get("h1", []):
		g[p[1]][p[0]]["h"] = 1
	for p in biome.get("h2", []):
		g[p[1]][p[0]]["h"] = 2
	for p in biome.get("hard", []):
		g[p[1]][p[0]]["cover"] = 0.4
		g[p[1]][p[0]]["deco"] = biome.get("hardDeco", "crate")
	for p in biome.get("soft", []):
		g[p[1]][p[0]]["cover"] = 0.2
		g[p[1]][p[0]]["deco"] = biome.get("softDeco", "cactus")
	return g

func _apply_blessing() -> void:
	if GS.state["flags"].has("blessing"):
		var bg = GS.state["flags"]["blessing"]
		for u in battle["players"]:
			u["aim"] += 10 if u.get("godId") == bg else 5
		GS.state["flags"].erase("blessing")
		GS.save_game()
		var g: Dictionary = GS.god_by_id(bg)
		_log("%s's blessing steadies every hand (+aim)." % (g.get("name", "A god")))

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
	cam.position = Vector3(sin(cam_azimuth) * cos(elev) * dist, sin(elev) * dist,
		cos(cam_azimuth) * cos(elev) * dist)
	cam.look_at(Vector3(0, 0.8, 0))

func _tile_materials(biome_id: String) -> Array:
	var top := StandardMaterial3D.new()
	var side := StandardMaterial3D.new()
	var top_path := "res://assets/tiles/%s_top.png" % biome_id
	if ResourceLoader.exists(top_path):
		top.albedo_texture = load(top_path)
		top.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		top.albedo_color = Color("#4a3820")
	if ResourceLoader.exists("res://assets/tiles/cliff_side.png"):
		side.albedo_texture = load("res://assets/tiles/cliff_side.png")
		side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		side.albedo_color = Color(0.62, 0.58, 0.52)
	else:
		side.albedo_color = Color("#241a0e")
	return [top, side]

func _build_board() -> void:
	var biome_id: String = params.get("biome", "mesa")
	var mats := _tile_materials(biome_id)
	for r in core.ROWS:
		for q in core.COLS:
			var cell: Dictionary = grid[r][q]
			var h := _top_y(int(cell["h"]))
			var mesh := BoxMesh.new()
			mesh.size = Vector3(TILE * 0.98, h, TILE * 0.98)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			# top face brightness varies slightly per tile for life
			var vary := 0.92 + float((q * 5 + r * 11) % 4) * 0.035
			var top: StandardMaterial3D = mats[0].duplicate()
			top.albedo_color = Color(vary, vary, vary) * (Color.WHITE if top.albedo_texture else Color("#4a3820"))
			mi.mesh.surface_set_material(0, mats[1])
			mi.material_override = null
			mi.set_surface_override_material(0, mats[1])
			# BoxMesh is one surface; fake the top by an overlay plane
			mi.position = Vector3(_tx(q), h / 2.0, _tz(r))
			add_child(mi)
			var top_plane := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(TILE * 0.98, TILE * 0.98)
			pm.material = top
			top_plane.mesh = pm
			top_plane.position = Vector3(_tx(q), h + 0.001, _tz(r))
			add_child(top_plane)
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = mesh.size
			shape.shape = box
			body.add_child(shape)
			body.set_meta("q", q)
			body.set_meta("r", r)
			mi.add_child(body)
			if float(cell["cover"]) > 0.0:
				_add_prop(str(cell.get("deco", "crate")), q, r, h,
					float(cell["cover"]) > 0.3)

func _add_prop(deco: String, q: int, r: int, h: float, big: bool) -> void:
	var path := "res://assets/props/%s.png" % deco
	if ResourceLoader.exists(path):
		var spr := Sprite3D.new()
		spr.texture = load(path)
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var world_h := 0.78 if big else 0.6
		spr.pixel_size = world_h / float(spr.texture.get_height())
		spr.shaded = false
		spr.position = Vector3(_tx(q), h + world_h / 2.0 - 0.02, _tz(r))
		add_child(spr)
		_add_ground_shadow(Vector3(_tx(q), h, _tz(r)), 0.4)
	else:
		var deco_mesh := BoxMesh.new()
		deco_mesh.size = Vector3(0.34, 0.5 if big else 0.3, 0.34)
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color("#6b4a26") if big else Color("#5a7a4a")
		deco_mesh.material = dmat
		var dmi := MeshInstance3D.new()
		dmi.mesh = deco_mesh
		dmi.position = Vector3(_tx(q), h + deco_mesh.size.y / 2.0, _tz(r))
		add_child(dmi)

static var _blob_tex: ImageTexture = null
func _blob_texture() -> ImageTexture:
	if _blob_tex != null:
		return _blob_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length() / 30.0
			img.set_pixel(x, y, Color(0, 0, 0, clampf(0.55 * (1.0 - d), 0.0, 0.55)))
	_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex

func _add_ground_shadow(pos: Vector3, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size * 2.0, size * 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _blob_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = mat
	mi.mesh = qm
	mi.rotation_degrees.x = -90
	mi.position = pos + Vector3(0, 0.012, 0)
	add_child(mi)
	return mi

# ---- damage feedback: floaters + hit flash ------------------------------------
func _on_unit_damaged(u: Dictionary, dmg: int) -> void:
	var y := _top_y(int(grid[u["r"]][u["q"]]["h"]))
	_floater("-%d" % dmg, Vector3(_tx(u["q"]), y + 1.7, _tz(u["r"])),
		Color("#c0392b") if u["side"] == "p" else Color("#d4a843"))
	if unit_nodes.has(u["id"]):
		var spr: Sprite3D = unit_nodes[u["id"]]["sprite"]
		spr.modulate = Color(3, 3, 3)
		var tw := create_tween()
		tw.tween_property(spr, "modulate", Color.WHITE, 0.28)

func _floater(text: String, pos: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 56
	l.pixel_size = 0.007
	l.outline_size = 10
	l.modulate = col
	l.position = pos
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 0.9, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

# ---- unit sprites -----------------------------------------------------------------
func _sprite_texture(u: Dictionary) -> Texture2D:
	var id := str(u.get("archetype", ""))
	var art := "res://assets/sprites/%s.png" % id
	if ResourceLoader.exists(art):
		return load(art)
	# fallback: rasterize the shared pixel data
	var pal: Dictionary = GS.sprites_data["palette"]
	var sprites: Dictionary = GS.sprites_data["sprites"]
	var key := id if sprites.has(id) else "gunslinger"
	var rows: Array = sprites[key]
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, (row as String).length())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in row.length():
			var col = pal.get(row[x])
			if col != null:
				img.set_pixel(x, y, Color(col))
	return ImageTexture.create_from_image(img)

func _build_units() -> void:
	for u in battle["units"]:
		var spr := Sprite3D.new()
		spr.texture = _sprite_texture(u)
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# normalize world height to ~1.35 tiles regardless of source resolution
		var world_h := 2.1 if u.get("boss", false) else 1.35
		spr.pixel_size = world_h / float(spr.texture.get_height())
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
		var shadow := _add_ground_shadow(Vector3.ZERO, 0.5)
		unit_nodes[u["id"]] = {"sprite": spr, "label": lbl, "ring": ring, "shadow": shadow}
	_sync_units()

func _sync_units() -> void:
	for u in battle["units"]:
		if not unit_nodes.has(u["id"]):
			continue # boss-phase summons get nodes on demand below
		var n: Dictionary = unit_nodes[u["id"]]
		var y := _top_y(int(grid[u["r"]][u["q"]]["h"]))
		var half := 1.07 if u.get("boss", false) else 0.7
		n["sprite"].position = Vector3(_tx(u["q"]), y + half, _tz(u["r"]))
		n["sprite"].visible = u["alive"]
		if n.has("shadow"):
			n["shadow"].position = Vector3(_tx(u["q"]), y + 0.012, _tz(u["r"]))
			n["shadow"].visible = u["alive"]
		n["label"].position = Vector3(_tx(u["q"]), y + (2.35 if u.get("boss", false) else 1.6), _tz(u["r"]))
		n["label"].text = "%d" % maxi(0, int(u["hp"]))
		n["label"].visible = u["alive"]
		n["ring"].position = Vector3(_tx(u["q"]), y + 0.03, _tz(u["r"]))
		n["ring"].visible = u["alive"] and not sel.is_empty() and u["id"] == sel.get("id")
	# boss-phase summons (Risen Dead) appear mid-fight
	for u in battle["units"]:
		if not unit_nodes.has(u["id"]):
			_build_unit_node(u)

func _build_unit_node(u: Dictionary) -> void:
	var spr := Sprite3D.new()
	spr.texture = _sprite_texture(u)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = 1.35 / float(spr.texture.get_height())
	spr.shaded = false
	add_child(spr)
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 40
	lbl.pixel_size = 0.006
	lbl.modulate = Color("#c0392b")
	add_child(lbl)
	var ring := MeshInstance3D.new()
	ring.visible = false
	add_child(ring)
	unit_nodes[u["id"]] = {"sprite": spr, "label": lbl, "ring": ring}

# ---- HUD ---------------------------------------------------------------------------
func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var title := Label.new()
	title.text = str(params.get("title", "Skirmish"))
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 24)
	cl.add_child(title)
	log_label = Label.new()
	log_label.position = Vector2(16, 44)
	log_label.add_theme_font_size_override("font_size", 15)
	cl.add_child(log_label)
	ability_bar = HBoxContainer.new()
	ability_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ability_bar.position = Vector2(16, -56)
	ability_bar.offset_top = -56.0
	ability_bar.offset_left = 16.0
	cl.add_child(ability_bar)
	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.visible = false
	var bb := VBoxContainer.new()
	banner_label = Label.new()
	banner_label.add_theme_font_size_override("font_size", 40)
	bb.add_child(banner_label)
	var cont := Button.new()
	cont.text = "Continue"
	cont.pressed.connect(_finish_and_return)
	bb.add_child(cont)
	banner.add_child(bb)
	cl.add_child(banner)

var _log_lines: Array = []
func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > 7:
		_log_lines.pop_front()
	log_label.text = "\n".join(_log_lines)

func _rebuild_ability_bar() -> void:
	for c in ability_bar.get_children():
		c.queue_free()
	if sel.is_empty() or ended:
		return
	var ap_lbl := Label.new()
	ap_lbl.text = "%s  AP %d/%d   " % [sel["name"], int(sel["ap"]), int(sel["maxAp"])]
	ability_bar.add_child(ap_lbl)
	for aname in sel.get("abilities", []):
		var fx: Dictionary = core.ABIL_FX.get(aname, {})
		var cost := int(fx.get("cost", 2))
		var b := Button.new()
		b.text = "%s (%d)" % [aname, cost]
		b.disabled = int(sel["ap"]) < cost
		b.pressed.connect(_choose_ability.bind(aname))
		ability_bar.add_child(b)
	if sel.get("divine") and not sel.get("divineUsed", false):
		var db := Button.new()
		db.text = "✦ %s (favor %d)" % [sel["divine"], int(sel.get("divineFavor", 0))]
		db.disabled = int(sel.get("divineFavor", 0)) < 1 or int(sel["ap"]) < 2
		db.pressed.connect(_choose_ability.bind(str(sel["divine"])))
		ability_bar.add_child(db)
	var hb := Button.new()
	hb.text = "Hunker (1)"
	hb.disabled = int(sel["ap"]) < 1
	hb.pressed.connect(func():
		sel["ap"] = int(sel["ap"]) - 1
		sel["status"]["hunker"] = maxi(int(sel["status"]["hunker"]), 2)
		_log("%s hunkers down — harder to hit." % sel["name"])
		_select(sel))
	ability_bar.add_child(hb)
	for item in [["bandages", "Bandage"], ["ashfall_charge", "Charge"], ["smelling_salts", "Salts"]]:
		var n := int(GS.state["inventory"].get(item[0], 0))
		if n <= 0:
			continue
		var ib := Button.new()
		ib.text = "%s ×%d (1)" % [item[1], n]
		ib.disabled = int(sel["ap"]) < 1
		ib.pressed.connect(_use_item.bind(str(item[0])))
		ability_bar.add_child(ib)
	var endb := Button.new()
	endb.text = "End Turn"
	endb.pressed.connect(_end_turn)
	ability_bar.add_child(endb)

# ---- abilities / items (interactive port of doAbility) ------------------------------
func _choose_ability(aname: String) -> void:
	pending_item = ""
	if aname == "Lay on Hands" or aname == "Soul Drain":
		var fallen := {}
		if aname == "Lay on Hands":
			for p in battle["players"]:
				if not p["alive"]:
					fallen = p
					break
		var who: Dictionary
		if not fallen.is_empty():
			who = fallen
		elif aname == "Soul Drain":
			who = sel
		else:
			var alive: Array = battle["players"].filter(func(p): return p["alive"])
			alive.sort_custom(func(a, c): return float(a["hp"]) / float(a["maxHp"]) < float(c["hp"]) / float(c["maxHp"]))
			who = alive[0]
		sel["ap"] = int(sel["ap"]) - 2
		var amt: int = 6 + core.randint(0, 4)
		if not who["alive"]:
			who["alive"] = true
			who["hp"] = amt
			who["ap"] = 0
			who["status"] = {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}
			_log("%s pulls %s back from the brink." % [sel["name"], who["name"]])
		else:
			who["hp"] = mini(int(who["maxHp"]), int(who["hp"]) + amt)
			_log("%s mends %s (+%d)." % [sel["name"], who["name"], amt])
		_after_action()
		return
	pending_ability = aname
	_log("%s: pick a target" % aname)

func _use_item(id: String) -> void:
	pending_ability = ""
	if id == "bandages":
		sel["ap"] = int(sel["ap"]) - 1
		GS.state["inventory"][id] = int(GS.state["inventory"][id]) - 1
		sel["hp"] = mini(int(sel["maxHp"]), int(sel["hp"]) + 8)
		GS.save_game()
		_log("%s ties off the wound (+8)." % sel["name"])
		_after_action()
	elif id == "smelling_salts":
		var fallen := {}
		for p in battle["players"]:
			if not p["alive"]:
				fallen = p
				break
		if fallen.is_empty():
			_log("No one needs the salts.")
			return
		sel["ap"] = int(sel["ap"]) - 1
		GS.state["inventory"][id] = int(GS.state["inventory"][id]) - 1
		fallen["alive"] = true
		fallen["hp"] = 5
		fallen["ap"] = 0
		fallen["status"] = {"burn": 0, "bleed": 0, "hex": 0, "marked": 0, "hunker": 0, "stun": 0, "conf": 0}
		GS.save_game()
		_log("%s brings %s around with the salts." % [sel["name"], fallen["name"]])
		_after_action()
	elif id == "ashfall_charge":
		pending_item = id
		_log("Ashfall Charge: pick a target")

func _exec_pending_on(target: Dictionary) -> void:
	if pending_item == "ashfall_charge":
		pending_item = ""
		sel["ap"] = int(sel["ap"]) - 1
		GS.state["inventory"]["ashfall_charge"] = int(GS.state["inventory"]["ashfall_charge"]) - 1
		GS.save_game()
		# item blast: 6-10, mirror of the web build
		for u in battle["units"]:
			if u["alive"] and absi(u["q"] - target["q"]) <= 1 and absi(u["r"] - target["r"]) <= 1:
				var dmg: int = core.randint(6, 10)
				if int(u.get("armorDef", 0)) > 0:
					dmg = maxi(1, dmg - int(u["armorDef"]))
				core.apply_damage(battle, u, dmg)
		_log("The Ashfall charge goes off!")
		_after_action()
		return
	var aname := pending_ability
	pending_ability = ""
	if aname == sel.get("divine"):
		_cast_divine(target)
		return
	var fx: Dictionary = core.ABIL_FX.get(aname, {})
	if fx.is_empty():
		return
	sel["ap"] = int(sel["ap"]) - int(fx.get("cost", 2))
	core._exec_atk(battle, sel, target, fx)
	_log("%s — %s!" % [sel["name"], aname])
	_after_action()

func _cast_divine(target: Dictionary) -> void:
	var pool := int(sel.get("divineFavor", 0))
	if pool < 1:
		_log("The god is silent — earn favor at a shrine.")
		return
	var emp := pool >= 3
	sel["divineFavor"] = pool - 1
	sel["divineUsed"] = true
	var g = sel.get("godId")
	if g and GS.state["favor"].has(g):
		GS.state["favor"][g] = maxi(0, int(GS.state["favor"][g]) - 1)
		GS.save_game()
	var a: String = sel["divine"]
	_log("%s channels %s%s" % [sel["name"], a, " — EMPOWERED!" if emp else "!"])
	if core.DIVINE_BLAST.has(a):
		core.do_blast(battle, target)
		core.do_blast(battle, target)
		if emp:
			core.do_blast(battle, target)
		var rk := "burn" if a == "Vulcan's Forgefire" else "stun"
		for x in battle["enemies"]:
			if x["alive"] and absi(x["q"] - target["q"]) <= 1 and absi(x["r"] - target["r"]) <= 1:
				x["status"][rk] = maxi(int(x["status"].get(rk, 0)), 2 if rk == "burn" else 1)
	else:
		var sv := int(sel["aim"])
		sel["aim"] = 999
		core.do_fire(battle, sel, target, {"ignoreCover": true, "mult": 3.5 if emp else 2.5,
			"status": "marked" if emp else null, "statusN": 2})
		sel["aim"] = sv
		if a == "Samedi's Embrace":
			sel["hp"] = mini(int(sel["maxHp"]), int(sel["hp"]) + (9 if emp else 6))
		elif a == "Coyote's Gambit":
			sel["status"]["hunker"] = maxi(int(sel["status"]["hunker"]), 2)
		elif a == "Iron Verdict" and target["alive"]:
			target["status"]["marked"] = maxi(int(target["status"]["marked"]), 2)
		elif a == "Anansi's Trick" and target["alive"]:
			target["status"]["conf"] = maxi(int(target["status"].get("conf", 0)), 1)
	sel["ap"] = 0
	_after_action()

# ---- selection / highlights -----------------------------------------------------
func _select(u: Dictionary) -> void:
	sel = u
	pending_ability = ""
	pending_item = ""
	reach_map = core.reach(grid, battle["units"], u) if (not u.is_empty() and u["alive"]) else {}
	_refresh_highlights()
	_sync_units()
	_rebuild_ability_bar()

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
		mi.position = Vector3(_tx(q), _top_y(int(grid[r][q]["h"])) + 0.02, _tz(r))
		add_child(mi)
		highlight_nodes.append(mi)

# ---- input -----------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if ended:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: cam_target_azimuth -= PI / 2
			KEY_E: cam_target_azimuth += PI / 2
			KEY_ENTER, KEY_KP_ENTER: _end_turn()
			KEY_ESCAPE:
				pending_ability = ""
				pending_item = ""
				_log("Cancelled.")
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
		if pending_ability != "" or pending_item != "":
			_exec_pending_on(occ)
			return
		if core.dist(sel, occ) <= int(sel["rng"]) + 1 and int(sel["ap"]) >= 2:
			sel["ap"] = int(sel["ap"]) - 2
			var hp0: int = occ["hp"]
			var landed: bool = core.do_fire(battle, sel, occ, {"ignoreCover": sel.get("wIC", false)})
			_log("%s %s %s%s" % [sel["name"], "hits" if landed else "misses", occ["name"],
				(" for %d" % (hp0 - int(occ["hp"]))) if landed else ""])
			_after_action()
		else:
			_log("Out of range or no AP.")
		return
	var key := "%d,%d" % [q, r]
	if not sel.is_empty() and pending_ability == "" and reach_map.has(key):
		sel["ap"] = int(sel["ap"]) - int(reach_map[key])
		sel["q"] = q
		sel["r"] = r
		if int(sel["status"]["bleed"]) > 0:
			core.apply_damage(battle, sel, 2)
			sel["status"]["bleed"] = int(sel["status"]["bleed"]) - 1
		_select(sel)

func _end_turn() -> void:
	if ended:
		return
	_log("Enemies stir...")
	core.enemy_phase(battle)
	for p in battle["players"]:
		if p["alive"]:
			p["ap"] = p["maxAp"]
			core.tick_status(battle, p)
	_sync_units()
	if _check_end():
		return
	var alive: Array = battle["players"].filter(func(p): return p["alive"])
	if alive.size() > 0:
		_select(alive[0])
		_log("— Your move —")

func _after_action() -> void:
	_sync_units()
	_select(sel if sel.get("alive", false) else sel)
	_check_end()

func _check_end() -> bool:
	if ended:
		return true
	var e_alive: bool = not battle["enemies"].filter(func(e): return e["alive"]).is_empty()
	var p_alive: bool = not battle["players"].filter(func(p): return p["alive"]).is_empty()
	if e_alive and p_alive:
		return false
	ended = true
	var win := p_alive
	banner_label.text = "THE DUST SETTLES" if win else "WIPED OUT"
	banner_label.modulate = Color("#d4a843") if win else Color("#c0392b")
	banner.visible = true
	set_meta("win", win)
	return true

func _finish_and_return() -> void:
	var win: bool = get_meta("win", false)
	var summary: Dictionary = GS.apply_battle_result(battle, win, int(battle["kills"]))
	GS.last_result = {"win": win, "kills": int(battle["kills"]),
		"xp": summary["xp"], "context": params.get("context", {})}
	get_tree().change_scene_to_file("res://scenes/worldmap.tscn")
