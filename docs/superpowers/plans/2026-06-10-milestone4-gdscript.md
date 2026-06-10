# Milestone 4 — MULT Pegs + Full Run + Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 MULT 钉、8 区完整跑局、本地存档（最高分 + 每日种子完成记录）。

**Architecture:** MULT 钉在 _build_honeycomb() 按固定模式分布，命中时向 ScoreContext.ledger 写入 ADD_MULT 条目；RunManager 新增 max_areas 变量使 8 区通关可配置（测试可覆盖为 3）；SaveSystem 用 Godot ConfigFile 持久化到 user://；DailySeed 从系统日期派生 master_seed，每天只能完成一次。

**Tech Stack:** Godot 4.6.3 GDScript, GUT, Godot ConfigFile, Time.get_date_dict_from_system()

---

## 文件结构

**新建：**
- `run/save_system.gd` — SaveSystem：ConfigFile 持久化 best_score / runs_completed / last_date / daily_completed + daily_seed() 静态方法

**修改：**
- `view/board_view.gd` — _build_honeycomb() 插入 MULT 钉逻辑；_process() PEG_HIT 块写入 ADD_MULT；_draw() MULT 钉橙色；_ready() 设置 daily seed；_handle_phase_transition() 自动存档
- `run/run_manager.gd` — 新增 max_areas 变量；ANTE_CLEAR 胜利条件改为 max_areas
- `view/hud.gd` — _ready 后显示 Daily 状态

**新建测试：**
- `tests/test_mult_peg.gd`
- `tests/test_save_system.gd`

**修改测试：**
- `tests/test_run_loop.gd` — 现有测试加 `mgr.max_areas = 3`；新增 8 区测试
- `tests/test_run_manager.gd` — 如有测试驱动至 WIN 则加 `mgr.max_areas = 3`

---

## Task 1: MULT Pegs

**Files:**
- Modify: `view/board_view.gd` (_build_honeycomb, _process PEG_HIT block, _draw)
- Test: `tests/test_mult_peg.gd`

### Step 1.1 — 写失败测试

- [ ] 创建 `tests/test_mult_peg.gd`，运行测试，确认红色失败

```gdscript
# tests/test_mult_peg.gd
extends GutTest

const ScoreContextScript := preload("res://scoring/score_context.gd")
const ScoringEngineScript := preload("res://scoring/scoring_engine.gd")

func test_gamedb_has_mult_peg_type() -> void:
    assert_true(GameDB.peg_types.has(&"mult"), "GameDB must have mult peg type")

func test_mult_peg_behavior_is_mult() -> void:
    var pm: PegType = GameDB.peg_types[&"mult"]
    assert_eq(pm.behavior, PegType.Behavior.MULT)

func test_mult_peg_mult_add_is_positive() -> void:
    var pm: PegType = GameDB.peg_types[&"mult"]
    assert_true(pm.mult_add > 0.0, "mult_add must be positive")

func test_mult_peg_adds_to_ledger() -> void:
    var ctx := ScoreContextScript.new()
    var peg_type: PegType = GameDB.peg_types[&"mult"]
    # Simulate what _process does when hitting a MULT peg
    ctx.pegs_hit += 1
    ctx.add(ScoreContextScript.KIND_ADD_MULT, peg_type.mult_add, &"mult_peg")
    # Verify the ledger entry
    assert_eq(ctx.ledger.size(), 1)
    assert_eq(ctx.ledger[0][&"kind"], ScoreContextScript.KIND_ADD_MULT)
    assert_almost_eq(ctx.ledger[0][&"value"], peg_type.mult_add, 0.001)

func test_mult_peg_increases_final_score() -> void:
    var ctx := ScoreContextScript.new()
    ctx.add(ScoreContextScript.KIND_ADD_BASE, 10.0, &"base")
    ctx.add(ScoreContextScript.KIND_ADD_MULT, 0.5, &"mult_peg")  # +0.5 multiplier
    var engine := ScoringEngineScript.new()
    var result := engine.settle(ctx)
    var score: float = result[0]
    # score = 10.0 * (1.0 + 0.5) = 15.0
    assert_almost_eq(score, 15.0, 0.01)
```

