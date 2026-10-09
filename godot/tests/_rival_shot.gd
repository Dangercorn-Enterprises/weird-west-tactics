# =============================================================================
# DUSTFALL — RIVAL SCREENSHOT HELPER (dev tool, not a test)
# Mounts an in-memory GameState (never touches user://save.json), mints one
# rank-2 scarred rival last seen at Tucson, then captures:
#   user://rival_shot_board.png   the marshal board with the WANTED row
#   user://rival_shot_battle.png  a battle the rival leads (WANTED tag + log)
# Needs a window: godot --path godot --resolution 1280x720 --script res://tests/_rival_shot.gd
# =============================================================================
extends SceneTree

const MemoryState = preload("res://tests/_memory_state.gd")
const RivalsLib = preload("res://scripts/rivals.gd")

var stage := -1
var t0 := 0
var scene

func _init() -> void:
	process_frame.connect(_tick)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % name)
	print("RIVAL SHOT user://%s.png" % name)

func _tick() -> void:
	match stage:
		-1:
			var gs = MemoryState.mount(self)
			gs.new_game()
			gs.state["location"] = "tucson"
			gs.set_rival_seed(42)
			var r := RivalsLib.mint(gs.state, gs.design, "coyote_beast", "p0", "tucson", gs.rival_rng(), "shot")
			r["rank"] = 2
			r["scars"] = ["eye"]
			r["fights"] = 1
			scene = load("res://scenes/town.tscn").instantiate()
			root.add_child(scene)
			scene.cur_service = "marshal"
			scene._render()
			t0 = Time.get_ticks_msec()
			stage = 0
		0:
			if Time.get_ticks_msec() - t0 < 700:
				return
			_shot("rival_shot_board")
			var gs = root.get_node("/root/GameState")
			var r: Dictionary = RivalsLib.live(gs.state)[0]
			var spec := RivalsLib.spec_for(gs.design, r)
			gs.pending_battle = {"title": "%s rides again" % spec["name"], "biome": "mesa",
				"enemies": [spec] + gs.enemies_by_ids(["walkin_dead", "forge_sentry"]), "context": {}}
			scene.queue_free()
			scene = load("res://scenes/battle.tscn").instantiate()
			root.add_child(scene)
			t0 = Time.get_ticks_msec()
			stage = 1
		1:
			if Time.get_ticks_msec() - t0 < 900:
				return
			_shot("rival_shot_battle")
			print("RIVAL SHOTS done")
			quit(0)
