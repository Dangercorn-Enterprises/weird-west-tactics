# =============================================================================
# DUSTFALL — CHARACTER CREATOR (Godot port)
# Forge your lead: pick an archetype (shown with its real sprite art), name
# them, ride out. Ported from the web build's creator; the companion is the
# complementary archetype, same as the web rules.
# =============================================================================
extends Control

var GS
var sel_id := "gunslinger"
var cards := {}

@onready var grid: HBoxContainer = $VBox/Cards
@onready var detail: Label = $VBox/Detail
@onready var name_edit: LineEdit = $VBox/NameRow/NameEdit

func _ready() -> void:
	GS = get_node("/root/GameState")
	GS.apply_theme(self)
	var _a := get_node_or_null("/root/Audio")
	if _a: _a.on_scene("creator")
	GS.headline($VBox/Heading, 44)
	if ResourceLoader.exists("res://assets/scenes/title.png"):
		$Art.texture = load("res://assets/scenes/title.png")
	for arch in GS.design["archetypes"]:
		var aid: String = arch["id"]
		var card := Button.new()
		card.custom_minimum_size = Vector2(150, 210)
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(0, 120)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var art := "res://assets/sprites/%s.png" % aid
		if ResourceLoader.exists(art):
			tex.texture = load(art)
		v.add_child(tex)
		var nm := Label.new()
		nm.text = arch["name"]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GS.headline(nm, 16)
		v.add_child(nm)
		var bo := Label.new()
		bo.text = arch.get("bonuses", "")
		bo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bo.add_theme_font_size_override("font_size", 11)
		bo.add_theme_color_override("font_color", Color("#4ecdc4"))
		v.add_child(bo)
		card.add_child(v)
		card.pressed.connect(_pick.bind(aid))
		grid.add_child(card)
		cards[aid] = card
	$VBox/NameRow/BeginBtn.pressed.connect(_begin)
	$VBox/BackBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	_pick(sel_id)

func _pick(aid: String) -> void:
	sel_id = aid
	for id in cards:
		cards[id].modulate = Color(1, 1, 1) if id == aid else Color(0.62, 0.62, 0.62)
	var arch := {}
	for a in GS.design["archetypes"]:
		if a["id"] == aid:
			arch = a
			break
	detail.text = "%s  %s" % [arch.get("desc", ""), arch.get("lore", "")]
	var pg: Dictionary = GS.design["pregen"].get(aid, {})
	name_edit.text = str(pg.get("name", ""))

func _begin() -> void:
	var nm := name_edit.text.strip_edges()
	GS.new_game(sel_id, nm)
	get_tree().change_scene_to_file("res://scenes/worldmap.tscn")
