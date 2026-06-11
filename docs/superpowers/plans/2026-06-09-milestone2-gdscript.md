# Milestone 2: Building Blocks + Scoring Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add data-driven resource classes, a full trigger/scoring pipeline, a 4-gate system, multi-ball support, and fan prediction — delivering one complete scored launch cycle with triggers and gates.

**Architecture:** Three new directories (`data/`, `scoring/`, `run/`) sit beneath `sim/` and `view/`. `data/` defines Resource subclasses and a GameDB Autoload that registers hardcoded defaults. `scoring/` holds the three-tier settle pipeline. `run/` holds gate transforms. `view/board_view.gd` is rewritten to handle N active balls, feed events to trigger runtimes, and call `ScoringEngine.settle()` on drain.

**Tech Stack:** Godot 4 GDScript (no .NET), GUT headless tests (`godot --headless -s addons/gut/gut_cmdln.gd`), no new third-party dependencies.

---

## File Map

### New files
| File | Responsibility |
|---|---|
| `sim/deterministic_rng.gd` | Seeded xoroshiro RNG, `derive()` for sub-streams |
| `data/peg_type.gd` | `PegType extends Resource` — behavior enum + base_score |
| `data/trigger_def.gd` | `TriggerDef extends Resource` — listen_mask, effect, condition |
| `data/gate_def.gd` | `GateDef extends Resource` — kind enum, speed_mul, scatter params |
| `data/game_database.gd` | Autoload `GameDB` — registers hardcoded defaults for M2 |
| `scoring/score_context.gd` | Ledger: `add(kind, value, source)`, counters, `clear_for_launch()` |
| `scoring/trigger_runtime.gd` | `on_event(event, ctx)` — checks mask + condition, writes to ledger |
| `scoring/scoring_engine.gd` | `settle(ctx) -> [score, steps]` — +base → +mult → ×mult order |
| `run/gate_runtime.gd` | `apply(balls) -> Array` — NORMAL / ACCEL / SCATTER_ANGLE / SCATTER_SPLIT |
| `run/gate_chain.gd` | Chains ≥1 GateRuntime in sequence (MVP: length 1) |

### Modified files
| File | Change |
|---|---|
| `sim/trajectory_predictor.gd` | Add `predict_fan(sim, start, scatter_rad, samples, steps)` |
| `view/board_view.gd` | Multi-ball, gate chain on launch, new scoring pipeline wired |
| `view/input_controller.gd` | Keys 1–4 switch gate; fan prediction for scatter gates |
| `view/hud.gd` | Add `set_gate_label(name)` and show settle score breakdown |

### New test files
| File | Covers |
|---|---|
| `tests/test_deterministic_rng.gd` | RNG basics, determinism, `derive()` |
| `tests/test_game_database.gd` | GameDB defaults registered correctly |
| `tests/test_scoring_pipeline.gd` | ScoreContext, TriggerRuntime, ScoringEngine |
| `tests/test_gate_runtime.gd` | All 4 gate kinds + GateChain |
| `tests/test_trajectory_fan.gd` | `predict_fan` shape and correctness |

---

## Task 1: DeterministicRng

**Files:**
- Create: `sim/deterministic_rng.gd`
- Create: `tests/test_deterministic_rng.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_deterministic_rng.gd
extends GutTest

func test_next_float_in_range() -> void:
    var rng := DeterministicRng.new(1)
    for _i in 100:
        var f := rng.next_float()
        assert_true(f >= 0.0 and f < 1.0, "float in [0,1)")

func test_same_seed_same_sequence() -> void:
    var a := DeterministicRng.new(42)
    var b := DeterministicRng.new(42)
    for _i in 20:
        assert_eq(a.next_int(), b.next_int(), "same seed → same sequence")

func test_different_seeds_different_sequences() -> void:
    var a := DeterministicRng.new(1)
    var b := DeterministicRng.new(2)
    var same := true
    for _i in 10:
        if a.next_int() != b.next_int():
            same = false; break
    assert_false(same, "different seeds must diverge")

func test_range_int_bounds() -> void:
    var rng := DeterministicRng.new(7)
    for _i in 200:
        var v := rng.range_int(3, 8)
        assert_true(v >= 3 and v < 8, "range_int in [3,8)")

func test_range_float_bounds() -> void:
    var rng := DeterministicRng.new(13)
    for _i in 100:
        var v := rng.range_float(-1.0, 1.0)
        assert_true(v >= -1.0 and v < 1.0, "range_float in [-1,1)")

func test_derive_gives_independent_stream() -> void:
    var a := DeterministicRng.derive(100, 0)
    var b := DeterministicRng.derive(100, 1)
    var same := true
    for _i in 10:
        if a.next_int() != b.next_int():
            same = false; break
    assert_false(same, "different tags must diverge")
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: ERROR — `DeterministicRng` not found.

- [ ] **Step 3: Implement DeterministicRng**

```gdscript
# sim/deterministic_rng.gd
class_name DeterministicRng

