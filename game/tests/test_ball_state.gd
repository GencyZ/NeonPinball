extends GutTest

func test_ball_state_init() -> void:
	var b := BallState.new(Vector2(10, 20), Vector2(1, 2), 5.0)
	assert_eq(b.pos, Vector2(10, 20), "pos set")
	assert_eq(b.vel, Vector2(1, 2), "vel set")
	assert_almost_eq(b.radius, 5.0, 1e-6, "radius set")
	assert_eq(b.bounce_count, 0, "bounce_count starts 0")
	assert_true(b.alive, "alive starts true")

func test_ball_state_clone_is_independent() -> void:
	var a := BallState.new(Vector2(1, 2), Vector2(3, 4), 5.0)
	var b := a.clone()
	b.pos = Vector2(99, 99)
	assert_eq(a.pos, Vector2(1, 2), "original pos unchanged after clone mutation")

func test_sim_event_peg_hit() -> void:
	var e := SimEvent.peg_hit(3, Vector2(10, 20))
	assert_eq(e[&"type"], SimEvent.PEG_HIT, "type is PEG_HIT")
	assert_eq(e[&"peg_id"], 3, "peg_id correct")
	assert_eq(e[&"pos"], Vector2(10, 20), "pos correct")

func test_sim_event_non_peg_has_minus_one_id() -> void:
	var e := SimEvent.bounce(Vector2.ZERO)
	assert_eq(e[&"peg_id"], -1, "non-peg events have peg_id -1")
