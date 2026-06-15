# 连击计分（Combo → ×倍率）设计文档

**日期：** 2026-06-15
**主题：** 把"本发命中数（combo）"接进计分——命中越多、×倍率越爆，并在落定时显著揭示，让局内核心循环产生滚雪球式爽感

---

## 目标

补上局内玩法最大的爽感漏点：**"疯狂刷击中"现在几乎不直接给分**。让本发命中的钉数（含连锁/炸弹连带）折算成一个 ×倍率，走进现有三段计分链，一发连撞一片 → 分数指数爆炸；并在落定时把 `COMBO ×N` 和放大的最终分数显著弹出，让爆发"看得见"。同步上调配额以匹配新的分数体量。

## 设计原则

- **复用现有计分管线**：combo 作为一个 `KIND_MUL_MULT` ledger 条目在落定前注入，自然走 `base × (1+mult_add) × ×mult`，不改 `ScoringEngine.settle` 的算法本身。
- **确定性不破坏**：combo ×倍率是 `pegs_hit` 的确定函数；sim 与计分确定性不变。
- **纯逻辑可测**：×倍率曲线、配额新值都是纯函数/纯数据，TDD 单测；揭示视觉实机确认。
- **首版数值 + 实机微调**：曲线系数与配额给出首版，明确标注需试玩调参。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript；项目根 `D:/NeonPinball/game/`。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**207 个测试全部通过，32 个脚本**。缩进用 TAB（`scoring/`、`run/`、`view/`、`juice/`、`tests/`）。

### 计分管线

- `scoring/score_context.gd`：`ledger`（`[{kind,value,source}]`）、`bounce_count`、`pegs_hit`、`add(kind,value,source)`、`clear_for_launch()`（每发清空 ledger 与计数）。
- `scoring/scoring_engine.gd`：`settle(ctx) -> [score, steps]`，`base × (1+mult_add) × Π(mul_mults)`；`steps` 记录每步来源/增量/running。
- `scoring/trigger_runtime.gd`：触发器按事件/条件往 ctx 加条目。
- `view/board_view.gd`：
  - PEG_HIT 处理：NORMAL→`_score_peg`（`pegs_hit += 1` + `add(ADD_BASE,...)`）；MULT→`pegs_hit += 1` + `add(ADD_MULT, mult_add)`；CHAIN→`_score_peg` + `_trigger_chain`（连带钉各 `_score_peg`，各 `pegs_hit += 1`）；BOMB→`_trigger_bomb`（半径内各 `_score_peg`）；JACKPOT→`_score_peg` + 随机 `add(ADD_MULT, 1..10)`；LIFE/POISON/MAGNET→`_score_peg`。
  - `_on_all_settled()`：`var result := _engine.settle(_score_ctx)`；`score := result[0]`；`_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())`；`$Hud.add_score(score)`；`RunMan.add_launch_score(score)`。
  - `_score_ctx.clear_for_launch()` 在 `launch()` 调用。
  - 视觉 `_combo`（PEG_HIT 事件计数，落地清零）已存在，**仅驱动音/光**，与本特性的"计分 combo（用 pegs_hit）"是不同层，互不影响。

### 配额

- `run/run_manager.gd` `quota_of(ante, round_in_ante)`：`ante_base = 50.0 * pow(1.6, ante-1)`；`mul = {0:1.0, 1:1.3, 2:1.8}`；返回 `roundf(ante_base * mul)`。
- `tests/test_run_manager.gd` 含配额断言（值会因本次调整而变，需同步更新）。

### Juice

- `juice/juice_controller.gd` `on_settle(pos, score, is_final_launch)`：飘字 `+N` + 屏震 0.2 + 最后一球慢动作。`floaters.add(pos, text)`。

---

## 系统组成

### 1. `scoring/combo_score.gd`（新建，纯逻辑）

**职责：** 本发命中数 → ×倍率。

```gdscript
class_name ComboScore extends RefCounted

const COMBO_RATE := 0.12      # 每命中一钉的 ×倍率增量
const COMBO_CAP := 5.0        # ×倍率封顶
const COMBO_MIN_PEGS := 2     # 低于此命中数不给 combo 加成

# 本发命中钉数 → ×倍率（与现有 ×mult 相乘）
static func xmult_for(pegs_hit: int) -> float:
	if pegs_hit < COMBO_MIN_PEGS:
		return 1.0
	return minf(1.0 + float(pegs_hit) * COMBO_RATE, COMBO_CAP)
```

- 示例：1→×1.0，2→×1.24，5→×1.6，10→×2.2，20→×3.4，30→×4.6，34+→×5 封顶。

### 2. `view/board_view.gd`（改动，注入 + 揭示）

`_on_all_settled()` 里，在 `_engine.settle(_score_ctx)` **之前**注入 combo ×倍率：
```gdscript
	var combo_pegs: int = _score_ctx.pegs_hit
	var combo_x: float = ComboScoreScript.xmult_for(combo_pegs)
	if combo_x > 1.0:
		_score_ctx.add(ScoreContext.KIND_MUL_MULT, combo_x, &"combo")
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
```
并把 combo 信息传给揭示（见下），随后照旧 `add_score` / `add_launch_score`。
- 预载：`const ComboScoreScript := preload("res://scoring/combo_score.gd")`。

