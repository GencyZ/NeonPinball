extends GutTest

func _sim() -> BallSimulation:
    var rect := Rect2(0, 0, 540, 900)
    var cfg := {&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
                &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": 1.0 / 120.0}
    return BallSimulation.new(rect, [], cfg)

func _start() -> BallState:
    return BallState.new(Vector2(270, 0), Vector2(0, 1) * 1000.0, 8.0)

func test_fan_count_matches_samples() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 30)
    assert_eq(fans.size(), 5, "5 samples → 5 fans")

func test_fan_each_has_points() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 30)
    for fan in fans:
        assert_true(fan.size() > 0, "each fan non-empty")

func test_fan_each_bounded_by_steps() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 20)
    for fan in fans:
        assert_true(fan.size() <= 20, "at most 20 pts per fan")

func test_fan_zero_scatter_matches_predict() -> void:
    var sim := _sim(); var start := _start()
    var fans := TrajectoryPredictor.predict_fan(sim, start, 0.0, 1, 15)
    var direct := TrajectoryPredictor.predict(sim, start.clone(), 15)
    assert_eq(fans.size(), 1)
    assert_eq(fans[0].size(), direct.size(), "zero-scatter fan = direct predict")
    for i in fans[0].size():
        assert_almost_eq(fans[0][i].x, direct[i].x, 1e-3)
        assert_almost_eq(fans[0][i].y, direct[i].y, 1e-3)

func test_fan_single_sample_uses_leftmost_angle() -> void:
    var sim := _sim()
    var start := _start()
    var fans := TrajectoryPredictor.predict_fan(sim, start, 0.5, 1, 10)
    var rotated := BallState.new(start.pos, start.vel.rotated(-0.5), start.radius)
    var direct := TrajectoryPredictor.predict(sim, rotated, 10)
    assert_eq(fans[0].size(), direct.size())
    if fans[0].size() > 0:
        assert_almost_eq(fans[0][0].x, direct[0].x, 1e-3)