var _s0: int
var _s1: int

func _init(seed_val: int) -> void:
    _s0 = _splitmix64(seed_val)
    _s1 = _splitmix64(_s0)

func next_int() -> int:
    var s0 := _s0; var s1 := _s1
    var result := (s0 + s1) & 0x7FFFFFFFFFFFFFFF
    s1 ^= s0
    _s0 = (_rotl(s0, 24) ^ s1 ^ (s1 << 16)) & 0x7FFFFFFFFFFFFFFF
    _s1 = _rotl(s1, 37) & 0x7FFFFFFFFFFFFFFF
    return result

func next_float() -> float:
    return float(next_int() & 0xFFFFFF) / float(0x1000000)

func range_float(lo: float, hi: float) -> float:
    return lo + next_float() * (hi - lo)

func range_int(lo: int, hi: int) -> int:
    return lo + (next_int() % (hi - lo))

static func derive(master: int, tag: int) -> DeterministicRng:
    return DeterministicRng.new(master ^ _splitmix64(tag))

static func _splitmix64(x: int) -> int:
    x = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & 0x7FFFFFFFFFFFFFFF
    x = ((x ^ (x >> 27)) * 0x94D049BB133111EB) & 0x7FFFFFFFFFFFFFFF
    return x ^ (x >> 31)

static func _rotl(x: int, k: int) -> int:
    return ((x << k) | (x >> (64 - k))) & 0x7FFFFFFFFFFFFFFF
```

- [ ] **Step 4: Run test to verify it passes**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all tests pass (existing 33 + 6 new = 39 total).

- [ ] **Step 5: Commit**

```bash
git -C D:/NeonPinball/game add sim/deterministic_rng.gd tests/test_deterministic_rng.gd
git -C D:/NeonPinball/game commit -m "feat: add DeterministicRng (xoroshiro-like, seeded, derive)"
```

---

## Task 2: Data Resource Classes

**Files:**
- Create: `data/peg_type.gd`
- Create: `data/trigger_def.gd`
- Create: `data/gate_def.gd`

No unit tests for pure data class definitions; validation is covered by Task 3 (GameDB test).

- [ ] **Step 1: Create `data/` directory and write PegType**

```gdscript
# data/peg_type.gd
class_name PegType extends Resource

enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB }

@export var id: StringName
@export var behavior: Behavior = Behavior.NORMAL
@export var base_score: float = 5.0
@export var mult_add: float = 0.0
@export var one_shot: bool = false
@export var glow: Color = Color(0.2, 0.9, 1.0, 1.0)
```

- [ ] **Step 2: Write TriggerDef**

```gdscript
# data/trigger_def.gd
class_name TriggerDef extends Resource

enum Effect { ADD_BASE, ADD_MULT, MUL_MULT }
enum Condition { NONE, BOUNCE_GTE, PEGS_HIT_GTE }

@export var id: StringName
@export_flags("PegHit:1", "Bounce:2", "Settled:4", "Launch:8") var listen_mask: int = 1
@export var effect: Effect = Effect.ADD_BASE
@export var value: float = 1.0
@export var condition: Condition = Condition.NONE
@export var condition_threshold: int = 0
@export var rarity: int = 1
```

- [ ] **Step 3: Write GateDef**

```gdscript
# data/gate_def.gd
class_name GateDef extends Resource

enum Kind { NORMAL, ACCEL, SCATTER_ANGLE, SCATTER_SPLIT }

@export var id: StringName
@export var kind: Kind = Kind.NORMAL
@export var speed_mul: float = 1.5
@export var scatter_angle: float = 0.3
@export var split_count: int = 3
```

- [ ] **Step 4: Re-import project so class_names are recognized**

```
godot --headless --path D:/NeonPinball/game --import
```

- [ ] **Step 5: Commit**

```bash
git -C D:/NeonPinball/game add data/peg_type.gd data/trigger_def.gd data/gate_def.gd
git -C D:/NeonPinball/game commit -m "feat: add PegType, TriggerDef, GateDef resource classes"
```

---

## Task 3: GameDB Autoload

**Files:**
- Create: `data/game_database.gd`
- Modify: `D:/NeonPinball/game/project.godot` (add Autoload entry)
- Create: `tests/test_game_database.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_game_database.gd
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
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: ERROR — `GameDB` not found (no Autoload yet).

- [ ] **Step 3: Write GameDB**

