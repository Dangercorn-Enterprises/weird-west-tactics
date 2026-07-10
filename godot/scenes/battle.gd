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
var banner_summary: Label
var intro_open := false
var intro_panel: PanelContainer
var _animating := {} # unit id -> true while a tween owns the sprite transform
var _anim_time := 0.0
var preview_panel: PanelContainer
var preview_label: Label
var _hover_id: Variant = null # unit id currently previewed, to skip redundant rebuilds

func _tx(q: int) -> float: return (float(q) - 4.5) * TILE
func _tz(r: int) -> float: return (float(r) - 4.5) * TILE
func _top_y(h: int) -> float: return BASE + float(h) * STEP

func _ready() -> void:
	GS = get_node("/root/GameState")
	core = CombatCoreScript.new()
	core.design = GS.design
	core.seed_rng(int(Time.get_ticks_usec()) & 0x7FFFFFFF)
	core.on_damage = _on_unit_damaged
	core.on_cover_hit = _on_cover_hit
	core.on_charge = _on_charge
	core.on_summon = func(m: Dictionary): _log("%s claws out of the dust!" % m["name"])
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
	# boss-aware battle music (mirrors web scene_battle enter(): boss fights get
	# the tighter, lower "boss" mood; normal skirmishes get "battle").
	var abus := get_node_or_null("/root/Audio")
	if abus:
		var is_boss := bool(params.get("context", {}).get("boss", false)) \
			or "boss" in String(params.get("title", "")).to_lower() \
			or "reckoning" in String(params.get("title", "")).to_lower()
		abus.play_music("boss" if is_boss else "battle")

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
		"units": players + enemies, "kills": 0, "playerDeaths": 0,
		"charges": []}

func _build_biome_grid(biome: Dictionary) -> Array:
	var g: Array = []
	for r in core.ROWS:
		var row: Array = []
		for q in core.COLS:
			# cover0/chp/heavy/rough mirror CombatCore.build_grid so destructible
			# cover + difficult terrain work in interactive play.
			row.append({"h": 0, "cover": 0.0, "cover0": 0.0, "chp": 0,
				"heavy": false, "rough": false, "deco": null})
		g.append(row)
	for p in biome.get("h1", []):
		g[p[1]][p[0]]["h"] = 1
	for p in biome.get("h2", []):
		g[p[1]][p[0]]["h"] = 2
	for p in biome.get("hard", []):
		var c: Dictionary = g[p[1]][p[0]]
		c["cover"] = 0.4; c["cover0"] = 0.4; c["chp"] = -1; c["heavy"] = true
		c["deco"] = biome.get("hardDeco", "crate")
	for p in biome.get("soft", []):
		var c: Dictionary = g[p[1]][p[0]]
		c["cover"] = 0.2; c["cover0"] = 0.2; c["chp"] = core.LIGHT_COVER_HP
		c["heavy"] = false
		c["rough"] = true  # 2e: brush/wreckage is difficult terrain (double MP)
		c["deco"] = biome.get("softDeco", "cactus")
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
			# per-tile variation: brightness + a whisper of warm/cool tint so a
			# single biome texture doesn't read as a wallpaper grid
			var vary := 0.92 + float((q * 5 + r * 11) % 4) * 0.035
			var warm := float((q * 3 + r * 7) % 5 - 2) * 0.012
			var top: StandardMaterial3D = mats[0].duplicate()
			top.albedo_color = Color(vary + warm, vary, vary - warm) * (Color.WHITE if top.albedo_texture else Color("#4a3820"))
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
			# deterministic quarter-turn per tile — 4 orientations of one
			# texture kill the repeating-pattern read for free
			top_plane.rotation_degrees.y = 90.0 * float((q * 7 + r * 13 + (q * r) % 3) % 4)
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
			elif int(cell["h"]) == 0:
				# set dressing: small scatter clutter on ~1 in 7 empty flat
				# tiles, deterministic per board position (no gameplay effect)
				var sh: int = (q * 31 + r * 17 + q * r * 7) % 29
				if sh < SCATTER_DECO.size():
					_add_scatter(SCATTER_DECO[sh], q, r, h)

const SCATTER_DECO := ["scatter_tumbleweed", "scatter_grass", "scatter_pebbles", "scatter_wheel"]

