# 目标钉 / 每轮目标感 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每轮指定 K 个金色目标钉（带 HP、跨本轮 5 发持久），清光它们 = ALL CLEAR 高潮 + 锁定过关（不提前结束回合）；与配额双路并存（清光 或 够配额，发完时判定）。

**Architecture:** 纯曲线放 `run/round_goal.gd`（可测）；RunManager 加 `targets_done` 赢条件（可测）；board_view 维护持久 `_target_pegs`，每发把"填充钉 + 存活目标钉"合成为 `_pegs` 并按下标重排 id，目标钉只被**直接命中**扣 HP（连锁/炸弹跳过），全清触发 ALL CLEAR；HUD 加 `目标 X/K`。对确定性 sim 零侵入。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## 关键决策（已定）

**D1 — 目标钉可被直接命中、炸弹、连锁伤害（每次 −1 HP，扣完才消）。**（用户 2026-06-15 定）统一走 `_damage_target(peg) -> bool` 助手：扣 1 HP + 计分，hp≤0 时从 `_target_pegs` 移除并检测全清，返回"是否被摧毁"。三个调用方各自安全地处理 `_pegs` 移除（炸弹/连锁"先收集后删除"，避免迭代中改数组）。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
  （`godot` 不在 PATH；单文件 `-gselect=<file>`。）
- 基线：**217 测试全绿，33 脚本**。缩进 TAB。每任务只提交自己的文件。**不要 push**。**不要新建分支**（main）。
- `run/run_manager.gd`：
  - `state` 字面量 与 `_make_default_state()` 必须字段一致（`_ready` 有 `assert(state.hash() == _make_default_state().hash())`）。
  - `advance()` 在 `Phase.ROUND, Phase.BOSS_ROUND`：`if state[&"round_score"] >= state[&"quota"]: state[&"phase"] = Phase.ANTE_CLEAR else: state[&"phase"] = Phase.RUN_LOSE`。
  - `_start_round()`：设 `round_score=0`、`launches_left=5`、`quota`、boss_mod。
  - `_payout()`：`var base_reward := 3 + state[&"ante"]`；`var launch_bonus := state[&"launches_left"]`；`var interest := mini(state[&"money"]/5, 5)`；`state[&"money"] += base_reward + launch_bonus + interest`。
- `view/board_view.gd`：
  - 顶部已有 `const RunManagerScript`, `SaveSystemScript`, `JuiceControllerScript`, `ComboScoreScript`, `SfxControllerScript`, `COMBO_DISPLAY_DUR`。
  - `_generate_pegs() -> Array`：每发随机填充钉；钉 dict `{id,pos,radius,base_score,type,frozen,poisoned}`，`id == 数组下标`。放置区 `area`、拒绝采样最小间距 18、半径 10~20。
  - `_ready()`：`_pegs = _generate_pegs()`（首轮）。
  - `_on_peg_exit_done()`：发间重生 `_pegs = _generate_pegs()`。
  - `leave_shop()`：商店后新轮 `_pegs = _generate_pegs()`。
  - PEG_HIT 处理（约 399 行起）：`var hit_peg := _pegs[hit_peg_id]`，按 `hit_type.behavior` match；一次性钉用 `_pegs.erase(hit_peg); _sim = _make_sim(_pegs); _rebuild_wall_segs(_gate_applied); _events.resize(_event_cursor + 1)`。
  - `_score_peg(peg)`：加 base 分 + `pegs_hit += 1` + flash。
  - `_trigger_bomb(bomb_peg)` / `_trigger_chain(chain_peg)`：遍历 `_pegs` 半径内 `_score_peg`（bomb 还 erase）。
  - `_on_all_settled()`：结算 → `launches_exhausted()` ? `RunMan.advance()` + `_handle_phase_transition()` : `_start_peg_transition()`。
  - `_juice`（JuiceController：`slowmo.request`、`floaters.add`、`shake.add`）。`DeterministicRng.derive(seed, tag)` 可用。
- `view/hud.gd`：成员 `_label_*`；`_make_label(pos, size, color)`；`update_run_state(ante, round_in_ante, quota, money, launches_left, round_score)`。右侧标签在 x=490，y=20/44/68/92。

---

## 文件结构

**新建：** `run/round_goal.gd`（纯曲线）、`tests/test_round_goal.gd`
**修改：** `run/run_manager.gd`（+ targets_done 逻辑）、`tests/test_run_manager.gd`（+ 双路/奖励测试）、`view/board_view.gd`（目标钉系统）、`view/hud.gd`（目标计数器）