```gdscript
# data/game_database.gd
extends Node

var triggers: Dictionary = {}
var gate_defs: Dictionary = {}
var peg_types: Dictionary = {}

func _ready() -> void:
    _register_defaults()

func _register_defaults() -> void:
    # --- Peg types ---
    var pn := PegType.new()
    pn.id = &"normal"; pn.behavior = PegType.Behavior.NORMAL
    pn.base_score = 5.0; pn.glow = Color(0.2, 0.9, 1.0, 1.0)
    peg_types[pn.id] = pn

    var pm := PegType.new()
    pm.id = &"mult"; pm.behavior = PegType.Behavior.MULT
    pm.base_score = 8.0; pm.mult_add = 0.5; pm.glow = Color(1.0, 0.5, 0.1, 1.0)
    peg_types[pm.id] = pm

    # --- Triggers ---
    var peg_bonus := TriggerDef.new()
    peg_bonus.id = &"peg_bonus"
    peg_bonus.listen_mask = 1   # PEG_HIT
    peg_bonus.effect = TriggerDef.Effect.ADD_BASE
    peg_bonus.value = 3.0
    triggers[peg_bonus.id] = peg_bonus

    var bmult := TriggerDef.new()
    bmult.id = &"bounce_mult"
    bmult.listen_mask = 2       # BOUNCE
    bmult.effect = TriggerDef.Effect.ADD_MULT
    bmult.value = 0.2
    triggers[bmult.id] = bmult

    var big_hit := TriggerDef.new()
    big_hit.id = &"big_hit"
    big_hit.listen_mask = 4     # SETTLED
    big_hit.effect = TriggerDef.Effect.MUL_MULT
    big_hit.value = 1.5
    big_hit.condition = TriggerDef.Condition.PEGS_HIT_GTE
    big_hit.condition_threshold = 5
    triggers[big_hit.id] = big_hit

    # --- Gates ---
    var gn := GateDef.new()
    gn.id = &"normal"; gn.kind = GateDef.Kind.NORMAL
    gate_defs[gn.id] = gn

    var ga := GateDef.new()
    ga.id = &"accel"; ga.kind = GateDef.Kind.ACCEL; ga.speed_mul = 1.5
    gate_defs[ga.id] = ga

    var gsa := GateDef.new()
    gsa.id = &"scatter_angle"; gsa.kind = GateDef.Kind.SCATTER_ANGLE; gsa.scatter_angle = 0.3
    gate_defs[gsa.id] = gsa

    var gss := GateDef.new()
    gss.id = &"scatter_split"; gss.kind = GateDef.Kind.SCATTER_SPLIT
    gss.split_count = 3; gss.scatter_angle = 0.4
    gate_defs[gss.id] = gss
```

- [ ] **Step 4: Register GameDB as Autoload in project.godot**

Read `D:/NeonPinball/game/project.godot`. Find the `[autoload]` section (add it if absent) and insert:

```ini
[autoload]

GameDB="*res://data/game_database.gd"
```

The `*` prefix means Godot auto-instantiates it as a Node. If other autoloads already exist, append to the section.

- [ ] **Step 5: Re-import so Autoload is recognized**

```
godot --headless --path D:/NeonPinball/game --import
```

- [ ] **Step 6: Run tests to verify they pass**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all tests pass (39 + 6 = 45 total).

- [ ] **Step 7: Commit**

```bash
git -C D:/NeonPinball/game add data/game_database.gd tests/test_game_database.gd project.godot
git -C D:/NeonPinball/game commit -m "feat: add GameDB autoload with hardcoded M2 triggers and gates"
```

---

## Task 4: Scoring Pipeline