func _add_scatter(name: String, q: int, r: int, h: float) -> void:
	var path := "res://assets/props/%s.png" % name
	if not ResourceLoader.exists(path):
		return
	var spr := Sprite3D.new()
	spr.texture = load(path)
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var world_h := 0.30
	spr.pixel_size = world_h / float(spr.texture.get_height())
	spr.shaded = false
	# hash jitter off tile-center so clutter doesn't sit under unit feet
	var jx := float((q * 13 + r * 5) % 5 - 2) * 0.09
	var jz := float((q * 3 + r * 11) % 5 - 2) * 0.09
	spr.position = Vector3(_tx(q) + jx, h + world_h / 2.0 - 0.02, _tz(r) + jz)
	add_child(spr)

var _cover_props := {} # "q,r" -> the cover Node3D, so it can degrade/shatter

func _add_prop(deco: String, q: int, r: int, h: float, big: bool) -> void:
	var key := "%d,%d" % [q, r]
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
		_cover_props[key] = spr
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
		_cover_props[key] = dmi

# CombatCore.on_cover_hit(q, r, chp_left): light cover degrades (lean it,
# darken it) and, when destroyed (chp<=0 or blast=-1), topples and vanishes.
func _on_cover_hit(q: int, r: int, chp_left: int) -> void:
	var node: Node3D = _cover_props.get("%d,%d" % [q, r])
	if node == null or not is_instance_valid(node):
		return
	if chp_left <= 0:
		# destroyed — topple + shrink out, leave the tile bare
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "rotation:z", 1.4, 0.35).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), 0.4)
		tw.chain().tween_callback(node.queue_free)
		_cover_props.erase("%d,%d" % [q, r])
		if node is Sprite3D:
			_spawn_puff(node.position, Color("#c9b89a"))
	else:
		# degraded — a shove and a darker, more battered look
		var tw2 := create_tween()
		tw2.tween_property(node, "position:x", node.position.x + 0.04, 0.06)
		tw2.tween_property(node, "position:x", node.position.x, 0.10)
		if node is Sprite3D:
			node.modulate = node.modulate.darkened(0.18)

# Quick dust burst when cover shatters (a few blob sprites that expand + fade).
func _spawn_puff(pos: Vector3, tint: Color) -> void:
	for i in 5:
		var p := Sprite3D.new()
		p.texture = _blob_texture()
		p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		p.shaded = false
		p.modulate = tint
		p.pixel_size = 0.006
		var ang := float(i) * TAU / 5.0
		p.position = pos
		add_child(p)
		var dst := pos + Vector3(cos(ang) * 0.35, 0.15 + 0.2 * float(i % 2), sin(ang) * 0.35)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(p, "position", dst, 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "modulate:a", 0.0, 0.45)
		tw.tween_property(p, "scale", Vector3(2.2, 2.2, 2.2), 0.45)
		tw.chain().tween_callback(p.queue_free)

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

# CombatCore.on_charge(q, r, lit): a fuse-delay stick (2c) lands lit or goes
# off. The pulsing marker IS the trope — the cowboy sees it and moves.
var _charge_props := {}

