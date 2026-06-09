extends GutTest

func _run_once() -> Array:
	var rect := Rect2(0, 0, 200, 400)
	var pegs := [
		{&"id": 0, &"pos": Vector2(60, 120), &"radius": 8.0, &"base_score": 5.0},
		{&"id": 1, &"pos": Vector2(140, 160), &"radius": 8.0, &"base_score": 5.0},
		{&"id": 2, &"pos": Vector2(100, 220), &"radius": 8.0, &"base_score": 5.0},
	]
	var cfg := {
		&"gravity": Vector2(0, 500), &"max_speed": 2000.0,
		&"restitution": 0.85, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
	}
	var sim := BallSimulation.new(rect, pegs, cfg)
	var scorer := Scorer.new(pegs)
	var ball := EntryResolver.make_ball(
		EntryResolver.BoardEdge.TOP, 0.42, 0.15, 280.0, 5.0, rect)
	var path: Array[Vector2] = []
	var events: Array = []
	for _i in 1000:
		if not ball.alive: break
		sim.step(ball, events)
		path.append(ball.pos)
	return [path, scorer.score_launch(events)]

func test_same_inputs_produce_identical_result() -> void:
	var a := _run_once()
	var b := _run_once()
	# 得分逐位相等（float ==，无需 almost_eq）
	assert_eq(a[1], b[1], "score must match exactly bit-for-bit")
	var pa: Array = a[0]; var pb: Array = b[0]
	assert_eq(pa.size(), pb.size(), "path length must match")
	for i in pa.size():
		assert_eq(pa[i], pb[i], "pos[%d] must match exactly" % i)
