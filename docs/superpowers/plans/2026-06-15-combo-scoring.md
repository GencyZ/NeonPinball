# 连击计分（Combo → ×倍率）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本发命中钉数（`ScoreContext.pegs_hit`，含连锁/炸弹连带）折算成封顶 ×5 的 ×倍率，落定前注入计分乘法链，并在落定显著揭示（`COMBO ×N` 飘字 + 越爆震越强），同步上调配额。

**Architecture:** 纯曲线函数放 `scoring/combo_score.gd`（可单测）；落定时 board_view 把 combo ×倍率作为 `KIND_MUL_MULT` 条目注入 `ScoreContext`，自然走现有 `ScoringEngine.settle`；揭示用 `JuiceController.on_settle_combo`；配额在 `run/run_manager.gd` 上调。对确定性 sim 与 settle 算法零侵入。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
  （`godot` 不在 PATH；单文件用 `-gselect=<file>`。）
- 基线：**207 测试全绿，32 脚本**。缩进 **TAB**。每任务只提交自己的文件。**不要 push**（用户单独确认）。**不要新建分支**（在 main 上做）。
- 计分（`class_name` 全局类，测试里直接用 `ScoreContext` / `ScoringEngine`）：
  - `ScoreContext`：`KIND_ADD_BASE=0 / KIND_ADD_MULT=1 / KIND_MUL_MULT=2`；`add(kind,value,source)`；`pegs_hit`；`clear_for_launch()`。
  - `ScoringEngine.settle(ctx) -> [score, steps]`：`base × (1+mult_add) × Π(mul_mults)`。
- `view/board_view.gd` `_on_all_settled()`（约 486 行）当前：
  ```gdscript
  func _on_all_settled() -> void:
  	var result := _engine.settle(_score_ctx)
  	var score: float = result[0]
  	_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())
  	$Hud.add_score(score)
  	RunMan.add_launch_score(score)
  	...
  ```
  顶部 const 区有 `const JuiceControllerScript := preload(...)` 等。
- `juice/juice_controller.gd` `on_settle(pos, score, is_final_launch)`：`floaters.add(pos, "+%d" % int(score))` + `shake.add(0.2)` + 最后一球 `slowmo.request(0.35, 0.25)`。成员 `floaters`（`.items`、`.add(pos,text)`）、`shake`（`.trauma`、`.add()`）、`slowmo`。`class_name JuiceController`，测试用 `const JuiceControllerScript := preload("res://juice/juice_controller.gd")`。
- `run/run_manager.gd` `static func quota_of(ante, round_in_ante)`：`var ante_base := 50.0 * pow(1.6, ante - 1)`；`mul = {0:1.0,1:1.3,2:1.8}`。
- `tests/test_run_manager.gd`：第 6 行断言 `quota_of(1,0)==50.0`、第 9 行 `quota_of(1,2)==90.0`（需更新）。

---

## 文件结构

**新建：**
- `scoring/combo_score.gd` — `xmult_for(pegs_hit) -> float` + 常量（纯逻辑）。
- `tests/test_combo_score.gd` — 曲线 + 计分管线测试。

**修改：**
- `run/run_manager.gd` — `quota_of` 基数 50→90。
- `tests/test_run_manager.gd` — 两个配额断言更新。
- `juice/juice_controller.gd` — 新增 `on_settle_combo`。
- `tests/test_juice_controller.gd` — `on_settle_combo` 测试。
- `view/board_view.gd` — `_on_all_settled` 注入 combo ×倍率 + 改调 `on_settle_combo`。

---

## Task 1：ComboScore 曲线

**Files:**
- Create: `scoring/combo_score.gd`
- Test: `tests/test_combo_score.gd`

- [ ] **Step 1: 写失败测试** `tests/test_combo_score.gd`（TAB 缩进）

```gdscript
extends GutTest

const ComboScoreScript := preload("res://scoring/combo_score.gd")

func test_below_min_no_bonus() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(0), 1.0, 1e-5, "0 钉无加成")
	assert_almost_eq(ComboScoreScript.xmult_for(1), 1.0, 1e-5, "1 钉无加成")

func test_threshold_start() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(2), 1.24, 1e-4, "2 钉 = ×1.24")

func test_mid_value() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(10), 2.2, 1e-4, "10 钉 = ×2.2")

func test_monotonic_non_decreasing() -> void:
	for n in range(0, 40):
		assert_true(ComboScoreScript.xmult_for(n + 1) >= ComboScoreScript.xmult_for(n),
			"单调不降 @%d" % n)

func test_capped_at_5() -> void:
	assert_almost_eq(ComboScoreScript.xmult_for(100), 5.0, 1e-4, "封顶 ×5")
	for n in range(0, 120):
		assert_true(ComboScoreScript.xmult_for(n) <= 5.0, "不超过 5 @%d" % n)

func test_pipeline_combo_multiplies() -> void:
	# base 10 × combo(10)=2.2 → 22
	var eng := ScoringEngine.new()
	var ctx := ScoreContext.new()
	ctx.add(ScoreContext.KIND_ADD_BASE, 10.0, &"peg")
	ctx.add(ScoreContext.KIND_MUL_MULT, ComboScoreScript.xmult_for(10), &"combo")
	assert_almost_eq(float(eng.settle(ctx)[0]), 22.0, 1e-4, "10 × 2.2 = 22")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_combo_score.gd -gexit`
