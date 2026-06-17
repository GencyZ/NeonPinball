# 商店/构筑策略第一档打包 设计文档

**日期：** 2026-06-17
**主题：** 激活"已建好但闲置/半残"的构筑-经济策略：① 商店 Reroll 接线 ② 触发器满槽可卖/换 + 卖出回钱（修静默丢弃 bug）③ 下一轮 BOSS 词条预告。把现有最强的策略轴（装哪 5 触发器+1 门）从"半残"变成完整可玩。

---

## 目标

代码审计（strategy-depth-roadmap）发现：构筑是当前最强策略轴，但被三处问题拖累——reroll 写完没接 UI、买触发器满槽静默丢弃（真 bug + 无取舍）、boss 词条已确定性 roll 却不展示（备战策略隐形）。本次三件小事打包，激活这层深度，新增三个真决策：**重掷 / 卖换取舍 / 备战 BOSS**。

## 设计原则
- **激活已有、低风险**：复用 `Shop.roll/reroll_cost`、确定性 `boss_mod`、现有装备逻辑；改动集中在商店 UI 接线 + `buy_shop_slot` 修复。
- **纯逻辑抽出可测**：sell 价、boss_mod 计算/文案做成纯静态函数 TDD。
- **零侵入 sim/物理/计分**：纯商店/经济层。
- **范围克制**：门暂保持"买入即替换、不单独卖"；不动 reroll 代价曲线/价格公式（实机调）。

---

## 现状（代码库事实，已核对）

- 基线 **262 测试全绿，38 脚本**。缩进 TAB。`run/shop.gd` 是 `class_name Shop extends Object`。
- `run/shop.gd`：`SLOT_COUNT=4`；`roll(master_seed, ante, node_cursor, reroll_count)`（tag=`ante*10000+node_cursor*100+reroll_count`，确定性）；`static reroll_cost(reroll_count)=1+reroll_count`（已测 `test_shop.gd`）；`buy(slot, inventory, money_ref)`（扣钱+标 sold+`inventory["items"].append`）；`_price_of(item, ante)`（实例方法，`base=[3,5,8,12][rarity]+ante/2`）；`_roll_item`/`_roll_from_pool`（35% 门/65% 触发器，稀有度权重）。
- `view/board_view.gd`：
  - `_show_shop_ui()`（697-708）：`_active_shop = Shop.new()`；`roll(seed, ante, round_in_ante, 0)`；`$Hud.show_shop(offerings, money)`。
  - `buy_shop_slot(slot)`（710-727）：`shop.buy(...)` → 成功后 `for item in inv["items"]`：`TriggerDef` 时 `if equipped.size() < 5: equipped.append(item.id)`（**满 5 静默丢弃 = bug，钱已扣**）；`GateDef` 时 `equipped_gate = item.id`。
  - `leave_shop()`（729-742）：清 shop、`RunMan.advance()`、重建棋盘、`_apply_boss_mod()`、`_refresh_equipped()`。
  - `_ready` 接 `$Hud.shop_slot_pressed.connect(buy_shop_slot)`、`shop_continue_pressed.connect(leave_shop)`。
- `view/hud.gd`：代码构建商店面板（`_build_shop_panel`，63-93）：PanelContainer→VBox→标题 + 4 个 slot 按钮（`shop_slot_pressed(slot)` 信号）+ Continue 按钮（`shop_continue_pressed`）。`show_shop(offerings, money)`（113-137）刷新 4 槽文案/可买态。`hide_shop()`。**无 reroll 按钮、无 equipped 展示、无 boss 预告**。
- `run/run_manager.gd`：`advance()`——ROUND/BOSS_ROUND→(过)→ANTE_CLEAR(`_payout`+`round_in_ante+=1` 进位 ante)→SHOP→`_start_round`。**每轮后都有商店**。`_start_round`（100-110）：`round_in_ante==2` 时 `boss_mod=_roll_boss_mod()`、phase=BOSS_ROUND。`_roll_boss_mod()`（119-124）：`DeterministicRng.derive(master_seed, ante*7+13)`，50% `{type:ban_mult}` / 50% `{type:sparse, remove_chance:0.30}`——**仅依赖 seed+ante，确定性**。`_payout`：money += base(3+ante)+launch_bonus(剩球)+interest(min(money/5,5))+targets(5)。
- `_apply_boss_mod()`（board_view 375+，读 `state["boss_mod"]`）：ban_mult→把 MULT 钉转 NORMAL；sparse→随机移除 30% 钉。
- **关键时序**：在 SHOP 时 `round_in_ante` 已是即将进入的那轮的序号 → `round_in_ante==2` ⟺ 下一轮是 boss，且其 `boss_mod` = `boss_mod_for(seed, ante)`（当前 ante，未变）。

