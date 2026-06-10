# tests/test_run_loop.gd
extends GutTest

const RunManagerScript := preload("res://run/run_manager.gd")

# Simulate full 3-area run (3 areas × 3 rounds = 9 rounds)
# with cheat score to guarantee passing each round.
# Purpose: verify state machine transitions, payout logic, boss mod at round 3.

func test_full_3_area_run_win() -> void:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.advance()   # BOOT → RUN_START
    mgr.advance()   # RUN_START → ROUND

    var round_count := 0
    var shop_count  := 0

    for _iter in 60:   # upper bound to prevent infinite loop
        var phase: int = mgr.state[&"phase"]
        match phase:
            RunManagerScript.Phase.ROUND, RunManagerScript.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance()   # → ANTE_CLEAR
                round_count += 1
            RunManagerScript.Phase.ANTE_CLEAR:
                mgr.advance()   # → SHOP or RUN_WIN
            RunManagerScript.Phase.SHOP:
                mgr.advance()   # → ROUND (skip shop)
                shop_count += 1
            RunManagerScript.Phase.RUN_WIN:
                break
            RunManagerScript.Phase.RUN_LOSE:
                fail_test("Should not lose with cheat score")
                break

    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_WIN, "should win after 3 areas")
    assert_eq(round_count, 9, "3 areas × 3 rounds = 9 rounds")
    # Last boss round of area 3 transitions ANTE_CLEAR → RUN_WIN (no shop).
    # 8 shops total: 2 per area for rounds 0+1, plus 1 boss-round shop for areas 1+2 only.
    assert_eq(shop_count,  8, "8 shops (boss round of final area skips to RUN_WIN)")
    mgr.free()

func test_lose_on_low_score() -> void:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 0.0
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_LOSE)
    mgr.free()

func test_boss_round_at_round_2() -> void:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.advance()
    mgr.advance()
    # Pass first 2 rounds (round_in_ante 0 and 1)
    for _r in 2:
        mgr.state[&"round_score"] = 999999.0
        mgr.advance()   # ROUND → ANTE_CLEAR
        mgr.advance()   # ANTE_CLEAR → SHOP
        mgr.advance()   # SHOP → next ROUND
    assert_eq(mgr.state[&"round_in_ante"], 2)
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOSS_ROUND)
    assert_false(mgr.state[&"boss_mod"].is_empty(), "boss mod must be set in boss round")
    mgr.free()

func test_money_accumulates_across_rounds() -> void:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.advance()
    mgr.advance()

    var prev_money := 0
    for _r in 3:
        mgr.state[&"round_score"] = 999999.0
        # launches_left is reset by _start_round; set it after advancing to ANTE_CLEAR
        mgr.advance()   # ROUND/BOSS_ROUND → ANTE_CLEAR (payout reads launches_left here)
        assert_true(mgr.state[&"phase"] == RunManagerScript.Phase.ANTE_CLEAR or \
                    mgr.state[&"phase"] == RunManagerScript.Phase.RUN_WIN, \
                    "expected ANTE_CLEAR or RUN_WIN")
        if mgr.state[&"phase"] == RunManagerScript.Phase.RUN_WIN:
            break
        mgr.advance()   # ANTE_CLEAR → SHOP (triggers payout, increases money)
        assert_true(mgr.state[&"money"] > prev_money, "money must grow after payout")
        prev_money = mgr.state[&"money"]
        mgr.advance()   # SHOP → ROUND

    mgr.free()

func test_quota_grows_each_ante() -> void:
    var q1 := RunManagerScript.quota_of(1, 0)
    var q2 := RunManagerScript.quota_of(2, 0)
    var q3 := RunManagerScript.quota_of(3, 0)
    assert_true(q1 < q2, "quota grows with ante")
    assert_true(q2 < q3, "quota grows with ante")

func test_replay_same_final_state() -> void:
    var state_a := _run_headless(12345)
    var state_b := _run_headless(12345)

    assert_eq(state_a[&"money"],  state_b[&"money"])
    assert_eq(state_a[&"ante"],   state_b[&"ante"])
    assert_eq(state_a[&"phase"],  state_b[&"phase"])

func test_8_area_run_win_requires_24_rounds() -> void:
    var mgr := RunManagerScript.new()
    mgr.advance(); mgr.advance()
    var rounds := 0
    for _i in 200:
        match mgr.state[&"phase"]:
            RunManagerScript.Phase.ROUND, RunManagerScript.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance(); rounds += 1
            RunManagerScript.Phase.ANTE_CLEAR:
                mgr.advance()
            RunManagerScript.Phase.SHOP:
                mgr.advance()
            RunManagerScript.Phase.RUN_WIN:
                break
            _:
                break
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_WIN)
    assert_eq(rounds, 24, "8 areas x 3 rounds = 24")
    mgr.free()

func _run_headless(seed: int) -> Dictionary:
    var mgr := RunManagerScript.new()
    mgr.max_areas = 3
    mgr.state[&"master_seed"] = seed
    mgr.advance()
    mgr.advance()
    for _iter in 60:
        var phase: int = mgr.state[&"phase"]
        match phase:
            RunManagerScript.Phase.ROUND, RunManagerScript.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance()
            RunManagerScript.Phase.ANTE_CLEAR:
                mgr.advance()
            RunManagerScript.Phase.SHOP:
                mgr.advance()
            _:
                break
    var result := mgr.state.duplicate()
    mgr.free()
    return result
