# DUSTFALL — TITLE (Godot port, v1.3 art pass)
extends Control

var GS

func _ready() -> void:
	GS = get_node("/root/GameState")
	if ResourceLoader.exists("res://assets/scenes/title.png"):
		$Art.texture = load("res://assets/scenes/title.png")
	$Menu/NewBtn.pressed.connect(func():
		GS.new_game()
		get_tree().change_scene_to_file("res://scenes/worldmap.tscn"))
	$Menu/ContinueBtn.visible = GS.has_save()
	$Menu/ContinueBtn.pressed.connect(func():
		GS.load_game()
		get_tree().change_scene_to_file("res://scenes/worldmap.tscn"))
	$Menu/SkirmishBtn.pressed.connect(func():
		if GS.state.is_empty():
			GS.new_game()
		GS.go_battle({"title": "Skirmish at the Crossing", "biome": "mesa",
			"enemies": GS.enemies_by_ids(["walkin_dead", "coyote_beast", "forge_sentry", "dust_devil"]),
			"context": {}}))
	$Menu/QuitBtn.pressed.connect(func(): get_tree().quit())
