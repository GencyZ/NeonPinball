# Milestone 3 — Run Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现完整的 3 区跑局循环：RunManager 状态机 + 经济系统 + 商店 + Boss 词条 + HUD 集成，玩家可以打完 3 区并看到胜利/失败结果。

**Architecture:** RunManager 作为 Autoload（`RunMan`）持有跑局状态字典；BoardView 从 RunMan 读取 `launches_left`、写入本发得分，并在每轮结束后触发 `advance()`；商店阶段在 HUD 层用键盘 1-4 购买物品；Boss 词条在 board_view 建立钉子数组后直接修改钉子类型。

**Tech Stack:** Godot 4.6.3 GDScript, GUT 测试框架, 已有 `GameDB`/`DeterministicRng`/`BallSimulation`/`ScoringEngine` 基础

---

## 文件结构

**新建：**
- `run/run_manager.gd` — Autoload：状态机、quota、经济（payout / interest）
- `run/shop.gd` — 商店：roll / buy / reroll，从 GameDB pool 随机抽取
- `tests/test_run_manager.gd` — RunManager 单元测试
- `tests/test_shop.gd` — Shop 单元测试
- `tests/test_run_loop.gd` — 3 区 headless 集成测试

**修改：**
- `project.godot` — 注册 `RunMan` Autoload
- `data/game_database.gd` — 扩充商店可抽物品池（多加 2 个触发器）
- `view/hud.gd` — 新增 quota / money / ante / launches / 商店面板标签
- `view/board_view.gd` — 集成 RunMan（launches_left 限制、得分写入、Boss 词条应用）
- `view/input_controller.gd` — launches_left 检查、商店阶段键盘处理

---

## Task 1: RunManager 状态机 + 经济

**Files:**
- Create: `run/run_manager.gd`
- Modify: `project.godot`
- Test: `tests/test_run_manager.gd`

- [ ] **Step 1: 写失败测试**

```gdscript
# tests/test_run_manager.gd
extends GutTest

func test_quota_of_ante1_round0() -> void:
    # ante=1, round_in_ante=0 → quota = round(50.0 * 1.0 * 1.0) = 50
    assert_almost_eq(RunManager.quota_of(1, 0), 50.0, 1.0)

func test_quota_of_ante1_round2() -> void:
    # ante=1, round_in_ante=2 (boss) → round(50.0 * 1.8) = 90
    assert_almost_eq(RunManager.quota_of(1, 2), 90.0, 1.0)

func test_quota_grows_with_ante() -> void:
    assert_true(RunManager.quota_of(2, 0) > RunManager.quota_of(1, 0))
    assert_true(RunManager.quota_of(8, 0) > RunManager.quota_of(4, 0))

func test_boot_to_round() -> void:
    var mgr := RunManager.new()
    assert_eq(mgr.state[&"phase"], RunManager.Phase.BOOT)
    mgr.advance()   # BOOT → RUN_START → ROUND
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManager.Phase.ROUND)
    assert_eq(mgr.state[&"ante"], 1)
    assert_eq(mgr.state[&"round_in_ante"], 0)
    assert_eq(mgr.state[&"launches_left"], 5)
    mgr.free()

func test_round_win_to_shop() -> void:
    var mgr := RunManager.new()
    mgr.advance()   # BOOT
    mgr.advance()   # RUN_START → ROUND
    # 模拟得分超过 quota
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()   # ROUND → ANTE_CLEAR
    assert_eq(mgr.state[&"phase"], RunManager.Phase.ANTE_CLEAR)
    mgr.advance()   # ANTE_CLEAR → SHOP (payout here)
    assert_eq(mgr.state[&"phase"], RunManager.Phase.SHOP)
    assert_true(mgr.state[&"money"] > 0, "payout must give money")
    mgr.free()

func test_round_fail_to_lose() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 0.0   # definitely fails quota
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManager.Phase.RUN_LOSE)
    mgr.free()

func test_three_rounds_advance_ante() -> void:
    var mgr := RunManager.new()
    mgr.advance()   # BOOT
    mgr.advance()   # RUN_START → ROUND
    for _r in 3:
        mgr.state[&"round_score"] = 9999.0
        mgr.advance()   # ROUND → ANTE_CLEAR
        mgr.advance()   # ANTE_CLEAR → SHOP
        mgr.advance()   # SHOP → ROUND (next round in ante or next ante)
    # After 3 rounds of ante 1, should be in ante 2
    assert_eq(mgr.state[&"ante"], 2)
    assert_eq(mgr.state[&"round_in_ante"], 0)
    mgr.free()

func test_payout_includes_interest() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"money"] = 10   # 10 gold → interest = min(10/5, 5) = 2
    mgr.state[&"launches_left"] = 3
    mgr.state[&"round_score"] = 9999.0
    mgr.advance()   # ROUND → ANTE_CLEAR
    mgr.advance()   # ANTE_CLEAR → SHOP (triggers payout)
    # base_reward(3+1=4) + launch_bonus(3) + interest(2) = 9, plus existing 10 = 19
    assert_eq(mgr.state[&"money"], 19)
    mgr.free()

func test_boss_round_is_round_2() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()
    # Advance past round 0 and 1
    for _r in 2:
        mgr.state[&"round_score"] = 9999.0
        mgr.advance()   # ROUND → ANTE_CLEAR
        mgr.advance()   # ANTE_CLEAR → SHOP
        mgr.advance()   # SHOP → ROUND
    assert_eq(mgr.state[&"round_in_ante"], 2)
    assert_eq(mgr.state[&"phase"], RunManager.Phase.BOSS_ROUND)
    mgr.free()
```

