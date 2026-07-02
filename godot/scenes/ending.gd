# DUSTFALL — ENDING (campaign epilogue + credits)
extends Control

func _ready() -> void:
	var GS = get_node("/root/GameState")
	if ResourceLoader.exists("res://assets/scenes/title.png"):
		$Art.texture = load("res://assets/scenes/title.png")
	$Box/Body.text = ("The Hollow Man is unmade, and the Sleeping One turns over in the deep earth — for now. "
		+ "Your crew rides out of Groom Lake under a bruised dawn, their names already passing into the "
		+ "frontier's tall tales. The gods still war over a broken country. But today, the dust belongs to the living.")
	$Box/Credits.text = "Survived %d days · %d gold · A Dangercorn Enterprises production\nThe Pantheon: Vulcan · Perun · Baron Samedi · Coyote · Anansi · the Sleeping One" % [
		int(GS.state.get("day", 1)), int(GS.state.get("gold", 0))]
	$Box/BackBtn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
