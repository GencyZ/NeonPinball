class_name SettingsSystem extends RefCounted
# Persists display / gameplay settings to user://settings.cfg

const SETTINGS_PATH := "user://settings.cfg"

# Supported window size presets (logical units; actual px = these values)
const PRESETS: Array = [
	Vector2i(540, 900),
	Vector2i(810, 1350),
	Vector2i(1080, 1800),
]
const DEFAULT_PRESET_INDEX := 1   # Medium (810x1350)

static func load_window_size() -> Vector2i:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return PRESETS[DEFAULT_PRESET_INDEX]
	var w: int = cfg.get_value("display", "window_width",  PRESETS[DEFAULT_PRESET_INDEX].x)
	var h: int = cfg.get_value("display", "window_height", PRESETS[DEFAULT_PRESET_INDEX].y)
	return Vector2i(w, h)

static func save_window_size(size: Vector2i) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # 若已有其它 section 不丢失
	cfg.set_value("display", "window_width",  size.x)
	cfg.set_value("display", "window_height", size.y)
	cfg.save(SETTINGS_PATH)

static func preset_label(size: Vector2i) -> String:
	match size:
		Vector2i(540,  900):  return "Small  (540×900)"
		Vector2i(810,  1350): return "Medium (810×1350)"
		Vector2i(1080, 1800): return "Large  (1080×1800)"
	return "%d×%d" % [size.x, size.y]
