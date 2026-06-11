extends GutTest
const ScreenShakeScript := preload("res://juice/screen_shake.gd")

func test_add_sets_trauma() -> void:
	var s := ScreenShakeScript.new()
	s.add(0.5)
	assert_almost_eq(s.trauma, 0.5, 0.0001)

func test_add_clamps_to_one() -> void:
	var s := ScreenShakeScript.new()
	s.add(1.5)
	assert_almost_eq(s.trauma, 1.0, 0.0001)

func test_update_decays_trauma() -> void:
	var s := ScreenShakeScript.new()
	s.add(1.0)
	s.update(0.1)
	assert_lt(s.trauma, 1.0)

func test_trauma_never_negative() -> void:
	var s := ScreenShakeScript.new()
	s.add(0.2)
	s.update(10.0)
	assert_eq(s.trauma, 0.0)

func test_zero_trauma_zero_offset() -> void:
	var s := ScreenShakeScript.new()
	assert_eq(s.update(0.016), Vector2.ZERO)
	assert_false(s.is_active())

func test_is_active_when_trauma() -> void:
	var s := ScreenShakeScript.new()
	s.add(0.5)
	assert_true(s.is_active())

func test_offset_within_component_bound() -> void:
	var s := ScreenShakeScript.new()
	s.add(1.0)
	var o := s.update(0.0)
	assert_true(absf(o.x) <= ScreenShakeScript.MAX_OFFSET + 0.001)
	assert_true(absf(o.y) <= ScreenShakeScript.MAX_OFFSET + 0.001)