**Files:**
- Create: `scoring/score_context.gd`
- Create: `scoring/trigger_runtime.gd`
- Create: `scoring/scoring_engine.gd`
- Create: `tests/test_scoring_pipeline.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_scoring_pipeline.gd
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
    var rt := _make_rt(1, TriggerDef.Effect.ADD_BASE, 3.0)  # only PEG_HIT
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
    assert_eq(ctx.ledger.size(), 0, "condition not met → no fire")

func test_tr_condition_pegs_hit_gte_met() -> void:
    var rt := _make_rt(4, TriggerDef.Effect.MUL_MULT, 1.5,
                       TriggerDef.Condition.PEGS_HIT_GTE, 5)
    var ctx := ScoreContext.new(); ctx.pegs_hit = 5
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 1, "condition met → fire")

func test_tr_condition_bounce_gte() -> void:
    var rt := _make_rt(4, TriggerDef.Effect.ADD_MULT, 1.0,
                       TriggerDef.Condition.BOUNCE_GTE, 3)
    var ctx := ScoreContext.new(); ctx.bounce_count = 2
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 0, "2 < 3 → no fire")
    ctx.bounce_count = 3
    rt.on_event(_settled_event(), ctx)
    assert_eq(ctx.ledger.size(), 1, "3 >= 3 → fire")

# ---- ScoringEngine ----

func test_se_base_only() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_BASE, 5.0,  &"peg")
    var result := eng.settle(ctx)
    # base=15, mult=1.0 → score=15
    assert_almost_eq(float(result[0]), 15.0, 1e-4, "score=15")

func test_se_add_mult() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_MULT, 0.5,  &"bounce")
    # base=10, mult=1+0.5=1.5 → score=15
    var result := eng.settle(ctx)
    assert_almost_eq(float(result[0]), 15.0, 1e-4, "score=15")

func test_se_mul_mult() -> void:
    var eng := ScoringEngine.new()
    var ctx := ScoreContext.new()
    ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
    ctx.add(ScoreContext.KIND_ADD_MULT, 1.0,  &"bonus")  # mult = 1+1 = 2
    ctx.add(ScoreContext.KIND_MUL_MULT, 2.0,  &"big")    # mult = 2*2 = 4
    # score = 10 * 4 = 40
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
    assert_almost_eq(float(result[0]), 0.0, 1e-4, "empty → score=0")
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: ERROR — `ScoreContext` / `TriggerRuntime` / `ScoringEngine` not found.

- [ ] **Step 3: Implement ScoreContext**

```gdscript
# scoring/score_context.gd
class_name ScoreContext

const KIND_ADD_BASE := 0
const KIND_ADD_MULT := 1
const KIND_MUL_MULT := 2

var ledger: Array = []
var bounce_count: int = 0
var pegs_hit: int = 0
var gate_used_accel: bool = false
var gate_used_scatter: bool = false
var launch_index: int = 0

func add(kind: int, value: float, source: StringName) -> void:
    ledger.append({&"kind": kind, &"value": value, &"source": source})

func clear_for_launch() -> void:
    ledger.clear()
    bounce_count = 0; pegs_hit = 0
    gate_used_accel = false; gate_used_scatter = false
```

- [ ] **Step 4: Implement TriggerRuntime**

```gdscript
# scoring/trigger_runtime.gd
class_name TriggerRuntime

var _def: TriggerDef

func _init(def: TriggerDef) -> void:
    _def = def

func on_event(event: Dictionary, ctx: ScoreContext) -> void:
    if not _listens_to(event[&"type"]):
        return
    if not _condition_met(ctx):
        return
    match _def.effect:
        TriggerDef.Effect.ADD_BASE:
            ctx.add(ScoreContext.KIND_ADD_BASE, _def.value, _def.id)
        TriggerDef.Effect.ADD_MULT:
            ctx.add(ScoreContext.KIND_ADD_MULT, _def.value, _def.id)
        TriggerDef.Effect.MUL_MULT:
            ctx.add(ScoreContext.KIND_MUL_MULT, _def.value, _def.id)

func _listens_to(event_type: StringName) -> bool:
    var flag := {SimEvent.PEG_HIT: 1, SimEvent.BOUNCE: 2,
                 SimEvent.SETTLED: 4, SimEvent.LAUNCH: 8}.get(event_type, 0)
    return (_def.listen_mask & flag) != 0

func _condition_met(ctx: ScoreContext) -> bool:
    match _def.condition:
        TriggerDef.Condition.NONE:         return true
        TriggerDef.Condition.BOUNCE_GTE:   return ctx.bounce_count >= _def.condition_threshold
        TriggerDef.Condition.PEGS_HIT_GTE: return ctx.pegs_hit >= _def.condition_threshold
    return true
```

- [ ] **Step 5: Implement ScoringEngine**

```gdscript
# scoring/scoring_engine.gd
class_name ScoringEngine

# Returns [score: float, settle_steps: Array]
# Three-tier order: +base → +mult → ×mult
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
```

- [ ] **Step 6: Re-import and run tests**

```
godot --headless --path D:/NeonPinball/game --import
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass (45 + 13 = 58 total).

- [ ] **Step 7: Commit**

```bash
git -C D:/NeonPinball/game add scoring/score_context.gd scoring/trigger_runtime.gd scoring/scoring_engine.gd tests/test_scoring_pipeline.gd
git -C D:/NeonPinball/game commit -m "feat: add ScoreContext, TriggerRuntime, ScoringEngine (three-tier settle)"
```

---

## Task 5: Gate System

