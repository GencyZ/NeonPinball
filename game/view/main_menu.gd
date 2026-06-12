extends Control

const SaveSystemScript    := preload("res://run/save_system.gd")
const SettingsSystemScript := preload("res://run/settings_system.gd")
const UnlockManagerScript  := preload("res://run/unlock_manager.gd")

func _ready() -> void:
	call_deferred(&"_apply_saved_window_size")
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
	title.position = Vector2(180, 180)
	add_child(title)

	var best := Label.new()
	best.text = best_text(saved)
	best.add_theme_font_size_override(&"font_size", 22)
	best.position = Vector2(180, 300)
	add_child(best)

	var start_btn := Button.new()
	start_btn.text = "Start Run"
	start_btn.position = Vector2(180, 420)
	start_btn.custom_minimum_size = Vector2(300, 64)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.position = Vector2(180, 500)
	quit_btn.custom_minimum_size = Vector2(300, 64)
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)

	# ---- 解锁进度 ----
	var runs := int(saved.get(&"runs_completed", 0))
	var nxt: Dictionary = UnlockManagerScript.next_unlock(runs)
	var unlock_lbl := Label.new()
	if nxt.is_empty():
		unlock_lbl.text = "All content unlocked!"
	else:
		var need: int = int(nxt["required_runs"]) - runs
		unlock_lbl.text = "Next unlock in %d run%s" % [need, "s" if need > 1 else ""]
	unlock_lbl.add_theme_font_size_override(&"font_size", 16)
	unlock_lbl.modulate = Color(0.6, 1.0, 0.7)
	unlock_lbl.position = Vector2(180, 580)
	add_child(unlock_lbl)

	# ---- 分辨率 ----
	var res_label := Label.new()
	res_label.text = "Window Size"
	res_label.add_theme_font_size_override(&"font_size", 18)
	res_label.position = Vector2(180, 640)
	add_child(res_label)

	var current_sz := SettingsSystemScript.load_window_size()
	var btn_y := 678
	for preset in SettingsSystemScript.PRESETS:
		var btn := Button.new()
		btn.text = SettingsSystemScript.preset_label(preset)
		btn.position = Vector2(180, btn_y)
		btn.custom_minimum_size = Vector2(420, 64)
		if preset == current_sz:
			btn.disabled = true
		btn.pressed.connect(_on_resolution_pressed.bind(preset))
		add_child(btn)
		btn_y += 78

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
