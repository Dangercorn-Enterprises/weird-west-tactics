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
var music_slider: HSlider
var sfx_slider: HSlider
var mute_check: CheckButton
var quit_title_btn: Button

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