**Files:**
- Create: `run/gate_runtime.gd`
- Create: `run/gate_chain.gd`
- Create: `tests/test_gate_runtime.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_gate_runtime.gd
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
    assert_almost_eq(result[0].vel.length(), 750.0, 1e-3, "speed × 1.5")

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
    assert_almost_eq(result[0].vel.length(), 1000.0, 1e-3, "500 × 2 = 1000")
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: ERROR — `GateRuntime` / `GateChain` not found.

- [ ] **Step 3: Implement GateRuntime**

```gdscript
# run/gate_runtime.gd
class_name GateRuntime

var _def: GateDef
var _rng: DeterministicRng

func _init(def: GateDef, rng: DeterministicRng) -> void:
    _def = def; _rng = rng

func apply(balls: Array) -> Array:
    var result := []
    for ball in balls:
        match _def.kind:
            GateDef.Kind.NORMAL:
                result.append(ball)
            GateDef.Kind.ACCEL:
                var speed := ball.vel.length()
                if speed > 1e-6:
                    ball.vel = ball.vel * (_def.speed_mul * speed / speed)
                result.append(ball)
            GateDef.Kind.SCATTER_ANGLE:
                var angle := _rng.range_float(-_def.scatter_angle, _def.scatter_angle)
                ball.vel = ball.vel.rotated(angle)
                result.append(ball)
            GateDef.Kind.SCATTER_SPLIT:
                for k in _def.split_count:
                    var frac := float(k) / maxf(_def.split_count - 1, 1) - 0.5
                    var nb := ball.clone()
                    nb.vel = ball.vel.rotated(frac * _def.scatter_angle)
                    result.append(nb)
    return result
```

Note: ACCEL simplification — `(speed_mul * speed / speed) = speed_mul`, so effectively `ball.vel *= speed_mul`. Written verbosely to match spec.

- [ ] **Step 4: Implement GateChain**

```gdscript
# run/gate_chain.gd
class_name GateChain

var _gates: Array[GateRuntime] = []

func _init(gates: Array = []) -> void:
    for g in gates:
        _gates.append(g as GateRuntime)

func process(entry_ball: BallState) -> Array:
    var balls: Array = [entry_ball]
    for gate in _gates:
        balls = gate.apply(balls)
    return balls
```

- [ ] **Step 5: Re-import and run tests**

```
godot --headless --path D:/NeonPinball/game --import
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass (58 + 12 = 70 total).

- [ ] **Step 6: Commit**

```bash
git -C D:/NeonPinball/game add run/gate_runtime.gd run/gate_chain.gd tests/test_gate_runtime.gd
git -C D:/NeonPinball/game commit -m "feat: add GateRuntime (4 kinds) and GateChain"
```

---

## Task 6: predict_fan()

**Files:**
- Modify: `sim/trajectory_predictor.gd`
- Create: `tests/test_trajectory_fan.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_trajectory_fan.gd
extends GutTest

func _sim() -> BallSimulation:
    var rect := Rect2(0, 0, 540, 900)
    var cfg := {&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
                &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": 1.0 / 120.0}
    return BallSimulation.new(rect, [], cfg)

func _start() -> BallState:
    return BallState.new(Vector2(270, 0), Vector2(0, 1) * 1000.0, 8.0)

func test_fan_count_matches_samples() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 30)
    assert_eq(fans.size(), 5, "5 samples → 5 fans")

func test_fan_each_has_points() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 30)
    for fan in fans:
        assert_true(fan.size() > 0, "each fan non-empty")

func test_fan_each_bounded_by_steps() -> void:
    var fans := TrajectoryPredictor.predict_fan(_sim(), _start(), 0.3, 5, 20)
    for fan in fans:
        assert_true(fan.size() <= 20, "at most 20 pts per fan")

func test_fan_zero_scatter_matches_predict() -> void:
    var sim := _sim(); var start := _start()
    var fans := TrajectoryPredictor.predict_fan(sim, start, 0.0, 1, 15)
    var direct := TrajectoryPredictor.predict(sim, start.clone(), 15)
    assert_eq(fans.size(), 1)
    assert_eq(fans[0].size(), direct.size(), "zero-scatter fan = direct predict")
    for i in fans[0].size():
        assert_almost_eq(fans[0][i].x, direct[i].x, 1e-3)
        assert_almost_eq(fans[0][i].y, direct[i].y, 1e-3)

func test_fan_single_sample_uses_leftmost_angle() -> void:
    # samples=1 → i=0 → lerpf(-r, r, 0/max(0,1)) = lerpf(-r,r,0) = -r
    var sim := _sim()
    var start := _start()
    var fans := TrajectoryPredictor.predict_fan(sim, start, 0.5, 1, 10)
    var rotated := BallState.new(start.pos, start.vel.rotated(-0.5), start.radius)
    var direct := TrajectoryPredictor.predict(sim, rotated, 10)
    assert_eq(fans[0].size(), direct.size())
    if fans[0].size() > 0:
        assert_almost_eq(fans[0][0].x, direct[0].x, 1e-3)
```

