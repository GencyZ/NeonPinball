extends GutTest

const RunManagerScript := preload("res://run/run_manager.gd")

func test_quota_of_ante1_round0() -> void:
    assert_almost_eq(RunManagerScript.quota_of(1, 0), 50.0, 1.0)

func test_quota_of_ante1_round2() -> void:
    assert_almost_eq(RunManagerScript.quota_of(1, 2), 90.0, 1.0)

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
