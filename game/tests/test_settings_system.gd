extends GutTest
const SettingsSystemScript := preload("res://run/settings_system.gd")

func before_each() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("settings.cfg"):
		dir.remove("settings.cfg")

func test_default_window_size() -> void:
	# No file exists → should return default preset
	var sz := SettingsSystemScript.load_window_size()
	assert_eq(sz, SettingsSystemScript.PRESETS[SettingsSystemScript.DEFAULT_PRESET_INDEX],
		"无存档时返回默认中档尺寸")

func test_save_and_load_round_trip() -> void:
	var target := Vector2i(1080, 1800)
	SettingsSystemScript.save_window_size(target)
	var loaded := SettingsSystemScript.load_window_size()
	assert_eq(loaded, target, "保存后读取返回相同尺寸")

func test_preset_label_small() -> void:
	assert_eq(SettingsSystemScript.preset_label(Vector2i(540, 900)),
		"Small  (540×900)")

func test_preset_label_medium() -> void:
	assert_eq(SettingsSystemScript.preset_label(Vector2i(810, 1350)),
		"Medium (810×1350)")

func test_preset_label_large() -> void:
	assert_eq(SettingsSystemScript.preset_label(Vector2i(1080, 1800)),
		"Large  (1080×1800)")