- [ ] **Step 2: Run test to verify it fails**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: ERROR — `predict_fan` not found.

- [ ] **Step 3: Add predict_fan to trajectory_predictor.gd**

Replace the full file content:

```gdscript
# sim/trajectory_predictor.gd
class_name TrajectoryPredictor

static func predict(sim: BallSimulation, start: BallState, steps: int) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var ball := start.clone()
    var scratch := []
    for _i in steps:
        if not ball.alive:
            break
        scratch.clear()
        sim.step(ball, scratch)
        pts.append(ball.pos)
    return pts

# Returns Array of Array[Vector2], one per angular sample.
# Samples span [-scatter_rad, +scatter_rad] left-to-right.
static func predict_fan(sim: BallSimulation, start: BallState,
                        scatter_rad: float, samples: int,
                        steps: int) -> Array:
    var fans := []
    for i in samples:
        var a := lerpf(-scatter_rad, scatter_rad,
                       float(i) / maxf(samples - 1, 1))
        var b := BallState.new(start.pos, start.vel.rotated(a), start.radius)
        fans.append(predict(sim, b, steps))
    return fans
```

- [ ] **Step 4: Run tests to verify they pass**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass (70 + 5 = 75 total).

- [ ] **Step 5: Commit**

```bash
git -C D:/NeonPinball/game add sim/trajectory_predictor.gd tests/test_trajectory_fan.gd
git -C D:/NeonPinball/game commit -m "feat: add TrajectoryPredictor.predict_fan for scatter gate preview"
```

---

## Task 7: Wire Multi-ball, Gates, and Scoring into BoardView

**Files:**
- Rewrite: `view/board_view.gd`
- Modify: `view/input_controller.gd`
- Modify: `view/hud.gd`

No automated tests for view wiring; verify manually with smoke test at end.

### BoardView rewrite

- [ ] **Step 1: Write new board_view.gd**

