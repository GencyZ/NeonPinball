extends GutTest
func test_mult_type_exists() -> void:
	assert_true(GameDB.peg_types.has(&"mult"))
	var pm: PegType = GameDB.peg_types[&"mult"]
	assert_eq(pm.behavior, PegType.Behavior.MULT)
	assert_true(pm.mult_add > 0.0)
func test_mult_peg_adds_to_ledger() -> void:
	var ctx := ScoreContext.new()
	var pm: PegType = GameDB.peg_types[&"mult"]
	ctx.pegs_hit += 1
	ctx.add(ScoreContext.KIND_ADD_MULT, pm.mult_add, &"mult_peg")
	assert_eq(ctx.ledger.size(), 1)
	assert_eq(ctx.ledger[0][&"kind"], ScoreContext.KIND_ADD_MULT)
	assert_almost_eq(ctx.ledger[0][&"value"], pm.mult_add, 0.001)
func test_mult_peg_increases_score() -> void:
	var ctx := ScoreContext.new()
	ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"base")
	ctx.add(ScoreContext.KIND_ADD_MULT, 0.5, &"mult_peg")
	var engine := ScoringEngine.new()
	var result := engine.settle(ctx)
	assert_almost_eq(result[0], 15.0, 0.01)