- [ ] **Step 2: 运行测试确认失败**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

预期：`test_run_manager` 中所有测试失败（RunManager 未定义）

- [ ] **Step 3: 创建 `run/run_manager.gd`**

```gdscript
# run/run_manager.gd
class_name RunManager extends Node

enum Phase {
    BOOT, RUN_START,
    ROUND, BOSS_ROUND,
    ANTE_CLEAR, SHOP,
    RUN_WIN, RUN_LOSE
}

# 完整跑局状态（可序列化为 JSON）
var state: Dictionary = {
    &"master_seed":    0,
    &"phase":          Phase.BOOT,
    &"ante":           1,
    &"round_in_ante":  0,
    &"round_score":    0.0,
    &"quota":          0.0,
    &"launches_left":  5,
    &"money":          0,
    # 已装备的触发器 id 列表（StringName）
    &"equipped_triggers": [&"peg_bonus", &"bounce_mult", &"big_hit"],
    # 已装备的门 id（StringName，单槽 MVP）
    &"equipped_gate":  &"normal",
    # Boss 词条（空 = 无；详见 Phase.BOSS_ROUND 处理）
    &"boss_mod":       {},
}

const LAUNCHES_PER_ROUND := 5

static func quota_of(ante: int, round_in_ante: int) -> float:
    var ante_base := 50.0 * pow(1.6, ante - 1)
    var mul := [1.0, 1.3, 1.8][clampi(round_in_ante, 0, 2)]
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
                if state[&"ante"] > 3:   # MVP：3 区通关
                    state[&"phase"] = Phase.RUN_WIN
                    return
            state[&"phase"] = Phase.SHOP

        Phase.SHOP:
            _start_round()

        Phase.RUN_WIN, Phase.RUN_LOSE:
            _reset()

# 每发球减少 launches_left（由 BoardView 调用）
func spend_launch() -> void:
    state[&"launches_left"] = maxi(0, state[&"launches_left"] - 1)

# 每发球结束后由 BoardView 调用，累加得分
func add_launch_score(score: float) -> void:
    state[&"round_score"] += score

# 当前轮是否已用完发射次数
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

# MVP：两种 Boss 词条，按 ante 的种子决定
func _roll_boss_mod() -> Dictionary:
    var rng := DeterministicRng.derive(state[&"master_seed"],
                                       state[&"ante"] * 7 + 13)
    if rng.next_float() < 0.5:
        return {&"type": &"ban_mult"}
    return {&"type": &"sparse", &"remove_chance": 0.30}

func _reset() -> void:
    state = {
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
```

- [ ] **Step 4: 在 `project.godot` 中注册 Autoload**

打开 `D:/NeonPinball/game/project.godot`，在 `[autoload]` 节中加一行：

```ini
RunMan="*res://run/run_manager.gd"
```

完整 `[autoload]` 节应为：
```ini
[autoload]
GameDB="*res://data/game_database.gd"
RunMan="*res://run/run_manager.gd"
```

- [ ] **Step 5: 运行测试确认全部通过**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

预期：新增的 7 个 RunManager 测试全部通过，原有 75 个测试不回归。

- [ ] **Step 6: 提交**

```bash
git -C D:/NeonPinball/game add run/run_manager.gd tests/test_run_manager.gd project.godot
git -C D:/NeonPinball/game commit -m "feat: RunManager state machine with quota, payout, boss mod rolling"
```

---

## Task 2: 扩充 GameDB 物品池 + Shop 逻辑

**Files:**
- Modify: `data/game_database.gd`
- Create: `run/shop.gd`
- Test: `tests/test_shop.gd`