---

## 系统组成

### A. `run/shop.gd`（加静态纯函数）
```gdscript
# 价格纯函数（抽出 _price_of 的逻辑，供 sell_value 与实例 _price_of 共用）
static func price_for(item: Resource, ante: int) -> int:
	var r: int = item.rarity if ("rarity" in item) else 0
	var base: int = ([3, 5, 8, 12] as Array[int])[clampi(r, 0, 3)]
	return base + ante / 2

# 卖出回收价 = 买价的一半（下取整，至少 1）
static func sell_value(item: Resource, ante: int) -> int:
	return maxi(1, price_for(item, ante) / 2)
```
`_price_of` 改为 `return price_for(item, ante)`（行为不变）。`reroll_cost` 不动。

### B. `run/run_manager.gd`（boss_mod 抽静态 + 文案）
```gdscript
static func boss_mod_for(master_seed: int, ante: int) -> Dictionary:
	var rng := DeterministicRng.derive(master_seed, ante * 7 + 13)
	if rng.next_float() < 0.5:
		return {&"type": &"ban_mult"}
	return {&"type": &"sparse", &"remove_chance": 0.30}

static func boss_mod_label(bm: Dictionary) -> String:
	match bm.get(&"type", &""):
		&"ban_mult": return "禁用 MULT 钉"
		&"sparse":   return "钉子稀疏 −30%"
		_:           return ""
```
`_roll_boss_mod()` 改为 `return boss_mod_for(state[&"master_seed"], state[&"ante"])`（行为不变；现有 `test_run_loop`/`test_run_manager` 的 boss_mod 非空断言仍通过）。

### C. `view/hud.gd`（商店面板扩展）
- 新信号：`shop_reroll_pressed`、`shop_sell_trigger_pressed(index: int)`。
- `_build_shop_panel` 增：
  - **Boss 预告 Label**（标题下，`_shop_boss_label`，红/橙色，默认空隐藏）。
  - **已装备触发器区**（一行/一列 `_equip_sell_btns`，最多 5 个按钮，文案 `卖 <id> (+N)`，点击 `shop_sell_trigger_pressed.emit(i)`）。
  - **Reroll 按钮**（slots 与 continue 之间，`_shop_reroll_btn`，文案 `Reroll (N gold)`）。
- `show_shop` 签名扩展为：
  `show_shop(offerings, money, reroll_cost, boss_preview: String, equipped: Array)`
  —— 刷新 4 槽（不变）+ reroll 按钮文案/可买态 + boss 预告（空则隐藏）+ equipped 卖出按钮（按 `equipped` 的 id 列表生成文案，回收价由 board_view 经 `Shop.sell_value` 预算后随 equipped 传入，或 HUD 仅显示 id、回收逻辑在 board_view）。
  > 实现细节（HUD 是否拿到 sell_value 文案 vs 只显 id）在 plan 阶段定；优先在 HUD 显示"卖 <id> (+N)"，N 由 board_view 计算后传入（避免 HUD 依赖 GameDB/ante）。

