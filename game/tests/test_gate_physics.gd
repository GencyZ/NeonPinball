extends GutTest

const BallSimulation := preload("res://sim/ball_simulation.gd")
const BallState := preload("res://sim/ball_state.gd")

var _cfg := {
	&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
	&"restitution": 0.82, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
}
var _rect := Rect2(0, 0, 540, 900)

func _make_sim(segs: Array) -> BallSimulation:
	var sim := BallSimulation.new(_rect, [], _cfg)
	sim.set_wall_segs(segs)
	return sim

func test_funnel_wall_low_bounce():
	# Ball hits left funnel wall (0,780)→(240,900) and barely bounces
	var sim := _make_sim([
		{&"a": Vector2(0, 780), &"b": Vector2(240, 900), &"restitution": 0.05}
	])
	var ball := BallState.new(Vector2(50, 750), Vector2(0, 500), 8.0)
	var events: Array = []
	for _i in 60:
		sim.step(ball, events)
	# After hitting funnel, ball should be deflected toward center (positive x)
	assert_true(ball.vel.x > 0.0, "funnel redirects ball toward center")

func test_gate_closed_blocks_ball():
	# Gate segment at x=0, y=100..140; ball moving left should bounce
	var gate_seg := {&"a": Vector2(0, 100), &"b": Vector2(0, 140), &"restitution": 0.82}
	# Also include left wall above and below gate
	var sim := _make_sim([
		{&"a": Vector2(0, 0), &"b": Vector2(0, 100), &"restitution": 0.82},
		gate_seg,
		{&"a": Vector2(0, 140), &"b": Vector2(0, 900), &"restitution": 0.82},
	])
	var ball := BallState.new(Vector2(50, 120), Vector2(-500, 0), 8.0)
	var events: Array = []
	for _i in 20:
		sim.step(ball, events)
	assert_true(ball.vel.x > 0.0, "gate closed: ball bounces right")

func test_gate_open_ball_passes():
	# Gate is open (gap in wall at y=100..140); ball at y=120 passes through x=0
	var sim := _make_sim([
		{&"a": Vector2(0, 0), &"b": Vector2(0, 100), &"restitution": 0.82},
		# gate segment NOT included — open
		{&"a": Vector2(0, 140), &"b": Vector2(0, 900), &"restitution": 0.82},
	])
	var ball := BallState.new(Vector2(50, 120), Vector2(-500, 0), 8.0)
	var events: Array = []
	for _i in 20:
		sim.step(ball, events)
	# Ball should have crossed x=0 (or be very close without bouncing)
	assert_true(ball.vel.x < 0.0, "gate open: ball continues left")