- [ ] **Step 1: 写失败测试**

```gdscript
# tests/test_shop.gd
extends GutTest

var _shop: Shop

func before_each() -> void:
    _shop = Shop.new()

func after_each() -> void:
    _shop.free()

func test_roll_fills_4_slots() -> void:
    _shop.roll(12345, 1, 0, 0)
    assert_eq(_shop.offerings.size(), 4)

func test_offerings_have_required_keys() -> void:
    _shop.roll(12345, 1, 0, 0)
    for offer in _shop.offerings:
        assert_true(offer.has(&"item"),  "missing item key")
        assert_true(offer.has(&"price"), "missing price key")
        assert_true(offer.has(&"sold"),  "missing sold key")
        assert_false(offer[&"sold"],     "should start unsold")

func test_buy_deducts_money() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    var price: int = _shop.offerings[0][&"price"]
    var ok := _shop.buy(0, inv, money)
    assert_true(ok, "buy should succeed with enough money")
    assert_eq(money[0], 100 - price)

func test_buy_marks_sold() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    _shop.buy(0, inv, money)
    assert_true(_shop.offerings[0][&"sold"], "slot should be marked sold")

func test_buy_insufficient_money_fails() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [0]
    var inv := {&"items": []}
    var ok := _shop.buy(0, inv, money)
    assert_false(ok, "buy should fail with no money")

func test_buy_cannot_repurchase() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    _shop.buy(0, inv, money)
    var money2 := [100]
    var inv2 := {&"items": []}
    var ok := _shop.buy(0, inv2, money2)
    assert_false(ok, "sold slot cannot be bought again")

func test_reroll_refreshes_offerings() -> void:
    _shop.roll(12345, 1, 0, 0)
    var first := _shop.offerings.duplicate(true)
    _shop.roll(12345, 1, 0, 1)   # reroll_count = 1
    var different := false
    for i in 4:
        if _shop.offerings[i][&"item"] != first[i][&"item"]:
            different = true
            break
    assert_true(different, "reroll should generate different offerings")

func test_reroll_cost_increases() -> void:
    assert_eq(Shop.reroll_cost(0), 1)
    assert_eq(Shop.reroll_cost(1), 2)
    assert_eq(Shop.reroll_cost(2), 3)

func test_deterministic_same_seed() -> void:
    var shop_a := Shop.new()
    var shop_b := Shop.new()
    shop_a.roll(99, 2, 0, 0)
    shop_b.roll(99, 2, 0, 0)
    for i in 4:
        assert_eq(shop_a.offerings[i][&"price"], shop_b.offerings[i][&"price"])
    shop_a.free(); shop_b.free()
```

- [ ] **Step 2: 运行测试确认失败**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

预期：`test_shop` 所有测试失败（Shop 未定义）

- [ ] **Step 3: 扩充 `data/game_database.gd`，增加商店物品池**

在 `_register_defaults()` 末尾，`# --- Gates ---` 前，追加 2 个新触发器：

```gdscript
    # --- Extra triggers (for shop pool) ---
    var chain_bonus := TriggerDef.new()
    chain_bonus.id = &"chain_bonus"
    chain_bonus.listen_mask = 4         # SETTLED
    chain_bonus.effect = TriggerDef.Effect.ADD_BASE
    chain_bonus.value = 10.0
    chain_bonus.condition = TriggerDef.Condition.PEGS_HIT_GTE
    chain_bonus.condition_threshold = 3
    chain_bonus.rarity = 1
    triggers[chain_bonus.id] = chain_bonus

    var double_mult := TriggerDef.new()
    double_mult.id = &"double_mult"
    double_mult.listen_mask = 4         # SETTLED
    double_mult.effect = TriggerDef.Effect.MUL_MULT
    double_mult.value = 2.0
    double_mult.condition = TriggerDef.Condition.BOUNCE_GTE
    double_mult.condition_threshold = 10
    double_mult.rarity = 2
    triggers[double_mult.id] = double_mult
```

同时，给现有三个触发器加上 `rarity` 字段（当前缺省为 0）：

```gdscript
    peg_bonus.rarity = 0
    bmult.rarity = 0
    big_hit.rarity = 1
```

（在各自 `triggers[x.id] = x` 行之前插入）

- [ ] **Step 4: 创建 `run/shop.gd`**

