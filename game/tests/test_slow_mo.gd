extends GutTest
const SlowMoScript := preload("res://juice/slow_mo.gd")

func test_idle_returns_one() -> void:
	var s := SlowMoScript.new()
	assert_almost_eq(s.update(0.016), 1.0, 0.0001)

func test_returns_target_in_window() -> void:
	var s := SlowMoScript.new()
	s.request(0.3, 0.5)
	assert_almost_eq(s.update(0.016), 0.3, 0.0001)

func test_returns_one_after_window() -> void:
	var s := SlowMoScript.new()
	s.request(0.3, 0.5)
	s.update(0.6)
	assert_almost_eq(s.update(0.016), 1.0, 0.0001)

func test_is_active_tracks_window() -> void:
	var s := SlowMoScript.new()
	assert_false(s.is_active())
	s.request(0.3, 0.5)
	assert_true(s.is_active())
	s.update(0.6)
	assert_false(s.is_active())
