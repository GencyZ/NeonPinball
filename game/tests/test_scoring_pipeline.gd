extends GutTest

# ---- ScoreContext ----

func test_sc_add_and_ledger() -> void:
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 5.0, &"peg")
    assert_eq(ctx.ledger.size(), 1)
    assert_almost_eq(float(ctx.ledger[0][&"value"]), 5.0, 1e-4)
    assert_eq(ctx.ledger[0][&"source"], &"peg")

func test_sc_clear_for_launch() -> void:
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 5.0, &"peg")
    ctx.bounce_count = 3; ctx.pegs_hit = 2
    ctx.clear_for_launch()
    assert_eq(ctx.ledger.size(), 0, "ledger cleared")
    assert_eq(ctx.bounce_count, 0)
    assert_eq(ctx.pegs_hit, 0)

# ---- TriggerRuntime helpers ----

func _make_rt(mask: int, effect: TriggerDef.Effect, value: float,
              cond: TriggerDef.Condition = TriggerDef.Condition.NONE,
              thresh: int = 0) -> TriggerRuntime:
    var def := TriggerDef.new()
    def.id = &"t"; def.listen_mask = mask
    def.effect = effect; def.value = value
    def.condition = cond; def.condition_threshold = thresh
    return TriggerRuntime.new(def)

func _peg_event() -> Dictionary:
    return {&"type": SimEvent.PEG_HIT, &"peg_id": 0, &"pos": Vector2.ZERO}
func _bounce_event() -> Dictionary:
    return {&"type": SimEvent.BOUNCE, &"peg_id": -1, &"pos": Vector2.ZERO}
func _settled_event() -> Dictionary:
    return {&"type": SimEvent.SETTLED, &"peg_id": -1, &"pos": Vector2.ZERO}

# ---- TriggerRuntime ----

func test_tr_fires_on_peg_hit() -> void:
    var rt := _make_rt(1, TriggerDef.Effect.ADD_BASE, 3.0)
    var ctx := ScoreContext.new()
    rt.on_event(_peg_event(), ctx)
    assert_eq(ctx.ledger.size(), 1)
    assert_almost_eq(float(ctx.ledger[0][&"value"]), 3.0, 1e-4)

func test_tr_ignores_wrong_event() -> void:
    var rt := _make_rt(1, TriggerDef.Effect.ADD_BASE, 3.0)
    var ctx := ScoreContext.new()
    rt.on_event(_bounce_event(), ctx)
    assert_eq(ctx.ledger.size(), 0, "bounce must be ignored")

func test_tr_bounce_adds_mult() -> void:
    var rt := _make_rt(2, TriggerDef.Effect.ADD_MULT, 0.2)
    var ctx := ScoreContext.new()
    rt.on_event(_bounce_event(), ctx)
    assert_eq(ctx.ledger.size(), 1)
    assert_eq(int(ctx.ledger[0][&"kind"]), ScoreContext.KIND_ADD_MULT)

func test_tr_condition_pegs_hit_gte_not_met() -> void:
    var rt := _make_rt(4, TriggerDef.Effect.MUL_MULT, 1.5,
                       TriggerDef.Condition.PEGS_HIT_GTE, 5)
    var ctx := ScoreContext.new(); ctx.pegs_hit = 4
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 0, "condition not met -> no fire")

func test_tr_condition_pegs_hit_gte_met() -> void:
    var rt := _make_rt(4, TriggerDef.Effect.MUL_MULT, 1.5,
                       TriggerDef.Condition.PEGS_HIT_GTE, 5)
    var ctx := ScoreContext.new(); ctx.pegs_hit = 5
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 1, "condition met -> fire")

func test_tr_condition_bounce_gte() -> void:
    var rt := _make_rt(4, TriggerDef.Effect.ADD_MULT, 1.0,
                       TriggerDef.Condition.BOUNCE_GTE, 3)
    var ctx := ScoreContext.new(); ctx.bounce_count = 2
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 0, "2 < 3 -> no fire")
    ctx.bounce_count = 3
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 1, "3 >= 3 -> fire")

# ---- ScoringEngine ----

func test_se_base_only() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_BASE, 5.0,  &"peg")
    var result := eng.settle(ctx)
    assert_almost_eq(float(result[0]), 15.0, 1e-4, "score=15")

func test_se_add_mult() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_MULT, 0.5,  &"bounce")
    var result := eng.settle(ctx)
    assert_almost_eq(float(result[0]), 15.0, 1e-4, "score=15")

func test_se_mul_mult() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_MULT, 1.0,  &"bonus")
    ctx.add(ScoreContext.KIND_MUL_MULT, 2.0,  &"big")
    var result := eng.settle(ctx)
    assert_almost_eq(float(result[0]), 40.0, 1e-4, "score=40")

func test_se_settle_steps_non_empty() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 5.0, &"peg")
    var result := eng.settle(ctx)
    assert_true(result[1].size() > 0, "steps array non-empty")

func test_se_empty_context_returns_zero() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    var result := eng.settle(ctx)
    assert_almost_eq(float(result[0]), 0.0, 1e-4, "empty -> score=0")
