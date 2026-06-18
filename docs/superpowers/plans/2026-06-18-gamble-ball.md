# 赌球：双倍或清零 Implementation Plan（第二档 2.1 切片）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 逐球可选"押注"：押注的球落定得分 ×2（命中钉数达阈值）或清零；每球一个贪 vs 稳的决策。

**Architecture:** 纯模块 `scoring/gamble.gd`（成功判定+结算，可测）；board_view 持押注状态 + 在 `_on_all_settled` 连击之后套用；HUD 加状态 label；input 加 G 键切换。零侵入 sim/物理/连击曲线。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库事实，已核对）

- 项目根 `D:/NeonPinball/game/`。Godot `/d/Program/Godot/godot`（不在 PATH）。缩进 **TAB**。
- 全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
- **基线：266 测试全绿，38 脚本。** 每任务只提交自己的文件。**不要 push、不要新建分支（main）。**
- spec：`docs/superpowers/specs/2026-06-18-gamble-ball-design.md`。
- `view/board_view.gd`：
  - 顶部 const 区有 `const ComboScoreScript := preload("res://scoring/combo_score.gd")`（约 14 行）。
  - `launch()`（407-435）含：`_score_ctx.clear_for_launch()`、`_combo = 0`、`_score_ticker.reset()`、`_live_target = 0.0`、`_combo_display_ttl = 0.0`（约 419-423）。
  - `_on_all_settled()`（594-616）：`var result := _engine.settle(_score_ctx)`、`var score: float = result[0]`、`_live_target = score`、`_juice.on_settle_combo(...)`、`$Hud.add_score(score)`、`RunMan.add_launch_score(score)`。
  - `_show_shop_ui()`（含 `_shop_reroll_count = 0` 一行，shop-tier1 已加）。
  - `_juice.floaters.add(pos, text)` 可用；`_last_settle_pos` 成员存在。`_has_ball`/`_is_transitioning` 成员存在。
- `view/input_controller.gd`：`_unhandled_input`（72-102）`match event.keycode`：`KEY_TAB`/`KEY_SPACE`/`KEY_1..KEY_4`，最后一条 `KEY_4: _board.set_active_gate(&"scatter_split")`（98 行）。`toggle_gamble` 内部自保护相位/飞行，故 G 键直接调即可。
- `view/hud.gd`：`_make_label(pos: Vector2, size: int, color := Color.WHITE) -> Label`；`_ready` 里 top-right 列 `_label_launches = _make_label(Vector2(490, 92), 18, ...)`、`_label_targets = _make_label(Vector2(490, 116), ...)`。下一空位 y≈140。

---

## 文件结构
- **新建**：`scoring/gamble.gd`、`tests/test_gamble.gd`（T1）
- **修改**：`view/hud.gd`（T2）；`view/board_view.gd`、`view/input_controller.gd`（T3）

---

## Task 1：纯模块 `scoring/gamble.gd` + 测试

**Files:** Create `scoring/gamble.gd`, `tests/test_gamble.gd`

- [ ] **Step 1: 写失败测试** —— 新建 `tests/test_gamble.gd`：
```gdscript
extends GutTest

const GambleScript := preload("res://scoring/gamble.gd")

func test_is_success_threshold() -> void:
	assert_false(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS - 1), "阈值-1 → 失败")
	assert_true(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS), "恰好阈值 → 成功")
	assert_true(GambleScript.is_success(GambleScript.GAMBLE_MIN_PEGS + 5), "更多 → 成功")
	assert_false(GambleScript.is_success(0), "0 钉 → 失败")

func test_resolve_double_or_zero() -> void:
	assert_almost_eq(GambleScript.resolve(100.0, GambleScript.GAMBLE_MIN_PEGS), 100.0 * GambleScript.GAMBLE_MULT, 1e-4, "成功 ×倍率")
	assert_almost_eq(GambleScript.resolve(100.0, GambleScript.GAMBLE_MIN_PEGS - 1), 0.0, 1e-4, "失败清零")
	assert_almost_eq(GambleScript.resolve(0.0, GambleScript.GAMBLE_MIN_PEGS), 0.0, 1e-4, "base 0 成功仍 0")
```

- [ ] **Step 2: 跑确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_gamble.gd -gexit`
预期：脚本加载失败（`gamble.gd` 未创建）。

- [ ] **Step 3: 实现** —— 新建 `scoring/gamble.gd`：
```gdscript
class_name Gamble extends RefCounted
# 赌球：双倍或清零。成功 = 本球命中钉数达阈值。纯逻辑，无状态。