```gdscript
# run/shop.gd
class_name Shop

const SLOT_COUNT := 4
const BASE_REROLL_COST := 1
const REROLL_STEP := 1

var offerings: Array = []   # Array of {&"item": Resource, &"price": int, &"sold": bool}

# master_seed + ante + node_cursor + reroll_count → 可复现
func roll(master_seed: int, ante: int, node_cursor: int, reroll_count: int) -> void:
    var tag := ante * 10000 + node_cursor * 100 + reroll_count
    var rng := DeterministicRng.derive(master_seed, tag)
    offerings.clear()
    for _i in SLOT_COUNT:
        var item: Resource = _roll_item(ante, rng)
        offerings.append({
            &"item":  item,
            &"price": _price_of(item, ante),
            &"sold":  false,
        })

static func reroll_cost(reroll_count: int) -> int:
    return BASE_REROLL_COST + reroll_count * REROLL_STEP

# 购买：扣钱 + 加入 inventory[&"items"]。money_ref 是 [int] 包装引用。
func buy(slot: int, inventory: Dictionary, money_ref: Array) -> bool:
    if slot < 0 or slot >= offerings.size():
        return false
    var offer: Dictionary = offerings[slot]
    if offer[&"sold"]:
        return false
    if money_ref[0] < offer[&"price"]:
        return false
    money_ref[0] -= offer[&"price"]
    offer[&"sold"] = true
    inventory[&"items"].append(offer[&"item"])
    return true

# 抽物品：6/4 触发器和门，按稀有度权重
func _roll_item(ante: int, rng: DeterministicRng) -> Resource:
    var use_gate := rng.next_float() < 0.35   # 35% 抽门
    if use_gate:
        return _roll_from_pool(GameDB.gate_defs.values(), ante, rng)
    return _roll_from_pool(GameDB.triggers.values(), ante, rng)

func _roll_from_pool(pool: Array, ante: int, rng: DeterministicRng) -> Resource:
    if pool.is_empty():
        return GameDB.triggers.values()[0]   # 兜底
    var weights: Array[int] = []
    for item in pool:
        var r: int = item.get(&"rarity") if item.get(&"rarity") != null else 0
        var base_w := 100 - r * 25
        var ante_bonus := r * ante
        weights.append(maxi(5, base_w + ante_bonus))
    var total := 0
    for w in weights: total += w
    var roll := rng.range_int(0, total)
    var acc := 0
    for i in pool.size():
        acc += weights[i]
        if roll < acc:
            return pool[i]
    return pool[-1]

func _price_of(item: Resource, ante: int) -> int:
    var r: int = item.get(&"rarity") if item.get(&"rarity") != null else 0
    var base := [3, 5, 8, 12][clampi(r, 0, 3)]
    return base + ante / 2
```

- [ ] **Step 5: 运行测试确认全部通过**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

预期：9 个 Shop 测试全部通过，所有先前测试不回归。

- [ ] **Step 6: 提交**

```bash
git -C D:/NeonPinball/game add run/shop.gd data/game_database.gd tests/test_shop.gd
git -C D:/NeonPinball/game commit -m "feat: Shop logic with weighted item pool; expand GameDB trigger pool"
```

---

## Task 3: HUD 扩充（quota / money / ante / launches / 商店面板）

**Files:**
- Modify: `view/hud.gd`
- Test: 无（视图层，手动验证）

- [ ] **Step 1: 重写 `view/hud.gd`**

完整替换为下列代码（保留原有 `add_score` / `set_gate_label` 接口）：

