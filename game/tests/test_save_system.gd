extends GutTest

const SaveSystemScript := preload("res://run/save_system.gd")

func test_load_has_all_keys() -> void:
	var d := SaveSystemScript.load_data()
	assert_true(d.has(&"best_score"))
	assert_true(d.has(&"runs_completed"))
	assert_true(d.has(&"last_date"))
	assert_true(d.has(&"daily_completed"))

func test_save_load_roundtrip() -> void:
	SaveSystemScript.save({&"best_score": 1234, &"runs_completed": 5, &"last_date": "2026-06-10", &"daily_completed": true})
	var l := SaveSystemScript.load_data()
	assert_eq(int(l[&"best_score"]), 1234)
	assert_eq(int(l[&"runs_completed"]), 5)
	assert_eq(String(l[&"last_date"]), "2026-06-10")
	assert_eq(bool(l[&"daily_completed"]), true)

func test_today_string_format() -> void:
	var s: String = SaveSystemScript.today_string()
	assert_eq(s.length(), 10)
	assert_eq(s[4], "-")
	assert_eq(s[7], "-")

func test_daily_seed_positive() -> void:
	var s := SaveSystemScript.daily_seed()
	assert_true(s > 0)
	assert_true(s < 0x7FFFFFFF)

func test_daily_seed_deterministic() -> void:
	assert_eq(SaveSystemScript.daily_seed(), SaveSystemScript.daily_seed())
