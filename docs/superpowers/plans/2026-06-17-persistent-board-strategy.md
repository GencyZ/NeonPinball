# 局内棋盘整轮持久 + 命中清除 + 补钉 Implementation Plan（Phase 1）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把"每发随机重生一盘"改成"整轮持久同一盘、命中即清（落定才移除）、每发补 3 颗新钉"，5 发变成一盘可规划的棋。

**Architecture:** 飞行中标记被直接命中的钉（`_hit_ids`，按稳定 `id` 字段），球落定后只清掉它们 + 补 N 颗（不再整盘重随机）；轮首仍 `_compose_pegs` 铺满整盘。新增纯函数 `run/board_refill.gd::survivors()`（可单测）；board_view 重构钉放置（抽 `_place_pegs` 给补钉复用）+ 改写落定过渡。复用现有飞行物理/计分/连击/目标钉/动画，零侵入 sim 与确定性。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库事实，已核对当前代码）

- 项目根 `D:/NeonPinball/game/`。Godot `/d/Program/Godot/godot`（不在 PATH）。缩进 **TAB**。
- 全套测试：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
  单文件：`-gselect=test_board_refill.gd -gexit`。
- **基线：257 测试全绿，37 脚本。** 每任务只提交自己的文件。**不要 push**。**不要新建分支**（main）。
- spec：`docs/superpowers/specs/2026-06-17-persistent-board-strategy-design.md`。三决策已锁：`TOPUP_COUNT=3`、Phase 1 不动 combo 曲线、过渡保留阻塞。
- `view/board_view.gd` 现状（行号为当前实测）：
  - consts（顶部）：`PEG_EXIT_DUR := 0.4`（行7）、`PEG_ENTER_DUR := 0.4`（行8）、`const RoundGoalScript := preload("res://run/round_goal.gd")`（行16）。
  - members：`var _pegs: Array`（行28）、`var _peg_anims: Dictionary = {}`（行46）、`var _launch_count := 0`（行48）、`var _is_transitioning := false`（行50）、`_dying_pegs`（行51）、`_peg_enter_ttls`（行52）、`_target_pegs`（行65）。
  - `_generate_pegs(avoid_pos)`（行127-182）：算 depth/rng（`DeterministicRng.derive(master_seed+_launch_count, 0x9E3779B9)`）/count，再跑放置循环。
  - `_compose_pegs()`（行221-229）：`_generate_pegs(avoid)` + `append_array(_target_pegs)` + 重排 id。**仅在轮首 `leave_shop` 与 `_on_peg_exit_done` 调用**（本计划移除后者的调用）。
  - `_build_type_pool(depth)`（行231-244）。`_make_sim(pegs)`（行246）。
  - `launch(ball)`（行407-435）：`_score_ctx.clear_for_launch()`（行419）、`_combo = 0`（行420）、`_launch_count += 1`（行434）。
  - PEG_HIT 处理（行470-540）：`_combo += 1`…`_peg_anims[hit_peg_id] = PEG_ANIM_DUR`（行480）、`var hit_peg: Dictionary = _pegs[hit_peg_id]`（行481）；普通钉 `_score_peg`，特殊钉分支；JACKPOT/LIFE/POISON 的 `one_shot` 在**飞行中** `_pegs.erase(hit_peg)` + `_make_sim` + `_events.resize`（行507/515/522）。
  - `_on_all_settled()`（行594-616）：发完 `RunMan.advance()`，否则 `_start_peg_transition()`（行615-616）。
  - `_start_peg_transition()`（行618-632）：把**所有非目标钉**塞 `_dying_pegs`、目标钉留 survivors、`_pegs=survivors`、重排 id、`_make_sim`、`_rebuild_wall_segs(false)`、计时器 → `_on_peg_exit_done`。
  - `_on_peg_exit_done()`（行634-644）：`_pegs = _compose_pegs()`（整盘重随机）、`_make_sim`、给非目标钉设 `_peg_enter_ttls`、计时器 → `_on_peg_enter_done`。
  - `_on_peg_enter_done()`（行646-648）：`_peg_enter_ttls.clear()`、`_is_transitioning=false`。
  - cascade：`_trigger_bomb`/`_trigger_chain` 等在**飞行中**对波及钉 `_pegs.erase` + `_make_sim` + `_events.resize`；`_damage_target` 摧毁目标时由调用方从 `_pegs` 移除（行963-968）。
