extends GutTest

const ComboScoreScript := preload("res://scoring/combo_score.gd")

func test_below_min_no_bonus() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(0), 1.0, 1e-5, "0 钉无加成")
	assert_almost_eq(ComboScoreScript.xmult_for(1), 1.0, 1e-5, "1 钉无加成")

func test_threshold_start() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(2), 1.24, 1e-4, "2 钉 = ×1.24")

func test_mid_value() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(10), 2.2, 1e-4, "10 钉 = ×2.2")

func test_monotonic_non_decreasing() -> void:
	for n in range(0, 40):
		assert_true(ComboScoreScript.xmult_for(n + 1) >= ComboScoreScript.xmult_for(n),
			"单调不降 @%d" % n)

func test_capped_at_5() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(100), 5.0, 1e-4, "封顶 ×5")
	for n in range(0, 120):
		assert_true(ComboScoreScript.xmult_for(n) <= 5.0, "不超过 5 @%d" % n)

func test_cap_boundary() -> void:
	# 34 钉首次封顶（(5-1)/0.12=33.3），33 钉仍未封顶
	assert_lt(ComboScoreScript.xmult_for(33), 5.0, "33 钉未封顶")
	assert_almost_eq(ComboScoreScript.xmult_for(34), 5.0, 1e-4, "34 钉首次封顶")

func test_pipeline_combo_multiplies() -> void:
	# base 10 × combo(10)=2.2 → 22
	var eng := ScoringEngine.new()
	var ctx := ScoreContext.new()
	ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
	ctx.add(ScoreContext.KIND_MUL_MULT, ComboScoreScript.xmult_for(10), &"combo")
	assert_almost_eq(float(eng.settle(ctx)[0]), 22.0, 1e-4, "10 × 2.2 = 22")
