extends SceneTree
func _init() -> void:
	for p in ["res://assets/scenes/title.png", "res://assets/scenes/worldmap.png", "res://assets/tiles/boneyard_top.png"]:
		print(p, " exists=", ResourceLoader.exists(p))
	quit(0)