- **关键正确性点**：sim 事件里的 `peg_id` 是**数组下标**（`_pegs[hit_peg_id]`），而 one_shot/cascade 在飞行中 `_pegs.erase` 会让下标漂移；但每个 peg 的 `&"id"` **字段**在单发内不重排（只在 `_compose_pegs`/落定后重排），故**用 `hit_peg[&"id"]` 字段做标记是稳定的**。`survivors()` 也按 `id` 字段过滤。
- `peg.get(&"hit", false)` 仅被读、从不赋值（死防御）；`_hit_ids` 是独立成员字典，与之无关。

---

## 文件结构
- **新建**：`run/board_refill.gd`（纯函数 `survivors`）、`tests/test_board_refill.gd`
- **修改**：`view/board_view.gd`

---

## Task 1：纯函数 `survivors()` + 测试

**Files:** Create `run/board_refill.gd`, `tests/test_board_refill.gd`

- [ ] **Step 1: 写失败测试** — 新建 `tests/test_board_refill.gd`：
```gdscript
extends GutTest

const BoardRefillScript := preload("res://run/board_refill.gd")

func _peg(id: int, is_target := false) -> Dictionary:
	return {&"id": id, &"is_target": is_target}

func test_keeps_unhit_removes_hit() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1), _peg(2)], {1: true})
	var ids: Array = []
	for p in kept:
		ids.append(int(p[&"id"]))
	assert_eq(kept.size(), 2, "撞中的 id1 被清，剩 2")
	assert_does_not_have(ids, 1, "id1 已清")
	assert_has(ids, 0, "id0 留")
	assert_has(ids, 2, "id2 留")

func test_targets_always_kept_even_if_hit() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0, true), _peg(1)], {0: true, 1: true})
	var ids: Array = []
	for p in kept:
		ids.append(int(p[&"id"]))
	assert_has(ids, 0, "目标钉无条件保留（存亡由 HP 管）")
	assert_does_not_have(ids, 1, "非目标撞中清除")

func test_empty_hit_keeps_all() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1, true), _peg(2)], {})
	assert_eq(kept.size(), 3, "没撞任何钉 → 全留")

func test_empty_pegs_returns_empty() -> void:
	assert_eq(BoardRefillScript.survivors([], {3: true}).size(), 0, "空盘 → 空")

func test_all_hit_nontargets_cleared_target_stays() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1), _peg(2, true)], {0: true, 1: true, 2: true})
	assert_eq(kept.size(), 1, "两普通清除，目标留")
	assert_true(kept[0].get(&"is_target", false), "留下的是目标钉")
```

- [ ] **Step 2: 跑确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_board_refill.gd -gexit`
预期：脚本加载失败/方法不存在（`board_refill.gd` 尚未创建）。

- [ ] **Step 3: 实现** — 新建 `run/board_refill.gd`：
```gdscript
extends RefCounted
# 棋盘持久/补钉的纯决策逻辑（可单测）。view 层调用，不持有状态。

# 落定后保留哪些钉：目标钉无条件保留（存亡由 HP 管）；
# 非目标钉若本发被直接命中（其 id 在 hit_ids）则清除，否则保留。
# pegs: Array[Dictionary]（每个含 &"id"，可选 &"is_target"）；hit_ids: Dictionary（peg id -> true）。
static func survivors(pegs: Array, hit_ids: Dictionary) -> Array:
	var kept: Array = []
	for peg in pegs:
		if peg.get(&"is_target", false):
			kept.append(peg)
		elif not hit_ids.has(int(peg[&"id"])):
			kept.append(peg)
	return kept