Expected: FAIL（类不存在）

- [ ] **Step 3: 实现** `scoring/combo_score.gd`（TAB 缩进）

```gdscript
class_name ComboScore extends RefCounted

const COMBO_RATE := 0.12      # 每命中一钉的 ×倍率增量
const COMBO_CAP := 5.0        # ×倍率封顶
const COMBO_MIN_PEGS := 2     # 低于此命中数不给加成

# 本发命中钉数 → ×倍率（与现有 ×mult 相乘）
static func xmult_for(pegs_hit: int) -> float:
	if pegs_hit < COMBO_MIN_PEGS:
		return 1.0
	return minf(1.0 + float(pegs_hit) * COMBO_RATE, COMBO_CAP)
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_combo_score.gd -gexit`
Expected: PASS（6/6）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add scoring/combo_score.gd tests/test_combo_score.gd
git -C D:/NeonPinball/game commit -m "feat: ComboScore — pegs_hit -> capped xmult curve"
```

---

## Task 2：重平衡配额

**Files:**
- Modify: `run/run_manager.gd`
- Test: `tests/test_run_manager.gd`

- [ ] **Step 1: 先更新测试期望（红）** — `tests/test_run_manager.gd`，把：
```gdscript
func test_quota_of_ante1_round0() -> void:
	assert_almost_eq(RunManagerScript.quota_of(1, 0), 50.0, 1.0)

func test_quota_of_ante1_round2() -> void:
	assert_almost_eq(RunManagerScript.quota_of(1, 2), 90.0, 1.0)
```
改为：
```gdscript
func test_quota_of_ante1_round0() -> void:
	assert_almost_eq(RunManagerScript.quota_of(1, 0), 90.0, 1.0)

func test_quota_of_ante1_round2() -> void:
	assert_almost_eq(RunManagerScript.quota_of(1, 2), 162.0, 1.0)
```
（90×1.8 = 162。）

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_run_manager.gd -gexit`
Expected: FAIL（这两个断言不匹配旧的 50/90）

- [ ] **Step 3: 改配额基数** — `run/run_manager.gd`，把：
```gdscript
	var ante_base := 50.0 * pow(1.6, ante - 1)
```
改为：
```gdscript
	var ante_base := 90.0 * pow(1.6, ante - 1)   # 首版：配合 combo ×倍率上调，待试玩微调
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_run_manager.gd -gexit`
Expected: PASS（全部，含两个改后的配额断言）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add run/run_manager.gd tests/test_run_manager.gd
git -C D:/NeonPinball/game commit -m "balance: raise quota base 50 -> 90 for combo scoring (first pass)"
```

---

## Task 3：落定揭示 on_settle_combo

**Files:**
- Modify: `juice/juice_controller.gd`
- Test: `tests/test_juice_controller.gd`

- [ ] **Step 1: 追加失败测试** 到 `tests/test_juice_controller.gd` 末尾（TAB 缩进；文件顶部已有 `const JuiceControllerScript := preload(...)`）

```gdscript
func test_on_settle_combo_two_floaters_when_combo() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle_combo(Vector2.ZERO, 100.0, 2.2, false)
	assert_eq(jc.floaters.items.size(), 2, "+N 与 COMBO 两条飘字")

func test_on_settle_combo_one_floater_at_x1() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle_combo(Vector2.ZERO, 100.0, 1.0, false)
	assert_eq(jc.floaters.items.size(), 1, "×1 时只有 +N")

func test_on_settle_combo_higher_x_more_shake() -> void:
	var a := JuiceControllerScript.new()
	var b := JuiceControllerScript.new()
	a.on_settle_combo(Vector2.ZERO, 100.0, 1.0, false)
	b.on_settle_combo(Vector2.ZERO, 100.0, 3.0, false)
	assert_gt(b.shake.trauma, a.shake.trauma, "越爆震越强")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_juice_controller.gd -gexit`
Expected: FAIL（`on_settle_combo` 不存在）

- [ ] **Step 3: 实现** — `juice/juice_controller.gd`，在现有 `on_settle(...)` 方法之后加（TAB 缩进；保留 `on_settle` 不删）：

```gdscript
# 落定揭示：+N 飘字 + （combo>1 时）COMBO ×N 飘字 + 越爆震越强。
func on_settle_combo(pos: Vector2, score: float, combo_x: float, is_final_launch: bool) -> void:
	floaters.add(pos, "+%d" % int(score))
	if combo_x > 1.0:
		floaters.add(pos + Vector2(0, -28), "COMBO x%.1f" % combo_x)
	shake.add(minf(0.2 + (combo_x - 1.0) * 0.12, 0.6))
	if is_final_launch and score > 0.0:
		slowmo.request(0.35, 0.25)
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_juice_controller.gd -gexit`
Expected: PASS（原有 + 新 3 个）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/juice_controller.gd tests/test_juice_controller.gd
git -C D:/NeonPinball/game commit -m "feat: JuiceController.on_settle_combo — combo reveal floater + scaled shake"
```

