extends GutTest

const RunManagerScript := preload("res://run/run_manager.gd")

func test_quota_of_ante1_round0() -> void:
    assert_almost_eq(RunManagerScript.quota_of(1, 0), 90.0, 1.0)

func test_quota_of_ante1_round2() -> void:
    assert_almost_eq(RunManagerScript.quota_of(1, 2), 162.0, 1.0)

func test_quota_grows_with_ante() -> void:
    assert_true(RunManagerScript.quota_of(2, 0) > RunManagerScript.quota_of(1, 0))
    assert_true(RunManagerScript.quota_of(8, 0) > RunManagerScript.quota_of(4, 0))

func test_boot_to_round() -> void:
    var mgr := RunManagerScript.new()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOOT)
    mgr.advance()
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ROUND)
    assert_eq(mgr.state[&"ante"], 1)
    assert_eq(mgr.state[&"round_in_ante"], 0)
    assert_eq(mgr.state[&"launches_left"], 5)
    mgr.free()

func test_round_win_to_shop() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ANTE_CLEAR)
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.SHOP)
    assert_true(mgr.state[&"money"] > 0, "payout must give money")
    mgr.free()

func test_round_fail_to_lose() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 0.0
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_LOSE)
    mgr.free()

func test_three_rounds_advance_ante() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    for _r in 3:
        mgr.state[&"round_score"] = 9999.0
        mgr.advance()
        mgr.advance()
        mgr.advance()
    assert_eq(mgr.state[&"ante"], 2)
    assert_eq(mgr.state[&"round_in_ante"], 0)
    mgr.free()

func test_payout_includes_interest() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"money"] = 10
    mgr.state[&"launches_left"] = 3
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()
    mgr.advance()
    # base_reward(3+1=4) + launch_bonus(3) + interest(min(10/5,5)=2) = 9, plus existing 10 = 19
    assert_eq(mgr.state[&"money"], 19)
    mgr.free()

func test_boss_round_is_round_2() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    for _r in 2:
        mgr.state[&"round_score"] = 9999.0
        mgr.advance()
        mgr.advance()
        mgr.advance()
    assert_eq(mgr.state[&"round_in_ante"], 2)
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOSS_ROUND)
    assert_false(mgr.state[&"boss_mod"].is_empty(), "boss mod must be set")
    mgr.free()

func test_launches_exhausted() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()   # BOOT → RUN_START
    mgr.advance()   # RUN_START → ROUND
    assert_false(mgr.launches_exhausted(), "should not be exhausted at start")
    for _i in 5:
        mgr.spend_launch()
    assert_true(mgr.launches_exhausted(), "should be exhausted after 5 launches")
    # Extra spend_launch should not go below 0
    mgr.spend_launch()
    assert_eq(mgr.state[&"launches_left"], 0)
    mgr.free()

func test_full_3_areas_run_win() -> void:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.advance()   # BOOT → RUN_START
    mgr.advance()   # RUN_START → ROUND

    for _iter in 60:
        var phase: int = mgr.state[&"phase"]
        if phase == RunManagerScript.Phase.ROUND or phase == RunManagerScript.Phase.BOSS_ROUND:
            mgr.state[&"round_score"] = 999999.0
            mgr.advance()
        elif phase == RunManagerScript.Phase.ANTE_CLEAR:
            mgr.advance()
        elif phase == RunManagerScript.Phase.SHOP:
            mgr.advance()
        elif phase == RunManagerScript.Phase.RUN_WIN:
            break
        else:
            break

    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_WIN)
    mgr.free()

func test_reset_after_lose() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 0.0
    mgr.advance()   # → RUN_LOSE
    mgr.advance()   # → _reset() → BOOT
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOOT)
    assert_eq(mgr.state[&"ante"], 1)
    assert_eq(mgr.state[&"money"], 0)
    mgr.free()

func test_targets_done_wins_below_quota() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()   # -> ROUND
    mgr.state[&"round_score"] = 0.0
    mgr.state[&"targets_done"] = true
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ANTE_CLEAR, "clear wins even below quota")
    mgr.free()

func test_quota_still_wins_without_targets() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()
    mgr.state[&"round_score"] = 9999.0
    mgr.state[&"targets_done"] = false
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ANTE_CLEAR, "quota wins (original behavior)")
    mgr.free()

func test_neither_loses() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()
    mgr.state[&"round_score"] = 0.0
    mgr.state[&"targets_done"] = false
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_LOSE, "neither satisfied -> lose")
    mgr.free()

func test_start_round_resets_targets_done() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()
    mgr.state[&"targets_done"] = true
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()   # ROUND -> ANTE_CLEAR
    mgr.advance()   # ANTE_CLEAR -> SHOP (round_in_ante +1)
    mgr.advance()   # SHOP -> ROUND (_start_round)
    assert_false(mgr.state[&"targets_done"], "new round resets targets_done")
    mgr.free()

func test_payout_targets_bonus() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()
    mgr.state[&"money"] = 0
    mgr.state[&"launches_left"] = 0
    mgr.state[&"targets_done"] = true
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()   # ROUND -> ANTE_CLEAR
    mgr.advance()   # ANTE_CLEAR -> _payout + SHOP
    # base_reward(3+1=4) + launch_bonus(0) + interest(0) + targets_bonus(5) = 9
    assert_eq(mgr.state[&"money"], 9, "clear bonus +5")
    mgr.free()
