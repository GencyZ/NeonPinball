extends GutTest

func _make_sim_with_peg() -> BallSimulation:
	var pegs := [{&"id": 0, &"pos": Vector2(100, 150), &"radius": 8.0, &"base_score": 5.0}]
	var cfg := {
		&"gravity": Vector2(0, 500), &"max_speed": 2000.0,
		&"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
	}
	return BallSimulation.new(Rect2(0, 0, 200, 400), pegs, cfg)

func test_prediction_matches_actual_path() -> void:
	var sim := _make_sim_with_peg()
	var start := EntryResolver.make_ball(
		EntryResolver.BoardEdge.TOP, 0.5, 0.2, 300.0, 5.0, Rect2(0, 0, 200, 400))

	var predicted := TrajectoryPredictor.predict(sim, start, 40)

	# 以相同起点实际跑 40 步
	var ball := start.clone()
	var actual: Array[Vector2] = []
	var ev: Array = []
	for _i in 40:
		if not ball.alive: break
		sim.step(ball, ev)
		actual.append(ball.pos)

	assert_eq(actual.size(), predicted.size(), "path length must match")
	for i in actual.size():
		assert_almost_eq(predicted[i].x, actual[i].x, 1e-4,
						 "x[%d] predicted == actual" % i)
		assert_almost_eq(predicted[i].y, actual[i].y, 1e-4,
						 "y[%d] predicted == actual" % i)

func test_prediction_does_not_mutate_sim_state() -> void:
	var sim := _make_sim_with_peg()
	var start := EntryResolver.make_ball(
		EntryResolver.BoardEdge.TOP, 0.5, 0.0, 300.0, 5.0, Rect2(0, 0, 200, 400))
	# 跑两次预测，结果应一致（说明 sim 内部状态未被污染）
	var a := TrajectoryPredictor.predict(sim, start, 30)
	var b := TrajectoryPredictor.predict(sim, start, 30)
	for i in a.size():
		assert_eq(a[i], b[i], "predict[%d] same on second call" % i)