---

## Task 1：RoundGoal 曲线

**Files:** Create `run/round_goal.gd`; Test `tests/test_round_goal.gd`

- [ ] **Step 1: 写失败测试** `tests/test_round_goal.gd`（TAB 缩进）

```gdscript
extends GutTest

const RoundGoalScript := preload("res://run/round_goal.gd")

func test_target_count_curve() -> void:
	assert_eq(RoundGoalScript.target_count_for(1), 3, "区1 → 3")
	assert_eq(RoundGoalScript.target_count_for(3), 4, "区3 → 4")
	assert_eq(RoundGoalScript.target_count_for(5), 5, "区5 → 5")
	assert_eq(RoundGoalScript.target_count_for(7), 6, "区7 → 6")

func test_target_count_monotonic_and_capped() -> void:
	for a in range(1, 12):
		assert_true(RoundGoalScript.target_count_for(a + 1) >= RoundGoalScript.target_count_for(a),
			"数量单调不降 @%d" % a)
	assert_eq(RoundGoalScript.target_count_for(20), 6, "封顶 6")

func test_target_hp_curve() -> void:
	assert_eq(RoundGoalScript.target_hp_for(1), 2, "区1 HP2")
	assert_eq(RoundGoalScript.target_hp_for(3), 2, "区3 HP2")
	assert_eq(RoundGoalScript.target_hp_for(4), 3, "区4 HP3")

func test_target_hp_monotonic_and_capped() -> void:
	for a in range(1, 12):
		assert_true(RoundGoalScript.target_hp_for(a + 1) >= RoundGoalScript.target_hp_for(a),
			"HP 单调不降 @%d" % a)
	assert_eq(RoundGoalScript.target_hp_for(20), 3, "封顶 3")
```

- [ ] **Step 2: 运行确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_round_goal.gd -gexit`

- [ ] **Step 3: 实现** `run/round_goal.gd`（TAB 缩进）

```gdscript
class_name RoundGoal extends RefCounted

# 每轮目标钉数量（随区轻微增长，封顶 6）
static func target_count_for(ante: int) -> int:
	return clampi(3 + (ante - 1) / 2, 3, 6)

# 每个目标钉 HP（随区轻微增长，封顶 3；HP=1 即一击清）
static func target_hp_for(ante: int) -> int:
	return clampi(2 + (ante - 1) / 3, 2, 3)
```

- [ ] **Step 4: 运行确认通过**（4/4）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add run/round_goal.gd tests/test_round_goal.gd
git -C D:/NeonPinball/game commit -m "feat: RoundGoal — per-ante target count + HP curves"
```

---

## Task 2：RunManager 双路赢条件 + 奖励

**Files:** Modify `run/run_manager.gd`, `tests/test_run_manager.gd`

- [ ] **Step 1: 写失败测试** — 追加到 `tests/test_run_manager.gd` 末尾（TAB 缩进；文件已有 `const RunManagerScript := preload("res://run/run_manager.gd")`）

```gdscript
func test_targets_done_wins_below_quota() -> void:
	var mgr := RunManagerScript.new()
	mgr.advance(); mgr.advance()   # → ROUND
	mgr.state[&"round_score"] = 0.0
	mgr.state[&"targets_done"] = true
	mgr.advance()
	assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ANTE_CLEAR, "清光即使没够配额也过关")
	mgr.free()

func test_quota_still_wins_without_targets() -> void:
	var mgr := RunManagerScript.new()
	mgr.advance(); mgr.advance()
	mgr.state[&"round_score"] = 9999.0
	mgr.state[&"targets_done"] = false
	mgr.advance()
	assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.ANTE_CLEAR, "够配额过关（原行为）")
	mgr.free()

func test_neither_loses() -> void:
	var mgr := RunManagerScript.new()
	mgr.advance(); mgr.advance()
	mgr.state[&"round_score"] = 0.0
	mgr.state[&"targets_done"] = false
	mgr.advance()
	assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.RUN_LOSE, "皆不满足 → 输")
	mgr.free()

func test_start_round_resets_targets_done() -> void:
	var mgr := RunManagerScript.new()
	mgr.advance(); mgr.advance()
	mgr.state[&"targets_done"] = true
	mgr.state[&"round_score"] = 9999.0
	mgr.advance()   # ROUND → ANTE_CLEAR
	mgr.advance()   # ANTE_CLEAR → SHOP (round_in_ante +1)
	mgr.advance()   # SHOP → ROUND (_start_round)
	assert_false(mgr.state[&"targets_done"], "新轮重置 targets_done")
	mgr.free()

func test_payout_targets_bonus() -> void:
	var mgr := RunManagerScript.new()
	mgr.advance(); mgr.advance()
	mgr.state[&"money"] = 0
	mgr.state[&"launches_left"] = 0
	mgr.state[&"targets_done"] = true
	mgr.state[&"round_score"] = 9999.0
	mgr.advance()   # ROUND → ANTE_CLEAR
	mgr.advance()   # ANTE_CLEAR → _payout + SHOP
	# base_reward(3+1=4) + launch_bonus(0) + interest(0) + targets_bonus(5) = 9
	assert_eq(mgr.state[&"money"], 9, "清光额外 +5")
	mgr.free()
```