```gdscript
# view/hud.gd
extends CanvasLayer

# ---------- 运行状态标签 ----------
var _label_total: Label
var _label_last: Label
var _label_gate: Label
var _label_ante: Label
var _label_quota: Label
var _label_money: Label
var _label_launches: Label

# ---------- 商店面板 ----------
var _shop_panel: PanelContainer
var _shop_title: Label
var _shop_slots: Array[Label] = []   # 4 个商店槽标签
var _shop_hint: Label
var _shop_visible := false

# ---------- 内部 ----------
var _total := 0.0

func _ready() -> void:
    # 左上角：总分 + 上次得分 + 门名
    _label_total = _make_label(Vector2(20, 20), 28)
    _label_last  = _make_label(Vector2(20, 56), 18, Color(1, 1, 0.5))
    _label_gate  = _make_label(Vector2(20, 82), 18, Color(0.6, 1.0, 0.8))

    # 右上角：区/轮 + quota + 金币 + 剩余发射
    _label_ante    = _make_label(Vector2(350, 20), 18, Color(1.0, 0.8, 0.4))
    _label_quota   = _make_label(Vector2(350, 44), 18, Color(1.0, 0.5, 0.5))
    _label_money   = _make_label(Vector2(350, 68), 18, Color(0.4, 1.0, 0.6))
    _label_launches = _make_label(Vector2(350, 92), 18, Color(0.8, 0.8, 1.0))

    _label_total.text   = "Score: 0"
    _label_last.text    = ""
    _label_gate.text    = "Gate: normal"
    _label_ante.text    = "Ante 1 · Round 1"
    _label_quota.text   = "Quota: 0"
    _label_money.text   = "Gold: 0"
    _label_launches.text = "Launches: 5"

    _build_shop_panel()

func _make_label(pos: Vector2, size: int, color: Color = Color.WHITE) -> Label:
    var lbl := Label.new()
    lbl.position = pos
    lbl.add_theme_font_size_override(&"font_size", size)
    lbl.modulate = color
    add_child(lbl)
    return lbl

func _build_shop_panel() -> void:
    _shop_panel = PanelContainer.new()
    _shop_panel.position = Vector2(60, 200)
    _shop_panel.size = Vector2(420, 340)
    _shop_panel.visible = false
    add_child(_shop_panel)

    var vbox := VBoxContainer.new()
    _shop_panel.add_child(vbox)

    _shop_title = Label.new()
    _shop_title.text = "=== SHOP ==="
    _shop_title.add_theme_font_size_override(&"font_size", 24)
    _shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(_shop_title)

    for i in 4:
        var lbl := Label.new()
        lbl.add_theme_font_size_override(&"font_size", 18)
        vbox.add_child(lbl)
        _shop_slots.append(lbl)

    _shop_hint = Label.new()
    _shop_hint.text = "Press 1-4 to buy · Space to continue"
    _shop_hint.add_theme_font_size_override(&"font_size", 14)
    _shop_hint.modulate = Color(0.7, 0.7, 0.7)
    _shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(_shop_hint)

# ---- 公开接口 ----

func add_score(s: float) -> void:
    _total += s
    _label_total.text = "Score: %d" % int(_total)
    _label_last.text  = "+%d" % int(s)

func set_gate_label(gate_name: String) -> void:
    _label_gate.text = "Gate: " + gate_name

func update_run_state(ante: int, round_in_ante: int,
                      quota: float, money: int, launches: int, round_score: float) -> void:
    _label_ante.text    = "Ante %d · Round %d" % [ante, round_in_ante + 1]
    _label_quota.text   = "Score %d / %d" % [int(round_score), int(quota)]
    _label_money.text   = "Gold: %d" % money
    _label_launches.text = "Launches: %d" % launches

func show_shop(offerings: Array, money: int) -> void:
    _shop_visible = true
    _shop_panel.visible = true
    for i in minf(offerings.size(), 4):
        var offer: Dictionary = offerings[i]
        var item: Resource = offer[&"item"]
        var name_str: String = String(item.id) if item.has_method("get") else "?"
        var price: int = offer[&"price"]
        var sold: bool = offer[&"sold"]
        if sold:
            _shop_slots[i].text = "[%d] SOLD" % (i + 1)
            _shop_slots[i].modulate = Color(0.4, 0.4, 0.4)
        else:
            _shop_slots[i].text = "[%d] %s  (%d gold)" % [i + 1, name_str, price]
            _shop_slots[i].modulate = Color(1, 1, 0.5) if money >= price else Color(0.5, 0.5, 0.5)
    _shop_panel.get_parent().set_process_unhandled_input(false)   # 让 InputController 处理按键

func hide_shop() -> void:
    _shop_visible = false
    _shop_panel.visible = false

func is_shop_visible() -> bool:
    return _shop_visible
```

- [ ] **Step 2: 提交**

```bash
git -C D:/NeonPinball/game add view/hud.gd
git -C D:/NeonPinball/game commit -m "feat: expand HUD with quota/money/ante/launches and shop panel"
```

---

## Task 4: BoardView + InputController 集成 RunManager

**Files:**
- Modify: `view/board_view.gd`
- Modify: `view/input_controller.gd`

核心改动：
1. BoardView 每次 launch 前检查 RunMan.launches_exhausted()；发射时调用 RunMan.spend_launch()
2. 每发球落底后调用 RunMan.add_launch_score(score)，再检查 launches_exhausted → advance()
3. Boss 词条在 BoardView._build_honeycomb() 后应用
4. InputController 在 SHOP 阶段拦截键 1-4 / Space，其余阶段正常

- [ ] **Step 1: 修改 `view/board_view.gd`**

**新增字段：**
```gdscript
var _boss_mod_applied := false
```

**修改 `_ready()`** — 在 `set_active_gate(&"normal")` 之前，加一行：

```gdscript
    # 自动推进 RunManager 到 ROUND 阶段
    if RunMan.state[&"phase"] == RunManager.Phase.BOOT:
        RunMan.advance()   # BOOT → RUN_START
        RunMan.advance()   # RUN_START → ROUND
    _apply_boss_mod()
    _refresh_equipped()
```

