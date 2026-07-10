# =============================================================================
# DUSTFALL — PAUSE / SYSTEM MENU (autoload singleton "PauseMenu")
# Esc anywhere: pause the tree under a dim overlay — resume, music/SFX volume,
# mute, quit to title, quit to desktop. Built in code (no scene file) so the
# headless test harness can drive it. Campaign state saves on every mutation,
# so quitting from here never loses progress. Battle swallows Esc only while a
# targeting flow is pending; otherwise the event falls through to this layer.
# =============================================================================
extends CanvasLayer

var open := false
var ui_root: Control
var main_box: VBoxContainer
var posse_box: VBoxContainer
var music_slider: HSlider
var sfx_slider: HSlider
var mute_check: CheckButton
var quit_title_btn: Button
var posse_btn: Button

func _gamestate() -> Node:
	return get_node_or_null("/root/GameState")

func _audio() -> Node:
	return get_node_or_null("/root/Audio")

func _ready() -> void:
	layer = 100
	# the menu itself must keep processing while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	ui_root.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if open:
		close()
	else:
		open_menu()

func open_menu() -> void:
	if open:
		return
	open = true
	get_tree().paused = true
	_sync_controls()
	ui_root.visible = true

func close() -> void:
	if not open:
		return
	open = false
	get_tree().paused = false
	ui_root.visible = false
	# next Esc opens the main menu, not a stale posse view
	if posse_box != null:
		posse_box.visible = false
	if main_box != null:
		main_box.visible = true

func _quit_to_title() -> void:
	close()
	var a := _audio()
	if a:
		a.stop_music() # title.gd's on_scene("title") restarts the right mood
	get_tree().change_scene_to_file("res://scenes/title.tscn")

