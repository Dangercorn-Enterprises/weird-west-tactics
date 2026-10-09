# =============================================================================
# DUSTFALL — FEEL PASS SCREENSHOT HELPER (dev tool, not a test)
# Boots battle.tscn on an in-memory GameState (never touches user://save.json),
# parks one enemy two tiles from the posse, ends the turn, and saves frames of
# the enemy-phase PLAYBACK to user://feel_shot_<ms>.png. Needs a window (the
# headless build has no renderer):
#   godot --path godot --resolution 1280x720 --script res://tests/_feel_shot.gd
# =============================================================================
extends SceneTree

const MemoryState = preload("res://tests/_memory_state.gd")
const FRAMES_MS := [120, 450, 900, 1500]

var scene
var stage := -1
var t0 := 0
var shot_idx := 0

func _init() -> void:
	process_frame.connect(_tick)

func _tick() -> void:
	match stage:
		-1:
			var gs = MemoryState.mount(self)
			gs.new_game()
			scene = preload("res://scenes/battle.tscn").instantiate()
			root.add_child(scene)
			scene.core.seed_rng(4242)
			t0 = Time.get_ticks_msec()
			stage = 0
		0:
			if Time.get_ticks_msec() - t0 < 700:
				return
			var e0: Dictionary = scene.battle["enemies"][0]
			var p0: Dictionary = scene.battle["players"][0]
			e0["q"] = int(p0["q"]) + 2
			e0["r"] = int(p0["r"])
			scene._sync_units()
			scene._end_turn()
			t0 = Time.get_ticks_msec()
			stage = 1
		1:
			if shot_idx >= FRAMES_MS.size():
				print("FEEL SHOTS done")
				quit(0)
				return
			var ms := Time.get_ticks_msec() - t0
			if ms < int(FRAMES_MS[shot_idx]):
				return
			var img := root.get_viewport().get_texture().get_image()
			var path := "user://feel_shot_%d.png" % int(FRAMES_MS[shot_idx])
			img.save_png(path)
			print("FEEL SHOT %s busy=%s" % [path, str(scene._busy)])
			shot_idx += 1
