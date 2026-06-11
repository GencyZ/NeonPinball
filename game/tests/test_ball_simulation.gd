extends GutTest

func _make_sim(pegs: Array) -> BallSimulation:
	var rect := Rect2(0, 0, 200, 400)
	var cfg := {
		&"gravity": Vector2(0, 500),
		&"max_speed": 2000.0,
		&"restitution": 0.8,
		&"tangent_keep": 1.0,
		&"dt": 1.0 / 120.0,
	}
	return BallSimulation.new(rect, pegs, cfg)

func test_ball_falls_and_settles() -> void:
	var sim := _make_sim([])
	var ball := BallState.new(Vector2(100, 10), Vector2.ZERO, 5.0)
	var events: Array = []
	for _i in 600:
		if not ball.alive: break
		sim.step(ball, events)
	assert_false(ball.alive, "ball should become inactive after settling")
	var settled := events.filter(func(e): return e[&"type"] == SimEvent.SETTLED)
	assert_gt(settled.size(), 0, "SETTLED event must be emitted")

func test_ball_hits_peg_directly_above() -> void:
	var pegs := [{&"id": 0, &"pos": Vector2(100, 100), &"radius": 8.0, &"base_score": 5.0}]
	var sim := _make_sim(pegs)
	var ball := BallState.new(Vector2(100, 10), Vector2.ZERO, 5.0)
	var events: Array = []
	for _i in 600:
		if not ball.alive: break
		sim.step(ball, events)
	var peg_hits := events.filter(func(e): return e[&"type"] == SimEvent.PEG_HIT and e[&"peg_id"] == 0)
	assert_gt(peg_hits.size(), 0, "should emit PEG_HIT for peg 0")

func test_no_tunneling_at_high_speed() -> void:
	# 高初速（3000px/s），单步位移远超钉直径；CCD 必须仍能命中
	var pegs := [{&"id": 0, &"pos": Vector2(100, 200), &"radius": 8.0, &"base_score": 5.0}]
	var sim := _make_sim(pegs)
	var ball := BallState.new(Vector2(100, 10), Vector2(0, 3000), 5.0)
	var events: Array = []
	for _i in 600:
		if not ball.alive: break
		sim.step(ball, events)
	var hits := events.filter(func(e): return e[&"type"] == SimEvent.PEG_HIT and e[&"peg_id"] == 0)
	assert_gt(hits.size(), 0, "CCD must catch high-speed ball")

func test_bounce_event_emitted_on_wall() -> void:
	var sim := _make_sim([])
	# 球从左侧向左运动，必然碰左墙产生 WALL_HIT + BOUNCE
	var ball := BallState.new(Vector2(5, 200), Vector2(-500, 0), 5.0)
	var events: Array = []
	for _i in 30:
		if not ball.alive: break
		sim.step(ball, events)
	var wall_hits := events.filter(func(e): return e[&"type"] == SimEvent.WALL_HIT)
	assert_gt(wall_hits.size(), 0, "wall hit event emitted")

func test_ball_bounces_off_wall_segment():
	# Custom wall segment at x=200; ball bounces with per-segment restitution 0.5
	var sim := BallSimulation.new(Rect2(0, 0, 540, 900), [], {
		&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
		&"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0})
	sim.set_wall_segs([
		{&"a": Vector2(200, 0), &"b": Vector2(200, 300), &"restitution": 0.5}
	])
	var ball := BallState.new(Vector2(100, 100), Vector2(1200, 0), 8.0)
	var events: Array = []
	for _i in 20:
		sim.step(ball, events)
		if not events.is_empty():
			break
	var wall_hits := events.filter(func(e): return e[&"type"] == SimEvent.WALL_HIT)
	assert_gt(wall_hits.size(), 0, "wall collision should be detected")
	assert_true(ball.vel.x < 0.0, "ball should bounce left")
	assert_almost_eq(abs(ball.vel.x), 600.0, 50.0, "per-seg restitution 0.5 applied")

func test_wall_seg_low_restitution():
	# Funnel-like segment with low restitution 0.05; ball barely bounces back
	var sim := BallSimulation.new(Rect2(0, 0, 540, 900), [], {
		&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
		&"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0})
	sim.set_wall_segs([
		{&"a": Vector2(200, 0), &"b": Vector2(200, 300), &"restitution": 0.05}
	])
	var ball := BallState.new(Vector2(100, 100), Vector2(1200, 0), 8.0)
	var events: Array = []
	for _i in 20:
		sim.step(ball, events)
		if not events.is_empty():
			break
	var wall_hits := events.filter(func(e): return e[&"type"] == SimEvent.WALL_HIT)
	assert_gt(wall_hits.size(), 0, "should hit wall")
	assert_true(ball.vel.x < 0.0, "ball bounces back")
	assert_true(ball.vel.x > -100.0, "very low bounce with restitution 0.05")
