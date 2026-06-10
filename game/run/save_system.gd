class_name SaveSystem extends RefCounted

const SAVE_PATH := "user://neon_pinball.cfg"

static func save(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_score", data.get(&"best_score", 0))
	cfg.set_value("run", "runs_completed", data.get(&"runs_completed", 0))
	cfg.set_value("daily", "last_date", data.get(&"last_date", ""))
	cfg.set_value("daily", "daily_completed", data.get(&"daily_completed", false))
	cfg.save(SAVE_PATH)

static func load_data() -> Dictionary:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return {&"best_score": 0, &"runs_completed": 0, &"last_date": "", &"daily_completed": false}
	return {
		&"best_score":      cfg.get_value("run", "best_score", 0),
		&"runs_completed":  cfg.get_value("run", "runs_completed", 0),
		&"last_date":       cfg.get_value("daily", "last_date", ""),
		&"daily_completed": cfg.get_value("daily", "daily_completed", false),
	}

static func today_string() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
