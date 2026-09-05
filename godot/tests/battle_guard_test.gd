# =============================================================================
# DUSTFALL, BATTLE GUARD TEST (headless)
# Boots battle.tscn with a mounted GameState (anim_test pattern) and probes the
# dead-rider guards in battle.gd:
# 1) a selected rider killed by their own action loses the action surface:
#    _after_action moves the selection to the first living rider, and a bar
#    rebuilt for a dead selection has every button disabled.
# 2) Lay on Hands never picks the caster as the fallen target.
# 3) a bleed-out on _do_move that drops the last rider ends the battle at once
#    (WIPED OUT banner) instead of waiting for End Turn.
# The campaign save is backed up before new_game() and restored on exit.
# Run: godot --headless --path godot --script res://tests/battle_guard_test.gd
# =============================================================================
extends SceneTree

var fails: Array = []
var battle_scene
var stage := 0
var stage_start_ms := 0
var saved_text = null
var dead_id = null
var p_dead: Dictionary = {}
var p_live: Dictionary = {}

func _fail(msg: String) -> void:
	fails.append(msg)
	print("FAIL: ", msg)

func _init() -> void:
	stage = -1 # autoloads mount after _init, set the scene up on frame 1
	stage_start_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)

func _elapsed() -> float:
	return float(Time.get_ticks_msec() - stage_start_ms) / 1000.0

func _next_stage() -> void:
	stage += 1
	stage_start_ms = Time.get_ticks_msec()

func _restore_save() -> void:
	if saved_text == null:
		if FileAccess.file_exists("user://save.json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
		return
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(saved_text)

func _finish() -> void:
	_restore_save()
	if fails.is_empty():
		print("BATTLE GUARD TEST: ALL PASS")
		quit(0)
	else:
		print("BATTLE GUARD TEST: %d FAILURES" % fails.size())
		quit(1)

func _setup_scene() -> void:
	print("== live battle scene ==")
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		_fail("GameState autoload missing under --script")
		_finish()
		return
	if FileAccess.file_exists("user://save.json"):
		saved_text = FileAccess.open("user://save.json", FileAccess.READ).get_as_text()
	gs.new_game()
	battle_scene = preload("res://scenes/battle.tscn").instantiate()
	if not ("sel" in battle_scene):
		_fail("battle.gd failed to attach, parse error (scene is bare %s)" % battle_scene.get_class())
		_finish()
		return
	root.add_child(battle_scene)

func _bar_buttons() -> Array:
	var out: Array = []
	for c in battle_scene.ability_bar.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _tick() -> void:
	match stage:
		-1:
			_setup_scene()
			_next_stage()
		0: # settle, then kill the selected rider by their own hand
			if _elapsed() < 0.3:
				return
			print("== dead rider loses the action surface ==")
			var players: Array = battle_scene.battle["players"]
			if players.size() < 2:
				_fail("need at least two riders for the reselect probe")
				_finish()
				return
			p_dead = battle_scene.sel
			if p_dead.is_empty():
				_fail("no unit selected after boot")
				_finish()
				return
			dead_id = p_dead["id"]
			for p in players:
				if p["id"] != dead_id:
					p_live = p
					break
			battle_scene.core.apply_damage(battle_scene.battle, p_dead, 9999)
			if p_dead["alive"]:
				_fail("apply_damage did not drop the rider")
			# the refresh path every action ends on
			battle_scene._after_action()
			if battle_scene.ended:
				_fail("battle ended with a living rider still standing")
			if battle_scene.sel.is_empty() or battle_scene.sel["id"] == dead_id:
				_fail("selection stayed on the dead rider after _after_action")
			elif not battle_scene.sel.get("alive", false):
				_fail("selection moved to a non-living unit")
			# a bar rebuilt for a dead selection must be fully disabled
			battle_scene.sel = p_dead
			battle_scene._rebuild_ability_bar()
			_next_stage()
		1: # queued-free children clear on the frame after the rebuild
			var btns := _bar_buttons()
			if btns.is_empty():
				_fail("dead-selection bar built no buttons to check")
			for b in btns:
				if not b.disabled:
					_fail("dead rider still has a live button: %s" % b.text)
			print("checked %d buttons on the dead rider's bar" % btns.size())
			# Lay on Hands must not treat the caster as the fallen target
			print("== Lay on Hands skips the caster ==")
			p_dead["abilities"] = ["Lay on Hands"]
			p_dead["ap"] = 4
			var live_hp0 := int(p_live["hp"])
			battle_scene._choose_ability("Lay on Hands")
			if p_dead["alive"]:
				_fail("dead preacher revived themself with Lay on Hands")
			if int(p_live["hp"]) < live_hp0:
				_fail("Lay on Hands hurt the living rider")
			if battle_scene.sel.is_empty() or battle_scene.sel["id"] == dead_id:
				_fail("selection stayed on the dead caster after Lay on Hands")
			if battle_scene.ended:
				_fail("battle ended early during the Lay on Hands probe")
			_next_stage()
		2: # bleed-out on the move drops the last rider: battle ends now
			print("== bleed-out on move ends the battle ==")
			battle_scene._select(p_live)
			p_live["hp"] = 2
			p_live["status"]["bleed"] = 1
			var dest := []
			for key in battle_scene.reach_map.keys():
				if int(battle_scene.reach_map[key]) >= 1:
					var parts: PackedStringArray = (key as String).split(",")
					dest = [int(parts[0]), int(parts[1])]
					break
			if dest.is_empty():
				_fail("no destination in reach for the bleed probe")
				_finish()
				return
			battle_scene._do_move(dest[0], dest[1])
			if p_live["alive"]:
				_fail("bleed on move did not drop the 2 HP rider")
			if not battle_scene.ended:
				_fail("_do_move bleed-out did not end the battle")
			if String(battle_scene.banner_label.text) != "WIPED OUT":
				_fail("banner should read WIPED OUT, got %s" % battle_scene.banner_label.text)
			if not battle_scene.banner.visible:
				_fail("end banner not shown after bleed-out")
			if not battle_scene.sel.is_empty():
				_fail("selection should clear when no rider is left standing")
			_next_stage()
		3: # let the walk tween release before quitting
			if not battle_scene._animating.is_empty() and _elapsed() < 4.0:
				return
			_finish()
