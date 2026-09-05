# =============================================================================
# DUSTFALL, SCREENSHOT AUTOPILOT TEST (headless, no scenes booted)
# The DUSTFALL_AUTOPILOT tour in game_state.gd needs a window to render its
# shots, so its contract is pinned statically here:
# 1) stage order: the battle's representative shot (shot_battle) is taken
#    AFTER the intro card is dismissed, the rotated shot after that, the pause
#    shot after the pause menu opens. The 2026-07-09 shot_battle was taken with
#    the card still up.
# 2) the timer shot never fires on a scene that owns an intro card
#    (ap_has_intro), so the explicit stages are the only path to shot_battle.
# 3) the campaign save backup/restore around the tour round-trips a real save,
#    deletes a tour-written save when there was none, and keeps a leftover
#    backup from a crashed tour as the truth. Runs on scratch files under
#    user://, never on user://save.json.
# Run:  godot --headless --path godot --script res://tests/autopilot_test.gd
# =============================================================================
extends SceneTree

const MemoryState = preload("res://tests/_memory_state.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const T_SAVE := "user://autopilot_test_save.json"
const T_BAK := "user://autopilot_test_save.bak"

class IntroScene extends Node:
	var intro_open := true

var passed := 0
var failed := 0

func ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.open(path, FileAccess.READ).get_as_text()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)

func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _init() -> void:
	print("== stage order ==")
	var GS = GameStateScript
	ok("battle launches before the intro card is dismissed",
		GS.AP_STAGE_BATTLE < GS.AP_STAGE_INTRO_DISMISS)
	ok("shot_battle is taken after the intro card is dismissed",
		GS.AP_STAGE_BATTLE_SHOT > GS.AP_STAGE_INTRO_DISMISS)
	ok("rotated shot follows the straight battle shot",
		GS.AP_STAGE_ROTATED_SHOT > GS.AP_STAGE_BATTLE_SHOT)
	ok("pause shot follows the pause open",
		GS.AP_STAGE_PAUSE_SHOT > GS.AP_STAGE_PAUSE_OPEN and GS.AP_STAGE_PAUSE_OPEN > GS.AP_STAGE_ROTATED_SHOT)
	ok("stages are consecutive from 1 (the tour ticks one per beat)",
		[GS.AP_STAGE_CREATOR, GS.AP_STAGE_WORLDMAP, GS.AP_STAGE_TOWN, GS.AP_STAGE_BATTLE,
			GS.AP_STAGE_INTRO_DISMISS, GS.AP_STAGE_BATTLE_SHOT, GS.AP_STAGE_ROTATED_SHOT,
			GS.AP_STAGE_PAUSE_OPEN, GS.AP_STAGE_PAUSE_SHOT] == [1, 2, 3, 4, 5, 6, 7, 8, 9])

	print("== timer shot skips intro-card scenes ==")
	var intro := IntroScene.new()
	var plain := Node.new()
	ok("a scene with an intro card is left to the explicit stages", GS.ap_has_intro(intro))
	ok("a plain scene is shot by the timer", not GS.ap_has_intro(plain))
	ok("null scene is not an intro scene", not GS.ap_has_intro(null))
	intro.free()
	plain.free()

	print("== campaign save backup/restore (scratch files) ==")
	var gs := MemoryState.new()
	_rm(T_SAVE)
	_rm(T_BAK)
	# a) campaign present: tour clobbers it, restore brings the bytes back
	var campaign := '{"party":[{"uid":"p0"}],"gold":1234,"day":17,"version":1}'
	_write(T_SAVE, campaign)
	gs._ap_backup_save(T_SAVE, T_BAK)
	ok("backup holds the campaign verbatim", _read(T_BAK) == campaign)
	_write(T_SAVE, '{"party":[],"gold":300,"day":1,"version":1}')
	gs._ap_restore_save(T_SAVE, T_BAK)
	ok("restore puts the campaign back byte for byte", _read(T_SAVE) == campaign)
	ok("restore removes the backup", not FileAccess.file_exists(T_BAK))
	# b) no campaign: whatever the tour wrote is deleted, no save is invented
	_rm(T_SAVE)
	gs._ap_backup_save(T_SAVE, T_BAK)
	ok("no-save backup is the empty marker", FileAccess.file_exists(T_BAK) and _read(T_BAK) == "")
	_write(T_SAVE, '{"party":[],"gold":300,"day":1,"version":1}')
	gs._ap_restore_save(T_SAVE, T_BAK)
	ok("restore with no prior campaign deletes the tour's save", not FileAccess.file_exists(T_SAVE))
	ok("marker removed after restore", not FileAccess.file_exists(T_BAK))
	# c) leftover backup from a crashed tour wins over the clobbered save
	_write(T_BAK, campaign)
	_write(T_SAVE, '{"party":[],"gold":300,"day":1,"version":1}')
	gs._ap_backup_save(T_SAVE, T_BAK)
	ok("leftover backup is not overwritten by the clobbered save", _read(T_BAK) == campaign)
	gs._ap_restore_save(T_SAVE, T_BAK)
	ok("crashed-tour campaign restored on the next completed tour", _read(T_SAVE) == campaign)
	# d) restore with nothing to restore is a no-op
	_write(T_SAVE, campaign)
	gs._ap_restore_save(T_SAVE, T_BAK)
	ok("restore without a backup leaves the save alone", _read(T_SAVE) == campaign)
	_rm(T_SAVE)
	_rm(T_BAK)
	gs.free()

	print("")
	print("AUTOPILOT TEST: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
