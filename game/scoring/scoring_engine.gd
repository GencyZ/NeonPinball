class_name ScoringEngine

# Returns [score: float, settle_steps: Array]
# Three-tier order: +base -> +mult -> x mult
func settle(ctx: ScoreContext) -> Array:
    var base := 0.0
    var mult_add := 0.0
    var mult := 1.0
    var steps := []

    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_ADD_BASE:
            base += c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"+base",
                          &"delta": c[&"value"], &"running": base})
    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_ADD_MULT:
            mult_add += c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"+mult",
                          &"delta": c[&"value"], &"running": 1.0 + mult_add})
    mult = 1.0 + mult_add
    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_MUL_MULT:
            mult *= c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"x mult",
                          &"delta": c[&"value"], &"running": mult})

    return [base * mult, steps]
