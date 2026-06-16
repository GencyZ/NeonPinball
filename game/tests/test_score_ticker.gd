extends GutTest

const ScoreTickerScript := preload("res://juice/score_ticker.gd")

func test_approaches_target() -> void:
	var t := ScoreTickerScript.new()
	t.update(100.0, 1.0 / 60.0)
	assert_gt(t.value(), 0.0, "开始上升")
	assert_lt(t.value(), 100.0, "未瞬达")
	for i in 200:
		t.update(100.0, 1.0 / 60.0)
	assert_almost_eq(t.value(), 100.0, 1e-3, "最终收敛到 target")

func test_monotonic_rise() -> void:
	var t := ScoreTickerScript.new()
	var prev := 0.0
	for i in 30:
		t.update(100.0, 1.0 / 60.0)
		assert_true(t.value() >= prev, "单调不降 @%d" % i)
		prev = t.value()

func test_big_jump_punches() -> void:
	var t := ScoreTickerScript.new()
	t.update(10.0, 1.0 / 60.0)   # 10 < JUMP_MIN(20) → 不 punch
	assert_almost_eq(t.punch_scale(), 1.0, 1e-3, "小增量不 punch")
	t.update(300.0, 1.0 / 60.0)  # 大跳
	assert_gt(t.punch_scale(), 1.0, "大跳触发 punch")

func test_punch_decays() -> void:
	var t := ScoreTickerScript.new()
	t.update(0.0, 1.0 / 60.0)
	t.update(300.0, 1.0 / 60.0)
	assert_gt(t.punch_scale(), 1.0)
	for i in 60:
		t.update(300.0, 1.0 / 60.0)
	assert_almost_eq(t.punch_scale(), 1.0, 1e-2, "punch 衰减回 1.0")

func test_small_increment_no_punch() -> void:
	var t := ScoreTickerScript.new()
	for i in 300:
		t.update(200.0, 1.0 / 60.0)
	t.update(210.0, 1.0 / 60.0)   # +10 < JUMP_MIN(20) → 不 punch
	assert_almost_eq(t.punch_scale(), 1.0, 1e-2, "小增量不 punch")

func test_reset() -> void:
	var t := ScoreTickerScript.new()
	t.update(300.0, 1.0 / 60.0)
	t.reset()
	assert_eq(t.value(), 0.0, "归零")
	assert_almost_eq(t.punch_scale(), 1.0, 1e-3, "punch 归零")

func test_frac_threshold_blocks_punch() -> void:
	var t := ScoreTickerScript.new()
	for i in 300:
		t.update(200.0, 1.0 / 60.0)   # 收敛到 _target=200
	t.update(222.0, 1.0 / 60.0)        # jump=22 > JUMP_MIN(20)，但 22 < 200*0.15=30 → 不 punch
	assert_almost_eq(t.punch_scale(), 1.0, 1e-2, "超 JUMP_MIN 但未超 JUMP_FRAC → 不 punch")
