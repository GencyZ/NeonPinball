extends GutTest

func test_triggers_registered() -> void:
    assert_true(GameDB.triggers.has(&"peg_bonus"),    "peg_bonus registered")
    assert_true(GameDB.triggers.has(&"bounce_mult"),  "bounce_mult registered")
    assert_true(GameDB.triggers.has(&"big_hit"),      "big_hit registered")

func test_gates_registered() -> void:
    assert_true(GameDB.gate_defs.has(&"normal"),        "normal gate registered")
    assert_true(GameDB.gate_defs.has(&"accel"),         "accel gate registered")
    assert_true(GameDB.gate_defs.has(&"scatter_angle"), "scatter_angle gate registered")
    assert_true(GameDB.gate_defs.has(&"scatter_split"), "scatter_split gate registered")

func test_peg_bonus_definition() -> void:
    var t: TriggerDef = GameDB.triggers[&"peg_bonus"]
    assert_eq(t.listen_mask, 1, "peg_bonus listens to PEG_HIT (mask=1)")
    assert_eq(int(t.effect), int(TriggerDef.Effect.ADD_BASE), "peg_bonus is ADD_BASE")
    assert_almost_eq(t.value, 3.0, 1e-4, "peg_bonus value=3")

func test_big_hit_condition() -> void:
    var t: TriggerDef = GameDB.triggers[&"big_hit"]
    assert_eq(int(t.condition), int(TriggerDef.Condition.PEGS_HIT_GTE))
    assert_eq(t.condition_threshold, 5)
    assert_almost_eq(t.value, 1.5, 1e-4)

func test_accel_gate_speed_mul() -> void:
    var g: GateDef = GameDB.gate_defs[&"accel"]
    assert_almost_eq(g.speed_mul, 1.5, 1e-4)

func test_scatter_split_count() -> void:
    var g: GateDef = GameDB.gate_defs[&"scatter_split"]
    assert_eq(g.split_count, 3)
