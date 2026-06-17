# 局内棋盘整轮持久 + 命中清除 + 每发补钉 设计文档（Phase 1）

**日期：** 2026-06-17
**主题：** 把"每发随机重生一盘"改成"整轮持久同一盘、命中即清（落定才移除）、每发小幅补钉"，让 5 发变成一盘可规划的棋——提升局内策略性。

---

## 目标

局内目前的决策点太薄：玩家一轮只能决定**发射边（Tab）/ 瞄准角度（±60°）/ 何时发射**，而**棋盘每发随机重生**让"前两个决策"几乎没有规划价值（你瞄的钉下一发就变了）。本次把棋盘改为**整轮持久**：

- 一轮**开局只铺一次**整盘（含目标钉）。
- 球飞行时穿过**完整密盘**（弹撞/连击/特效不变）；**球落定后**才清除本发撞到的钉（命中即清，Peggle 式）。
- 没撞到的钉**留到下一发**；每发落定再**小补 N 颗**新钉，使棋盘逐发变稀但不立刻见底。
- 于是 5 发打的是**同一盘逐渐被清开**的棋 → 可规划路线、可留特殊钉给后续串连锁。

## 设计原则

- **低侵入、复用现有系统**：球的飞行物理、`_events` 预计算、撞钉回调、计分/连击/heat、目标钉/ALL CLEAR、缩放动画——尽量不动；改动集中在"落定时如何重组棋盘"。
- **标记命中、落定才清**（不是命中即从 `_pegs` 移除）：保留"密盘里反复弹撞攒连击"的手感，且**避免每次撞钉重建物理**（零性能风险、无中途重模拟正确性问题）。
- **零侵入 sim 确定性**：补钉用确定性 RNG（`DeterministicRng.derive(seed + launch)`）；棋盘状态属 view 层，不进 RunManager.state 的哈希校验路径（除非必要）。
- **可测的纯逻辑抽出来**：survivors 过滤等做成纯函数 TDD；绘制/集成靠场景冒烟 + 实机。
- **Phase 1 只做地基**：显式"相邻加成 payoff"留 Phase 2——持久后 BOMB/CHAIN 已自动成为可规划路线。

---

## 现状（代码库事实，2026-06-15 摸查）

> 单测基线 **257 全绿，37 脚本**。缩进 TAB。Godot `/d/Program/Godot/godot`。

棋盘钉生命周期（`view/board_view.gd`）：
- **钉数据**：`_pegs: Array`（所有活跃钉=普通+目标，dict `{id,pos,radius,base_score,type,frozen,poisoned, [is_target,hp,hp_max]}`）；`_target_pegs: Array`（跨发持久的目标钉，第 65 行）。
- **生成**：`_generate_pegs(avoid)`（127-182，`count := rng.range_int(25+ante*2, 38+ante*3)`，半径 10-20，特殊类型按 ante 渐进）；`_generate_target_pegs()`（185-218，一轮一次）；`_compose_pegs()`（221-229，填充避开目标位 + `append_array(_target_pegs)` + 重排 id）。
- **每发重生（要改的核心）**：`_on_all_settled()`（594-616）发末若未发完 → `_start_peg_transition()`（618-632，把**所有普通钉**塞入 `_dying_pegs` 缩小退场、目标钉留 `survivors`）→ 计时器 → `_on_peg_exit_done()`（634-644，`_pegs = _compose_pegs()` **整盘重随机**、给非目标钉设 `_peg_enter_ttls` 放大出现）→ `_on_peg_enter_done()`（646-648，`_is_transitioning=false`）。
- **撞钉回调（不改主体）**：`_process()` PEG_HIT（472-540）：`_combo += 1`、`_sfx.play_hit`、`_combo_display_ttl`、`_wall_heat += HEAT_PER_HIT`、`_peg_anims[id]=pop`、`_score_peg(hit_peg)`（**普通钉只加分不移除**）、特殊类型分支、`_juice.on_peg_hit_combo`、`_score_ctx.pegs_hit += 1`、`_live_target`。JACKPOT/LIFE/POISON（506-524）`_pegs.erase` + `_make_sim` + `_events.resize`（**飞行中即清**）。
- **目标钉**：`_damage_target()`（950-960）HP-1，归零移出 `_target_pegs`/`_pegs`，空了 `targets_done=true` + `_play_all_clear()`。
- **动画常量**：`PEG_EXIT_DUR=0.4`、`PEG_ENTER_DUR=0.4`、`PEG_ANIM_DUR=0.18`（pop）。`_dying_pegs`（缩小，draw 839-847）、`_peg_enter_ttls`（放大，draw 856-859）。
- **发数/换轮**：`RunMan.launches_left`（init 5，`spend_launch`/`launches_exhausted`）；发完 `RunMan.advance()` → ANTE_CLEAR/SHOP；`leave_shop()`（713-726）新轮 `_target_pegs=_generate_target_pegs()`、`_pegs=_compose_pegs()`。
- **禁发射**：`_is_transitioning`（`input_controller.gd:18/92` 检查）。

