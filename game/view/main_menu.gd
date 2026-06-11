extends Control

const SaveSystemScript := preload("res://run/save_system.gd")

func _ready() -> void:
	var saved := SaveSystemScript.load_data()
	_build_ui(saved)

func _build_ui(saved: Dictionary) -> void:
	var title := Label.new()
	title.text = "NEON PINBALL"
	title.add_theme_font_size_override(&"font_size", 48)
	title.position = Vector2(120, 120)
	add_child(title)

	var best := Label.new()
	best.text = best_text(saved)
	best.add_theme_font_size_override(&"font_size", 22)
	best.position = Vector2(120, 200)
	add_child(best)

	var start_btn := Button.new()
	start_btn.text = "Start Run"
	start_btn.position = Vector2(120, 280)
	start_btn.custom_minimum_size = Vector2(200, 48)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.position = Vector2(120, 344)
	quit_btn.custom_minimum_size = Vector2(200, 48)
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)

func best_text(saved: Dictionary) -> String:
	return "Best: %d" % int(saved.get(&"best_score", 0))

func _on_start_pressed() -> void:
	SceneMan.start_run()

func _on_quit_pressed() -> void:
	get_tree().quit()
