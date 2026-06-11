extends Node
# Autoload: SceneMan — switches between menu and game.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/board.tscn"

func goto_menu() -> void:
	FadeMan.fade_to(func(): get_tree().change_scene_to_file(MENU_SCENE))

func start_run() -> void:
	RunMan.reset_run()
	FadeMan.fade_to(func(): get_tree().change_scene_to_file(GAME_SCENE))