```gdscript
# view/board_view.gd
extends Node2D

const DT := 1.0 / 120.0

var _rect: Rect2
var _pegs: Array = []
var _sim: BallSimulation
var _engine: ScoringEngine
var _score_ctx: ScoreContext
var _trigger_runtimes: Array = []
var _gate_chain: GateChain
var _active_gate_def: GateDef

var _active_balls: Array = []
var _prev_positions: Array = []
var _curr_positions: Array = []
var _has_ball := false
var _acc := 0.0

var _events: Array = []
var _event_cursor := 0
var _flashes: Array = []

var _launch_count := 0

var prediction_pts: Array[Vector2] = []
var prediction_fans: Array = []

var rect: Rect2:
    get: return _rect
var sim: BallSimulation:
    get: return _sim
var active_gate_def: GateDef:
    get: return _active_gate_def

func _ready() -> void:
    _rect = Rect2(0, 0, 540, 900)
    _pegs = _build_honeycomb()
    var cfg := {
        &"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
        &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
    }
    _sim = BallSimulation.new(_rect, _pegs, cfg)
    _engine = ScoringEngine.new()
    _score_ctx = ScoreContext.new()

    for tid in [&"peg_bonus", &"bounce_mult", &"big_hit"]:
        _trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))

    set_active_gate(&"normal")

func _build_honeycomb() -> Array:
    var list := []
    var id := 0
    var rows := 8; var cols := 7
    var spacing := 64.0; var margin := 60.0
    var sizes := [7.0, 10.0, 13.0]
    var scores := [3.0, 5.0, 8.0]
    for r in rows:
        var y := margin + 140.0 + r * spacing
        var x_off := (r % 2) * spacing * 0.5
        for c in cols:
            var x := margin + x_off + c * spacing
            if x < _rect.end.x - margin:
                var tier := (r + c * 2) % 3
                list.append({&"id": id, &"pos": Vector2(x, y),
                            &"radius": sizes[tier], &"base_score": scores[tier]})
                id += 1
    return list

func set_active_gate(gate_id: StringName) -> void:
    _active_gate_def = GameDB.gate_defs[gate_id]
    var rng := DeterministicRng.new(_launch_count * 1000 + gate_id.hash())
    var gate_rt := GateRuntime.new(_active_gate_def, rng)
    _gate_chain = GateChain.new([gate_rt])
    $Hud.set_gate_label(String(gate_id))

func launch(ball: BallState) -> void:
    if _has_ball:
        return
    _score_ctx.clear_for_launch()
    _active_balls = _gate_chain.process(ball)
    _has_ball = _active_balls.size() > 0
    _prev_positions.resize(_active_balls.size())
    _curr_positions.resize(_active_balls.size())
    for i in _active_balls.size():
        _prev_positions[i] = _active_balls[i].pos
        _curr_positions[i] = _active_balls[i].pos
    _events.clear(); _event_cursor = 0; _flashes.clear()
    _launch_count += 1
    # Refresh gate RNG for next launch
    set_active_gate(_active_gate_def.id)

func _process(delta: float) -> void:
    if _has_ball:
        _acc += delta
        while _acc >= DT:
            for i in _active_balls.size():
                if _active_balls[i].alive:
                    _prev_positions[i] = _active_balls[i].pos
                    _sim.step(_active_balls[i], _events)
                    _curr_positions[i] = _active_balls[i].pos

            while _event_cursor < _events.size():
                var e: Dictionary = _events[_event_cursor]
                if e[&"type"] == SimEvent.PEG_HIT:
                    _score_ctx.pegs_hit += 1
                    _flashes.append({&"pos": e[&"pos"], &"ttl": 0.15})
                elif e[&"type"] == SimEvent.BOUNCE:
                    _score_ctx.bounce_count += 1
                for rt in _trigger_runtimes:
                    rt.on_event(e, _score_ctx)
                _event_cursor += 1

            _acc -= DT

            var all_dead := true
            for b in _active_balls:
                if b.alive:
                    all_dead = false; break
            if all_dead:
                _on_all_settled()
                break

        for i in range(_flashes.size() - 1, -1, -1):
            _flashes[i][&"ttl"] -= delta
            if _flashes[i][&"ttl"] <= 0.0:
                _flashes.remove_at(i)
    queue_redraw()

func _on_all_settled() -> void:
    var result := _engine.settle(_score_ctx)
    var score: float = result[0]
    $Hud.add_score(score)
    _has_ball = false; _acc = 0.0
    _active_balls.clear()
    _prev_positions.clear(); _curr_positions.clear()

func _draw() -> void:
    for peg in _pegs:
        draw_circle(peg[&"pos"], peg[&"radius"], Color(0.2, 0.9, 1.0))
    for i in range(1, prediction_pts.size()):
        draw_line(prediction_pts[i - 1], prediction_pts[i], Color(1, 1, 1, 0.4), 2.0)
    for fan in prediction_fans:
        for i in range(1, fan.size()):
            draw_line(fan[i - 1], fan[i], Color(1.0, 1.0, 0.4, 0.25), 1.5)
    if _has_ball:
        var alpha := _acc / DT
        for i in _active_balls.size():
            if _active_balls[i].alive:
                var dp := (_prev_positions[i] as Vector2).lerp(_curr_positions[i], alpha)
                draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))
    for f in _flashes:
        var a: float = f[&"ttl"] / 0.15
        draw_circle(f[&"pos"], 16.0, Color(1.0, 1.0, 0.6, a * 0.8))
```

### HUD update

- [ ] **Step 2: Update hud.gd**

```gdscript
# view/hud.gd
extends CanvasLayer

var _total := 0.0

func _ready() -> void:
    $TotalLabel.text = "Score: 0"
    $LastLabel.text = ""
    $GateLabel.text = "Gate: normal"

func add_score(s: float) -> void:
    _total += s
    $TotalLabel.text = "Score: %d" % int(_total)
    $LastLabel.text = "+%d" % int(s)

func set_gate_label(gate_name: String) -> void:
    $GateLabel.text = "Gate: " + gate_name
```

Add a third Label node called `GateLabel` to the HUD scene in the Godot editor:
- Open `scenes/hud.tscn` (or the scene that contains the Hud CanvasLayer)
- Add a `Label` node named `GateLabel`
- Position it below the existing labels (e.g., position `(10, 60)`, font size 16)

### InputController update

- [ ] **Step 3: Update input_controller.gd**