**关键事实**：现在普通钉**命中不消失**（同发可反复撞，每撞 +分+连击），是**发末整盘抹掉重随机**；只有目标钉跨发持久。

---

## 系统组成（Phase 1 改动）

### A. 新纯逻辑（可测）— `run/board_refill.gd`（新建，Script，无 class_name，autoload 友好）

```gdscript
extends RefCounted
# 棋盘持久/补钉的纯决策逻辑（可单测）。view 层调用，不持有状态。

# 落定后保留哪些钉：被撞到的非目标钉清除；没撞到的留下；目标钉无条件保留（其存亡由 HP 管）。
# pegs: Array[Dictionary]；hit_ids: Dictionary（id->true，本发撞过的钉 id 集合）。
static func survivors(pegs: Array, hit_ids: Dictionary) -> Array:
	var kept: Array = []
	for peg in pegs:
		if peg.get(&"is_target", false):
			kept.append(peg)
		elif not hit_ids.has(int(peg[&"id"])):
			kept.append(peg)
	return kept
```
> 仅此一个纯函数有实质可测价值。补钉数 Phase 1 用常量（见旋钮），不做曲线，故不抽函数。

### B. `view/board_view.gd` 改动

**新增成员：**
```gdscript
const BoardRefillScript := preload("res://run/board_refill.gd")
const TOPUP_COUNT := 3          # 每发落定补几颗新钉（实机头号旋钮）
var _hit_ids: Dictionary = {}   # 本发撞过的（非已移除）钉 id 集合，落定时据此清除
```

**1. 标记命中** — PEG_HIT 回调（472-540）在 `_peg_anims[hit_peg_id]=...` 附近加一行：
`_hit_ids[hit_peg_id] = true`（普通钉与 BOMB/CHAIN/FREEZE/MAGNET/PORTAL 等"落定才清"的钉都标记；JACKPOT/LIFE/POISON 飞行中已 erase、不必标记，落定时其 id 不在 `_pegs` 中也无碍）。**其余回调逻辑全不变**（仍每撞加分/连击/特效）。

**2. 发射重置** — `launch()`（407-435）清空 `_hit_ids`（`_hit_ids.clear()`），与现有 `_combo=0`/`_score_ctx` 重置同处。

**3. 落定改"持久+补钉"** — 把发末 `else` 分支（未发完时）的过渡逻辑改为：
- `_start_peg_transition()`：用 `var keep := BoardRefillScript.survivors(_pegs, _hit_ids)` 拆分——被撞的非目标钉（即 `_pegs` 中不在 `keep` 里的）塞入 `_dying_pegs` 缩小退场；`_pegs = keep`（没撞的 + 目标钉留下，不动画）。survivors() 只在这一处调用。
- `_on_peg_exit_done()` **不再** `_compose_pegs()`：改为
  1. **补钉**：`_topup_pegs(TOPUP_COUNT)`（见下），`append` 进 `_pegs`。
  2. 重排 id（`for i in _pegs.size(): _pegs[i][&"id"]=i`）、`_sim=_make_sim(_pegs)`、`_rebuild_wall_segs(false)`。
  3. 只给**新补的钉**设 `_peg_enter_ttls`（放大出现）；存活钉不重播动画。
- `_on_peg_enter_done()` 不变（`_is_transitioning=false`）。

**3b. 钉放置重构 + `_topup_pegs`** — 现 `_generate_pegs(avoid)` 内部自算整盘 `count`，无法直接生成"恰好 N 颗"。重构：抽出 `_place_pegs(count: int, avoid: Array, rng) -> Array`（封装现有"随机 pos + 半径 10-20 + 避重 + 按深度 `_build_type_pool` 选类型"的放置循环）：
- `_generate_pegs(avoid)` 改为：算现有 `count` 公式 → `return _place_pegs(count, avoid, <现有发钉 rng>)`（行为不变）。
- `_topup_pegs(n)`：`avoid` = 现有所有 `_pegs` 的 pos；`rng = DeterministicRng.derive(master_seed + _launch_count, 0x85EBCA6B)`（salt 区别于 `_generate_pegs` 的 `0x9E3779B9`）；`return _place_pegs(n, avoid, rng)`。补钉与发钉同一类型池（按 ante 渐进）。

**4. 开局/换轮不变**：`leave_shop()` 仍 `_compose_pegs()` 铺满整盘——大铺场动画保留在轮首。

> 过渡仍走 `_is_transitioning`（沿用现有计时器/禁发射），只是退场只动被撞的钉。Phase 1 保留该 gate；若实机觉得拖沓，后续可缩短/改非阻塞（旋钮）。