```

- [ ] **Step 4: 跑确认通过**

单文件应 5/5 过。全套应 **262**（257 + 5）：
`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add run/board_refill.gd tests/test_board_refill.gd
git -C D:/NeonPinball/game commit -m "feat: board_refill.survivors() pure fn (persist non-hit pegs)"
```

---

## Task 2：board_view 持久 + 命中清除 + 补钉

**Files:** Modify `view/board_view.gd`

> board_view 无单测；靠场景冒烟 + 全套保持绿 + 实机。按内容匹配锚点；找不到就停下回报。

- [ ] **Step 1: 加常量/成员**
(a) `BoardRefillScript` preload —— 找到 `const RoundGoalScript := preload("res://run/round_goal.gd")`，在其**后**加：
```gdscript
const BoardRefillScript := preload("res://run/board_refill.gd")
```
(b) `TOPUP_COUNT` —— 找到 `const PEG_ENTER_DUR := 0.4      # peg appear animation (s)`，在其**后**加：
```gdscript
const TOPUP_COUNT := 3          # 每发落定补几颗新钉（持久棋盘头号旋钮，见 balance-tunables）
```
(c) `_hit_ids` 成员 —— 找到 `var _peg_anims: Dictionary = {}   # peg_id -> remaining pop-anim ttl`，在其**后**加：
```gdscript
var _hit_ids: Dictionary = {}     # 本发被"直接命中"的非目标钉的稳定 id 集合（落定时据此清除）
```

- [ ] **Step 2: `launch()` 重置 `_hit_ids`** —— 找到 `launch()` 里的 `_score_ctx.clear_for_launch()`，在其**后**加一行（同缩进，TAB×1）：
```gdscript
	_hit_ids.clear()
```

- [ ] **Step 3: PEG_HIT 标记命中** —— 找到 `var hit_peg: Dictionary = _pegs[hit_peg_id]`（在 `if hit_peg_id >= 0 ...` 块内，缩进 6 个 TAB），在其**后**插入（`if` 与 `var hit_peg` 同缩进=6 TAB，赋值体 7 TAB）：
```gdscript
						if not hit_peg.get(&"is_target", false):
							_hit_ids[int(hit_peg[&"id"])] = true
```
> 只标记**直接命中的非目标钉**；chain/magnet 顺带计分的邻居、freeze/poison 受影响的邻居**不标记**（它们不被清，可后续再撞）。目标钉由 HP 管、不标记。one_shot/cascade 已飞行中清除的钉即便其 id 被标记，落定时已不在 `_pegs`，`survivors()` 自然忽略（幂等无害）。

- [ ] **Step 4: 重构钉放置 + 加 `_topup_pegs`** —— 把整个 `_generate_pegs` 函数（从 `func _generate_pegs(avoid_pos: Array = []) -> Array:` 到它的 `return list`）**替换**为下面三个函数：
```gdscript
func _generate_pegs(avoid_pos: Array = []) -> Array:
	var ante: int = RunMan.state[&"ante"]
	var ria: int  = RunMan.state[&"round_in_ante"]
	var depth := (ante - 1) * 3 + ria   # 0 (ante1 r1) … 23 (ante8 boss)
	var rng := DeterministicRng.derive(int(RunMan.state[&"master_seed"]) + _launch_count, 0x9E3779B9)
	var count := rng.range_int(25 + ante * 2, 38 + ante * 3)
	return _place_pegs(count, avoid_pos, rng, depth)

# 放置 count 颗钉：随机 pos + 半径 10-20 + 避重(避开已放置 + avoid_pos) + 按 depth 选类型。
# 供 _generate_pegs(整盘) 与 _topup_pegs(补钉) 共用。
func _place_pegs(count: int, avoid_pos: Array, rng: DeterministicRng, depth: int) -> Array:
	var margin := 44.0
	var area := Rect2(
		_rect.position.x + margin,
		_rect.position.y + margin + 80.0,   # extra top gap for channel walls
		_rect.size.x - margin * 2.0,
		780.0 - margin * 2.0 - 80.0)        # height fits above funnel (local y < 780)
	var special_rate := minf(float(depth) / 23.0 * 0.55, 0.55)
	var type_pool := _build_type_pool(depth)
	var list: Array = []
	var placed_pos: Array = []
	var placed_rad: Array = []
	var id := 0
	var attempts := 0
	while list.size() < count and attempts < count * 30:
		attempts += 1
		var r := rng.range_float(10.0, 20.0)
		var pos := Vector2(
			rng.range_float(area.position.x + r, area.end.x - r),
			rng.range_float(area.position.y + r, area.end.y - r))
		var too_close := false
		for j in placed_pos.size():
			if pos.distance_to(placed_pos[j]) < r + placed_rad[j] + 18.0:
				too_close = true; break
		if not too_close:
			for ap in avoid_pos:
				if pos.distance_to(ap) < r + 24.0 + 18.0:
					too_close = true; break
		if too_close:
			continue
		var peg_type: PegType
		if type_pool.size() > 0 and rng.next_float() < special_rate:
			peg_type = type_pool[rng.range_int(0, type_pool.size())]
		else:
			peg_type = GameDB.peg_types[&"normal"]
		list.append({&"id": id, &"pos": pos, &"radius": r,
					 &"base_score": r * 0.6, &"type": peg_type,
					 &"frozen": false, &"poisoned": false})
		placed_pos.append(pos)
		placed_rad.append(r)
		id += 1
	return list

# 落定后补 n 颗新钉：避开现有所有钉，确定性 RNG（salt 0x85EBCA6B 区别于发钉 0x9E3779B9，互不相关）。
func _topup_pegs(n: int) -> Array:
	var ante: int = RunMan.state[&"ante"]
	var ria: int  = RunMan.state[&"round_in_ante"]
	var depth := (ante - 1) * 3 + ria
	var avoid: Array = []
	for peg in _pegs:
		avoid.append(peg[&"pos"])
	var rng := DeterministicRng.derive(int(RunMan.state[&"master_seed"]) + _launch_count, 0x85EBCA6B)
	return _place_pegs(n, avoid, rng, depth)
```
> `_generate_pegs(avoid_pos)` 签名与行为不变（只是委托给 `_place_pegs`），其唯一调用方 `_compose_pegs` 不受影响。

