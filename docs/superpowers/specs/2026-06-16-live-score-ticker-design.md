# 飞行中实时分数 Ticker 设计文档

**日期：** 2026-06-16
**主题：** 飞行中显示"本发实时总分"——棋盘上方居中一个大数字，随撞钉 count-up 上涨、撞 mult 钉跳一下，落定时 combo ×N 再猛跳，补上"赌注垒高"的张力

---

## 目标

补上局内可读性/张力漏点：分数现在憋到落定才出现一个数字，飞行过程没有"赌注实时垒高"的紧张。本期在棋盘上方居中显示**本发实时总分**（对当前 ledger 跑 `ScoringEngine.settle`），数字平滑 count-up 上涨、撞 mult 钉/触发器时跳升 punch，落定时 combo ×倍率注入让数字滚到最终值（接上已有的 `COMBO ×N` 揭示）。与 #1 连击计分天然搭。

## 设计原则

- **复用现有计分**：实时值 = `ScoringEngine.settle(_score_ctx)[0]`，不改计分算法。
- **对 sim/确定性零侵入**：纯 view 层 + 一个纯逻辑 ticker；sim 不变，现有 227 测试不受影响。
- **count-up 与 punch 可测**：逼近/跳升检测/衰减都是纯逻辑，放进可单测的 `ScoreTicker`；绘制实机确认。
- **与 combo 揭示衔接**：combo ×N 落定才注入，飞行中数字爬升、落定再猛跳，形成自然升级。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript；项目根 `D:/NeonPinball/game/`。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 基线：**227 测试全绿，34 脚本**。缩进 TAB。
- `scoring/scoring_engine.gd`：`settle(ctx) -> [score, steps]`，`score = base × (1+mult_add) × Π(mul_mults)`。纯函数、可随时调用。
- `view/board_view.gd`：
  - `_score_ctx`（ScoreContext）飞行中累积；`launch()` 里 `clear_for_launch()` 清空。
  - PEG_HIT 事件处理往 ledger 加 base/mult；触发器在事件上 fire。
  - **combo ×倍率在 `_on_all_settled()` 里、`settle` 之前注入**（`KIND_MUL_MULT`）——飞行中 ledger 不含 combo。
  - `_process(delta)`：有一段"不依赖 `_has_ball`"的计时区（`_combo_display_ttl`、`_all_clear_ttl` 递减 + `_juice.update`）；球在飞时在 `if _has_ball:` 里步进 sim、处理事件。
  - `_draw()`：已有 combo "×N" 数字、ALL CLEAR 大字、飘字等，末尾 `_draw_walls()`。
  - `_rect = Rect2(135, 225, 540, 900)`，局部中心 x=270；钉阵从局部 y≈124 起（margin+80），顶部 y<124 区域空着可放大数字。
  - `_last_settle_pos`、`_juice`（floaters/shake/slowmo）等已有。
- HUD `_label_total` 显示**累计 round_score**（落定才经 `RunMan.add_launch_score` 入账）——本特性的"本发实时分"是独立的、画在棋盘上的，不动 HUD 总分。

---

## 系统组成

### 1. `juice/score_ticker.gd`（新建，纯逻辑，可单测）

**职责：** 持有显示值/目标值，朝目标平滑逼近 + 检测跳升触发 punch + punch 随时间衰减。

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

### 2. `view/board_view.gd`（改动，接线 + 绘制）

- 预载 `const ScoreTickerScript := preload("res://juice/score_ticker.gd")`；状态 `var _score_ticker`（`_ready` 里 `new()`）。
- `launch()`：`_score_ticker.reset()`（本发归零重涨）。
- `_process(delta)`：
  - 球在飞时（`if _has_ball:` 段内，或紧随其后）算目标：`var live: float = _engine.settle(_score_ctx)[0]`；
  - 在**不依赖 `_has_ball`** 的计时区调用 `_score_ticker.update(live_or_lasttarget, delta)`，使 count-up 在落定后仍滚完。实现：维护 `var _live_target := 0.0`，`if _has_ball: _live_target = _engine.settle(_score_ctx)[0]`，然后无条件 `_score_ticker.update(_live_target, delta)`。