Run tests (expect failures on mult-peg placement which can't be headlessly tested yet — these data/logic tests should all pass if GameDB already has mult type):

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: some tests PASS (GameDB checks), no crashes. Note any failures.

### Step 1.2 — 实现 MULT 钉布局（_build_honeycomb）

- [ ] 打开 `view/board_view.gd`，找到 `_build_honeycomb()` 中 `list.append(...)` 的那行，将整个 append 替换为：

```gdscript
var peg_type: PegType = GameDB.peg_types[&"mult"] if (r * 7 + c) % 7 == 3 else GameDB.peg_types[&"normal"]
list.append({&"id": id, &"pos": Vector2(x, y),
             &"radius": sizes[tier], &"base_score": scores[tier],
             &"type": peg_type})
```

条件 `(r * 7 + c) % 7 == 3` 对 8×7=56 个钉中约 14% 生成 MULT 钉，分布在所有行。

### Step 1.3 — 实现 MULT 钉计分（_process PEG_HIT）

- [ ] 在 `_process()` 中，找到：

```gdscript
if e[&"type"] == SimEvent.PEG_HIT:
    _score_ctx.pegs_hit += 1
```

在 `_score_ctx.pegs_hit += 1` 之后，紧接着加入：

```gdscript
            var hit_peg_id: int = e[&"peg_id"]
            if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
                var hit_type: PegType = _pegs[hit_peg_id].get(&"type")
                if hit_type != null and hit_type.behavior == PegType.Behavior.MULT:
                    _score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
```

### Step 1.4 — 实现 MULT 钉橙色视觉（_draw）

- [ ] 在 `_draw()` 中，找到钉子绘制循环。将原来的单色 `draw_circle` 替换为：

```gdscript
for peg in _pegs:
    var pt: PegType = peg.get(&"type")
    var col := Color(0.2, 0.9, 1.0)
    if pt != null and pt.behavior == PegType.Behavior.MULT:
        col = Color(1.0, 0.55, 0.0)
    draw_circle(peg[&"pos"], peg[&"radius"], col)
```

普通钉保持青色 `(0.2, 0.9, 1.0)`，MULT 钉显示橙色 `(1.0, 0.55, 0.0)`。

### Step 1.5 — 运行测试确认绿色

- [ ] 运行：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: PASS — 106 tests（102 原有 + 4 新增 MULT 钉测试）

### Step 1.6 — 提交

- [ ] 提交：

```
git -C D:/NeonPinball/game add view/board_view.gd tests/test_mult_peg.gd
git -C D:/NeonPinball/game commit -m "feat: MULT pegs in honeycomb with orange visual and ADD_MULT scoring"
```

---

## Task 2: 8-Area Full Run

**Files:**
- Modify: `run/run_manager.gd` (add max_areas var, change win condition)
- Modify: `tests/test_run_loop.gd` (set mgr.max_areas = 3 for existing fast tests; add 8-area test)
- Modify: `tests/test_run_manager.gd` (set mgr.max_areas = 3 if any test drives to WIN)

### Step 2.1 — 写失败测试

- [ ] 在 `tests/test_run_loop.gd` 末尾添加以下新测试函数：

```gdscript
func test_8_area_run_win_requires_24_rounds() -> void:
    var mgr := RunManagerScript.new()
    # max_areas stays 8 (default) — do NOT set mgr.max_areas = 3 here
    mgr.advance()   # BOOT → RUN_START
    mgr.advance()   # RUN_START → ROUND
    var rounds := 0
    for _i in 150:  # upper bound: 8 areas * 3 rounds * ~2 steps each = ~48 iters needed
        match mgr.state[&"phase"]:
            RunManagerScript.Phase.ROUND, RunManagerScript.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance()
                rounds += 1
            RunManagerScript.Phase.ANTE_CLEAR:
                mgr.advance()
            RunManagerScript.Phase.SHOP:
                mgr.advance()
            RunManagerScript.Phase.RUN_WIN:
                break
            _:
                break
    assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_WIN)
    assert_eq(rounds, 24, "8 areas x 3 rounds = 24 rounds")
    mgr.free()
```

- [ ] 运行测试，确认新测试以当前 3-area 硬编码逻辑失败（rounds 将为 9，不等于 24）：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: 1 新测试 FAIL（test_8_area_run_win_requires_24_rounds），其余原有测试全部通过。

### Step 2.2 — 修改 run_manager.gd：新增 max_areas

- [ ] 打开 `run/run_manager.gd`，在 `const LAUNCHES_PER_ROUND := 5` 之后添加：

```gdscript
var max_areas := 8
```

### Step 2.3 — 修改 run_manager.gd：胜利条件

- [ ] 在 `advance()` 的 `ANTE_CLEAR` 分支中，将硬编码的胜利判断：

```gdscript
if state[&"ante"] > 3:   # MVP: 3 areas win
    state[&"phase"] = Phase.RUN_WIN
    return
```

替换为：

```gdscript
if state[&"ante"] > max_areas:
    state[&"phase"] = Phase.RUN_WIN
    return
```

### Step 2.4 — 修复现有测试：为快速测试设置 max_areas = 3

- [ ] 打开 `tests/test_run_loop.gd`，找到所有创建 `RunManagerScript.new()` 并驱动跑局至 WIN 状态的测试函数（例如 `test_full_3_area_run_win()`），在 `var mgr := RunManagerScript.new()` 之后立即添加：

```gdscript
mgr.max_areas = 3   # keep test fast; actual game uses 8
```

逐一检查 test_run_loop.gd 中的每个测试，凡是推进状态机超过 3 区的都要加这一行。

- [ ] 打开 `tests/test_run_manager.gd`，检查其中是否有测试驱动到 RUN_WIN。如果有，同样在创建 mgr 后加 `mgr.max_areas = 3`。

### Step 2.5 — 运行测试确认全绿

- [ ] 运行：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: PASS — 107 tests（106 + 1 新增 8 区测试）

### Step 2.6 — 提交

- [ ] 提交：

```
git -C D:/NeonPinball/game add run/run_manager.gd tests/test_run_loop.gd tests/test_run_manager.gd
git -C D:/NeonPinball/game commit -m "feat: extend run to 8 areas; max_areas var for test overrides"
```

---

## Task 3: SaveSystem

**Files:**
- Create: `run/save_system.gd`
- Modify: `view/board_view.gd` (_handle_phase_transition — RUN_WIN 和 RUN_LOSE 分支自动存档)
- Test: `tests/test_save_system.gd`

### Step 3.1 — 写失败测试

- [ ] 创建 `tests/test_save_system.gd`：

```gdscript
# tests/test_save_system.gd
extends GutTest

const SaveSystemScript := preload("res://run/save_system.gd")

func test_load_returns_defaults_when_no_file() -> void:
    # Use a temp path override by testing the logic directly.
    # Either has a file already or returns defaults — both are valid dicts.
    var d := SaveSystemScript.load_data()
    assert_true(d.has(&"best_score"),      "must have best_score key")
    assert_true(d.has(&"runs_completed"),  "must have runs_completed key")
    assert_true(d.has(&"last_date"),       "must have last_date key")
    assert_true(d.has(&"daily_completed"), "must have daily_completed key")

func test_save_and_load_roundtrip() -> void:
    var data := {
        &"best_score":      1234,
        &"runs_completed":  5,
        &"last_date":       "2026-06-10",
        &"daily_completed": true,
    }
    SaveSystemScript.save(data)
    var loaded := SaveSystemScript.load_data()
    assert_eq(loaded[&"best_score"],      1234)
    assert_eq(loaded[&"runs_completed"],  5)
    assert_eq(loaded[&"last_date"],       "2026-06-10")
    assert_eq(loaded[&"daily_completed"], true)

func test_today_string_format() -> void:
    var s: String = SaveSystemScript.today_string()
    # Format: YYYY-MM-DD (10 chars)
    assert_eq(s.length(), 10, "today_string must be 10 chars")
    assert_eq(s[4], "-",     "char 4 must be dash")
    assert_eq(s[7], "-",     "char 7 must be dash")
```

- [ ] 运行测试，确认三个新测试因缺少 save_system.gd 而失败（preload 错误）：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

### Step 3.2 — 创建 run/save_system.gd

- [ ] 创建 `run/save_system.gd`：

```gdscript
# run/save_system.gd
class_name SaveSystem extends RefCounted

const SAVE_PATH := "user://neon_pinball.cfg"

static func save(data: Dictionary) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(&"run",   &"best_score",      data.get(&"best_score",      0))
    cfg.set_value(&"run",   &"runs_completed",  data.get(&"runs_completed",  0))
    cfg.set_value(&"daily", &"last_date",       data.get(&"last_date",       ""))
    cfg.set_value(&"daily", &"daily_completed", data.get(&"daily_completed", false))
    cfg.save(SAVE_PATH)

static func load_data() -> Dictionary:
    var cfg := ConfigFile.new()
    var err := cfg.load(SAVE_PATH)
    if err != OK:
        return {
            &"best_score":      0,
            &"runs_completed":  0,
            &"last_date":       "",
            &"daily_completed": false,
        }
    return {
        &"best_score":      cfg.get_value(&"run",   &"best_score",      0),
        &"runs_completed":  cfg.get_value(&"run",   &"runs_completed",  0),
        &"last_date":       cfg.get_value(&"daily", &"last_date",       ""),
        &"daily_completed": cfg.get_value(&"daily", &"daily_completed", false),
    }

static func today_string() -> String:
    var d := Time.get_date_dict_from_system()
    return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
```

### Step 3.3 — 修改 board_view.gd：RUN_WIN 和 RUN_LOSE 自动存档

- [ ] 在 `view/board_view.gd` 的 `_handle_phase_transition()` 中，找到 `RunManager.Phase.RUN_WIN:` 分支，将原有的 HUD 更新调用替换/扩充为：

```gdscript
RunManager.Phase.RUN_WIN:
    var saved := SaveSystem.load_data()
    var total: int = RunMan.state[&"money"]  # use money as proxy score
    if total > int(saved[&"best_score"]):
        saved[&"best_score"] = total
    saved[&"runs_completed"] = int(saved[&"runs_completed"]) + 1
    saved[&"last_date"] = SaveSystem.today_string()
    saved[&"daily_completed"] = true
    SaveSystem.save(saved)
    $Hud.set_gate_label("YOU WIN!  Best: %d  (R to restart)" % int(saved[&"best_score"]))
```

- [ ] 找到 `RunManager.Phase.RUN_LOSE:` 分支，将原有调用替换/扩充为：

```gdscript
RunManager.Phase.RUN_LOSE:
    var saved := SaveSystem.load_data()
    saved[&"runs_completed"] = int(saved[&"runs_completed"]) + 1
    SaveSystem.save(saved)
    $Hud.set_gate_label("GAME OVER  (R to restart)")
```

### Step 3.4 — 运行测试确认绿色

- [ ] 运行：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: PASS — 110 tests（107 + 3 新增 SaveSystem 测试）

### Step 3.5 — 提交

- [ ] 提交：

```
git -C D:/NeonPinball/game add run/save_system.gd view/board_view.gd tests/test_save_system.gd
git -C D:/NeonPinball/game commit -m "feat: SaveSystem with ConfigFile persistence; auto-save on WIN/LOSE"
```

---

## Task 4: DailySeed

**Files:**
- Modify: `run/save_system.gd` (add daily_seed() static method)
- Modify: `view/board_view.gd` (_ready: set master_seed from daily seed; show daily status in HUD)
- Modify: `view/hud.gd` (no structural changes needed — set_gate_label already exists)
- Test: `tests/test_save_system.gd` (add two daily_seed tests)

### Step 4.1 — 写失败测试

- [ ] 在 `tests/test_save_system.gd` 末尾追加两个新测试函数：

```gdscript
func test_daily_seed_is_positive() -> void:
    var seed_val := SaveSystemScript.daily_seed()
    assert_true(seed_val > 0,             "daily seed must be positive")
    assert_true(seed_val < 0x7FFFFFFF,    "daily seed must fit in positive int")

func test_daily_seed_is_deterministic_same_call() -> void:
    var s1 := SaveSystemScript.daily_seed()
    var s2 := SaveSystemScript.daily_seed()
    assert_eq(s1, s2, "same day -> same seed")
```

- [ ] 运行测试，确认两个新测试因缺少 daily_seed() 方法而失败：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

### Step 4.2 — 为 save_system.gd 添加 daily_seed()

- [ ] 在 `run/save_system.gd` 末尾（today_string() 之后）添加：

```gdscript
static func daily_seed() -> int:
    var d := Time.get_date_dict_from_system()
    return (d["year"] * 10000 + d["month"] * 100 + d["day"]) & 0x7FFFFFFF
```

例如 2026-06-10 → 20260610 & 0x7FFFFFFF = 20260610（在正整数范围内）。同一天内多次调用返回相同值。

### Step 4.3 — 修改 board_view.gd：_ready() 设置 master_seed 并显示 Daily 状态

- [ ] 在 `view/board_view.gd` 的 `_ready()` 中，在 RunMan BOOT→ROUND 自动推进块之后、`_apply_boss_mod()` 之前，添加：

```gdscript
    # Set daily seed if master_seed not yet assigned
    if RunMan.state[&"master_seed"] == 0:
        RunMan.state[&"master_seed"] = SaveSystem.daily_seed()
    # Show daily completion status in HUD
    var saved := SaveSystem.load_data()
    var is_daily_done: bool = (saved[&"daily_completed"] == true
        and saved[&"last_date"] == SaveSystem.today_string())
    if is_daily_done:
        $Hud.set_gate_label("Daily DONE  Best: %d" % int(saved[&"best_score"]))
    else:
        $Hud.set_gate_label("Daily #%d" % RunMan.state[&"master_seed"])
```

### Step 4.4 — 运行测试确认全绿

- [ ] 运行：

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: PASS — 112 tests（110 + 2 新增 DailySeed 测试）

### Step 4.5 — 提交

- [ ] 提交：

```
git -C D:/NeonPinball/game add run/save_system.gd view/board_view.gd tests/test_save_system.gd
git -C D:/NeonPinball/game commit -m "feat: DailySeed from system date; show completion in HUD"
```

---

## Final Verification

After all four tasks are complete and committed, run the full test suite one final time:

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: PASS — 112 tests (102 original + 10 new)

New tests breakdown:
- `test_mult_peg.gd`: 4 tests
- `test_run_loop.gd`: +1 test (test_8_area_run_win_requires_24_rounds)
- `test_save_system.gd`: 5 tests (3 + 2 daily seed)

---

## Self-Check

- [ ] MULT 钉在 `_draw()` 显示橙色 `Color(1.0, 0.55, 0.0)`，普通钉显示青色 `Color(0.2, 0.9, 1.0)`
- [ ] 命中 MULT 钉向 ledger 写入 KIND_ADD_MULT 条目 → 最终得分乘以 (1.0 + mult_add)
- [ ] `ban_mult` boss mod 将 MULT 钉转为 NORMAL（M3 已实现，现在有实际意义）
- [ ] 游戏需要 8 个区域（24 轮）才能胜利；现有快速测试通过 `max_areas = 3` 保持不变
- [ ] RUN_WIN 时自动存档 best_score，并将 daily_completed 设为 true、last_date 设为今天
- [ ] RUN_LOSE 时自动存档 runs_completed 递增
- [ ] 同一天按 R 重开游戏得到相同 master_seed（daily seed 确定性）
- [ ] HUD 在已完成今日挑战时显示 "Daily DONE  Best: N"
- [ ] 102 原有测试 + 10 新测试全部通过，共 112 tests
