# =============================================================================
# DUSTFALL, IN-MEMORY GAME STATE FOR HEADLESS TESTS
# GameState with its three disk touch-points (has_save / load_game /
# save_game) swapped for a Dictionary, so nothing a test drives can reach
# user://save.json. Scene-booting tests (battle.tscn, PauseMenu quit-to-title)
# hit save_game() through the autoload path: new_game() ends in save_game(),
# apply_battle_result() saves, title.gd's ensure_party() starts a new game
# when it sees no save. Before this helper those tests overwrote the player's
# real campaign save every run (2026-09-04 audit).
# Usage from a SceneTree test, on frame 1 (autoloads mount after _init):
#   const MemoryState = preload("res://tests/_memory_state.gd")
#   var gs = MemoryState.mount(self)   # replaces /root/GameState
#   gs.new_game()                      # writes gs.disk, never user://
# Every scene and autoload looks GameState up by node path
# (get_node("/root/GameState")), so the swap is transparent to them.
# =============================================================================
extends "res://scripts/game_state.gd"

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

# Replace the mounted GameState autoload with a MemoryState. The real node is
# taken out of the tree before it can be asked to save anything; the
# replacement runs the same _ready (design.json, sprites.json, settings) so
# scenes see an identical GameState that only ever "saves" to a Dictionary.
# Returns the mounted MemoryState, or null when no autoload is present.
static func mount(tree: SceneTree) -> Node:
	var root := tree.root
	var old := root.get_node_or_null("GameState")
	if old == null:
		return null
	var ms: Node = load("res://tests/_memory_state.gd").new()
	ms.name = "GameState"
	root.remove_child(old)
	old.queue_free()
	root.add_child(ms)
	if Engine.has_singleton("GameState"):
		Engine.unregister_singleton("GameState")
	Engine.register_singleton("GameState", ms)
	return ms
