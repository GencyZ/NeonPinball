# 飞行中实时分数 Ticker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 飞行中在棋盘上方居中显示"本发实时总分"——每帧对当前 ledger 跑 `ScoringEngine.settle`，平滑 count-up 上涨、撞 mult 钉大跳时 punch，落定 combo ×N 注入让数字滚到最终值。

**Architecture:** 纯逻辑 count-up/punch 放可单测的 `juice/score_ticker.gd`；board_view 持一个 ScoreTicker，`_process` 每帧喂当前 settle 值并 tick，`_draw()` 居中画大数字。复用 `ScoringEngine`，不改计分、不碰 sim/确定性。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
  （`godot` 不在 PATH；单文件 `-gselect=<file>`。）
- 基线：**227 测试全绿，34 脚本**。缩进 **TAB**。每任务只提交自己的文件。**不要 push**。**不要新建分支**（main）。
- `scoring/scoring_engine.gd`：`settle(ctx) -> [score, steps]`（纯函数，随时可调）。
- `view/board_view.gd` 关键锚点（行号近似，**按内容匹配**）：
  - 顶部 const 区：有 `const ComboScoreScript := preload("res://scoring/combo_score.gd")` 等一串 preload。
  - 状态 var 区：`var _combo: int = 0`、`var _all_clear_ttl := 0.0`、`var _score_ticker`(无) 等。
  - `_ready()`：`_engine = ScoringEngine.new()`、`_juice = JuiceControllerScript.new()`、`_sfx = SfxControllerScript.new()` 一带创建对象。
  - `launch()`：内有 `_score_ctx.clear_for_launch()` 与 `_combo = 0`。
  - `_process(delta)` 的"不依赖 `_has_ball`"段（约 548 行起 `# Transition + halo animations run regardless of ball state`）：末尾有
    ```gdscript
    		if _combo_display_ttl > 0.0:
    			_combo_display_ttl -= delta
    		if _all_clear_ttl > 0.0:
    			_all_clear_ttl -= delta
    		_juice.update(delta)
    ```
  - `_on_all_settled()`（约 568 行）：
    ```gdscript
    func _on_all_settled() -> void:
    	var combo_x: float = ComboScoreScript.xmult_for(_score_ctx.pegs_hit)
    	if combo_x > 1.0:
    		_score_ctx.add(ScoreContext.KIND_MUL_MULT, combo_x, &"combo")
    	var result := _engine.settle(_score_ctx)
    	var score: float = result[0]
    	_juice.on_settle_combo(...)
    	...
    ```
  - `_draw()`：末尾附近 `_draw_walls()` 调用。
  - `_rect = Rect2(135, 225, 540, 900)`，局部中心 x=270，顶部 y<124 区域空着。

---

## 文件结构

**新建：** `juice/score_ticker.gd`（纯逻辑：count-up + 跳升 punch + 衰减）、`tests/test_score_ticker.gd`
**修改：** `view/board_view.gd`（持 ScoreTicker + 每帧喂 settle 值 + 绘制大数字）

---

## Task 1：ScoreTicker（纯逻辑）

**Files:** Create `juice/score_ticker.gd`; Test `tests/test_score_ticker.gd`

- [ ] **Step 1: 写失败测试** `tests/test_score_ticker.gd`（TAB 缩进）