**新增 `_apply_boss_mod()`** — 根据 RunMan boss_mod 修改 _pegs：

```gdscript
func _apply_boss_mod() -> void:
    var bm: Dictionary = RunMan.state[&"boss_mod"]
    if bm.is_empty(): return
    match bm[&"type"]:
        &"ban_mult":
            for peg in _pegs:
                if peg[&"type"] != null and peg[&"type"].behavior == PegType.Behavior.MULT:
                    peg[&"type"] = GameDB.peg_types[&"normal"]
        &"sparse":
            var rng := DeterministicRng.derive(RunMan.state[&"master_seed"],
                                               RunMan.state[&"ante"] * 77 + 3)
            var keep: Array = []
            for peg in _pegs:
                if peg[&"type"].behavior != PegType.Behavior.NORMAL or rng.next_float() >= bm[&"remove_chance"]:
                    keep.append(peg)
            _pegs = keep
            _sim = BallSimulation.new(_rect, _pegs, {
                &"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
                &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
            })

func _refresh_equipped() -> void:
    _trigger_runtimes.clear()
    for tid in RunMan.state[&"equipped_triggers"]:
        if GameDB.triggers.has(tid):
            _trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))
    var gate_id: StringName = RunMan.state[&"equipped_gate"]
    if GameDB.gate_defs.has(gate_id):
        set_active_gate(gate_id)
```

**修改 `launch(ball: BallState)`** — 在 `if _has_ball: return` 之后加：

```gdscript
    # 检查发射次数（RunManager 追踪）
    if RunMan.launches_exhausted():
        return
    RunMan.spend_launch()
```

**修改 `_on_all_settled()`** — 在 `$Hud.add_score(score)` 之后加：

```gdscript
    RunMan.add_launch_score(score)
    # 通知 HUD 当前累计 round_score
    $Hud.update_run_state(
        RunMan.state[&"ante"],
        RunMan.state[&"round_in_ante"],
        RunMan.state[&"quota"],
        RunMan.state[&"money"],
        RunMan.state[&"launches_left"],
        RunMan.state[&"round_score"],
    )
    # 用完发射次数 → 推进状态
    if RunMan.launches_exhausted():
        RunMan.advance()   # ROUND/BOSS_ROUND → ANTE_CLEAR or RUN_LOSE
        _handle_phase_transition()
```

**新增 `_handle_phase_transition()`：**

```gdscript
func _handle_phase_transition() -> void:
    match RunMan.state[&"phase"]:
        RunManager.Phase.ANTE_CLEAR:
            RunMan.advance()   # ANTE_CLEAR → SHOP
            _show_shop_ui()
        RunManager.Phase.RUN_LOSE:
            $Hud.add_score(0)   # 不额外加分
            _label_result("GAME OVER — Press R to restart")
        RunManager.Phase.RUN_WIN:
            _label_result("YOU WIN! — Press R to restart")

func _show_shop_ui() -> void:
    var shop := Shop.new()
    shop.roll(RunMan.state[&"master_seed"],
              RunMan.state[&"ante"],
              RunMan.state[&"round_in_ante"],
              0)
    # 存商店引用，供 InputController 访问
    _active_shop = shop
    $Hud.show_shop(shop.offerings, RunMan.state[&"money"])

func _label_result(msg: String) -> void:
    # 显示结果文字（借用 _label_last 位置）
    $Hud.add_score(0)   # 刷新 HUD
    # 注意：此处只调用 HUD 已有接口，不直接访问 HUD 私有标签
    print(msg)   # MVP：控制台输出；后续可以 HUD 标签显示
```

**新增字段：**

```gdscript
var _active_shop: Shop = null
```

- [ ] **Step 2: 修改 `view/input_controller.gd`**

**在 `_unhandled_input` 中加 SHOP 阶段处理**，在 `KEY_TAB` 之前插入：

```gdscript
        # 商店阶段：数字键购买，Space 继续
        if RunMan.state[&"phase"] == RunManager.Phase.SHOP:
            _handle_shop_input(event.keycode)
            return
        # 胜败后按 R 重置
        if event.keycode == KEY_R:
            if RunMan.state[&"phase"] == RunManager.Phase.RUN_WIN \
            or RunMan.state[&"phase"] == RunManager.Phase.RUN_LOSE:
                RunMan.advance()   # WIN/LOSE → BOOT → (通过 _ready 重新 advance)
                _board.get_tree().reload_current_scene()
                return
```

**新增 `_handle_shop_input(keycode: Key)`：**

