extends GutTest

func _make_pegs() -> Array:
	return [
		{&"id": 0, &"pos": Vector2.ZERO, &"radius": 5.0, &"base_score": 3.0},
		{&"id": 1, &"pos": Vector2.ZERO, &"radius": 5.0, &"base_score": 7.0},
	]

func test_sum_base_score_per_peg_hit() -> void:
	var scorer := Scorer.new(_make_pegs())
	var events := [
		SimEvent.peg_hit(0, Vector2.ZERO),  # +3
		SimEvent.peg_hit(1, Vector2.ZERO),  # +7
		SimEvent.peg_hit(0, Vector2.ZERO),  # +3
		SimEvent.bounce(Vector2.ZERO),       # 非计分，忽略
	]
	assert_almost_eq(scorer.score_launch(events), 13.0, 1e-4, "3+7+3=13")

func test_non_peg_events_ignored() -> void:
	var scorer := Scorer.new(_make_pegs())
	var events := [
		SimEvent.bounce(Vector2.ZERO),
		SimEvent.wall_hit(Vector2.ZERO),
		SimEvent.settled(Vector2.ZERO),
		SimEvent.launch(Vector2.ZERO),
	]
	assert_almost_eq(scorer.score_launch(events), 0.0, 1e-4, "no peg hits → 0 score")

func test_invalid_peg_id_skipped() -> void:
	var scorer := Scorer.new(_make_pegs())
	var events := [
		SimEvent.peg_hit(99, Vector2.ZERO),  # out of bounds
		SimEvent.peg_hit(-1, Vector2.ZERO),  # -1 sentinel
	]
	assert_almost_eq(scorer.score_launch(events), 0.0, 1e-4, "invalid ids → 0 score")