# ---- UI (pure code, themed like every other scene) --------------------------------
func _build_ui() -> void:
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_STOP # swallow board clicks under the menu
	var gs := _gamestate()
	if gs and gs.has_method("apply_theme"):
		gs.apply_theme(ui_root)
	add_child(ui_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.01, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(pad)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)
	main_box = box
	# posse sheet lives beside the main menu in the same panel; one visible at
	# a time (Session #2 decision 2i follow-up build — the "real" party screen)
	posse_box = VBoxContainer.new()
	posse_box.custom_minimum_size = Vector2(700, 0)
	posse_box.add_theme_constant_override("separation", 8)
	posse_box.visible = false
	pad.add_child(posse_box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if gs and gs.has_method("headline"):
		gs.headline(title, 40)
	box.add_child(title)

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(close)
	box.add_child(resume)

	posse_btn = Button.new()
	posse_btn.text = "Posse  (roster & ride order)"
	posse_btn.pressed.connect(_open_posse)
	box.add_child(posse_btn)

	music_slider = _add_slider(box, "Music", _on_music_changed)
	sfx_slider = _add_slider(box, "SFX", _on_sfx_changed)
	sfx_slider.drag_ended.connect(_on_sfx_drag_ended)

	mute_check = CheckButton.new()
	mute_check.text = "Mute all audio"
	mute_check.toggled.connect(_on_mute_toggled)
	box.add_child(mute_check)

	box.add_child(HSeparator.new())

	quit_title_btn = Button.new()
	quit_title_btn.text = "Quit to Title  (progress is saved)"
	quit_title_btn.pressed.connect(_quit_to_title)
	box.add_child(quit_title_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Desktop"
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

func _add_slider(box: VBoxContainer, label_text: String, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(64, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(220, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	box.add_child(row)
	return s

# ---- handlers ----------------------------------------------------------------------
func _on_music_changed(v: float) -> void:
	var a := _audio()
	if a:
		a.set_music_volume(v)

func _on_sfx_changed(v: float) -> void:
	var a := _audio()
	if a:
		a.set_sfx_volume(v)

func _on_sfx_drag_ended(_changed: bool) -> void:
	var a := _audio()
	if a:
		a.sfx("click") # audible feedback at the new level

func _on_mute_toggled(pressed: bool) -> void:
	var a := _audio()
	if a and pressed != a.is_muted():
		a.toggle_mute()

func _sync_controls() -> void:
	var a := _audio()
	if a:
		music_slider.set_value_no_signal(a.get_music_volume())
		sfx_slider.set_value_no_signal(a.get_sfx_volume())
		mute_check.set_pressed_no_signal(a.is_muted())
	var sc := get_tree().current_scene
	quit_title_btn.disabled = sc != null and String(sc.name) == "Title"
	posse_btn.disabled = _party().is_empty()

# ---- posse sheet (Session #2 decision 2i: the real party screen) -------------------
# Read-only character sheet + ride-order reorder. Battle deploys party[0..3]
# and only deployed riders earn XP, so the order IS the roster decision.
# LIVE stats render bright; dormant stats render dim — the sheet never prints
# a dead number as a live one (LIVE_STATS contract in game_state.gd).

func _party() -> Array:
	var gs := _gamestate()
	if gs != null and ("state" in gs) and gs.state is Dictionary:
		return gs.state.get("party", [])
	return []

func _open_posse() -> void:
	_refresh_posse()
	main_box.visible = false
	posse_box.visible = true

func _back_to_main() -> void:
	posse_box.visible = false
	main_box.visible = true

func _swap(a: int, b: int) -> void:
	var party := _party()
	if a < 0 or b < 0 or a >= party.size() or b >= party.size():
		return
	var t = party[a]
	party[a] = party[b]
	party[b] = t
	var gs := _gamestate()
	if gs and gs.has_method("save_game"):
		gs.save_game() # header contract: state saves on every mutation
	_refresh_posse()

func _refresh_posse() -> void:
	for c in posse_box.get_children():
		posse_box.remove_child(c)
		c.queue_free()
	var gs := _gamestate()
	var head := Label.new()
	head.text = "THE POSSE"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if gs and gs.has_method("headline"):
		gs.headline(head, 32)
	posse_box.add_child(head)
	var hint := Label.new()
	hint.text = "Top 4 ride into the next battle — only riders who fight earn XP."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.65)
	posse_box.add_child(hint)
	var party := _party()
	if party.is_empty():
		var none := Label.new()
		none.text = "No posse on the trail — start a campaign."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		posse_box.add_child(none)
	for i in party.size():
		posse_box.add_child(_posse_row(gs, i, party[i]))
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_back_to_main)
	posse_box.add_child(back)

func _gear_name(gs: Node, cat: String, id, fallback: String) -> String:
	if id == null or String(id) == "":
		return fallback
	if gs != null and ("design" in gs) and gs.design is Dictionary:
		for it in gs.design.get(cat, []):
			if it.get("id", "") == String(id):
				return it.get("name", String(id))
	return String(id)

func _posse_row(gs: Node, i: int, m: Dictionary) -> PanelContainer:
	var wrap := PanelContainer.new()
	var pad2 := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad2.add_theme_constant_override("margin_" + side, 10)
	wrap.add_child(pad2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad2.add_child(row)
	# ride-order controls
	var ordc := VBoxContainer.new()
	var up := Button.new()
	up.text = "▲"
	up.disabled = i == 0
	up.pressed.connect(_swap.bind(i, i - 1))
	ordc.add_child(up)
	var dn := Button.new()
	dn.text = "▼"
	dn.disabled = i >= _party().size() - 1
	dn.pressed.connect(_swap.bind(i, i + 1))
	ordc.add_child(dn)
	row.add_child(ordc)
	# identity, bars, stats, gear
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var stats: Dictionary = m.get("stats", {})
	var max_hp := 10 + int(stats.get("vigor", 5)) * 2
	var hp := maxi(1, max_hp - int(m.get("hpDamage", 0)))
	var god = m.get("god")
	var name_l := Label.new()
	name_l.text = "%d · %s — %s, Lv %d   [%s]%s" % [
		i + 1, m.get("name", "Rider"), String(m.get("archetype", "")).capitalize(),
		int(m.get("level", 1)), "RIDES" if i < 4 else "CAMP",
		("  ·  sworn to %s" % String(god).capitalize()) if god else ""]
	mid.add_child(name_l)
	var xp_need: int = gs.xp_for_level(int(m.get("level", 1))) \
		if gs and gs.has_method("xp_for_level") else int(m.get("level", 1)) * 100
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	var hp_l := Label.new()
	hp_l.text = "HP %d/%d" % [hp, max_hp]
	if hp < max_hp:
		hp_l.modulate = Color("#e07a5f") # wounded reads at a glance
	bar_row.add_child(hp_l)
	var xp_bar := ProgressBar.new()
	xp_bar.min_value = 0
	xp_bar.max_value = float(xp_need)
	xp_bar.value = float(int(m.get("xp", 0)))
	xp_bar.custom_minimum_size = Vector2(180, 10)
	xp_bar.show_percentage = false
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(xp_bar)
	var xp_l := Label.new()
	xp_l.text = "XP %d/%d" % [int(m.get("xp", 0)), xp_need]
	xp_l.modulate = Color(1, 1, 1, 0.8)
	bar_row.add_child(xp_l)
	mid.add_child(bar_row)
	var live: Array = gs.LIVE_STATS if gs != null and ("LIVE_STATS" in gs) \
		else ["vigor", "quickness", "strength", "deftness"]
	var live_parts: Array = []
	for s in live:
		live_parts.append("%s %d" % [String(s).substr(0, 3).to_upper(), int(stats.get(s, 0))])
	var live_l := Label.new()
	live_l.text = " · ".join(live_parts)
	mid.add_child(live_l)
	var dead_parts: Array = []
	for s in stats.keys():
		if not live.has(s):
			dead_parts.append("%s %d" % [String(s).substr(0, 3), int(stats.get(s, 0))])
	if dead_parts.size() > 0:
		var dead_l := Label.new()
		dead_l.text = " · ".join(dead_parts) + "   (dormant)"
		dead_l.modulate = Color(1, 1, 1, 0.38)
		mid.add_child(dead_l)
	var gear: Dictionary = m.get("gear", {})
	var wfall := "sidearm"
	if gs != null and ("design" in gs) and gs.design is Dictionary:
		for a in gs.design.get("archetypes", []):
			if a.get("id", "") == m.get("archetype", "") and a.get("weapons", []).size() > 0:
				wfall = a["weapons"][0].get("name", "sidearm")
				break
	var gear_l := Label.new()
	gear_l.text = "%s · %s · %s" % [
		_gear_name(gs, "weapons", gear.get("weapon"), wfall),
		_gear_name(gs, "armor", gear.get("armor"), "no armor"),
		_gear_name(gs, "weapon_mods", gear.get("mod"), "no mod")]
	gear_l.modulate = Color(1, 1, 1, 0.75)
	mid.add_child(gear_l)
	return wrap