const GAMBLE_MULT := 2.0       # 成功倍率
const GAMBLE_MIN_PEGS := 6     # 成功所需最少命中钉数（头号旋钮，实机调）

static func is_success(pegs_hit: int) -> bool:
	return pegs_hit >= GAMBLE_MIN_PEGS

# 押注的球落定得分结算：成功 ×GAMBLE_MULT，失败清零。
static func resolve(base_score: float, pegs_hit: int) -> float:
	return base_score * GAMBLE_MULT if is_success(pegs_hit) else 0.0
```

- [ ] **Step 4: 跑确认通过**

单文件 2/2 过。全套应 **268**（266 + 2）：
`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add scoring/gamble.gd tests/test_gamble.gd
git -C D:/NeonPinball/game commit -m "feat: Gamble.is_success/resolve pure module (double-or-nothing)"
```

---

## Task 2：HUD 押注状态 label

**Files:** Modify `view/hud.gd`

> board_view 尚未调用 `set_gamble_label`（T3 才调）→ 本任务自包含、不破。无单测，靠场景冒烟。

- [ ] **Step 1: 加成员** —— 找到 `var _label_targets: Label`，在其**后**加：
```gdscript
var _label_gamble: Label
```

- [ ] **Step 2: `_ready` 创建并初始化** —— 找到 `_label_targets = _make_label(Vector2(490, 116), 18, Color(1.0, 0.85, 0.2))`，在其**后**加：
```gdscript
	_label_gamble = _make_label(Vector2(490, 140), 16, Color(1.0, 0.55, 0.2))
```
并在 `_ready` 末尾（`_build_shop_panel()` / `_build_end_panel()` 调用之前或之后均可，放 `_build_end_panel()` 之后）加：
```gdscript
	set_gamble_label(false)
```

- [ ] **Step 3: 加方法** —— 在 `set_target_count(...)` 函数之后（或任意公共 API 区）加：
```gdscript
func set_gamble_label(armed: bool) -> void:
	if armed:
		_label_gamble.text = "🎲 押注:开 ×2/0  [G]"
		_label_gamble.modulate = Color(1.0, 0.85, 0.2)
	else:
		_label_gamble.text = "🎲 押注:关  [G]"
		_label_gamble.modulate = Color(0.55, 0.55, 0.55)
```

- [ ] **Step 4: 场景冒烟**
写 `/tmp/gb.gd`（extends SceneTree；load+instantiate `res://scenes/board.tscn`；print BOARD_OK/FAIL；quit），跑：
`/d/Program/Godot/godot --headless --path . -s /tmp/gb.gd 2>&1 | grep -iE "BOARD_OK|BOARD_FAIL|Parse Error|SCRIPT ERROR"`
预期 `BOARD_OK`，无新增 Parse/SCRIPT error。`rm -f /tmp/gb.gd`。全套仍 **268**。

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add view/hud.gd
git -C D:/NeonPinball/game commit -m "feat: HUD gamble status label"
```

---

## Task 3：board_view 押注状态/结算 + input G 键

**Files:** Modify `view/board_view.gd`, `view/input_controller.gd`

- [ ] **Step 1: board_view 加 preload + 成员**
(a) 找到 `const ComboScoreScript := preload("res://scoring/combo_score.gd")`，在其**后**加：
```gdscript
const GambleScript := preload("res://scoring/gamble.gd")
```
(b) 找到 `var _live_target := 0.0`（或任一成员声明区合适处），在其**后**加：
```gdscript
var _gamble_armed := false      # 玩家发射前的押注选择
var _gamble_active := false     # 本球是否押注（发射时锁定）
```

- [ ] **Step 2: `launch()` 锁定本球押注 + 重置选择** —— 找到 `launch()` 里的 `_combo = 0`，在其**后**加：
```gdscript
	_gamble_active = _gamble_armed
	_gamble_armed = false
	$Hud.set_gamble_label(false)
```

- [ ] **Step 3: 加 `toggle_gamble()`** —— 在 `launch()` 函数之后插入：
```gdscript
# 发射前切换"押注这球"（仅 ROUND/BOSS_ROUND 且无球/非过渡时有效）。
func toggle_gamble() -> void:
	if _has_ball or _is_transitioning:
		return
	var phase: int = RunMan.state[&"phase"]
	if phase != RunManager.Phase.ROUND and phase != RunManager.Phase.BOSS_ROUND:
		return
	_gamble_armed = not _gamble_armed
	$Hud.set_gamble_label(_gamble_armed)