func _on_charge(q: int, r: int, lit: bool) -> void:
	var key := "%d,%d" % [q, r]
	if lit:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.18)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#c0392b")
		mat.emission_enabled = true
		mat.emission = Color("#ff6b4a")
		mat.emission_energy_multiplier = 1.2
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(_tx(q), _top_y(int(grid[r][q]["h"])) + 0.12, _tz(r))
		add_child(mi)
		var tw := create_tween().set_loops()
		tw.tween_property(mi, "scale", Vector3(1.35, 1.35, 1.35), 0.35)
		tw.tween_property(mi, "scale", Vector3.ONE, 0.35)
		_charge_props[key] = mi
		_log("A lit stick of dynamite lands — MOVE!")
	else:
		var node: Node3D = _charge_props.get(key)
		if node != null and is_instance_valid(node):
			var tw := create_tween()
			tw.tween_property(node, "scale", Vector3(2.2, 2.2, 2.2), 0.12)
			tw.tween_property(node, "scale", Vector3.ZERO, 0.15)
			tw.tween_callback(node.queue_free)
		_charge_props.erase(key)
		_log("The dynamite goes off!")

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
func _on_unit_damaged(u: Dictionary, dmg: int, crit := false) -> void:
	var abus := get_node_or_null("/root/Audio")
	if abus:
		abus.sfx("shot")
		if dmg > 0:
			abus.sfx("hit")
			if crit:
				abus.sfx("blast") # extra punch on a crit
	var y := _top_y(int(grid[u["r"]][u["q"]]["h"]))
	# Crit: amber "CRIT -N" floater regardless of side; normal hits keep the
	# red(player)/gold(enemy) convention.
	var col := Color("#ffcf3f") if crit else (Color("#c0392b") if u["side"] == "p" else Color("#d4a843"))
	_floater(("CRIT -%d" % dmg) if crit else "-%d" % dmg,
		Vector3(_tx(u["q"]), y + 1.7, _tz(u["r"])), col, crit)
	if unit_nodes.has(u["id"]):
		var spr: Sprite3D = unit_nodes[u["id"]]["sprite"]
		spr.modulate = Color(5, 4.2, 2) if crit else Color(3, 3, 3) # brighter amber flash on crit
		var tw := create_tween()
		tw.tween_property(spr, "modulate", Color.WHITE, 0.42 if crit else 0.28)
		if crit:
			# localized hitstop feel: a quick scale-punch on the struck sprite
			# (no global time_scale, so it never fights the tween-based movement)
			var base_scale: Vector3 = spr.scale if not spr.has_meta("base_scale") else spr.get_meta("base_scale")
			spr.set_meta("base_scale", base_scale)
			var pt := create_tween()
			pt.tween_property(spr, "scale", base_scale * 1.28, 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pt.tween_property(spr, "scale", base_scale, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _floater(text: String, pos: Vector3, col: Color, crit := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 72 if crit else 56
	l.pixel_size = 0.009 if crit else 0.007
	l.outline_size = 14 if crit else 10
	l.modulate = col
	l.position = pos
	add_child(l)
	var rise := 1.2 if crit else 0.9
	var dur := 1.15 if crit else 0.9
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + rise, dur)
	tw.tween_property(l, "modulate:a", 0.0, dur).set_delay(0.3 if crit else 0.25)
	tw.chain().tween_callback(l.queue_free)

# ---- movement / attack animation (v1.3 juice pass) --------------------------------
# Procedural motion on the existing facing sprites: tiled walk with a hop arc,
# attack lunge + recoil, enemy-phase slides, idle breathing. Composes with
# future frame-art (swap textures per segment) without touching CombatCore.

# Reconstruct a tile path from CombatCore.reach()'s BFS cost map by greedy
# cost descent (every BFS node has a strictly cheaper neighbour toward start).
static func path_from_reach(reach: Dictionary, from_q: int, from_r: int, to_q: int, to_r: int) -> Array:
	if (from_q == to_q and from_r == to_r) or not reach.has("%d,%d" % [to_q, to_r]):
		return []
	var path: Array = []
	var q := to_q
	var r := to_r
	var guard := 0
	while (q != from_q or r != from_r) and guard < 128:
		guard += 1
		path.push_front([q, r])
		var best_cost := int(reach["%d,%d" % [q, r]])
		var best: Variant = null
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var k := "%d,%d" % [q + d[0], r + d[1]]
			if reach.has(k) and int(reach[k]) < best_cost:
				best_cost = int(reach[k])
				best = [q + d[0], r + d[1]]
		if best == null:
			return path # malformed map — return the partial path
		q = best[0]
		r = best[1]
	return path

# Move sprite+shadow+label along a ground segment with a sine hop.
func _anim_glide(t: float, id: Variant, a: Vector3, b: Vector3, hop: float) -> void:
	if not unit_nodes.has(id):
		return
	var n: Dictionary = unit_nodes[id]
	var g := a.lerp(b, t)
	var half := float(n.get("half", 0.7))
	n["sprite"].position = Vector3(g.x, g.y + half + sin(t * PI) * hop, g.z)
	if n.has("shadow"):
		n["shadow"].position = Vector3(g.x, g.y + 0.012, g.z)
	n["label"].position = Vector3(g.x, g.y + (2.35 if half > 1.0 else 1.6), g.z)

func _animate_move(u: Dictionary, from_q: int, from_r: int, path: Array) -> void:
	if path.is_empty() or not unit_nodes.has(u["id"]):
		return
	var id: Variant = u["id"]
	_animating[id] = true
	unit_nodes[id]["ring"].visible = false
	var tw := create_tween()
	var pq := from_q
	var pr := from_r
	for step in path:
		var sq: int = step[0]
		var sr: int = step[1]
		var a := Vector3(_tx(pq), _top_y(int(grid[pr][pq]["h"])), _tz(pr))
		var b := Vector3(_tx(sq), _top_y(int(grid[sr][sq]["h"])), _tz(sr))
		var fdir := Vector2(sq - pq, sr - pr)
		tw.tween_callback(func(): u["facing"] = fdir)
		tw.tween_method(_anim_glide.bind(id, a, b, 0.14), 0.0, 1.0, 0.13)
		pq = sq
		pr = sr
	tw.tween_callback(func():
		_animating.erase(id)
		_sync_units())

func _animate_lunge(att: Dictionary, tgt: Dictionary) -> void:
	if not unit_nodes.has(att["id"]) or _animating.has(att["id"]):
		return
	var id: Variant = att["id"]
	var n: Dictionary = unit_nodes[id]
	var spr: Sprite3D = n["sprite"]
	_animating[id] = true
	var origin: Vector3 = spr.position
	if n.has("base_y"):
		origin.y = float(n["base_y"]) # de-bob so the recoil settles at rest height
	var to := Vector3(_tx(int(tgt["q"])), origin.y, _tz(int(tgt["r"])))
	var dirv := to - origin
	dirv.y = 0.0
	var push := dirv.normalized() * 0.26 if dirv.length() > 0.01 else Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(spr, "position", origin + push, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position", origin, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _animating.erase(id))

func _animate_enemy_slide(e: Dictionary, from_q: int, from_r: int, delay: float) -> void:
	if not unit_nodes.has(e["id"]) or _animating.has(e["id"]):
		return
	var id: Variant = e["id"]
	_animating[id] = true
	var a := Vector3(_tx(from_q), _top_y(int(grid[from_r][from_q]["h"])), _tz(from_r))
	var b := Vector3(_tx(int(e["q"])), _top_y(int(grid[int(e["r"])][int(e["q"])]["h"])), _tz(int(e["r"])))
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	var dur := clampf(0.11 * a.distance_to(b), 0.14, 0.5)
	tw.tween_method(_anim_glide.bind(id, a, b, 0.1), 0.0, 1.0, dur)
	tw.tween_callback(func():
		_animating.erase(id)
		_sync_units())

# ---- status effect readout ----------------------------------------------------
# Neither the web nor the old Godot build showed WHO is burning/bleeding/
# marked — the player had to infer it from the log. This surfaces active
# statuses as compact codes above each unit (marked especially: it's a 1.3x
# damage multiplier the combat preview uses). Font-safe letter codes, not
# emoji (the bundled typewriter font renders those as tofu). Priority order
# controls the single label colour when several are active at once.
const STATUS_INFO := [
	["marked", "MRK", Color("#ffcf3f")],  # amber — the damage-mult flag, show first
	["bleed", "BLD", Color("#c0392b")],
	["burn", "BRN", Color("#e8823a")],
	["stun", "STN", Color("#d0d0d0")],
	["conf", "CNF", Color("#b07de0")],
	["hex", "HEX", Color("#8e5fd0")],
	["hunker", "HNK", Color("#4ecdc4")],  # teal — the one buff
]

func _status_display(u: Dictionary) -> Dictionary:
	var st: Dictionary = u.get("status", {})
	var parts: Array = []
	var color := Color.WHITE
	for entry in STATUS_INFO:
		var n := int(st.get(entry[0], 0))
		if n > 0:
			if parts.is_empty():
				color = entry[2]  # first (highest-priority) active status sets colour
			parts.append("%s%d" % [entry[1], n])
	return {"text": " ".join(parts), "color": color}

# ---- unit sprites -----------------------------------------------------------------
# HD-2D facings: front / back / side (side mirrors for the 4th quadrant).
# Missing views fall back to front so partial art never breaks a battle.
func _sprite_textures(u: Dictionary) -> Dictionary:
	var id := str(u.get("archetype", ""))
	var front := _sprite_texture(u)
	var out := {"front": front, "back": front, "side": front, "side_r": null}
	for k in ["back", "side", "side_r"]:
		var path := "res://assets/sprites/%s_%s.png" % [id, k]
		if ResourceLoader.exists(path):
			out[k] = load(path)
	if out["side_r"] == null:
		out["side_r"] = out["side"] # fallback: mirror the left view
		out["side_r_mirrored"] = true
	return out

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
		u["facing"] = Vector2(1, 0) if u["side"] == "p" else Vector2(-1, 0)
		var spr := Sprite3D.new()
		var texset := _sprite_textures(u)
		spr.set_meta("texset", texset)
		spr.set_meta("view", "front")
		spr.texture = texset["front"]
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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
		var status := _make_status_label()
		add_child(status)
		var shadow := _add_ground_shadow(Vector3.ZERO, 0.5)
		unit_nodes[u["id"]] = {"sprite": spr, "label": lbl, "ring": ring, "shadow": shadow,
			"status": status, "half": 1.07 if u.get("boss", false) else 0.7}
	_sync_units()

func _make_status_label() -> Label3D:
	var s := Label3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.font_size = 26
	s.pixel_size = 0.006
	s.outline_size = 6
	s.visible = false
	return s

func _sync_units() -> void:
	for u in battle["units"]:
		if not unit_nodes.has(u["id"]):
			continue # boss-phase summons get nodes on demand below
		if _animating.has(u["id"]):
			continue # a tween owns this sprite right now
		var n: Dictionary = unit_nodes[u["id"]]
		var y := _top_y(int(grid[u["r"]][u["q"]]["h"]))
		var half := 1.07 if u.get("boss", false) else 0.7
		n["sprite"].position = Vector3(_tx(u["q"]), y + half, _tz(u["r"]))
		n["base_y"] = n["sprite"].position.y
		n["sprite"].visible = u["alive"]
		if n.has("shadow"):
			n["shadow"].position = Vector3(_tx(u["q"]), y + 0.012, _tz(u["r"]))
			n["shadow"].visible = u["alive"]
		var hp_y := y + (2.35 if u.get("boss", false) else 1.6)
		n["label"].position = Vector3(_tx(u["q"]), hp_y, _tz(u["r"]))
		n["label"].text = "%d" % maxi(0, int(u["hp"]))
		n["label"].visible = u["alive"]
		if n.has("status"):
			var sd := _status_display(u)
			var slbl: Label3D = n["status"]
			slbl.position = Vector3(_tx(u["q"]), hp_y + 0.32, _tz(u["r"])) # just above HP
			slbl.text = sd["text"]
			slbl.modulate = sd["color"]
			slbl.visible = u["alive"] and sd["text"] != ""
		n["ring"].position = Vector3(_tx(u["q"]), y + 0.03, _tz(u["r"]))
		n["ring"].visible = u["alive"] and not sel.is_empty() and u["id"] == sel.get("id")
	# boss-phase summons (Risen Dead) appear mid-fight
	for u in battle["units"]:
		if not unit_nodes.has(u["id"]):
			_build_unit_node(u)

func _build_unit_node(u: Dictionary) -> void:
	u["facing"] = Vector2(-1, 0)
	var spr := Sprite3D.new()
	var texset := _sprite_textures(u)
	spr.set_meta("texset", texset)
	spr.set_meta("view", "front")
	spr.texture = texset["front"]
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
	var status := _make_status_label()
	add_child(status)
	unit_nodes[u["id"]] = {"sprite": spr, "label": lbl, "ring": ring, "status": status, "half": 0.7}

# ---- HUD ---------------------------------------------------------------------------
func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	# Themed full-rect root so the battle HUD matches every other scene
	# (parchment/brass leather look) — theme propagates to all children.
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE # don't eat board clicks
	GS.apply_theme(hud)
	cl.add_child(hud)
	var title := Label.new()
	title.text = str(params.get("title", "Skirmish"))
	title.position = Vector2(16, 8)
	GS.headline(title, 24) # Rye display face, amber, drop shadow — like town/worldmap
	hud.add_child(title)
	log_label = Label.new()
	log_label.position = Vector2(16, 44)
	log_label.add_theme_font_size_override("font_size", 15)
	hud.add_child(log_label)
	ability_bar = HBoxContainer.new()
	ability_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ability_bar.position = Vector2(16, -56)
	ability_bar.offset_top = -56.0
	ability_bar.offset_left = 16.0
	hud.add_child(ability_bar)
	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.visible = false
	var bb := VBoxContainer.new()
	banner_label = Label.new()
	banner_label.add_theme_font_size_override("font_size", 40)
	bb.add_child(banner_label)
	banner_summary = Label.new()
	banner_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_summary.custom_minimum_size = Vector2(420, 0)
	banner_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bb.add_child(banner_summary)
	var cont := Button.new()
	cont.text = "Continue"
	cont.pressed.connect(_finish_and_return)
	bb.add_child(cont)
	banner.add_child(bb)
	hud.add_child(banner)
	# combat preview panel — small odds readout shown while hovering an enemy
	preview_panel = PanelContainer.new()
	preview_panel.visible = false
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_panel.position = Vector2(16, 96)
	preview_label = Label.new()
	preview_label.add_theme_font_size_override("font_size", 16)
	preview_panel.add_child(preview_label)
	hud.add_child(preview_panel)
	# story beat intro (narrative overlay shown before the first move)
	if params.get("intro", "") != "":
		intro_open = true
		intro_panel = PanelContainer.new()
		intro_panel.set_anchors_preset(Control.PRESET_CENTER)
		intro_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		intro_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var iv := VBoxContainer.new()
		var it := Label.new()
		it.text = str(params.get("title", ""))
		GS.headline(it, 30)
		it.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		iv.add_child(it)
		var ib := Label.new()
		ib.text = str(params["intro"])
		ib.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ib.custom_minimum_size = Vector2(480, 0)
		iv.add_child(ib)
		var ride := Button.new()
		ride.text = "Ride"
		ride.pressed.connect(func():
			intro_open = false
			intro_panel.queue_free())
		iv.add_child(ride)
		intro_panel.add_child(iv)
		hud.add_child(intro_panel)

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
	# Session #2 decision 2b (Tim): hunkering ends the unit's turn — kills the
	# shoot-then-hunker dominant line (Njord's turtle exploit).
	hb.text = "Hunker (ends turn)"
	hb.disabled = int(sel["ap"]) < 1
	hb.pressed.connect(func():
		sel["ap"] = 0
		sel["status"]["hunker"] = maxi(int(sel["status"]["hunker"]), 2)
		_log("%s hunkers down for the rest of the turn." % sel["name"])
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
	# Positioning v1: direct-fire abilities and single-target divines respect LOS —
	# refuse (no cost, no lunge) rather than waste the AP/favor/once-per-fight ult
	# on do_fire's silent LOS gate. Blast divines and support/AoE lob over terrain.
	var fx: Dictionary = core.ABIL_FX.get(aname, {})
	var is_divine: bool = aname == sel.get("divine")
	var needs_los: bool = (is_divine and not core.DIVINE_BLAST.has(aname)) \
		or (not is_divine and not fx.is_empty()
			and not (str(fx.get("kind", "atk")) in ["heal", "blast"]))
	if needs_los and not core.has_los(grid, sel, target):
		_log("No line of sight.")
		return
	sel["facing"] = Vector2(int(target["q"]) - int(sel["q"]), int(target["r"]) - int(sel["r"])).normalized()
	_animate_lunge(sel, target)
	if is_divine:
		_cast_divine(target)
		return
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

# ---- combat preview (hover an enemy to see the odds) --------------------------
# Pure port of the web build's drawPreview math, driven by the parity-tested
# CombatCore.hit_chance + the shared ABIL_FX table (no PREVIEW_FX duplication).
# Returns a small dict the HUD renders; null when there's nothing to preview.
func combat_preview(attacker: Dictionary, target: Dictionary, ability := "") -> Dictionary:
	var fx: Dictionary = core.ABIL_FX.get(ability, {}) if ability != "" else {"ic": attacker.get("wIC", false)}
	var kind := str(fx.get("kind", "atk"))
	if kind in ["heal", "blast"]:
		# support/AoE abilities: no single-target hit roll to preview honestly
		return {"ability": ability, "kind": kind, "in_range": true}
	var ic := bool(fx.get("ic", false))
	# hit chance: apply aimMod on a copy so we never mutate live unit state mid-frame
	var att := attacker.duplicate()
	att["aim"] = int(att["aim"]) + int(fx.get("aimMod", 0))
	var ch: int = 95 if bool(fx.get("guaranteed", false)) else core.hit_chance(grid, att, target, ic)
	var mult := float(fx.get("mult", 1.0))
	var marked_f := 1.3 if int(target.get("status", {}).get("marked", 0)) > 0 else 1.0
	var base := int(attacker["str"]) / 3 # integer div, mirrors floor(str/3)
	var lo := int(round(float(int(attacker["wmin"]) + base) * mult * marked_f))
	var hi := int(round(float(int(attacker["wmax"]) + base) * mult * marked_f))
	var armor := int(target.get("armorDef", 0))
	if armor > 0:
		lo = maxi(1, lo - armor)
		hi = maxi(1, hi - armor)
	return {
		"ability": ability, "kind": kind, "hit": ch, "lo": lo, "hi": hi,
		"shots": int(fx.get("shots", 1)),
		"in_range": core.dist(attacker, target) <= int(attacker["rng"]) + 1,
		"los": core.has_los(grid, attacker, target),
	}

func _preview_text(p: Dictionary) -> String:
	if p.get("kind", "atk") in ["heal", "blast"]:
		var verb := "AoE strike" if p["kind"] == "blast" else "Support"
		return "%s\n%s" % [p.get("ability", ""), verb]
	var head := str(p.get("ability", "")).strip_edges()
	# a blocked shot has no honest odds to show — say why instead of a fake %
	if not p.get("los", true):
		return ("%s\n" % head if head != "" else "") + "NO LINE OF SIGHT"
	var shots: int = p.get("shots", 1)
	var line1 := "%d%% to hit%s" % [int(p["hit"]), (" x%d" % shots) if shots > 1 else ""]
	var line2 := "%d-%d dmg" % [int(p["lo"]), int(p["hi"])]
	var out := ("%s\n" % head if head != "" else "") + line1 + "\n" + line2
	if not p.get("in_range", true) and head == "":
		out += "\nOUT OF RANGE"
	return out

func _update_preview(screen_pos: Vector2) -> void:
	if preview_panel == null:
		return
	var hide: bool = ended or intro_open or sel.is_empty() or not sel.get("alive", false) or sel.get("side") != "p"
	var occ := {}
	if not hide:
		occ = _unit_at_screen(screen_pos)
	if occ.is_empty() or occ.get("side") != "e" or not occ.get("alive", false):
		preview_panel.visible = false
		_hover_id = null
		return
	var p := combat_preview(sel, occ, pending_ability)
	preview_label.text = _preview_text(p)
	preview_panel.visible = true
	_hover_id = occ["id"]

func _unit_at_screen(screen_pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit["collider"].has_meta("q"):
		return {}
	var q: int = hit["collider"].get_meta("q")
	var r: int = hit["collider"].get_meta("r")
	for u in battle["units"]:
		if u["alive"] and u["q"] == q and u["r"] == r:
			return u
	return {}

# ---- selection / highlights -----------------------------------------------------
func _select(u: Dictionary) -> void:
	sel = u
	pending_ability = ""
	pending_item = ""
	if preview_panel:
		preview_panel.visible = false # avoid stale odds until the next hover
		_hover_id = null
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
	if ended or intro_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: cam_target_azimuth -= PI / 2
			KEY_E: cam_target_azimuth += PI / 2
			KEY_ENTER, KEY_KP_ENTER: _end_turn()
			KEY_ESCAPE:
				# swallow Esc only while a targeting flow is pending; a bare Esc
				# falls through to the PauseMenu autoload
				if pending_ability != "" or pending_item != "":
					pending_ability = ""
					pending_item = ""
					_log("Cancelled.")
					get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
	if event is InputEventMouseMotion:
		_update_preview(event.position)

func _process(_delta: float) -> void:
	var d := cam_target_azimuth - cam_azimuth
	if absf(d) > 0.0005:
		cam_azimuth += d * 0.14
		_place_camera()
	_update_facings()
	# idle breathing: subtle bob around the synced rest height, phase per unit
	_anim_time += _delta
	for u in battle["units"]:
		if not u["alive"] or _animating.has(u["id"]) or not unit_nodes.has(u["id"]):
			continue
		var n: Dictionary = unit_nodes[u["id"]]
		if n.has("base_y"):
			n["sprite"].position.y = float(n["base_y"]) \
				+ sin(_anim_time * 2.3 + float(hash(u["id"]) % 628) / 100.0) * 0.018

# pick front/back/side (+mirror) from the angle between unit facing and camera
func _update_facings() -> void:
	# camera forward projected on the ground plane (from camera toward board)
	var cam_fwd := Vector2(-sin(cam_azimuth), -cos(cam_azimuth))
	for u in battle["units"]:
		if not unit_nodes.has(u["id"]):
			continue
		var spr: Sprite3D = unit_nodes[u["id"]]["sprite"]
		if not spr.has_meta("texset"):
			continue
		var f: Vector2 = u.get("facing", Vector2(1, 0))
		var dot := f.dot(cam_fwd)
		var cross := f.x * cam_fwd.y - f.y * cam_fwd.x
		var view: String
		var flip := false
		if dot > 0.5:
			view = "back" # walking away from the camera
		elif dot < -0.5:
			view = "front"
		else:
			if cross < 0.0:
				# right-facing: use the independent view when we have one;
				# only mirror the left view as a fallback
				var ts: Dictionary = spr.get_meta("texset")
				view = "side_r"
				flip = ts.get("side_r_mirrored", false)
			else:
				view = "side"
				flip = false
		if str(spr.get_meta("view")) != view or spr.flip_h != flip:
			var texset: Dictionary = spr.get_meta("texset")
			spr.texture = texset[view]
			spr.flip_h = flip
			spr.set_meta("view", view)

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
			# Positioning v1: refuse the impossible shot (no AP) instead of letting
			# do_fire's LOS gate silently whiff a paid action.
			if not core.has_los(grid, sel, occ):
				_log("No line of sight.")
				return
			sel["ap"] = int(sel["ap"]) - 2
			sel["facing"] = Vector2(int(occ["q"]) - int(sel["q"]), int(occ["r"]) - int(sel["r"])).normalized()
			_animate_lunge(sel, occ)
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
		_do_move(q, r)

# Move the selected unit along the BFS path with the walk animation.
# Split from _click so tests and the autopilot can drive moves directly.
func _do_move(q: int, r: int) -> void:
	var key := "%d,%d" % [q, r]
	var from_q := int(sel["q"])
	var from_r := int(sel["r"])
	var path := path_from_reach(reach_map, from_q, from_r, q, r)
	sel["ap"] = int(sel["ap"]) - int(reach_map[key])
	sel["q"] = q
	sel["r"] = r
	_animate_move(sel, from_q, from_r, path) # sets per-segment facing
	if path.is_empty():
		sel["facing"] = Vector2(q - from_q, r - from_r).normalized()
	if int(sel["status"]["bleed"]) > 0:
		core.apply_damage(battle, sel, 2)
		sel["status"]["bleed"] = int(sel["status"]["bleed"]) - 1
	_select(sel)

func _end_turn() -> void:
	if ended:
		return
	_log("Enemies stir...")
	var pre := {}
	for e in battle["enemies"]:
		pre[e["id"]] = Vector2(e["q"], e["r"])
	core.enemy_phase(battle)
	for e in battle["enemies"]:
		if not e["alive"]:
			continue
		var moved: Vector2 = Vector2(e["q"], e["r"]) - pre.get(e["id"], Vector2(e["q"], e["r"]))
		if moved.length() > 0.1:
			e["facing"] = moved.normalized()
		else:
			var best := {}
			var bd := 9999
			for pl in battle["players"]:
				if pl["alive"] and core.dist(e, pl) < bd:
					bd = core.dist(e, pl)
					best = pl
			if not best.is_empty():
				e["facing"] = Vector2(int(best["q"]) - int(e["q"]), int(best["r"]) - int(e["r"])).normalized()
	# staggered slide animation for every enemy that moved this phase
	var slide_delay := 0.0
	for e in battle["enemies"]:
		if not e["alive"]:
			continue
		var p: Vector2 = pre.get(e["id"], Vector2(e["q"], e["r"]))
		if Vector2(e["q"], e["r"]) != p:
			_animate_enemy_slide(e, int(p.x), int(p.y), slide_delay)
			slide_delay += 0.07
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
	var summary: Dictionary = GS.apply_battle_result(battle, win, int(battle["kills"]))
	GS.last_result = {"win": win, "kills": int(battle["kills"]),
		"xp": summary["xp"], "context": params.get("context", {})}
	banner_label.text = "THE DUST SETTLES" if win else "WIPED OUT"
	banner_label.modulate = Color("#d4a843") if win else Color("#c0392b")
	var lines := "%d kills · +%d XP" % [int(battle["kills"]), int(summary["xp"])]
	# 2i: XP surfaced where it lands — one line per deployed rider
	for g in summary.get("gains", []):
		lines += "\n%s  +%d XP — Lv %d (%d/%d)" % [g["name"], int(g["xp"]),
			int(g["level"]), int(g["into"]), int(g["next"])]
	if summary["levelUps"].size() > 0:
		lines += "\nLEVEL UP — " + ", ".join(summary["levelUps"])
	var hurt: Array = []
	for m in GS.state["party"]:
		if int(m.get("hpDamage", 0)) > 0:
			hurt.append(str(m["name"]))
	if hurt.size() > 0:
		lines += "\nWounded: " + ", ".join(hurt) + " — rest at a saloon or see a Doc."
	banner_summary.text = lines
	banner.visible = true
	return true

func _finish_and_return() -> void:
	get_tree().change_scene_to_file("res://scenes/worldmap.tscn")