- [ ] **Step 2: 运行确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_run_manager.gd -gexit`

- [ ] **Step 3: 改 `run/run_manager.gd`**

(a) `state` 字面量里加字段（在 `&"boss_mod": {},` 同级，例如其后）：
```gdscript
	&"targets_done":        false,
```
(b) `_make_default_state()` 返回的字典里加**完全相同**的一行（保证 hash 一致）：
```gdscript
		&"targets_done":        false,
```
(c) `advance()` 的 `Phase.ROUND, Phase.BOSS_ROUND` 分支，把：
```gdscript
			if state[&"round_score"] >= state[&"quota"]:
				state[&"phase"] = Phase.ANTE_CLEAR
			else:
				state[&"phase"] = Phase.RUN_LOSE
```
改为：
```gdscript
			if state[&"targets_done"] or state[&"round_score"] >= state[&"quota"]:
				state[&"phase"] = Phase.ANTE_CLEAR
			else:
				state[&"phase"] = Phase.RUN_LOSE
```
(d) `_start_round()` 末尾加：
```gdscript
	state[&"targets_done"] = false
```
(e) `_payout()` 在 `state[&"money"] += ...` 之前加奖励项，把：
```gdscript
	state[&"money"] += base_reward + launch_bonus + interest
```
改为：
```gdscript
	var targets_bonus: int = 5 if state[&"targets_done"] else 0
	state[&"money"] += base_reward + launch_bonus + interest + targets_bonus
```

- [ ] **Step 4: 运行确认通过**（全部，含新 5 个；原有 quota/payout 测试不受影响——它们 targets_done 默认 false）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add run/run_manager.gd tests/test_run_manager.gd
git -C D:/NeonPinball/game commit -m "feat: RunManager two-path win (targets_done or quota) + clear bonus"
```

---

## Task 3：board_view 目标钉系统（生成/持久/HP/全清）

**Files:** Modify `view/board_view.gd`

> 无单测；靠场景加载检查 + 全套保持绿 + 实机确认。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 预载 + 状态**
顶部 const 区，找到 `const ComboScoreScript := preload("res://scoring/combo_score.gd")`，其后加：
```gdscript
const RoundGoalScript := preload("res://run/round_goal.gd")
const ALL_CLEAR_DUR := 0.5
```
状态 var 区，找到 `var _sfx`，其后加：
```gdscript
var _target_pegs: Array = []        # 跨本轮持久的目标钉 dict（含 hp/is_target）
var _all_clear_ttl := 0.0           # ALL CLEAR 飘字计时
```

- [ ] **Step 2: 填充钉避开目标位置** — 修改 `_generate_pegs()`，让它接受要避开的位置。
把函数签名：
```gdscript
func _generate_pegs() -> Array:
```
改为：
```gdscript
func _generate_pegs(avoid_pos: Array = []) -> Array:
```
并在拒绝采样的 `too_close` 检查处，把：
```gdscript
			var too_close := false
			for j in placed_pos.size():
				if pos.distance_to(placed_pos[j]) < r + placed_rad[j] + 18.0:
					too_close = true; break
```
改为（追加对 avoid_pos 的检查）：
```gdscript
			var too_close := false
			for j in placed_pos.size():
				if pos.distance_to(placed_pos[j]) < r + placed_rad[j] + 18.0:
					too_close = true; break
			if not too_close:
				for ap in avoid_pos:
					if pos.distance_to(ap) < r + 24.0 + 18.0:
						too_close = true; break
```