---

## Task 4：board_view 接线

**Files:**
- Modify: `view/board_view.gd`

> board_view 是场景脚本，无单测；靠场景加载检查 + 全套测试保持绿 + 实机确认。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 加预载常量** — 顶部 const 区，找到：
`const JuiceControllerScript := preload("res://juice/juice_controller.gd")`
在其后加：
```gdscript
const ComboScoreScript := preload("res://scoring/combo_score.gd")
```

- [ ] **Step 2: `_on_all_settled` 注入 combo ×倍率 + 改调揭示** — 找到：
```gdscript
func _on_all_settled() -> void:
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
	_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())
```
替换为：
```gdscript
func _on_all_settled() -> void:
	var combo_x: float = ComboScoreScript.xmult_for(_score_ctx.pegs_hit)
	if combo_x > 1.0:
		_score_ctx.add(ScoreContext.KIND_MUL_MULT, combo_x, &"combo")
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
	_juice.on_settle_combo(_last_settle_pos, score, combo_x, RunMan.launches_exhausted())
```
（其余 `$Hud.add_score(score)` / `RunMan.add_launch_score(score)` 等保持不变。）

- [ ] **Step 3: 验证场景加载** — 创建 `/tmp/combo_check.gd`：
```gdscript
extends SceneTree
func _init():
	var ps = load("res://scenes/board.tscn")
	if ps == null: print("SCENE_LOAD_FAIL"); quit(); return
	var inst = ps.instantiate()
	print("BOARD_OK" if inst != null else "INSTANTIATE_FAIL")
	if inst != null: inst.free()
	quit()
```
Run: `/d/Program/Godot/godot --headless --path . -s /tmp/combo_check.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
Expected: `BOARD_OK`，无 Parse Error / SCRIPT ERROR。然后 `rm -f /tmp/combo_check.gd`。

- [ ] **Step 4: 跑全套，确认无回归**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
Expected: All tests passed，总数 207 + 9 = **216**（T1 +6、T3 +3；T2 不增减）。

> 实机验收（用户人工）：本发撞越多、落定分越高且弹出 `COMBO ×N`；配额手感（平庸够、爆 combo 碾压）需试玩，必要时再调 `COMBO_RATE` / `quota_of` 基数。

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: inject combo xmult into settle + combo reveal in board_view"
```

---

## 自检清单

- [ ] **Spec 覆盖**：combo=pegs_hit→×倍率(T1) ✓；封顶 ×5 / 阈值 2(T1) ✓；落定前注入 MUL_MULT 走乘法链(T4) ✓；落定揭示 COMBO ×N + 缩放震(T3+T4) ✓；配额上调 + 测试更新(T2) ✓；纯函数/管线单测(T1) ✓；对 sim/settle 算法零侵入(全在注入层) ✓
- [ ] **占位符扫描**：无 TBD/TODO；每步给完整代码与确切期望 ✓
- [ ] **类型/签名一致性**：
  - `ComboScore.xmult_for(int)->float` 与常量 `COMBO_RATE/COMBO_CAP/COMBO_MIN_PEGS` —— T1 定义、T1 测试、T4 调用一致 ✓
  - `JuiceController.on_settle_combo(pos, score, combo_x, is_final_launch)` —— T3 定义、T3 测试、T4 调用签名一致 ✓
  - preload 名 `ComboScoreScript` 一致；`ScoreContext.KIND_MUL_MULT` 用法与现有一致 ✓
  - combo 基于 `_score_ctx.pegs_hit`（计分层），与视觉 `_combo` 不混用 ✓
- [ ] **范围**：仅 combo→计分 + 最小揭示 + 配额；完整 tally / 跨发射 combo / cascade 放大 / 平衡 pass / 豪赌机制 留 Backlog ✓

---

## 备注

- combo ×倍率是 `pegs_hit` 的确定函数，sim/settle 算法不变；除配额断言外现有测试保持绿。
- 揭示视觉（飘字/震）headless 测不了的部分交实机；飘字条数/trauma 可测，已覆盖。
- 配额 90、`COMBO_RATE 0.12`、`COMBO_CAP 5` 为首版数值，实机试玩后只需改对应 const/基数 + 同步配额断言。
