extends GutTest

const GambleScript := preload("res://scoring/gamble.gd")

func test_is_success_threshold() -> void:
	assert_false(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS - 1), "阈值-1 → 失败")
	assert_true(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS), "恰好阈值 → 成功")
	assert_true(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS + 5), "更多 → 成功")
	assert_false(GambleScript.is_success(0), "0 钉 → 失败")

func test_resolve_double_or_zero() -> void:
	assert_almost_eq(GambleScript.resolve(100.0, GambleScript.GAMBLE_MIN_PEGS), 100.0 * GambleScript.GAMBLE_MULT, 1e-4, "成功 ×倍率")
	assert_almost_eq(GambleScript.resolve(100.0, GambleScript.GAMBLE_MIN_PEGS - 1), 0.0, 1e-4, "失败清零")
	assert_almost_eq(GambleScript.resolve(0.0, GambleScript.GAMBLE_MIN_PEGS), 0.0, 1e-4, "base 0 成功仍 0")
