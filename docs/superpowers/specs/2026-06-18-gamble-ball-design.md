# 赌球：双倍或清零 设计文档（第二档 2.1 切片）

**日期：** 2026-06-18
**主题：** 给局内加"押注这球"的 double-or-nothing：逐球自选，押注的球落定得分 ×2（成功）或清零（失败），成功 = 这球命中钉数达阈值。每球一个"贪 vs 稳"的决策，与持久棋盘（越打越稀越险）强协同。

---

## 目标

局内 5 球目前是固定流程、缺资源/风险决策。本切片加**逐球可选的押注**：发射前按一下"押注"，这球就进入 double-or-nothing——成功 ×2、失败清零。成功条件是技巧门槛（命中足够多钉），配合持久棋盘逐发变稀，制造"早期密盘敢押、后期稀盘犹豫"的张力。第二档的其余（多球/存球、连击可存可赌）仍留 roadmap。

## 设计原则
- **自包含、零侵入 sim**：纯计分层 + UI；不改物理/确定性/连击曲线。
- **逐球决策**：每球独立押/不押，落定后重置（每球重新决定）。
- **赌注只限该球**：只 ×2/×0 这球的落定得分，不波及其它球或回合分。
- **纯逻辑可测**：成功判定 + 结算做纯静态函数 TDD。
- **与持久棋盘协同**：成功=命中钉数阈值 → 盘越稀越难成功，风险随回合自然上升。

---

## 现状（代码库事实，已核对）

- 基线 **266 测试全绿，38 脚本**。缩进 TAB。
- `view/board_view.gd`：
  - `launch(ball)`（407-435）：`_score_ctx.clear_for_launch()`、`_combo=0`、`_launch_count += 1` 等。
  - `_on_all_settled()`（594-616）：`combo_x = ComboScoreScript.xmult_for(_score_ctx.pegs_hit)`；`combo_x>1` 注入 `KIND_MUL_MULT`；`var result = _engine.settle(_score_ctx)`；`var score = result[0]`；`_live_target = score`；`_juice.on_settle_combo(_last_settle_pos, score, combo_x, exhausted)`；`_sfx.play_settle()`；`_combo=0`；`$Hud.add_score(score)`；`RunMan.add_launch_score(score)`；…
  - `_score_ctx.pegs_hit`：计分层命中计数（含 chain/bomb cascade，每次 +1），落定时即本球命中数。
  - `_juice.floaters.add(pos, text)`（见 `_play_all_clear`：`_juice.floaters.add(_last_hit_pos + Vector2(0,-40), "ALL CLEAR!")`）。
  - `_sync_hud()`（406+）：`$Hud.update_run_state(...)`。
- `view/input_controller.gd`：`_unhandled_input`（72-102）`match event.keycode` 在 ROUND/BOSS_ROUND 上下文处理 TAB/SPACE/1-4；SPACE 发射前判 `cur_phase ∈ {ROUND,BOSS_ROUND} and not _is_transitioning`。
- `view/hud.gd`：代码构建 Label（`_make_label(pos, size, color)`）；有 `_label_gate` 等；`update_run_state(...)` 刷新。

---

## 系统组成

### A. `scoring/gamble.gd`（新，纯静态可测）
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

### B. `view/board_view.gd`（押注状态 + 结算 + 切换）
- 新成员：`var _gamble_armed := false`（玩家发射前的选择）、`var _gamble_active := false`（本球是否押注，发射时锁定）。
- `const GambleScript := preload("res://scoring/gamble.gd")`。
- `func toggle_gamble()`：仅在可发射时有效——`if _has_ball or _is_transitioning: return`；`var phase = RunMan.state["phase"]; if phase not in {ROUND, BOSS_ROUND}: return`；`_gamble_armed = not _gamble_armed`；`$Hud.set_gamble_label(_gamble_armed)`。
- `launch()`：在发射初始化处加 `_gamble_active = _gamble_armed`；`_gamble_armed = false`（每球重新决定）；`$Hud.set_gamble_label(false)`。
- `_on_all_settled()`：在 `var score = result[0]` **之后、`_live_target = score` 之前**插入：
  ```gdscript
  if _gamble_active:
  	var won := GambleScript.is_success(_score_ctx.pegs_hit)
  	score = GambleScript.resolve(score, _score_ctx.pegs_hit)
  	_juice.floaters.add(_last_settle_pos + Vector2(0, -60), "GAMBLE ×2!" if won else "BUST  清零")
  	_gamble_active = false
  ```
  之后的 `_live_target`/`on_settle_combo`/`add_score`/`add_launch_score` 全部用调整后的 `score`，自然一致。