### 3. `juice/juice_controller.gd`（改动，落定揭示）

把 `on_settle` 扩展为接收 combo 信息（或新增 `on_settle_combo`），实现"看得见的爆发"：
```gdscript
func on_settle_combo(pos: Vector2, score: float, combo_x: float, is_final_launch: bool) -> void:
	floaters.add(pos, "+%d" % int(score))
	if combo_x > 1.0:
		floaters.add(pos + Vector2(0, -28), "COMBO x%.1f" % combo_x)
	shake.add(minf(0.2 + (combo_x - 1.0) * 0.12, 0.6))   # 越爆震越强
	if is_final_launch and score > 0.0:
		slowmo.request(0.35, 0.25)
```
- `board_view._on_all_settled` 改调 `on_settle_combo(_last_settle_pos, score, combo_x, RunMan.launches_exhausted())`。
- 保留旧 `on_settle`（兼容/被现有测试引用），不删。

> 揭示走现有 `floaters`；最终分数飘字"放大/变色"用现有飘字加强即可（本期不做完整三段 tally，留 Backlog）。

### 4. `run/run_manager.gd`（改动，重平衡配额）

`quota_of` 基数 **50 → 90**（×1.8 首版）：
```gdscript
static func quota_of(ante: int, round_in_ante: int) -> float:
	var ante_base := 90.0 * pow(1.6, ante - 1)
	...
```
- **首版数值，最终靠试玩微调。** 让"平庸一发刚够、爆 combo 一发碾压"。
- 同步更新 `tests/test_run_manager.gd` 的配额期望值。

---

## 数据流

```
每发命中钉（含连锁/炸弹连带）→ ctx.pegs_hit 累加（已有）
落定 _on_all_settled:
   combo_x = ComboScore.xmult_for(ctx.pegs_hit)
   若 >1：ctx.add(MUL_MULT, combo_x, "combo")
   score = ScoringEngine.settle(ctx)        # combo 自然进乘法链
   on_settle_combo(pos, score, combo_x, ...)  # 揭示：+N、COMBO ×N、缩放震
   add_score / add_launch_score(score)        # 计入配额
```

combo ×倍率只读 `pegs_hit`，确定性、不改 settle 算法。

---

## 测试策略

新增/更新约 6~8 个测试，headless 可测（纯函数 + 计分管线），其余实机确认。

`tests/test_combo_score.gd`（新建）：
- `xmult_for(1) == 1.0`、`xmult_for(0) == 1.0`（低于阈值无加成）
- `xmult_for(2)` ≈ 1.24（阈值起点）
- 单调不降：`xmult_for(n+1) >= xmult_for(n)`（n 取 0..40）
- 封顶：`xmult_for(100) == 5.0`，且任意值 ≤ 5.0
- `xmult_for(10)` ≈ 2.2（中段抽检）

`tests/test_run_manager.gd`（更新）：
- 配额断言改为新基数 90 的期望值（如 ante1 round0 = 90，round1 = 117，round2 = 162；ante2 round0 = 144 …按 `roundf(90*1.6^(a-1)*mul)`）

计分管线（可并入 `tests/test_scoring_pipeline.gd` 或新测）：
- 给 ctx 加若干 base/mult + 一个 combo MUL_MULT，断言 `settle` 结果等于手算 `base×(1+mult_add)×combo_x×…`

揭示视觉（飘字/震缩放）：实机确认，不单测。

---

## 验收标准

- [ ] 本发命中越多，落定分数越高（×倍率随 pegs_hit 增长，封顶 ×5）
- [ ] combo ×倍率与现有 ×mult 触发器正确相乘（走同一乘法链）
- [ ] 落定显著弹出 `COMBO ×N` + 放大的 `+N`，越爆震越强
- [ ] 配额上调后：平庸一发约够、爆 combo 一发碾压（首版，待试玩调）
- [ ] `xmult_for` 纯函数全单测通过；配额断言更新通过；计分管线测试通过
- [ ] 无回归：物理、商店、关卡流程、击中反馈、霓虹（若已做）正常；除配额断言外现有测试保持绿
- [ ] 确定性不变：同样命中序列 → 同样分数

---

## 后期备用项（Backlog）

- 完整 Balatro 三段 tally（base→+mult→×mult 逐段动画 + 数字滚动 crescendo）
- combo 跨发射/跨整局累积（当前每发独立）
- 连锁 cascade 视觉放大（炸弹串烧整屏沸腾）
- combo ×倍率曲线/配额的试玩平衡 pass
- 风险/豪赌取舍机制（贪婪门、jackpot 钉簇、赌 modifier）

---

## 已知局限 / 留待后续

- 配额数值为盲调首版，必须实机试玩校准；调 `quota_of` 基数 + 同步测试即可。
- combo 用 `pegs_hit`（含连锁连带），与视觉 `_combo`（PEG_HIT 事件）是两套计数，分属计分层与表现层，互不影响——刻意如此。
- combo ×倍率与多个 ×mult 触发器叠乘可能在极端 build 下数值很大；封顶 ×5 限制 combo 自身贡献，整体仍可能很高（这正是"构筑爆发"的爽，属预期）。
- 揭示仅最小版（飘字 + 缩放震），完整 tally 留 Backlog。
