# run/run_manager.gd
class_name RunManager extends Node

enum Phase {
    BOOT, RUN_START,
    ROUND, BOSS_ROUND,
    ANTE_CLEAR, SHOP,
    RUN_WIN, RUN_LOSE
}

# Complete run state (serializable to JSON)
var state: Dictionary = {
    &"master_seed":         0,
    &"phase":               Phase.BOOT,
    &"ante":                1,
    &"round_in_ante":       0,
    &"round_score":         0.0,
    &"quota":               0.0,
    &"launches_left":       5,
    &"money":               0,
    &"equipped_triggers":   [&"peg_bonus", &"bounce_mult", &"big_hit"],
    &"equipped_gate":       &"normal",
    &"boss_mod":            {},
}

static func _make_default_state() -> Dictionary:
    return {
        &"master_seed":         0,
        &"phase":               0,   # Phase.BOOT — use int 0 because static func can't reference enum at class level in GDScript
        &"ante":                1,
        &"round_in_ante":       0,
        &"round_score":         0.0,
        &"quota":               0.0,
        &"launches_left":       5,
        &"money":               0,
        &"equipped_triggers":   [&"peg_bonus", &"bounce_mult", &"big_hit"],
        &"equipped_gate":       &"normal",
        &"boss_mod":            {},
    }

const LAUNCHES_PER_ROUND := 5

func _ready() -> void:
    assert(state.hash() == _make_default_state().hash(), \
           "state field and _make_default_state() diverged — update both")

static func quota_of(ante: int, round_in_ante: int) -> float:
    var ante_base := 50.0 * pow(1.6, ante - 1)
    var idx := clampi(round_in_ante, 0, 2)
    var mul: float
    if idx == 0:
        mul = 1.0
    elif idx == 1:
        mul = 1.3
    else:
        mul = 1.8
    return roundf(ante_base * mul)

func advance(input: Dictionary = {}) -> void:
    match state[&"phase"]:
        Phase.BOOT:
            state[&"phase"] = Phase.RUN_START
        Phase.RUN_START:
            _start_round()
        Phase.ROUND, Phase.BOSS_ROUND:
            if state[&"round_score"] >= state[&"quota"]:
                state[&"phase"] = Phase.ANTE_CLEAR
            else:
                state[&"phase"] = Phase.RUN_LOSE
        Phase.ANTE_CLEAR:
            _payout()
            state[&"round_in_ante"] += 1
            if state[&"round_in_ante"] > 2:
                state[&"round_in_ante"] = 0
                state[&"ante"] += 1
                if state[&"ante"] > 3:   # MVP: 3 areas win
                    state[&"phase"] = Phase.RUN_WIN
                    return
            state[&"phase"] = Phase.SHOP
        Phase.SHOP:
            _start_round()
        Phase.RUN_WIN, Phase.RUN_LOSE:
            _reset()

func spend_launch() -> void:
    state[&"launches_left"] = maxi(0, state[&"launches_left"] - 1)

func add_launch_score(score: float) -> void:
    state[&"round_score"] += score

func launches_exhausted() -> bool:
    return state[&"launches_left"] <= 0

func _start_round() -> void:
    state[&"round_score"] = 0.0
    state[&"launches_left"] = LAUNCHES_PER_ROUND
    state[&"quota"] = quota_of(state[&"ante"], state[&"round_in_ante"])
    if state[&"round_in_ante"] == 2:
        state[&"boss_mod"] = _roll_boss_mod()
        state[&"phase"] = Phase.BOSS_ROUND
    else:
        state[&"boss_mod"] = {}
        state[&"phase"] = Phase.ROUND

func _payout() -> void:
    var base_reward: int = 3 + state[&"ante"]
    var launch_bonus: int = state[&"launches_left"]
    var interest: int = mini(state[&"money"] / 5, 5)
    state[&"money"] += base_reward + launch_bonus + interest

func _roll_boss_mod() -> Dictionary:
    var rng := DeterministicRng.derive(state[&"master_seed"],
                                       state[&"ante"] * 7 + 13)
    if rng.next_float() < 0.5:
        return {&"type": &"ban_mult"}
    return {&"type": &"sparse", &"remove_chance": 0.30}

func _reset() -> void:
    state = _make_default_state()