- 进入商店/胜负时确保 `_gamble_armed=false`、label 关（`_show_shop_ui`/相关清理处 `$Hud.set_gamble_label(false)`；plan 阶段核对放置点）。

### C. `view/hud.gd`（押注状态 label）
- 新成员 `var _label_gamble: Label`，`_ready` 里 `_make_label(...)` 创建（位置/颜色 plan 阶段定，建议放发球数 label 附近）。
- `func set_gamble_label(armed: bool) -> void`：armed → text "🎲 押注:开 ×2/0 [G]"、醒目色；否则 text "🎲 押注:关 [G]"、暗色。
- `_ready` 初始 `set_gamble_label(false)`。

### D. `view/input_controller.gd`（切换键）
- `_unhandled_input` 的 `match event.keycode` 加：
  ```gdscript
  KEY_G:
  	_board.toggle_gamble()
  ```
  （`toggle_gamble` 内部已自保护相位/飞行态，故此处直接调即可。）

---

## 数据流

```
发射前：按 G / 调 toggle_gamble() → _gamble_armed 翻转（仅 ROUND 且无球时）→ HUD label 显示
launch()：_gamble_active = _gamble_armed；_gamble_armed = false（本球锁定、下球重选）
飞行：照常（_score_ctx.pegs_hit 累计）
_on_all_settled()：算 score（含连击）→ 若 _gamble_active：score = Gamble.resolve(score, pegs_hit)（成功×2/失败0）+ 飘字 → 其余照常用 score
```

成功条件随持久棋盘变稀而变难 → 风险随回合上升。

---

## 测试策略

- **纯函数（TDD）** `tests/test_gamble.gd`：
  - `is_success`：`GAMBLE_MIN_PEGS-1`→false、`GAMBLE_MIN_PEGS`→true、更多→true、0→false。
  - `resolve`：成功 `base*2`、失败 `0`、边界（恰好阈值→×2）、base=0 成功仍 0。
- **board_view/hud/input**：场景冒烟（board.tscn load+instantiate）+ 实机（view 层无单测，项目惯例）。

---

## 验收标准

- [ ] 发射前可按 G（或后续按钮）切换"押注"，HUD 显示开/关状态，每球落定后自动重置为关
- [ ] 押注的球：命中钉数 ≥ 阈值 → 落定得分 ×2 + "GAMBLE ×2!" 飘字；否则清零 + "BUST" 飘字
- [ ] 不押注的球行为完全不变
- [ ] 赌注只影响该球得分，不波及其它球/回合分/连击曲线
- [ ] 飞行/商店/胜负态下押注状态正确（不能飞行中改、进商店清零）
- [ ] `gamble.gd` 纯函数全单测通过；全套绿（~270）
- [ ] 无回归：物理/计分/连击/确定性正常；board 场景冒烟 OK

---

## Backlog / 留待后续
- 押注做成 HUD 按钮（更显眼）+ 相位自动隐藏。
- 飞行中 ticker 显示"×2 待定"潜在值。
- 押注成功/失败专属音效 + 更强反馈。
- 成功条件可改为"分数阈值"或"随盘上钉数比例"（若 peg-count 阈值实机手感不好）。
- 限制每回合押注次数（若"总是押"成最优）。

---

## 已知风险 / 留意
- **`GAMBLE_MIN_PEGS` 是核心手感旋钮**：太低→几乎稳赢（押注变白送 ×2、无决策）；太高→几乎必输（没人押）。默认 6 是猜测值，**必须实机调**到约 50/50 体感。记 `balance-tunables.md`。
- 与持久棋盘连击量级一并实机：押注 ×2 叠在已含连击的分上，可能很swingy（清零一个高连击球是强烈挫败=预期张力）。
- 成功用 `_score_ctx.pegs_hit`（含 cascade），与连击同源、一致。
