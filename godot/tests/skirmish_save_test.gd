# =============================================================================
# DUSTFALL — Quick Skirmish save-clobber regression test (2026-09-04 audit)
# title.gd's SkirmishBtn used to run `if GS.state.is_empty(): GS.new_game()`.
# title.gd never loads the save on _ready (only ContinueBtn does), so on a
# fresh launch with an existing user://save.json the state was empty,
# new_game() ran, and new_game() ends in save_game() — the campaign was
# overwritten with a fresh 2-rider/300g/day-1 party, no prompt.
# GameState.ensure_party() now loads the campaign first and only starts a new
# game when no readable save exists; the skirmish handler calls it.
# In-memory GameState (MemoryState): the "disk" is a Dictionary, so this test
# NEVER touches user://save.json (same no-save posture as combat_rules_test).
# Run:  godot --headless --path godot --script res://tests/skirmish_save_test.gd
# =============================================================================
extends SceneTree

# GameState with its three disk touch-points swapped for a Dictionary. NOT in
# the tree: _ready never runs, nothing reaches user://.
class MemoryState extends "res://scripts/game_state.gd":
	var disk: Dictionary = {}  # stands in for user://save.json ({} = no file)
	var writes := 0            # every save_game() call, clobbers included
	func has_save() -> bool:
		return not disk.is_empty()
	func load_game() -> bool:  # mirrors the real one: needs a "version" key
		if disk.is_empty() or not disk.has("version"):
			return false
		state = disk.duplicate(true)
		return true
	func save_game() -> void:
		writes += 1
		disk = state.duplicate(true)

var passed := 0
var failed := 0
var design: Dictionary = {}

func ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)

# a mid-campaign save that a fresh 2-rider/300g/day-1 state can't be confused with
func _campaign() -> Dictionary:
	return {"party": [{"uid": "p0"}, {"uid": "p1"}, {"uid": "p2"}, {"uid": "p3"}],
		"gold": 1234, "day": 17, "location": "boneyard", "version": 1}

func _mk(disk: Dictionary) -> MemoryState:
	var gs := MemoryState.new()
	gs.design = design  # new_game -> _mk_member reads design["pregen"]
	gs.disk = disk
	return gs

func _init() -> void:
	var f := FileAccess.open("res://data/design.json", FileAccess.READ)
	if f == null:
		push_error("design.json missing — run: node tools/export_data.js")
		quit(1)
		return
	design = JSON.parse_string(f.get_as_text())

	# ---- harness self-check: the fake disk DOES catch a clobber -------------------
	# (the old title.gd path — bare new_game() from an empty state)
	var ctl := _mk(_campaign())
	ctl.new_game()
	ok("control: bare new_game() overwrites the campaign on disk",
		ctl.writes == 1 and int(ctl.disk["gold"]) == 300 and ctl.disk["party"].size() == 2)
	ctl.free()

	# ---- the bug: fresh launch (empty state) with a campaign on disk --------------
	var a := _mk(_campaign())
	a.ensure_party()
	ok("fresh launch loads the campaign (gold 1234, day 17, 4 riders)",
		int(a.state.get("gold", -1)) == 1234 and int(a.state.get("day", -1)) == 17
		and a.state.get("party", []).size() == 4)
	ok("fresh launch writes NOTHING to disk", a.writes == 0)
	ok("campaign on disk untouched", int(a.disk["gold"]) == 1234 and int(a.disk["day"]) == 17)
	a.free()

	# ---- no save at all: a new game is the right call ----------------------------
	var b := _mk({})
	b.ensure_party()
	ok("no save -> new game (2 riders, 300g, day 1)",
		b.state.get("party", []).size() == 2 and int(b.state.get("gold", -1)) == 300
		and int(b.state.get("day", -1)) == 1)
	ok("no save -> new game saved once", b.writes == 1 and b.disk.has("version"))
	b.free()

	# ---- state already live (came from worldmap/town): leave it alone ------------
	var c := _mk(_campaign())
	c.state = {"party": [{"uid": "p0"}], "gold": 999, "day": 3, "version": 1}
	c.ensure_party()
	ok("live state untouched (gold 999)",
		int(c.state["gold"]) == 999 and c.state["party"].size() == 1 and c.writes == 0)
	ok("live state: disk untouched", int(c.disk["gold"]) == 1234)
	c.free()

	# ---- unreadable save (no version key): still yields a party, no empty-state ---
	var d := _mk({"party": [], "gold": 5})
	d.ensure_party()
	ok("unreadable save still yields a party (no empty-state crash)",
		d.state.get("party", []).size() == 2 and d.writes == 1)
	d.free()

	# ---- wiring guard: the title scene must go through ensure_party -----------------
	var tf := FileAccess.open("res://scenes/title.gd", FileAccess.READ)
	var src := tf.get_as_text() if tf != null else ""
	ok("title.gd calls GS.ensure_party()", src.contains("GS.ensure_party()"))
	ok("title.gd has no bare GS.new_game() (the clobber path)", not src.contains("GS.new_game()"))

	print("skirmish_save_test: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
