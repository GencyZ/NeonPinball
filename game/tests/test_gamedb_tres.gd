extends GutTest

# 解锁门控的资源：即使启动时被 _apply_unlocks 从 GameDB 过滤掉，
# .tres 文件本身仍须能正确解析，故直接 preload 验证。
const ChainBonusRes   := preload("res://data/resources/triggers/trigger_chain_bonus.tres")
const ScatterSplitRes := preload("res://data/resources/gates/gate_scatter_split.tres")

func test_all_pegs_loaded_from_tres() -> void:
	for id in [&"normal", &"mult", &"chain", &"bomb", &"freeze",
			   &"jackpot", &"life", &"poison", &"portal", &"magnet"]:
		assert_true(GameDB.peg_types.has(id), "%s peg 从 .tres 加载" % id)

func test_always_available_triggers_loaded() -> void:
	assert_true(GameDB.triggers.has(&"peg_bonus"),   "peg_bonus 从 .tres 加载")
	assert_true(GameDB.triggers.has(&"bounce_mult"), "bounce_mult 从 .tres 加载")
	assert_true(GameDB.triggers.has(&"big_hit"),     "big_hit 从 .tres 加载")

func test_always_available_gates_loaded() -> void:
	assert_true(GameDB.gate_defs.has(&"normal"), "normal gate 从 .tres 加载")
	assert_true(GameDB.gate_defs.has(&"accel"),  "accel gate 从 .tres 加载")

func test_peg_values_correct() -> void:
	var pm: PegType = GameDB.peg_types[&"mult"]
	assert_eq(pm.behavior, PegType.Behavior.MULT, "mult peg behavior")
	assert_eq(pm.mult_add, 0.5, "mult peg mult_add")
	var pb: PegType = GameDB.peg_types[&"bomb"]
	assert_eq(pb.behavior, PegType.Behavior.BOMB, "bomb peg behavior")
	assert_true(pb.one_shot, "bomb one_shot")
	assert_eq(pb.base_score, 20.0, "bomb base_score")

func test_trigger_values_correct() -> void:
	var td: TriggerDef = GameDB.triggers[&"big_hit"]
	assert_eq(td.condition, TriggerDef.Condition.PEGS_HIT_GTE, "big_hit condition")
	assert_eq(td.condition_threshold, 5, "big_hit threshold")
	assert_eq(td.effect, TriggerDef.Effect.MUL_MULT, "big_hit effect")

func test_gated_tres_parse_correctly() -> void:
	assert_eq(ChainBonusRes.condition, TriggerDef.Condition.PEGS_HIT_GTE, "chain_bonus condition")
	assert_eq(ChainBonusRes.value, 10.0, "chain_bonus value")
	assert_eq(ScatterSplitRes.kind, GateDef.Kind.SCATTER_SPLIT, "scatter_split kind")
	assert_eq(ScatterSplitRes.split_count, 3, "scatter_split split_count")