```gdscript
extends GutTest

const ScoreTickerScript := preload("res://juice/score_ticker.gd")

func test_approaches_target() -> void:
	var t := ScoreTickerScript.new()
	t.update(100.0, 1.0 / 60.0)
	assert_gt(t.value(), 0.0, "开始上升")
	assert_lt(t.value(), 100.0, "未瞬达")
	for i in 200:
		t.update(100.0, 1.0 / 60.0)
	assert_almost_eq(t.value(), 100.0, 1e-3, "最终收敛到 target")

func test_monotonic_rise() -> void:
	var t := ScoreTickerScript.new()
	var prev := 0.0
	for i in 30:
		t.update(100.0, 1.0 / 60.0)
		assert_true(t.value() >= prev, "单调不降 @%d" % i)
		prev = t.value()

func test_big_jump_punches() -> void:
	var t := ScoreTickerScript.new()
	t.update(10.0, 1.0 / 60.0)   # 10 < JUMP_MIN(20) → 不 punch
	assert_almost_eq(t.punch_scale(), 1.0, 1e-3, "小增量不 punch")
	t.update(300.0, 1.0 / 60.0)  # 大跳
	assert_gt(t.punch_scale(), 1.0, "大跳触发 punch")

func test_punch_decays() -> void:
	var t := ScoreTickerScript.new()
	t.update(0.0, 1.0 / 60.0)
	t.update(300.0, 1.0 / 60.0)
	assert_gt(t.punch_scale(), 1.0)
	for i in 60:
		t.update(300.0, 1.0 / 60.0)
	assert_almost_eq(t.punch_scale(), 1.0, 1e-2, "punch 衰减回 1.0")

func test_small_increment_no_punch() -> void:
	var t := ScoreTickerScript.new()
	for i in 300:
		t.update(200.0, 1.0 / 60.0)
	t.update(210.0, 1.0 / 60.0)   # +10 < JUMP_MIN(20) → 不 punch
	assert_almost_eq(t.punch_scale(), 1.0, 1e-2, "小增量不 punch")

func test_reset() -> void:
	var t := ScoreTickerScript.new()
	t.update(300.0, 1.0 / 60.0)
	t.reset()
	assert_eq(t.value(), 0.0, "归零")
	assert_almost_eq(t.punch_scale(), 1.0, 1e-3, "punch 归零")
```

- [ ] **Step 2: 运行确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_score_ticker.gd -gexit`

- [ ] **Step 3: 实现** `juice/score_ticker.gd`（TAB 缩进）

```gdscript
class_name ScoreTicker extends RefCounted

const APPROACH := 12.0       # display 朝 target 每秒逼近比例
const JUMP_FRAC := 0.15      # target 相对当前跳升超过此比例…
const JUMP_MIN := 20.0       # …且绝对增量超过此值 → 触发 punch（两者都满足）
const PUNCH_DUR := 0.18      # punch 持续（秒）
const PUNCH_SCALE := 0.4     # punch 峰值额外缩放（1.0 → 1.4）

var _display := 0.0
var _target := 0.0
var _punch_ttl := 0.0

# 每帧调用：设目标、检测跳升、逼近、衰减 punch。
func update(target: float, delta: float) -> void:
	var jump := target - _target
	if jump > JUMP_MIN and jump > _target * JUMP_FRAC:
		_punch_ttl = PUNCH_DUR
	_target = target
	_display += (_target - _display) * minf(1.0, APPROACH * delta)
	if absf(_target - _display) < 0.5:
		_display = _target
	if _punch_ttl > 0.0:
		_punch_ttl = maxf(0.0, _punch_ttl - delta)

func value() -> float:
	return _display

# punch 缩放：基准 1.0，跳升后鼓包再回落。
func punch_scale() -> float:
	return 1.0 + PUNCH_SCALE * sin(_punch_ttl / PUNCH_DUR * PI)

func reset() -> void:
	_display = 0.0
	_target = 0.0
	_punch_ttl = 0.0
```

- [ ] **Step 4: 运行确认通过**（6/6）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/score_ticker.gd tests/test_score_ticker.gd
git -C D:/NeonPinball/game commit -m "feat: ScoreTicker — count-up + jump-punch + decay"
```

---

## Task 2：board_view 接线 + 绘制

**Files:** Modify `view/board_view.gd`

> board_view 无单测；靠场景加载检查 + 全套保持绿 + 实机确认。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 预载常量** — 顶部 const 区，找到：
`const ComboScoreScript := preload("res://scoring/combo_score.gd")`
其后加：
```gdscript
const ScoreTickerScript := preload("res://juice/score_ticker.gd")
```

- [ ] **Step 2: 状态变量** — 找到 `var _all_clear_ttl := 0.0`，其后加：
```gdscript
var _score_ticker
var _live_target := 0.0
```

- [ ] **Step 3: `_ready` 创建 ticker** — 找到：
```gdscript
	_juice = JuiceControllerScript.new()
```
其后加：
```gdscript
	_score_ticker = ScoreTickerScript.new()
```