### D. `view/board_view.gd`（接线 + 修 bug）
- 新成员 `var _shop_reroll_count := 0`。
- `_ready` 增接线：`$Hud.shop_reroll_pressed.connect(reroll_shop)`、`$Hud.shop_sell_trigger_pressed.connect(sell_equipped_trigger)`。
- `_show_shop_ui`：`_shop_reroll_count = 0`；roll 用 `_shop_reroll_count`（=0）；调新的 `_refresh_shop_hud()`（统一组装 offerings/money/reroll_cost/boss_preview/equipped 传给 `$Hud.show_shop`）。
- `_refresh_shop_hud()`：算 `reroll_cost = Shop.reroll_cost(_shop_reroll_count)`；`boss_preview =` 若 `RunMan.state["round_in_ante"]==2` 则 `RunManager.boss_mod_label(RunManager.boss_mod_for(seed, ante))` 否则 `""`；`equipped =` 由 `RunMan.state["equipped_triggers"]` 映射成 `[{id, sell:int}]`（`sell=Shop.sell_value(GameDB.triggers[id], ante)`）；调 `$Hud.show_shop(...)`。`buy_shop_slot`/reroll/sell 后都调它（替换现有直接 `$Hud.show_shop`）。
- `reroll_shop()`：`cost=Shop.reroll_cost(_shop_reroll_count)`；`if money<cost: return`；`money-=cost`；`_shop_reroll_count+=1`；`_active_shop.roll(seed, ante, round_in_ante, _shop_reroll_count)`；`_refresh_shop_hud()`；`_sync_hud()`。
- `sell_equipped_trigger(index)`：边界检查；`var id = equipped[index]`；`money += Shop.sell_value(GameDB.triggers[id], ante)`；`equipped.remove_at(index)`；`_refresh_shop_hud()`；`_refresh_equipped()`；`_sync_hud()`。
- **修 bug** `buy_shop_slot`：在 `shop.buy` **之前**取 `offer.item`，若是 `TriggerDef` 且 `equipped_triggers.size() >= 5` → **不买**（return，HUD 提示"触发器已满，先卖一个"），不扣钱。否则照常 buy + 装备（装备时仍 `< 5` 守卫，但前置拦截后不会再丢弃）。门照常替换。

---

## 数据流

```
进店 _show_shop_ui: _shop_reroll_count=0; shop.roll(...,0); _refresh_shop_hud()
_refresh_shop_hud(): 组装 offerings + money + reroll_cost + boss_preview(round_in_ante==2?) + equipped(id+sell) → Hud.show_shop
买槽 buy_shop_slot(slot): [触发器满槽→拦截不扣钱] 否则 shop.buy→装备→_refresh_shop_hud
重掷 reroll_shop(): 够钱→扣 reroll_cost、count++、shop.roll(...,count)→_refresh_shop_hud
卖出 sell_equipped_trigger(i): 退 sell_value、移除装备→_refresh_shop_hud + _refresh_equipped
离店 leave_shop(): 不变
```

---

## 测试策略

- **纯函数（TDD）**：
  - `Shop.price_for`（rarity 0-3 → 3/5/8/12 + ante/2）、`Shop.sell_value`（=半价、≥1）—— `tests/test_shop.gd` 追加。
  - `RunManager.boss_mod_for`（同 seed+ante 可复现、type 合法）、`boss_mod_label`（ban_mult/sparse/未知→对应文案/空）—— `tests/test_run_manager.gd` 或 `test_run_loop.gd` 追加。
  - `reroll_cost` 已测，不动。
- **HUD/board_view**：场景冒烟（board.tscn load+instantiate）+ 实机（view 层无单测，项目惯例）。现有 boss_mod 非空断言（`test_run_loop`/`test_run_manager`）须保持通过（`_roll_boss_mod` 行为不变）。

---

## 验收标准

- [ ] 商店有 **Reroll 按钮**，显示当前花费，点击花钱重掷 4 槽（代价递增），钱不够禁用
- [ ] 买触发器满 5 槽时**不再静默扣钱丢弃**；提示先卖
- [ ] 商店展示已装备触发器，可**卖出**回收一半金钱、腾出槽位
- [ ] boss 轮前一个商店显示 **⚠ 下一轮 BOSS：禁用 MULT 钉 / 钉子稀疏 −30%**；非 boss 轮前不显示
- [ ] 新纯函数（price_for/sell_value/boss_mod_for/boss_mod_label）全单测通过；boss_mod 行为不变（现有测试绿）；全套绿
- [ ] 无回归：商店买/继续、装备、计分、棋盘、确定性正常；board 场景冒烟 OK

---

## Backlog / 留待后续
- 门也可卖/多门槽位。
- reroll 代价/价格/sellback 比例曲线实机调（记 balance-tunables）。
- boss 预告做成更醒目的图标/动画。
- 商店内"装备区"做成可视卡片（当前文字按钮够用）。

---

## 已知风险 / 留意
- HUD 商店面板尺寸（420×300）加 boss 预告 + 5 个卖出按钮 + reroll，可能需调 `custom_minimum_size`/布局（plan 阶段定，实机微调）。
- `GameDB.triggers[id]` 取 def 的确切结构 + `_refresh_equipped` 实现，plan 阶段核对。
- sell_value 用"当前 ante 价"的一半（非买入价），简化且无需记账；可接受。
