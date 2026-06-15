# 目标钉 / 每轮目标感设计文档

**日期：** 2026-06-15
**主题：** 给每轮一个看得见、打得掉的目标——金色目标钉（带 HP、跨发射持久），清光锁定过关并触发高潮（回合仍发完，不提前结束），与配额双路并存，提升局内目标感

---

## 目标

补上局内最大的目标感缺口：现在每轮唯一目标是"攒分够一个配额数字"，缺少"清掉它"的成就感。引入每轮一批**目标钉**作为明确任务：打掉它们是具体赢条件之一，清光触发"ALL CLEAR"高潮 + 奖励。让每轮从"攒数字"变成"有目标、有进度、有高潮"。

## 设计原则

- **双路过关**：清光目标钉 **或** 够配额，任一即过关——既给明确目标，又保留配额保底，与 combo 计分/配额计划兼容。
- **目标钉持久、填充钉重生**：目标钉跨本轮 5 发存在（打掉才消），普通填充钉仍每发重生（保留现有"每发换新棋盘"的设计）。
- **HP 可调、不锁死**：目标钉有 HP，命中扣 1、跨发射保留、钉上显示。HP=1 即退化为"一击清"——数值全在纯函数里，试玩随时调。
- **纯逻辑可测**：目标钉数量/HP 曲线、RunManager 双路赢条件都是纯函数/纯逻辑，TDD 单测；钉视觉/HUD/高潮实机确认。
- **对确定性 sim 零侵入**：目标钉的选定用确定性 RNG；清除/HP 是 view 层状态 + RunManager 状态，不改物理。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript；项目根 `D:/NeonPinball/game/`。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 基线：**207 测试全绿，32 脚本**（注：combo 计分计划已写未实现，配额仍 50 基数）。缩进 TAB。
- `run/run_manager.gd`：
  - `state` 含 `ante`、`round_in_ante`、`round_score`、`quota`、`launches_left`、`money`、`boss_mod` 等。`_make_default_state()` 与 `state` 字段必须同步（`_ready` 有 assert 校验）。
  - `advance()` 在 `ROUND/BOSS_ROUND`：`if round_score >= quota: phase=ANTE_CLEAR else phase=RUN_LOSE`。
  - `_start_round()`：`round_score=0`、`launches_left=5`、`quota=quota_of(...)`、设/清 `boss_mod`。
  - `_payout()`：`money += (3+ante) + launches_left + min(money/5,5)`。
  - `quota_of(ante, round)` 静态。
- `view/board_view.gd`：
  - 钉生成 `_generate_pegs()`（每发随机），新轮入口：`_ready()`（首轮）、`leave_shop()`（商店后新轮）；发间重生：`_on_all_settled()` 未发完 → `_start_peg_transition()` → `_on_peg_exit_done()` 重新 `_generate_pegs()`。
  - `_on_all_settled()`：结算分 → `_juice.on_settle(...)` → `$Hud.add_score` / `RunMan.add_launch_score` → 若 `launches_exhausted()` 则 `RunMan.advance()` + `_handle_phase_transition()`，否则 `_start_peg_transition()`。
  - PEG_HIT 处理含各钉行为分支（见计分文档）。钉是 Dictionary（`id/pos/radius/type/base_score` 等）。
  - `_juice`（JuiceController：`shake`/`slowmo`/`floaters`）。
- `view/hud.gd`：`update_run_state(ante, round_in_ante, quota, money, launches_left, round_score)` 显示局内数值。

---

## 系统组成

### 1. `run/round_goal.gd`（新建，纯逻辑）

**职责：** 每轮目标钉数量与 HP 曲线。

```gdscript
class_name RoundGoal extends RefCounted

# 每轮目标钉数量（随区轻微增长，封顶 6）
static func target_count_for(ante: int) -> int:
	return clampi(3 + (ante - 1) / 2, 3, 6)

# 每个目标钉 HP（随区轻微增长，封顶 3；HP=1 即一击清）
static func target_hp_for(ante: int) -> int:
	return clampi(2 + (ante - 1) / 3, 2, 3)
```
- `target_count_for`：区1→3，区3→4，区5→5，区7→6。
- `target_hp_for`：区1~3→2，区4~8→3。

### 2. `run/run_manager.gd`（改动，双路赢条件 + 状态）

- `state` 与 `_make_default_state()` 同步新增：`&"targets_done": false`。
- `_start_round()` 末尾：`state[&"targets_done"] = false`（每轮重置）。
- `advance()` 的 `ROUND/BOSS_ROUND` 分支改为：
  ```gdscript
  if state[&"targets_done"] or state[&"round_score"] >= state[&"quota"]:
      state[&"phase"] = Phase.ANTE_CLEAR
  else:
      state[&"phase"] = Phase.RUN_LOSE
  ```
- 清光奖励：`_payout()` 中按 `targets_done` 加奖励，例如 `if state[&"targets_done"]: reward += 5`（额外金钱）。

### 3. `view/board_view.gd`（改动，目标钉生成/持久/HP/全清）