- [ ] **Step 3: 目标钉生成 + 合成助手** — 在 `_generate_pegs()` 函数定义**之后**插入：
```gdscript
# 每轮生成一次的持久目标钉（金色、带 HP）。确定性 RNG。
func _generate_target_pegs() -> Array:
	var ante: int = RunMan.state[&"ante"]
	var k := RoundGoalScript.target_count_for(ante)
	var hp := RoundGoalScript.target_hp_for(ante)
	var rng := DeterministicRng.derive(int(RunMan.state[&"master_seed"]),
		ante * 131 + int(RunMan.state[&"round_in_ante"]) * 17 + 1009)
	var margin := 44.0
	var area := Rect2(
		_rect.position.x + margin,
		_rect.position.y + margin + 80.0,
		_rect.size.x - margin * 2.0,
		780.0 - margin * 2.0 - 80.0)
	var list: Array = []
	var placed: Array = []
	var attempts := 0
	while list.size() < k and attempts < k * 40:
		attempts += 1
		var r := 16.0
		var pos := Vector2(
			rng.range_float(area.position.x + r, area.end.x - r),
			rng.range_float(area.position.y + r, area.end.y - r))
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < 90.0:   # 目标钉之间拉开距离
				too_close = true; break
		if too_close:
			continue
		list.append({&"pos": pos, &"radius": r, &"base_score": 10.0,
					 &"type": GameDB.peg_types[&"normal"], &"frozen": false, &"poisoned": false,
					 &"is_target": true, &"hp": hp, &"hp_max": hp})
		placed.append(pos)
	return list

# 合成本发棋盘：填充钉（避开目标位）+ 存活目标钉，按下标重排 id。
func _compose_pegs() -> Array:
	var avoid: Array = []
	for t in _target_pegs:
		avoid.append(t[&"pos"])
	var combined: Array = _generate_pegs(avoid)
	combined.append_array(_target_pegs)
	for i in combined.size():
		combined[i][&"id"] = i
	return combined
```

- [ ] **Step 4: 新轮生成目标钉 + 用 _compose_pegs**
在 `_ready()` 里把：
```gdscript
	_pegs = _generate_pegs()
```
改为：
```gdscript
	_target_pegs = _generate_target_pegs()
	_pegs = _compose_pegs()
```
在 `_on_peg_exit_done()` 里把：
```gdscript
	_pegs = _generate_pegs()
```
改为：
```gdscript
	_pegs = _compose_pegs()
```
在 `leave_shop()` 里把：
```gdscript
	_pegs = _generate_pegs()
```
改为：
```gdscript
	_target_pegs = _generate_target_pegs()
	_pegs = _compose_pegs()
```

- [ ] **Step 5: PEG_HIT 直接命中扣 HP** — 在 PEG_HIT 处理里，找到：
```gdscript
						var hit_type: PegType = hit_peg.get(&"type")
						var behavior := hit_type.behavior if hit_type != null else PegType.Behavior.NORMAL
						match behavior:
```
改为（在 match 前插入 is_target 分支，用 if/else 包住原 match）：
```gdscript
						var hit_type: PegType = hit_peg.get(&"type")
						var behavior := hit_type.behavior if hit_type != null else PegType.Behavior.NORMAL
						if hit_peg.get(&"is_target", false):
							_hit_target_peg(hit_peg)
						else:
							match behavior:
```
（把原 match 块整体多缩进一级，使其位于 else 之下。）

- [ ] **Step 6: HP 助手 + 直接命中 + ALL CLEAR** — 在 `_score_peg(peg)` 函数定义**之后**插入：
```gdscript
# 给目标钉扣 1 HP + 计分；hp≤0 时从 _target_pegs 移除并检测全清。
# 返回是否被摧毁（调用方负责从 _pegs 移除 + 重建 sim）。不触碰 _pegs/sim。
func _damage_target(peg: Dictionary) -> bool:
	peg[&"hp"] = int(peg[&"hp"]) - 1
	_score_peg(peg)
	var destroyed := int(peg[&"hp"]) <= 0
	if destroyed:
		_target_pegs.erase(peg)
		if _target_pegs.is_empty():
			RunMan.state[&"targets_done"] = true
			_play_all_clear()
	_sync_hud()
	return destroyed

# 直接球命中目标钉。
func _hit_target_peg(peg: Dictionary) -> void:
	if _damage_target(peg):
		_pegs.erase(peg)
		_sim = _make_sim(_pegs)
		_rebuild_wall_segs(_gate_applied)
		_events.resize(_event_cursor + 1)

func _play_all_clear() -> void:
	_all_clear_ttl = ALL_CLEAR_DUR
	_juice.slowmo.request(0.3, 0.4)
	_juice.floaters.add(_last_hit_pos + Vector2(0, -40), "ALL CLEAR!")
	_juice.shake.add(0.5)
```

