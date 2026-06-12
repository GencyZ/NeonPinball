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

func test_inactive_returns_one() -> void:
	var s := SlowMoScript.new()
	assert_almost_eq(s.update(0.016), 1.0, 1e-4, "空闲时 time_scale=1.0")

func test_stronger_wins_over_weaker() -> void:
	var s := SlowMoScript.new()
	s.request(0.05, 0.04)   # 强（更慢）
	s.request(0.5, 0.04)    # 弱
	assert_almost_eq(s.update(0.0), 0.05, 1e-4, "更强(更低)的目标胜出")

func test_longer_duration_extends() -> void:
	var s := SlowMoScript.new()
	s.request(0.2, 0.1)
	s.request(0.2, 0.3)     # 更长
	s.update(0.15)
	assert_true(s.is_active(), "计时被延长到更长那个")
