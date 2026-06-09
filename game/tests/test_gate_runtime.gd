extends GutTest

func _ball(speed: float = 500.0) -> BallState:
    return BallState.new(Vector2(270, 0), Vector2(0, 1) * speed, 8.0)

func _def(kind: GateDef.Kind, speed_mul: float = 1.5,
         angle: float = 0.3, split: int = 3) -> GateDef:
    var d := GateDef.new()
    d.id = &"t"; d.kind = kind
    d.speed_mul = speed_mul; d.scatter_angle = angle; d.split_count = split
    return d

# ---- GateRuntime ----

func test_normal_passthrough() -> void:
    var rt := GateRuntime.new(_def(GateDef.Kind.NORMAL), DeterministicRng.new(0))
    var result := rt.apply([_ball(600.0)])
    assert_eq(result.size(), 1, "still 1 ball")
    assert_almost_eq(result[0].vel.length(), 600.0, 1e-3, "speed unchanged")

func test_accel_increases_speed() -> void:
    var rt := GateRuntime.new(_def(GateDef.Kind.ACCEL, 1.5), DeterministicRng.new(0))
    var result := rt.apply([_ball(500.0)])
    assert_eq(result.size(), 1)
    assert_almost_eq(result[0].vel.length(), 750.0, 1e-3, "speed x 1.5")

func test_accel_preserves_direction() -> void:
    var ball := _ball(500.0)
    var orig_dir := ball.vel.normalized()
    var rt := GateRuntime.new(_def(GateDef.Kind.ACCEL, 2.0), DeterministicRng.new(0))
    var result := rt.apply([ball])
    assert_almost_eq(result[0].vel.normalized().x, orig_dir.x, 1e-4)
    assert_almost_eq(result[0].vel.normalized().y, orig_dir.y, 1e-4)

func test_scatter_angle_preserves_speed() -> void:
    var rt := GateRuntime.new(_def(GateDef.Kind.SCATTER_ANGLE, 1.0, 0.3),
                              DeterministicRng.new(7))
    var result := rt.apply([_ball(500.0)])
    assert_eq(result.size(), 1, "still 1 ball")
    assert_almost_eq(result[0].vel.length(), 500.0, 1e-3, "speed preserved after rotation")

func test_scatter_angle_deterministic() -> void:
    var d := _def(GateDef.Kind.SCATTER_ANGLE, 1.0, 0.5)
    var r1 := GateRuntime.new(d, DeterministicRng.new(42))
    var r2 := GateRuntime.new(d, DeterministicRng.new(42))
    var res1 := r1.apply([_ball()])
    var res2 := r2.apply([_ball()])
    assert_almost_eq(res1[0].vel.x, res2[0].vel.x, 1e-6, "same rng seed → same result")

func test_scatter_split_count() -> void:
    var rt := GateRuntime.new(_def(GateDef.Kind.SCATTER_SPLIT, 1.0, 0.4, 3),
                              DeterministicRng.new(0))
    var result := rt.apply([_ball()])
    assert_eq(result.size(), 3, "split into 3 balls")

func test_scatter_split_preserves_speed() -> void:
    var rt := GateRuntime.new(_def(GateDef.Kind.SCATTER_SPLIT, 1.0, 0.4, 3),
                              DeterministicRng.new(0))
    var result := rt.apply([_ball(600.0)])
    for b in result:
        assert_almost_eq(b.vel.length(), 600.0, 1e-3, "each sub-ball keeps original speed")

func test_scatter_split_center_ball_same_dir() -> void:
    # Middle ball (index 1 of 3) has frac=0 → angle=0 → same direction as input
    var rt := GateRuntime.new(_def(GateDef.Kind.SCATTER_SPLIT, 1.0, 0.4, 3),
                              DeterministicRng.new(0))
    var ball := _ball(500.0)
    var orig_dir := ball.vel.normalized()
    var result := rt.apply([ball])
    assert_almost_eq(result[1].vel.normalized().x, orig_dir.x, 1e-4)
    assert_almost_eq(result[1].vel.normalized().y, orig_dir.y, 1e-4)

# ---- GateChain ----

func test_chain_single_normal() -> void:
    var gn := GateRuntime.new(_def(GateDef.Kind.NORMAL), DeterministicRng.new(0))
    var chain := GateChain.new([gn])
    var result := chain.process(_ball(700.0))
    assert_eq(result.size(), 1)
    assert_almost_eq(result[0].vel.length(), 700.0, 1e-3)

func test_chain_empty_passthrough() -> void:
    var chain := GateChain.new([])
    var result := chain.process(_ball(700.0))
    assert_eq(result.size(), 1, "no gates → ball passes through unchanged")

func test_chain_accel_then_normal() -> void:
    var ga := GateRuntime.new(_def(GateDef.Kind.ACCEL, 2.0), DeterministicRng.new(0))
    var gn := GateRuntime.new(_def(GateDef.Kind.NORMAL),     DeterministicRng.new(0))
    var chain := GateChain.new([ga, gn])
    var result := chain.process(_ball(500.0))
    assert_eq(result.size(), 1)
    assert_almost_eq(result[0].vel.length(), 1000.0, 1e-3, "500 x 2 = 1000")