- [ ] **Step 5: 改写 `_start_peg_transition`** —— 把整个函数替换为：
```gdscript
func _start_peg_transition() -> void:
	_is_transitioning = true
	_dying_pegs.clear()
	# 只清"本发被直接命中的非目标钉"（缩小退场）；没撞的 + 目标钉留下（持久）。
	for peg in _pegs:
		if peg.get(&"is_target", false):
			continue
		if _hit_ids.has(int(peg[&"id"])):
			_dying_pegs.append({&"data": peg.duplicate(), &"ttl": PEG_EXIT_DUR, &"max_ttl": PEG_EXIT_DUR})
	_pegs = BoardRefillScript.survivors(_pegs, _hit_ids)
	# id 重排 / _make_sim / _rebuild_wall_segs 推迟到补钉后统一做（见 _on_peg_exit_done）；
	# 退场期无球、sim/walls 不被使用（_is_transitioning 期间 input 也不出预测线）。
	get_tree().create_timer(PEG_EXIT_DUR).timeout.connect(_on_peg_exit_done)
```

- [ ] **Step 6: 改写 `_on_peg_exit_done`** —— 把整个函数替换为：
```gdscript
func _on_peg_exit_done() -> void:
	_dying_pegs.clear()
	# 持久棋盘：保留存活钉，补 TOPUP_COUNT 颗新钉（不再整盘重随机）。
	var fresh: Array = _topup_pegs(TOPUP_COUNT)
	var fresh_count: int = fresh.size()
	_pegs.append_array(fresh)
	for i in _pegs.size():
		_pegs[i][&"id"] = i
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(false)
	# 只给新补的钉播放放大出现动画（存活钉不重播）。
	_peg_enter_ttls.clear()
	for i in range(_pegs.size() - fresh_count, _pegs.size()):
		_peg_enter_ttls[_pegs[i][&"id"]] = PEG_ENTER_DUR
	get_tree().create_timer(PEG_ENTER_DUR).timeout.connect(_on_peg_enter_done)
```
> `_on_peg_enter_done` 不改。轮首铺满整盘仍走 `leave_shop` → `_compose_pegs`（本计划不动）。