### C. 特殊钉在持久下的行为（澄清，无需新代码）
- BOMB/CHAIN/FREEZE/MAGNET/PORTAL：效果仍在**命中时**触发（现有逻辑），改动后它们**跨发持久到被撞**→ 玩家可规划"留着炸弹下一发串 MULT 簇"。被撞后落定清除（进 `_hit_ids`）。
- JACKPOT/LIFE/POISON：维持现状（飞行中即 erase）。
- 目标钉：完全不变。

---

## 数据流

```
轮首(leave_shop): _pegs = _compose_pegs()  # 铺满整盘 + 目标钉（大铺场动画）
每发 launch(): _hit_ids.clear(); _combo=0; 球用完整 _pegs 预计算 _events
飞行中 PEG_HIT: 加分/连击/heat/特效照旧 + _hit_ids[id]=true   # 标记，不移除
落定 _on_all_settled():
   未发完 → 退场：被撞非目标钉 → _dying_pegs(缩小)，从 _pegs 移除；没撞的留下；目标钉留下
            → survivors 过滤 + _topup_pegs(TOPUP_COUNT) 补 N 颗(确定性RNG，放大出现)
            → 重排id / _make_sim / _rebuild_wall_segs
   发完/配额/目标全清 → RunMan.advance() → ANTE_CLEAR/SHOP（走现有换轮 → leave_shop 重铺）
```

整轮内：同一盘逐渐被清开 + 每发回补 N 颗；目标钉持久；越打越稀 → 后期珍惜密集区。

---

## 平衡旋钮（记入 `docs/superpowers/balance-tunables.md`，实机调）

- **`TOPUP_COUNT`（头号）**：每发补钉数。首版 **3**。太低→棋盘第 3 发就空；太高→不变稀、规划无意义。
- 起始密度 `_generate_pegs` 的 `count`（现 25+ante*2 .. 38+ante*3）：配合 TOPUP 调，使 5 发自然变稀但不见底。
- 连击曲线 `combo_score.xmult_for`（现 `min(1+pegs*0.12,5)`）/ 配额 `quota_of`：密盘清得多→单发连击可能更高，**实机看是否回调**。
- 过渡时长 `PEG_EXIT_DUR/PEG_ENTER_DUR`：只动被撞钉后是否觉得拖沓。

---

## 测试策略

- **纯函数（TDD）**：`run/board_refill.gd` `survivors()`——目标钉无条件保留、被撞非目标移除、没撞的保留、空 hit_ids 全留、混合场景。约 4-5 个 `tests/test_board_refill.gd`。
- **board_view（场景冒烟 + 实机）**：项目既有惯例（view 层无单测）。冒烟：`scenes/board.tscn` load+instantiate 无新 Parse/SCRIPT error。
- **手动实机验收**：见验收标准。

---

## 验收标准

- [ ] 一轮内棋盘**持久**：没撞到的钉跨发**留着**，不再每发整盘重随机
- [ ] 普通钉**命中即清**：撞到的钉在**球落定后**缩小消失（飞行中仍在、可反复弹撞攒连击）
- [ ] 每发落定**补 N 颗**新钉（放大出现），棋盘逐发变稀
- [ ] 轮首铺满整盘；目标钉持久 / HP / ALL CLEAR **完全不变**
- [ ] BOMB/CHAIN 等持久到被撞，可规划"留特殊钉串连锁"
- [ ] 补钉**确定性**（同 seed+发序可复现）
- [ ] 无回归：物理/计分/确定性/目标钉/霓虹等正常；`survivors` 单测绿；全套绿；board 场景冒烟 OK

---

## Backlog（Phase 2 及以后）

- **显式相邻 payoff**：特殊钉触发时按邻近钉/簇加成（炸弹炸到 MULT 簇额外倍率等）。
- 补钉智能化：按"已清空区"补钉、热区避让、补钉密度随 ante。
- "跳过补钉、保留空盘"作为高手清盘 reward 反馈。
- 预测线增强为规划工具（多球轨迹规划）。
- 落定过渡非阻塞/可缩短（snappier）。

---

## 已知风险 / 留意

- **连击量级变化**：持久密盘清除量大→单发连击/分数可能整体上移，或需回调 combo 曲线/配额（实机）。
- **棋盘空得太快**：若 TOPUP_COUNT/起始数没配好，后期可能近空盘（feel-bad）；首版靠旋钮调，必要时 Phase 2 加密度地板。
- **id 稳定性**：补钉/移除后在落定时统一重排 id + `_make_sim`，下一发 `_events` 全新预计算，故 id 只需单发内一致——与现有重排逻辑一致，无新约束。
- **确定性 salt**：补钉 RNG 的 salt 必须与 `_generate_pegs` 的 salt 区分，避免与同发其它随机相关。
