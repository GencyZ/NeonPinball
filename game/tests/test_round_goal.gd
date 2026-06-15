extends GutTest

const RoundGoalScript := preload("res://run/round_goal.gd")

func test_target_count_curve() -> void:
	assert_eq(RoundGoalScript.target_count_for(1), 3, "区1 → 3")
	assert_eq(RoundGoalScript.target_count_for(3), 4, "区3 → 4")
	assert_eq(RoundGoalScript.target_count_for(5), 5, "区5 → 5")
	assert_eq(RoundGoalScript.target_count_for(7), 6, "区7 → 6")

func test_target_count_monotonic_and_capped() -> void:
	for a in range(1, 12):
		assert_true(RoundGoalScript.target_count_for(a + 1) >= RoundGoalScript.target_count_for(a),
			"数量单调不降 @%d" % a)
	assert_eq(RoundGoalScript.target_count_for(20), 6, "封顶 6")

func test_target_hp_curve() -> void:
	assert_eq(RoundGoalScript.target_hp_for(1), 2, "区1 HP2")
	assert_eq(RoundGoalScript.target_hp_for(3), 2, "区3 HP2")
	assert_eq(RoundGoalScript.target_hp_for(4), 3, "区4 HP3")

func test_target_hp_monotonic_and_capped() -> void:
	for a in range(1, 12):
		assert_true(RoundGoalScript.target_hp_for(a + 1) >= RoundGoalScript.target_hp_for(a),
			"HP 单调不降 @%d" % a)
	assert_eq(RoundGoalScript.target_hp_for(20), 3, "封顶 3")