- `_on_all_settled()`：combo 注入 + `settle` 得最终分后，`_live_target = score`（让 ticker 滚到含 combo 的最终值）。
- `launch()` 同时 `_live_target = 0.0`。
- `_draw()`：在棋盘上方居中画大数字：
  ```gdscript
  var sv := int(round(_score_ticker.value()))
  if sv > 0:
      var f := ThemeDB.fallback_font
      var sc := _score_ticker.punch_scale()
      var fsize := int(40 * sc)
      var txt := str(sv)
      # 居中于 _rect 顶部上方（局部 x=270, y≈48）
      draw_string(f, _rect.position + Vector2(270 - txt.length() * fsize * 0.28, 60),
          txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1))
  ```
  （居中按字宽估算偏移；punch 时字号放大。）

> 复用现有 `ScoringEngine`，不改计分；ticker 是 view 表现，不入存档、不影响确定性回放。

---

## 数据流

```
launch()：_score_ticker.reset()；_live_target = 0
飞行中每帧：_live_target = settle(_score_ctx)[0]      # base×已触发倍率
每帧（无论是否有球）：_score_ticker.update(_live_target, delta)  # count-up + punch
撞 mult 钉/触发器 → live 跳升 → ticker punch（缩放弹一下）
落定 _on_all_settled：combo 注入 → settle → _live_target = 最终分 → 数字滚到位（combo 大跳）
_draw()：棋盘上方居中画 ticker.value() 大数字 × punch 缩放
下一次 launch() 归零重涨
```

---

## 测试策略

新增约 5 个测试（纯 ScoreTicker），headless 可测；绘制/位置实机确认。

`tests/test_score_ticker.gd`：
- **逼近**：`reset` 后多次 `update(100, 1/60)`，`value()` 单调上升且趋近 100；足够多次后 `value() == 100`（收敛）。
- **收敛吸附**：差 <0.5 时吸附为 target（不残留抖动）。
- **跳升 punch**：从 0 `update(10, dt)`（小、不 punch：10<JUMP_MIN 20）→ `punch_scale()≈1.0`；再 `update(300, dt)`（大跳）→ `punch_scale() > 1.0`。
- **punch 衰减**：大跳后持续 `update(同值, dt)` 超过 `PUNCH_DUR` → `punch_scale()` 回到 ~1.0。
- **小增量不 punch**：`update(200,dt)` 收敛后 `update(210,dt)`（+10 < JUMP_MIN）→ 不触发 punch。
- **reset**：归零 display/target/punch。

board_view 绘制/接线：场景加载检查 + 实机确认（view 层无单测，与现有一致）。

---

## 验收标准

- [ ] 飞行中棋盘上方居中显示本发实时总分，随撞钉平滑 count-up 上涨
- [ ] 撞 mult 钉 / 触发 big_hit 等大跳时数字缩放 punch 一下；普通钉小增量不 punch
- [ ] 落定时 combo ×N 注入，数字滚到最终值（与本发实际入账一致），接上 COMBO 揭示
- [ ] 下一次发射归零重涨
- [ ] `ScoreTicker` 纯函数全单测通过；232 左右全绿
- [ ] 无回归：物理、计分、商店、关卡流程、combo/目标钉正常；确定性不变

---

## 后期备用项（Backlog）

- 实时分数颜色随热度/combo 变（青→烫）
- ticker count-up 音效（滴答/上行音）
- HUD 累计总分也实时滚（本发入账时平滑滚动）
- 大跳时额外粒子/闪光

---

## 已知局限 / 留待后续

- 实时值飞行中**不含 combo ×倍率**（combo 落定才注入）——这是刻意的升级感（落定再跳）；玩家看到的飞行值会比最终值小一截。
- 每帧 `settle` 重算：ledger 数十条目、settle 三趟遍历，开销可忽略。
- 大数字居中按字宽估算偏移（无精确测宽）；实机微调偏移系数即可。
- 数值（APPROACH/JUMP/PUNCH、字号、位置）首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