- [ ] **Step 7: 炸弹/连锁也伤目标钉（D1，先收集后删除）**
`_trigger_chain`：把循环体：
```gdscript
	for peg in _pegs:
		if peg[&"id"] == chain_peg[&"id"] or peg.get(&"hit", false):
			continue
		if (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"]) <= CHAIN_RADIUS:
			_score_peg(peg)
```
改为（目标钉走 _damage_target，被摧毁的收集后统一删除）：
```gdscript
	var chain_removed: Array = []
	for peg in _pegs:
		if peg[&"id"] == chain_peg[&"id"] or peg.get(&"hit", false):
			continue
		if (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"]) <= CHAIN_RADIUS:
			if peg.get(&"is_target", false):
				if _damage_target(peg):
					chain_removed.append(peg)
			else:
				_score_peg(peg)
	for peg in chain_removed:
		_pegs.erase(peg)
	if not chain_removed.is_empty():
		_sim = _make_sim(_pegs)
		_rebuild_wall_segs(_gate_applied)
		_events.resize(_event_cursor + 1)
```
> 注：上面假设 `_trigger_chain` 现有循环对半径内的钉调用 `_score_peg(peg)`。实施时先读真实函数体，按其实际结构插入"目标钉→_damage_target、收集 chain_removed、循环后删除+重建 sim"，保持其余行为不变。

`_trigger_bomb`：把循环体：
```gdscript
	for peg in _pegs:
		if (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"]) <= BOMB_RADIUS:
			_score_peg(peg)
			to_remove.append(peg)
```
改为（目标钉扣 HP，只有被摧毁才进 to_remove）：
```gdscript
	for peg in _pegs:
		if (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"]) <= BOMB_RADIUS:
			if peg.get(&"is_target", false):
				if _damage_target(peg):
					to_remove.append(peg)
			else:
				_score_peg(peg)
				to_remove.append(peg)
```
（`to_remove` 之后的 `_pegs.erase` + `_make_sim` + `_events.resize` 套路不变。未被摧毁的目标钉留在场上，HP 已 −1。）

- [ ] **Step 8: ALL CLEAR 计时递减** — 在 `_process` 里 `if _combo_display_ttl > 0.0:` 那块之后加：
```gdscript
	if _all_clear_ttl > 0.0:
		_all_clear_ttl -= delta
```

- [ ] **Step 9: 验证场景加载 + 全套**
创建 `/tmp/tp_check.gd`（extends SceneTree；load+instantiate `res://scenes/board.tscn`；print BOARD_OK/FAIL；quit），运行：
`/d/Program/Godot/godot --headless --path . -s /tmp/tp_check.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
期望 `BOARD_OK`，无 Parse Error/SCRIPT ERROR。然后 `rm -f /tmp/tp_check.gd`。
全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`，期望 All tests passed，总数不变（board_view 无单测）。

- [ ] **Step 10: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: persistent target pegs with HP + all-clear (board_view)"
```

---

## Task 4：目标钉可视化 + HUD 计数器

**Files:** Modify `view/board_view.gd`, `view/hud.gd`

- [ ] **Step 1: HUD 目标计数器** — `view/hud.gd`。
在成员区 `var _label_launches: Label` 后加：
```gdscript
var _label_targets: Label
```
在 `_ready`（创建标签处，`_label_launches = _make_label(...)` 之后）加：
```gdscript
	_label_targets = _make_label(Vector2(490, 116), 18, Color(1.0, 0.85, 0.2))
	_label_targets.text = ""
```
文件末尾加方法：
```gdscript
func set_target_count(cleared: int, total: int) -> void:
	if total <= 0:
		_label_targets.text = ""
	else:
		_label_targets.text = "目标 %d/%d" % [cleared, total]
```

- [ ] **Step 2: board_view 刷新计数器** — 在 `_hit_target_peg` 末尾的 `_sync_hud()` 之后、以及 `_compose_pegs` 被调用后，调用计数刷新。最简：在 `_sync_hud()` 里追加一行。找到 `func _sync_hud() -> void:` 函数体末尾，加：
```gdscript
	var total: int = _target_total()
	$Hud.set_target_count(total - _target_pegs.size(), total)
```
并在 `_sync_hud` 之后加助手（本轮目标总数 = 当前存活 + 已清；用本轮初始数）：
```gdscript
func _target_total() -> int:
	return RoundGoalScript.target_count_for(int(RunMan.state[&"ante"]))