- [ ] **Step 7: 验证场景加载 + 全套**
(a) 确认 `_generate_pegs` 仅 `_compose_pegs` 调用、`_compose_pegs` 仅 `leave_shop` 与（被本计划移除的）旧 exit_done 调用：
```
grep -n "_generate_pegs\|_compose_pegs\|_place_pegs\|_topup_pegs" D:/NeonPinball/game/view/board_view.gd
```
预期：`_on_peg_exit_done` 内**不再**出现 `_compose_pegs`。
(b) 写临时冒烟 `/tmp/pb.gd`：
```gdscript
extends SceneTree
func _init() -> void:
	var ps := load("res://scenes/board.tscn")
	if ps == null:
		print("BOARD_FAIL: load null"); quit(); return
	var inst = ps.instantiate()
	if inst == null:
		print("BOARD_FAIL: instantiate null")
	else:
		print("BOARD_OK"); inst.free()
	quit()
```
跑：`/d/Program/Godot/godot --headless --path . -s /tmp/pb.gd 2>&1 | grep -iE "BOARD_OK|BOARD_FAIL|Parse Error|SCRIPT ERROR"`
预期 `BOARD_OK`，无**新增** Parse Error/SCRIPT ERROR（GameDB/RunMan/SceneMan autoload-absent 的预存报错无关）。然后 `rm -f /tmp/pb.gd`。
(c) 全套：
```
/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
```
预期 All tests passed，总数 **262**（board_view 无新单测）。若失败/解析错，修到全绿。

> 实机验收（用户人工）：① 没撞的钉跨发留着、不再整盘重随机 ② 撞到的钉落定后缩小消失、飞行中仍可反复弹撞 ③ 每发补几颗新钉放大出现、棋盘逐发变稀 ④ 轮首铺满整盘 ⑤ 目标钉/HP/ALL CLEAR 不变 ⑥ BOMB/CHAIN 可留到下发串。

- [ ] **Step 8: 提交**
```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: persistent board within round (clear hit pegs at settle + topup, retire per-launch regen)"
```

---

## 自检清单

- [ ] **Spec 覆盖**：标记命中飞行不移除(T2 Step3) ✓；落定清被撞非目标钉(T2 Step5 + survivors) ✓；保留没撞的(survivors) ✓；目标钉无条件留(survivors + T2 不标记目标) ✓；每发补 N=3 + 放大出现(T2 Step4/6) ✓；轮首铺满(leave_shop 不动) ✓；确定性补钉(salt 0x85EBCA6B) ✓；JACKPOT/LIFE/POISON 飞行即清不动(T2 不触) ✓；纯函数单测(T1) ✓；零侵入 sim(仅 view + 纯函数) ✓
- [ ] **占位符扫描**：每步完整代码 + 确切命令 ✓
- [ ] **类型/签名一致性**：
  - `BoardRefillScript.survivors(pegs, hit_ids)` —— 定义(T1)、测试(T1)、调用(T2 Step5) 一致 ✓
  - `_place_pegs(count, avoid_pos, rng: DeterministicRng, depth)` —— 定义 + `_generate_pegs`/`_topup_pegs` 两处调用一致(T2 Step4) ✓
  - `_topup_pegs(n)` 定义(Step4)、调用(Step6) 一致 ✓
  - `_hit_ids` 声明(Step1c)、清空(Step2)、写入(Step3)、读取(Step5 survivors + dying 判定) 闭环 ✓
  - 标记用 `hit_peg[&"id"]` **字段**(稳定)，survivors 按 `int(peg[&"id"])` 过滤 —— 一致，避开数组下标漂移 ✓
  - `_generate_pegs(avoid_pos)` 签名不变 → `_compose_pegs` 不受影响 ✓
- [ ] **范围**：仅棋盘持久 + 命中清 + 补钉；不动 combo 曲线/配额、不动过渡阻塞(决策②③)、cascade/目标钉逻辑不动；显式相邻 payoff 留 Phase 2 ✓

---

## 备注 / 已知行为
- **空击仍补钉**：某球 0 命中时 `_hit_ids` 空、无清除但仍补 TOPUP_COUNT → 棋盘会略增（避重满了 `_place_pegs` 自然少补，自限）。可接受，TOPUP_COUNT 可调。
- **棋盘变稀/见底**：高效清盘后期可能稀疏，是预期"珍惜密集区"的张力来源；TOPUP_COUNT/起始数 `count` 实机调（balance-tunables 已记）。
- **连击量级**：持久密盘清得多→单发连击/分数可能整体上移，Phase 1 先不动曲线/配额，实机后再调（balance-tunables 已记）。
- **退场期推迟 `_make_sim`**：退场 0.4s 内无球、`_is_transitioning=true`（input 不出预测线），`_sim` 暂旧但不被使用；exit_done 补钉后统一 `_make_sim` + `_rebuild_wall_segs`，下一发前已就绪。
- 数值落地后回填 `docs/superpowers/balance-tunables.md`。