```gdscript
func _handle_shop_input(keycode: Key) -> void:
    var shop: Shop = _board._active_shop
    if shop == null: return

    var slot := -1
    match keycode:
        KEY_1: slot = 0
        KEY_2: slot = 1
        KEY_3: slot = 2
        KEY_4: slot = 3
        KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
            # 离开商店 → 进入下一轮
            _board._active_shop = null
            _board.$Hud.hide_shop()
            RunMan.advance()   # SHOP → ROUND
            # 根据新状态重建钉子和触发器
            _board._pegs = _board._build_honeycomb()
            _board._sim = BallSimulation.new(_board._rect, _board._pegs, {
                &"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
                &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": _board.DT,
            })
            _board._apply_boss_mod()
            _board._refresh_equipped()
            _board.$Hud.update_run_state(
                RunMan.state[&"ante"],
                RunMan.state[&"round_in_ante"],
                RunMan.state[&"quota"],
                RunMan.state[&"money"],
                RunMan.state[&"launches_left"],
                RunMan.state[&"round_score"],
            )
            return

    if slot >= 0:
        var money_ref := [RunMan.state[&"money"]]
        var inv := {&"items": []}
        var ok := shop.buy(slot, inv, money_ref)
        if ok:
            RunMan.state[&"money"] = money_ref[0]
            # 将购买物品装备到 RunMan
            for item in inv[&"items"]:
                if item is TriggerDef:
                    var equipped: Array = RunMan.state[&"equipped_triggers"]
                    if equipped.size() < 5:   # 最多 5 个触发器槽
                        equipped.append(item.id)
                elif item is GateDef:
                    RunMan.state[&"equipped_gate"] = item.id
            _board.$Hud.show_shop(shop.offerings, RunMan.state[&"money"])
```

- [ ] **Step 3: 运行游戏手动验证**

在 Godot 编辑器中运行场景（`F5`）：
1. 游戏自动进入第 1 区第 1 轮
2. HUD 右上角显示 `Ante 1 · Round 1`、`Score 0 / 50`、`Gold: 0`、`Launches: 5`
3. 点击发球，每发后 Launches 减少
4. 第 5 发落底后：若分数 ≥ 50 → 商店出现；若 < 50 → 控制台打印 GAME OVER
5. 商店显示 4 个物品，按 1-4 购买，Space 继续
6. 继续后进入 Round 2

- [ ] **Step 4: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd view/input_controller.gd
git -C D:/NeonPinball/game commit -m "feat: integrate RunManager into BoardView/InputController (launches_left, shop, boss mod)"
```

---

## Task 5: 3 区 Headless 集成测试

**Files:**
- Create: `tests/test_run_loop.gd`
- Test: `tests/test_run_loop.gd`

- [ ] **Step 1: 创建 `tests/test_run_loop.gd`**

```gdscript
# tests/test_run_loop.gd
extends GutTest

# 模拟一整局（3 区 × 3 轮 = 9 轮），每轮固定传入足够高的 round_score 保证通关。
# 目的：验证状态机转移正确、payout 逻辑正确、boss 词条在第 3 轮触发。

func test_full_3_area_run_win() -> void:
    var mgr := RunManager.new()
    mgr.advance()   # BOOT → RUN_START
    mgr.advance()   # RUN_START → ROUND

    var round_count := 0
    var shop_count  := 0

    for _iter in 60:   # 上限 60 步，防止死循环
        var phase: int = mgr.state[&"phase"]
        match phase:
            RunManager.Phase.ROUND, RunManager.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance()   # → ANTE_CLEAR
                round_count += 1
            RunManager.Phase.ANTE_CLEAR:
                mgr.advance()   # → SHOP
            RunManager.Phase.SHOP:
                mgr.advance()   # → ROUND (skip shop)
                shop_count += 1
            RunManager.Phase.RUN_WIN:
                break
            RunManager.Phase.RUN_LOSE:
                fail_test("Should not lose with cheat score")
                break

    assert_eq(mgr.state[&"phase"], RunManager.Phase.RUN_WIN, "should win after 3 areas")
    assert_eq(round_count, 9, "3 areas × 3 rounds = 9 rounds")
    assert_eq(shop_count,  9, "9 shops (one after each round)")
    mgr.free()

func test_lose_on_low_score() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()
    mgr.state[&"round_score"] = 0.0
    mgr.advance()
    assert_eq(mgr.state[&"phase"], RunManager.Phase.RUN_LOSE)
    mgr.free()