```
> 说明：`_target_total()` 用本区目标钉数公式即本轮总数；`cleared = total - 存活数`。

- [ ] **Step 3: 目标钉绘制（金色 + HP 数字）** — `view/board_view.gd` 的 `_draw()`，在画活动钉的循环里区分目标钉。找到画钉循环中的：
```gdscript
		draw_circle(peg[&"pos"], radius, col)
```
在其后加：
```gdscript
		if peg.get(&"is_target", false):
			draw_arc(peg[&"pos"], radius + 3.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.2), 2.0)
			var f := ThemeDB.fallback_font
			draw_string(f, peg[&"pos"] + Vector2(-5, 5), str(int(peg[&"hp"])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
```

- [ ] **Step 4: ALL CLEAR 字样绘制** — `_draw()` 里、`_draw_walls()` 调用之前加：
```gdscript
	if _all_clear_ttl > 0.0:
		var f2 := ThemeDB.fallback_font
		var a := _all_clear_ttl / ALL_CLEAR_DUR
		draw_string(f2, _rect.position + Vector2(160, 400), "ALL CLEAR!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.9, 0.3, a))
```

- [ ] **Step 5: 验证场景加载 + 全套**（同 Task 3 Step 9 的检查；BOARD_OK + 全套绿，总数不变）

- [ ] **Step 6: 实机验收（用户人工）**：每轮有金色目标钉显示剩余 HP；HUD 显示 `目标 X/K`；直接命中扣 HP、扣完消失；清光弹 ALL CLEAR + 慢动作；炸弹/连锁不伤目标钉；清光不提前结束、发完后凭 targets_done 过关。

- [ ] **Step 7: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd view/hud.gd
git -C D:/NeonPinball/game commit -m "feat: target peg visuals (gold + HP) + HUD counter + ALL CLEAR"
```

---

## 自检清单

- [ ] **Spec 覆盖**：目标钉数/HP 曲线(T1) ✓；双路赢条件 targets_done or quota(T2) ✓；新轮重置 + 清光奖励 +5(T2) ✓；持久目标钉跨发(T3 _compose_pegs，_on_peg_exit_done 不重生目标) ✓；直接命中/炸弹/连锁均扣 HP、扣完移除、全清→targets_done+ALL CLEAR(T3 _damage_target, D1) ✓；不提前过关（_on_all_settled 未改 targets 分支）✓；金色+HP 显示 + HUD 计数(T4) ✓；零侵入 sim ✓
- [ ] **占位符扫描**：每步完整代码与确切命令 ✓
- [ ] **类型/签名一致性**：
  - `RoundGoal.target_count_for/target_hp_for(int)->int` —— T1 定义、T1/T2 测试、T3/T4 调用一致 ✓
  - `state[&"targets_done"]` —— T2 写入(start_round/advance/payout)、T3 写入(全清)、advance 读取一致 ✓
  - `_target_pegs` / `_compose_pegs` / `_generate_target_pegs` / `_hit_target_peg` / `_play_all_clear` / `_target_total` —— T3/T4 定义与调用一致 ✓
  - `Hud.set_target_count(cleared, total)` —— T4 定义、_sync_hud 调用一致 ✓
  - 目标钉 dict 含 `is_target/hp/hp_max`；PEG_HIT/bomb/chain 用 `get(&"is_target", false)` 一致 ✓
- [ ] **范围**：仅目标钉系统；硬目标/挑战目标/run map/配额进度条留 Backlog；D1（cascade 不伤目标）已标注待确认 ✓

---

## 备注

- `_make_default_state()` 必须与 `state` 字面量同步加 `targets_done`，否则 `_ready` 的 hash assert 会失败（T2 Step3 a+b 必须成对）。
- 目标钉移除沿用现有一次性钉的 `erase + _make_sim + _events.resize` 套路；`_compose_pegs` 重排 id 保证 `id==下标` 不变量。
- `_target_total()` 用公式值作本轮总数（目标钉一旦生成数量固定）；cleared = 总数 − 存活数。
- 数值（数量/HP/奖励 +5/ALL CLEAR 时长）见 `docs/superpowers/balance-tunables.md`，试玩后调。
- D1 已定为"炸弹/连锁也伤目标"：三个调用方统一走 `_damage_target`；炸弹/连锁"先收集后删除"避免迭代中改数组；未摧毁的目标钉留场、HP −1。
