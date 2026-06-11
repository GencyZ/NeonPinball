extends Control

const SaveSystemScript := preload("res://run/save_system.gd")
const SettingsSystemScript := preload("res://run/settings_system.gd")

func _ready() -> void:
	_apply_saved_window_size()
	var saved := SaveSystemScript.load_data()
	_build_ui(saved)

func _apply_saved_window_size() -> void:
	var sz := SettingsSystemScript.load_window_size()
	DisplayServer.window_set_size(sz)
	var screen_size := DisplayServer.screen_get_size()
	var win_size   := DisplayServer.window_get_size()
	DisplayServer.window_set_position((screen_size - win_size) / 2)

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

	# ---- 分辨率 ----
	var res_label := Label.new()
	res_label.text = "Window Size"
	res_label.add_theme_font_size_override(&"font_size", 18)
	res_label.position = Vector2(120, 430)
	add_child(res_label)

	var current_sz := SettingsSystemScript.load_window_size()
	var btn_y := 460
	for preset in SettingsSystemScript.PRESETS:
		var btn := Button.new()
		btn.text = SettingsSystemScript.preset_label(preset)
		btn.position = Vector2(120, btn_y)
		btn.custom_minimum_size = Vector2(280, 44)
		if preset == current_sz:
			btn.disabled = true
		btn.pressed.connect(_on_resolution_pressed.bind(preset))
		add_child(btn)
		btn_y += 52

func best_text(saved: Dictionary) -> String:
	return "Best: %d" % int(saved.get(&"best_score", 0))

func _on_start_pressed() -> void:
	SceneMan.start_run()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_resolution_pressed(size: Vector2i) -> void:
	SettingsSystemScript.save_window_size(size)
	DisplayServer.window_set_size(size)
	var screen_size := DisplayServer.screen_get_size()
	var win_size   := DisplayServer.window_get_size()
	DisplayServer.window_set_position((screen_size - win_size) / 2)
	SceneMan.goto_menu()