func test_boss_round_at_round_2() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()
    # 通过前 2 轮
    for _r in 2:
        mgr.state[&"round_score"] = 999999.0
        mgr.advance()   # → ANTE_CLEAR
        mgr.advance()   # → SHOP
        mgr.advance()   # → ROUND
    assert_eq(mgr.state[&"round_in_ante"], 2)
    assert_eq(mgr.state[&"phase"], RunManager.Phase.BOSS_ROUND)
    assert_false(mgr.state[&"boss_mod"].is_empty(), "boss mod must be set in boss round")
    mgr.free()

func test_money_accumulates_across_rounds() -> void:
    var mgr := RunManager.new()
    mgr.advance()
    mgr.advance()

    var prev_money := 0
    for _r in 3:
        mgr.state[&"round_score"] = 999999.0
        mgr.state[&"launches_left"] = 5
        mgr.advance()   # → ANTE_CLEAR
        mgr.advance()   # → SHOP (triggers payout)
        assert_true(mgr.state[&"money"] > prev_money, "money must grow after payout")
        prev_money = mgr.state[&"money"]
        mgr.advance()   # → ROUND

    mgr.free()

func test_quota_grows_each_ante() -> void:
    # ante=1,round=0 < ante=2,round=0 < ante=3,round=0
    var q1 := RunManager.quota_of(1, 0)
    var q2 := RunManager.quota_of(2, 0)
    var q3 := RunManager.quota_of(3, 0)
    assert_true(q1 < q2, "quota grows with ante")
    assert_true(q2 < q3, "quota grows with ante")

func test_replay_same_final_state() -> void:
    var inputs := _make_win_inputs()

    var state_a := _run_headless(12345, inputs)
    var state_b := _run_headless(12345, inputs)

    assert_eq(state_a[&"money"],      state_b[&"money"])
    assert_eq(state_a[&"ante"],       state_b[&"ante"])
    assert_eq(state_a[&"phase"],      state_b[&"phase"])

func _make_win_inputs() -> Array:
    # 每步 input 仅需知道 round_score；真实 replay 用 input_log
    return []   # headless 测试直接操控 state，不走 input_log

func _run_headless(seed: int, _inputs: Array) -> Dictionary:
    var mgr := RunManager.new()
    mgr.state[&"master_seed"] = seed
    mgr.advance()
    mgr.advance()
    for _iter in 60:
        match mgr.state[&"phase"]:
            RunManager.Phase.ROUND, RunManager.Phase.BOSS_ROUND:
                mgr.state[&"round_score"] = 999999.0
                mgr.advance()
            RunManager.Phase.ANTE_CLEAR:
                mgr.advance()
            RunManager.Phase.SHOP:
                mgr.advance()
            _:
                break
    var result := mgr.state.duplicate()
    mgr.free()
    return result
```

- [ ] **Step 2: 运行所有测试**

```
godot --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

预期：全部测试通过（原有 75 + 新增 RunManager 7 + Shop 9 + RunLoop 6 = ~97 个测试）

- [ ] **Step 3: 提交**

```bash
git -C D:/NeonPinball/game add tests/test_run_loop.gd
git -C D:/NeonPinball/game commit -m "test: 3-area headless integration test for run loop"
```

- [ ] **Step 4: Push 到远程**

```bash
git -C D:/NeonPinball/game push origin main
```

---

## 自检清单

- [ ] `RunManager.quota_of(1, 0)` ≈ 50，`quota_of(1, 2)` ≈ 90，`quota_of(8, 0)` > 500
- [ ] 3 区 × 3 轮 = 9 轮后进入 RUN_WIN（headless 测试）
- [ ] 第 3 轮（round_in_ante=2）进入 BOSS_ROUND 且 boss_mod 不为空
- [ ] payout 包含 base_reward + launch_bonus + interest
- [ ] Shop 4 个槽，按 1-4 可购买；购买触发器加入 equipped_triggers；购买门替换 equipped_gate
- [ ] 商店阶段 Space/Enter → 进入下一轮，BoardView 重建 pegs + 应用 boss_mod
- [ ] HUD 显示：`Ante X · Round Y`、`Score P / Q`、`Gold: G`、`Launches: L`
- [ ] 所有先前 75 个测试不回归
- [ ] `R` 键可重开一局

## 已知局限（留 M4 解决）

- Shop 购买后触发器超过 5 个不报错，仅截断（槽位管理留 M4）
- 商店面板是 CanvasLayer 文字，无鼠标点击支持（M4 添加按钮）
- `.tres` 资源文件迁移延后至 M4（GameDB 仍硬编码）
- SaveSystem / 续局留 M4
- 超过 3 区后 RUN_WIN（代码注释 `# MVP：3 区通关`），8 区完整 run 留 M4