- [ ] **Step 4: `launch()` 归零** — 找到 `launch()` 里的：
```gdscript
	_combo = 0
```
其后加：
```gdscript
	_score_ticker.reset()
	_live_target = 0.0
```

- [ ] **Step 5: `_process` 每帧喂值 + tick** — 在"不依赖 `_has_ball`"段，找到：
```gdscript
		if _all_clear_ttl > 0.0:
			_all_clear_ttl -= delta
		_juice.update(delta)
```
改为（在 `_juice.update` 之前插入）：
```gdscript
		if _all_clear_ttl > 0.0:
			_all_clear_ttl -= delta
		if _has_ball:
			_live_target = _engine.settle(_score_ctx)[0]
		_score_ticker.update(_live_target, delta)
		_juice.update(delta)
```

- [ ] **Step 6: `_on_all_settled` 滚到最终值** — 找到：
```gdscript
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
```
其后加：
```gdscript
	_live_target = score
```

- [ ] **Step 7: `_draw()` 画大数字** — 在 `_draw_walls()` 调用**之前**加：
```gdscript
	var sv := int(round(_score_ticker.value()))
	if sv > 0:
		var tf := ThemeDB.fallback_font
		var psc := _score_ticker.punch_scale()
		var fsz := int(40.0 * psc)
		var stxt := str(sv)
		draw_string(tf, _rect.position + Vector2(270.0 - float(stxt.length()) * float(fsz) * 0.28, 60.0),
			stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1, 1, 1))
```

- [ ] **Step 8: 验证场景加载 + 全套**
创建 `/tmp/lst.gd`（extends SceneTree；load+instantiate `res://scenes/board.tscn`；print BOARD_OK/FAIL；quit），运行：
`/d/Program/Godot/godot --headless --path . -s /tmp/lst.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
期望 `BOARD_OK`，无 NEW Parse Error/SCRIPT ERROR（预存 GameDB/RunMan/SceneMan autoload-absent 报错无关）。然后 `rm -f /tmp/lst.gd`。
全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`，期望 All tests passed，总数 227 + 6 = **233**（board_view 无新单测）。

> 实机验收（用户人工）：飞行中棋盘上方大数字随撞钉上涨，撞 mult 钉跳一下，落定 combo ×N 猛跳到最终值，下一发归零。

- [ ] **Step 9: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: live per-launch score ticker drawn above board"
```

---

## 自检清单

- [ ] **Spec 覆盖**：本发实时总分=settle(ledger)(T2 Step5) ✓；count-up + 跳升 punch + 衰减(T1) ✓；居中大数字绘制 + punch 缩放(T2 Step7) ✓；落定 combo 注入后滚到最终值(T2 Step6) ✓；发射归零(T2 Step4) ✓；count-up 不依赖 _has_ball 跑完(T2 Step5 在 regardless 段) ✓；纯逻辑全单测(T1) ✓；零侵入计分/sim ✓
- [ ] **占位符扫描**：每步完整代码与确切命令 ✓
- [ ] **类型/签名一致性**：
  - `ScoreTicker.update(target, delta)` / `value()` / `punch_scale()` / `reset()` —— T1 定义、T1 测试、T2 调用一致 ✓
  - preload 名 `ScoreTickerScript`；状态 `_score_ticker` / `_live_target` 一致 ✓
  - 实时值用 `_engine.settle(_score_ctx)[0]`（与 _on_all_settled 同源）✓
- [ ] **范围**：仅本发实时分 ticker；颜色随热度/音效/HUD 总分滚 留 Backlog ✓

---

## 备注

- 飞行中 `_live_target` **不含 combo**（combo 落定才注入）；落定 `_live_target = score` 让数字滚到含 combo 的最终值（升级感，与 spec/用户确认一致）。
- 每帧 `settle` 重算开销可忽略（ledger 数十条目）。
- 大数字居中按字宽估算偏移（`0.28*fsz*len`，无精确测宽）；实机微调系数即可。
- ScoreTicker 数值（APPROACH/JUMP/PUNCH）+ 字号 40 + 位置 y=60 首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
- `_score_ticker.update` 放在 regardless-of-ball 段，使落定后 count-up 仍滚完（含 combo 大跳）后再静止；下一发 `reset()` 重来。