```

- [ ] **Step 4: `_on_all_settled()` 套用结算** —— 找到：
```gdscript
	var score: float = result[0]
	_live_target = score
```
把这两行之间插入（即 `var score` 之后、`_live_target` 之前）：
```gdscript
	if _gamble_active:
		var won := GambleScript.is_success(_score_ctx.pegs_hit)
		score = GambleScript.resolve(score, _score_ctx.pegs_hit)
		_juice.floaters.add(_last_settle_pos + Vector2(0, -60), "GAMBLE ×2!" if won else "BUST  清零")
		_gamble_active = false
```

- [ ] **Step 5: 进商店清押注** —— 在 `_show_shop_ui()` 里找到 `_shop_reroll_count = 0`，在其**后**加：
```gdscript
	_gamble_armed = false
	$Hud.set_gamble_label(false)
```

- [ ] **Step 6: input 加 G 键** —— `view/input_controller.gd` 的 `match event.keycode` 里，找到 `KEY_4: _board.set_active_gate(&"scatter_split")`，在其**后**加（match 臂同缩进）：
```gdscript
				KEY_G:
					_board.toggle_gamble()
```

- [ ] **Step 7: 验证场景加载 + 全套**
(a) 场景冒烟（同 T2 的 `/tmp/gb.gd`）→ 期望 `BOARD_OK`，无新增 Parse/SCRIPT error，`rm -f /tmp/gb.gd`。
(b) 全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit` → 期望 **268** 全绿。若失败/解析错，修到全绿。

> 实机验收（用户人工）：① 发射前按 G 切换押注、HUD label 开/关、每球落定重置为关 ② 押注球命中≥阈值 →×2+"GAMBLE ×2!" 否则清零+"BUST" ③ 不押注的球不变 ④ 飞行中按 G 无效、进商店押注清零 ⑤ `GAMBLE_MIN_PEGS` 手感（实机调）。

- [ ] **Step 8: 提交**
```bash
git -C D:/NeonPinball/game add view/board_view.gd view/input_controller.gd
git -C D:/NeonPinball/game commit -m "feat: wire gamble ball — G toggle, settle resolve, shop reset"
```

---

## 自检清单

- [ ] **Spec 覆盖**：逐球自选(T3 toggle + launch 锁定/重置) ✓；落定 ×2/清零(T3 Step4 + T1 resolve) ✓；成功=钉数阈值(T1) ✓；飘字反馈(T3 Step4) ✓；只影响该球(改局部 score) ✓；飞行中不可改/进商店清零(T3 Step3 守卫 + Step5) ✓；HUD 状态(T2 + T3 调用) ✓；G 键(T3 Step6) ✓；纯函数单测(T1) ✓；零侵入 sim/连击曲线 ✓
- [ ] **占位符扫描**：每步完整代码 + 确切命令 ✓
- [ ] **类型/签名一致性**：
  - `Gamble.is_success(pegs)` / `resolve(base, pegs)` / 常量 `GAMBLE_MULT`/`GAMBLE_MIN_PEGS` —— 定义(T1)、测试(T1)、调用(T3) 一致 ✓
  - `HUD.set_gamble_label(armed: bool)` —— 定义(T2)、调用(T3 launch/toggle/_show_shop_ui) 一致；T2 先于 T3 → 调用前方法已存在 ✓
  - `board_view.toggle_gamble()` —— 定义(T3 Step3)、调用(input Step6) 一致 ✓
  - `_gamble_armed`/`_gamble_active` 声明(Step1)、launch 锁定/重置(Step2)、toggle(Step3)、settle 用+清(Step4)、商店清(Step5) 闭环 ✓
- [ ] **范围**：仅赌球；多球/存球/连击可存可赌、押注按钮/相位隐藏、ticker 预览 留 roadmap/Backlog ✓

---

## 备注 / 已知行为
- **`GAMBLE_MIN_PEGS=6` 是核心手感旋钮**，必须实机调到约 50/50；记 `balance-tunables.md`。
- 押注 ×2 叠在已含连击的分上，可能swingy（清零高连击球=强烈挫败=预期张力）。
- 成功用 `_score_ctx.pegs_hit`（含 cascade），与连击同源。
- 飞行中 ticker 不显示"×2 待定"（Phase 1 落定才结算）；押注状态靠 HUD label。
- 数值（MULT/MIN_PEGS）落地后回填 `docs/superpowers/balance-tunables.md`。