```gdscript
# view/input_controller.gd
extends Node

@export var board_path: NodePath

var _board: Node2D
var _edge: int = EntryResolver.BoardEdge.TOP
var _t := 0.5
var _aim := 0.0
const SPEED := 1500.0
const BALL_RADIUS := 8.0

func _ready() -> void:
    _board = get_node(board_path)

func _process(_delta: float) -> void:
    var m := _board.get_local_mouse_position()
    var r: Rect2 = _board.rect
    match _edge:
        EntryResolver.BoardEdge.TOP:
            _t = clampf((m.x - r.position.x) / r.size.x, 0.0, 1.0)
            _aim = clampf((m.x - r.get_center().x) / (r.size.x * 0.5), -1.0, 1.0) * 0.9
        _:  # LEFT / RIGHT: use mouse Y, range [0.15, 0.85]
            _t = clampf((m.y - r.position.y) / r.size.y, 0.15, 0.85)
            _aim = clampf((m.y - r.get_center().y) / (r.size.y * 0.5), -1.0, 1.0) * 0.9

    var gate_def: GateDef = _board.active_gate_def
    var start := EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r)

    match gate_def.kind:
        GateDef.Kind.ACCEL:
            _board.prediction_fans.clear()
            var fast := BallState.new(start.pos, start.vel * gate_def.speed_mul, start.radius)
            _board.prediction_pts = TrajectoryPredictor.predict(_board.sim, fast, 60)
        GateDef.Kind.SCATTER_ANGLE, GateDef.Kind.SCATTER_SPLIT:
            _board.prediction_pts.clear()
            _board.prediction_fans = TrajectoryPredictor.predict_fan(
                _board.sim, start, gate_def.scatter_angle, 5, 60)
        _:  # NORMAL
            _board.prediction_fans.clear()
            _board.prediction_pts = TrajectoryPredictor.predict(_board.sim, start, 60)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_TAB:
                _edge = (_edge + 1) % 3
            KEY_1: _board.set_active_gate(&"normal")
            KEY_2: _board.set_active_gate(&"accel")
            KEY_3: _board.set_active_gate(&"scatter_angle")
            KEY_4: _board.set_active_gate(&"scatter_split")
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            var r: Rect2 = _board.rect
            _board.launch(EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r))
```

### Smoke test

- [ ] **Step 4: Run all headless tests to confirm no regressions**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: 75 tests pass.

- [ ] **Step 5: Manual smoke test**

Open the game in Godot editor and run the main scene. Verify:
1. Game opens, pegs visible, prediction line shows
2. Press **Tab** — entry edge cycles TOP → LEFT → RIGHT → TOP
3. Press **2** — gate switches to "accel", HUD shows "Gate: accel", prediction line moves faster
4. Press **3** — gate switches to "scatter_angle", fan preview appears (5 faint yellow lines)
5. Press **4** — gate switches to "scatter_split", fan preview appears for 3 balls
6. Press **1** — back to normal
7. Left-click to launch — ball spawns, bounces off pegs, drains
8. HUD shows "+N" score. With 5+ pegs hit, `big_hit` trigger fires (×1.5 mult)
9. Press **4**, launch — 3 balls spawn simultaneously, all drain, combined score shown

- [ ] **Step 6: Commit**

```bash
git -C D:/NeonPinball/game add view/board_view.gd view/input_controller.gd view/hud.gd
git -C D:/NeonPinball/game commit -m "feat: multi-ball BoardView with gate chain and full scoring pipeline"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] DeterministicRng — seeded, `derive()` for sub-streams ✓ (Task 1)
- [x] PegType / TriggerDef / GateDef resource classes ✓ (Task 2)
- [x] GameDB Autoload with M2 hardcoded defaults ✓ (Task 3)
- [x] ScoreContext ledger + counters ✓ (Task 4)
- [x] TriggerRuntime — listen_mask, effect, condition ✓ (Task 4)
- [x] ScoringEngine — +base → +mult → ×mult order ✓ (Task 4)
- [x] GateRuntime — NORMAL / ACCEL / SCATTER_ANGLE / SCATTER_SPLIT ✓ (Task 5)
- [x] GateChain — sequential gate application ✓ (Task 5)
- [x] `predict_fan()` for scatter gate preview ✓ (Task 6)
- [x] Multi-ball BoardView — N balls, per-ball step, unified settle ✓ (Task 7)
- [x] Fan prediction in InputController for scatter gates ✓ (Task 7)
- [x] Gate switching via keys 1–4 ✓ (Task 7)

**Deferred to Milestone 3:**
- RunManager state machine (Phase enum, ante/round loop, quota)
- Shop / economy / money system
- Boss round modifiers
- `.tres` resource files (currently hardcoded in GameDB)
- PegType.behavior exhausted/one_shot mechanics
- JuiceController (camera shake, slow-mo, particles)
- SaveSystem

**Type consistency:**
- `ScoreContext.KIND_*` constants used consistently in TriggerRuntime and ScoringEngine ✓
- `GateDef.Kind` enum used in GateRuntime `match` ✓
- `BallState.clone()` used in GateRuntime SCATTER_SPLIT and predict_fan ✓
- `DeterministicRng` constructed consistently with `new(seed)` and `derive(master, tag)` ✓
- `GameDB.triggers` and `GameDB.gate_defs` keyed by `StringName` ✓
