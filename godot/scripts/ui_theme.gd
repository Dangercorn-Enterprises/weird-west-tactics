# =============================================================================
# DUSTFALL — UI THEME (v1.3 polish pass)
# The web build's look, rebuilt as a Godot Theme: parchment text, dark leather
# panels, rust borders that go teal on hover, Rye for display / Special Elite
# for body. Applied by GameState.apply_theme(root_control) in every scene.
# =============================================================================
class_name DustfallTheme
extends RefCounted

const PARCH := Color("#d4c5a9")
const AMBER := Color("#d4a843")
const TEAL := Color("#4ecdc4")
const RUST := Color("#a0522d")
const BLOOD := Color("#c0392b")
const PANEL := Color(0.118, 0.078, 0.039, 0.86)
const INK := Color("#1a1209")

static var _theme: Theme = null
static var rye: FontFile = null
static var elite: FontFile = null

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	rye = load("res://assets/fonts/Rye-Regular.ttf")
	elite = load("res://assets/fonts/SpecialElite-Regular.ttf")
	var t := Theme.new()
	t.default_font = elite
	t.default_font_size = 15

	# labels — parchment body text
	t.set_color("font_color", "Label", PARCH)

	# buttons — leather panel, rust border, teal text, hover glow
	var b := _panel(PANEL, RUST)
	var bh := _panel(Color(0.20, 0.13, 0.06, 0.92), TEAL)
	var bp := _panel(Color(0.10, 0.06, 0.03, 0.95), AMBER)
	var bd := _panel(Color(0.10, 0.07, 0.04, 0.5), Color(0.35, 0.25, 0.15, 0.4))
	t.set_stylebox("normal", "Button", b)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_font("font", "Button", rye)
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "Button", TEAL)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.45, 0.38, 0.5))

	# panels — dark leather with rust trim
	var p := _panel(PANEL, RUST)
	p.content_margin_left = 14
	p.content_margin_right = 14
	p.content_margin_top = 10
	p.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", p)

	_theme = t
	return _theme

static func _panel(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

# display-face helper for headings (Rye, amber, drop shadow)
static func headline(l: Label, size: int) -> void:
	l.add_theme_font_override("font", rye)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