- **新轮生成目标钉**（在 `_ready()` 首轮、`leave_shop()` 新轮）：用确定性 RNG 选 `RoundGoal.target_count_for(ante)` 个位置，建目标钉（标 `is_target=true`、`hp=RoundGoal.target_hp_for(ante)`、金色），存入持久集合 `_target_pegs`。
- **持久**：`_on_peg_exit_done()` 重生填充钉时，把未清的目标钉并入棋盘（不参与填充钉的消失/重生动画）。即 `_pegs = 填充钉 + 存活目标钉`。
- **命中**：直接球命中、**炸弹、连锁**命中目标钉均 → `hp -= 1` + 命中确认（闪光/音）；`hp <= 0` 时清除该目标钉、从 `_target_pegs` 移除、刷新 HUD 计数；并计分（目标钉也给 base 分）。（用户 2026-06-15 定：cascade 也伤目标，统一走 `_damage_target` 助手。）
- **全清检测 + 高潮（不提前过关）**：清除后若 `_target_pegs` 为空 → `RunMan.state[&"targets_done"] = true`，并**立即**播 ALL CLEAR 高潮（`_play_all_clear()`：慢动作 + "ALL CLEAR!" 飘字 + 庆祝）。**回合不结束**——继续发完剩余球（可继续刷分/combo）。
- **`_on_all_settled` 不为 targets_done 单独改动**：仍是现有流程——`launches_exhausted()` → `RunMan.advance()`（赢条件已含 `targets_done`，见 §2）+ `_handle_phase_transition()`；否则 `_start_peg_transition()`。即回合照常发完 5 球，结束时凭 `targets_done 或 够配额` 判胜负。
- 清光奖励金钱在 `_payout()` 按 `targets_done` 发放（回合结束 ANTE_CLEAR 时）。
- 目标钉绘制：金色 + 脉冲 + 钉上显示剩余 HP（`draw_string` 数字）。

### 4. `view/hud.gd`（改动，目标计数器）

- `update_run_state` 增参或新方法显示 `目标 X/K`（已清/总数）。board_view 在生成/清除目标钉时刷新。

---

## 数据流

```
新轮（_ready/leave_shop）：
   选 K=target_count_for(ante) 个目标钉，各 hp=target_hp_for(ante)，存 _target_pegs（持久）
每发：_generate_pegs() 填充钉 + 并入存活 _target_pegs
命中目标钉：hp -= 1；hp<=0 → 移除 + 刷新 HUD；_target_pegs 空 → targets_done=true + 立即 ALL CLEAR 高潮（回合不结束）
落定 _on_all_settled（不为 targets_done 改动）：
   launches_exhausted → advance（赢条件 = targets_done 或 够配额；ANTE_CLEAR 时 _payout 按 targets_done 给奖励）
   else → 下一发
```

RunManager 赢条件 = `targets_done or round_score >= quota`（双路）。

---

## 测试策略

新增约 8 个测试（纯函数 + RunManager 逻辑），headless 可测；钉视觉/HUD/高潮实机确认。

`tests/test_round_goal.gd`（新建）：
- `target_count_for(1)==3`、`(3)==4`、`(5)==5`、`(7)==6`；单调不降；封顶 6
- `target_hp_for(1)==2`、`(4)==3`；单调不降；封顶 3

`tests/test_run_manager.gd`（更新/新增）：
- 双路-清光：`round_score < quota` 但 `targets_done=true` → advance 后 `phase==ANTE_CLEAR`
- 双路-配额：`targets_done=false` 且 `round_score >= quota` → `ANTE_CLEAR`（原行为不变）
- 双路-皆不满足：`targets_done=false` 且 `round_score < quota` → `RUN_LOSE`
- `_start_round` 重置 `targets_done=false`
- 清光奖励：`targets_done=true` 时 `_payout` 多给 5（与基础公式对比）
- `_make_default_state` 与 `state` 含 `targets_done`（hash 校验通过，不破坏 `_ready` assert）

board_view 目标钉持久/HP/全清、HUD 计数、ALL CLEAR 高潮：实机确认（场景脚本无单测，与现有一致）。

---

## 验收标准

- [ ] 每轮开局有 K 个金色目标钉，和普通钉一眼区分，钉上显示剩余 HP
- [ ] 目标钉跨本轮 5 发持续存在；填充钉仍每发重生
- [ ] 命中目标钉扣 1 HP（跨发射保留），扣完才消失
- [ ] 清光所有目标钉 → ALL CLEAR 高潮 + 标记 targets_done（回合不提前结束，照常发完 5 球）；发完时凭 targets_done 过关 + 额外金钱
- [ ] 没清光但够配额 → 照旧过关（双路保底）；皆不满足 → RUN_LOSE
- [ ] HUD 显示 `目标 X/K`
- [ ] `target_count_for`/`target_hp_for` 纯函数 + RunManager 双路逻辑全单测通过；现有测试除受影响项外保持绿
- [ ] 确定性不破坏：目标钉选定用确定性 RNG

---

## 后期备用项（Backlog）

- 混合硬目标（少数高 HP 目标钉，尤其 Boss 轮）
- 可选挑战目标（N 球内清光、零失球等）给额外奖励
- 目标钉种类（移动目标、护盾目标）
- 清光连击与 combo 计分联动（清光时 combo 加成）
- 整局路线图（run map）/ 配额进度条（另两个目标感层面，本期未做）

---

## 已知局限 / 留待后续

- "目标钉持久 + 填充钉重生"打破了当前"每发全部重生"，是本特性最主要的改动量；需保证目标钉不被卷入填充钉的消失/重生动画。
- HP 数值（2~3）、目标钉数（3~6）、奖励（+5）为首版，待试玩调；调对应 const 即可（HP=1 退化为一击清）。
- 清光**不提前结束回合**（用户 2026-06-15 定）：清光即给 ALL CLEAR 高潮 + 标记 `targets_done`，但仍发完 5 球——回合长度恒定、不突兀，且清光后可继续刷分/combo。胜负在发完时按 `targets_done 或 够配额` 判定。ALL CLEAR 高潮在命中清光的那一刻触发（仅 juice 慢动作/飘字，不切场景）。
- 目标钉的 HP/清除是 view 层 + `state.targets_done`，不持久化存档、不影响确定性回放。
