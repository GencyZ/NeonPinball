# 商店/构筑策略第一档打包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 激活构筑-经济策略：① 商店 Reroll 接线 ② 触发器满槽可卖/换 + 卖出回钱（修静默丢弃 bug）③ 下一轮 BOSS 词条预告。

**Architecture:** 纯逻辑（sell 价、boss_mod 计算/文案）抽成静态函数 TDD；HUD 商店面板加 reroll 按钮 / boss 预告 / equipped 卖出按钮（新 param 带默认值，向后兼容）；board_view 接线 + 修 `buy_shop_slot`。复用现有 `Shop.roll/reroll_cost`、确定性 boss_mod、`_refresh_equipped`，零侵入 sim。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库事实，已核对）

- 项目根 `D:/NeonPinball/game/`。Godot `/d/Program/Godot/godot`（不在 PATH）。缩进 **TAB**。
- 全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
- **基线：262 测试全绿，38 脚本。** 每任务只提交自己的文件。**不要 push、不要新建分支（main）。**
- spec：`docs/superpowers/specs/2026-06-17-shop-depth-tier1-design.md`。
- `run/shop.gd`（`class_name Shop extends Object`）：`static reroll_cost(n)=1+n`（已测）；`_price_of(item, ante)`（74-79，实例方法）：`var r = item.rarity if "rarity" in item else 0; base=[3,5,8,12][clampi(r,0,3)]; return base + ante/2`。`roll(seed, ante, node_cursor, reroll_count)`、`buy(slot, inv, money_ref)`。
- `run/run_manager.gd`：`_roll_boss_mod()`（119-124，实例方法读 state）：`DeterministicRng.derive(master_seed, ante*7+13)`，<0.5→`{type:ban_mult}` 否则 `{type:sparse, remove_chance:0.30}`。`equipped_triggers` 默认 `[&"peg_bonus",&"bounce_mult",&"big_hit"]`（StringName 数组，上限 5）、`equipped_gate=&"normal"`（StringName）。
- `view/board_view.gd`：`const RunManagerScript := preload("res://run/run_manager.gd")`（11）；`Shop` 直接用（`Shop.new()`）；`GameDB` autoload（`GameDB.triggers.has(id)`/`GameDB.triggers[id]`→TriggerDef）。
  - `_ready` 商店接线（124-125）：`$Hud.shop_slot_pressed.connect(buy_shop_slot)`、`$Hud.shop_continue_pressed.connect(leave_shop)`。
  - `_show_shop_ui()`（697-708）、`buy_shop_slot(slot)`（710-727，含满槽静默丢弃 bug）、`_refresh_equipped()`（397-404，从 `equipped_triggers` 重建 `_trigger_runtimes` + set gate）。
- `view/hud.gd`：`_build_shop_panel()`（63-93）：PanelContainer(420×300)→VBox→标题 + 4 slot 按钮(`shop_slot_pressed`) + Continue(`shop_continue_pressed`)。`show_shop(offerings, money)`（113-137）。`hide_shop()`。
- `tests/test_shop.gd`：有 `const ShopScript := preload("res://run/shop.gd")` + `_shop` 实例 + reroll 测试。`tests/test_run_manager.gd`：有 `const RunManagerScript := preload("res://run/run_manager.gd")`（用 `RunManagerScript.Phase`）。

---

## 文件结构
- **修改**：`run/shop.gd`、`run/run_manager.gd`、`tests/test_shop.gd`、`tests/test_run_manager.gd`（T1）；`view/hud.gd`（T2）；`view/board_view.gd`（T3）

---

## Task 1：纯静态函数 + 测试（price_for / sell_value / boss_mod_for / boss_mod_label）

**Files:** Modify `run/shop.gd`, `run/run_manager.gd`, `tests/test_shop.gd`, `tests/test_run_manager.gd`

- [ ] **Step 1: 写失败测试** —— `tests/test_shop.gd` 末尾追加（文件已有 `const ShopScript := preload("res://run/shop.gd")`）：
```gdscript
const TriggerDefScript := preload("res://data/trigger_def.gd")

func _trig(rarity: int) -> Resource:
	var t = TriggerDefScript.new()
	t.rarity = rarity
	return t

func test_price_for_by_rarity() -> void:
	assert_eq(ShopScript.price_for(_trig(0), 0), 3, "rarity0 → 3")
	assert_eq(ShopScript.price_for(_trig(1), 0), 5, "rarity1 → 5")
	assert_eq(ShopScript.price_for(_trig(2), 0), 8, "rarity2 → 8")
	assert_eq(ShopScript.price_for(_trig(3), 0), 12, "rarity3 → 12")
	assert_eq(ShopScript.price_for(_trig(0), 4), 5, "+ante/2：3 + 4/2 = 5")

func test_sell_value_is_half_min_one() -> void:
	assert_eq(ShopScript.sell_value(_trig(2), 0), 4, "8/2 = 4")
	assert_eq(ShopScript.sell_value(_trig(0), 0), 1, "max(1, 3/2=1)")
```

`tests/test_run_manager.gd` 末尾追加：
```gdscript
func test_boss_mod_for_deterministic() -> void:
	var a: Dictionary = RunManagerScript.boss_mod_for(12345, 3)
	var b: Dictionary = RunManagerScript.boss_mod_for(12345, 3)
	assert_eq(a.get(&"type"), b.get(&"type"), "同 seed+ante 可复现")
	assert_true(a.get(&"type") == &"ban_mult" or a.get(&"type") == &"sparse", "type 合法")

func test_boss_mod_label_mapping() -> void:
	assert_eq(RunManagerScript.boss_mod_label({&"type": &"ban_mult"}), "禁用 MULT 钉")
	assert_eq(RunManagerScript.boss_mod_label({&"type": &"sparse", &"remove_chance": 0.3}), "钉子稀疏 −30%")
	assert_eq(RunManagerScript.boss_mod_label({}), "", "未知/空 → 空串")
```

- [ ] **Step 2: 跑确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_shop.gd -gexit`
`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_run_manager.gd -gexit`
预期：新测失败（方法不存在）。

- [ ] **Step 3: 实现**
(a) `run/shop.gd`：把 `_price_of`（74-79）替换为：
```gdscript
# 价格纯函数（供 sell_value 与实例 _price_of 共用）
static func price_for(item: Resource, ante: int) -> int:
	var r: int = item.rarity if ("rarity" in item) else 0
	var base: int = ([3, 5, 8, 12] as Array[int])[clampi(r, 0, 3)]
	return base + ante / 2

# 卖出回收价 = 当前 ante 价的一半（下取整，至少 1）
static func sell_value(item: Resource, ante: int) -> int:
	return maxi(1, price_for(item, ante) / 2)

func _price_of(item: Resource, ante: int) -> int:
	return price_for(item, ante)
```
(b) `run/run_manager.gd`：把 `_roll_boss_mod()`（119-124）替换为：
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

func _roll_boss_mod() -> Dictionary:
	return boss_mod_for(state[&"master_seed"], state[&"ante"])
```

- [ ] **Step 4: 跑确认通过**

两个单文件应全过。全套应 **266**（262 + 4 新）：
`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
（现有 boss_mod 非空断言仍绿——`_roll_boss_mod` 行为不变。）

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add run/shop.gd run/run_manager.gd tests/test_shop.gd tests/test_run_manager.gd
git -C D:/NeonPinball/game commit -m "feat: Shop.price_for/sell_value + RunManager.boss_mod_for/boss_mod_label statics"
```

---

## Task 2：HUD 商店面板扩展（reroll / boss 预告 / equipped 卖出）

**Files:** Modify `view/hud.gd`

> 新 param 带默认值 → 旧 2-arg `show_shop` 调用仍工作（T3 前不破）。无单测，靠场景冒烟。

- [ ] **Step 1: 加信号 + 成员** —— 找到：
```gdscript
signal shop_slot_pressed(slot: int)
signal shop_continue_pressed
```
在其**后**加：
```gdscript
signal shop_reroll_pressed
signal shop_sell_trigger_pressed(index: int)
```
找到 shop 成员区：
```gdscript
var _shop_slots: Array[Button] = []
var _shop_continue_btn: Button
```
在其**后**加：
```gdscript
var _shop_boss_label: Label
var _shop_hint: Label
var _shop_sell_btns: Array[Button] = []
var _shop_reroll_btn: Button
```

- [ ] **Step 2: 扩 `_build_shop_panel`** —— 把整个 `_build_shop_panel()` 替换为：
```gdscript
func _build_shop_panel() -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.position = Vector2(60, 180)
	_shop_panel.custom_minimum_size = Vector2(420, 480)
	_shop_panel.visible = false
	add_child(_shop_panel)

	var vbox := VBoxContainer.new()
	_shop_panel.add_child(vbox)

	_shop_title = Label.new()
	_shop_title.text = "=== SHOP ==="
	_shop_title.add_theme_font_size_override(&"font_size", 24)
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_shop_title)

	_shop_boss_label = Label.new()
	_shop_boss_label.add_theme_font_size_override(&"font_size", 17)
	_shop_boss_label.modulate = Color(1.0, 0.5, 0.3)
	_shop_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_boss_label.visible = false
	vbox.add_child(_shop_boss_label)

	for i in 4:
		var btn := Button.new()
		btn.add_theme_font_size_override(&"font_size", 17)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot_idx := i
		btn.pressed.connect(func(): shop_slot_pressed.emit(slot_idx))
		vbox.add_child(btn)
		_shop_slots.append(btn)

	_shop_reroll_btn = Button.new()
	_shop_reroll_btn.add_theme_font_size_override(&"font_size", 16)
	_shop_reroll_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_reroll_btn.visible = false
	_shop_reroll_btn.pressed.connect(func(): shop_reroll_pressed.emit())
	vbox.add_child(_shop_reroll_btn)

	var equip_label := Label.new()
	equip_label.text = "— 已装备触发器（点击卖出）—"
	equip_label.add_theme_font_size_override(&"font_size", 14)
	equip_label.modulate = Color(0.7, 0.9, 1.0)
	equip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(equip_label)

	for i in 5:
		var sbtn := Button.new()
		sbtn.add_theme_font_size_override(&"font_size", 15)
		sbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sbtn.visible = false
		var sell_idx := i
		sbtn.pressed.connect(func(): shop_sell_trigger_pressed.emit(sell_idx))
		vbox.add_child(sbtn)
		_shop_sell_btns.append(sbtn)

	_shop_hint = Label.new()
	_shop_hint.add_theme_font_size_override(&"font_size", 14)
	_shop_hint.modulate = Color(1.0, 0.7, 0.4)
	_shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_hint.text = ""
	vbox.add_child(_shop_hint)

	_shop_continue_btn = Button.new()
	_shop_continue_btn.text = "Continue →  (Space)"
	_shop_continue_btn.add_theme_font_size_override(&"font_size", 16)
	_shop_continue_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_continue_btn.pressed.connect(func(): shop_continue_pressed.emit())
	vbox.add_child(_shop_continue_btn)
```

- [ ] **Step 3: 扩 `show_shop`** —— 把整个 `show_shop(...)` 替换为：
```gdscript
func show_shop(offerings: Array, money: int, reroll_cost: int = -1, boss_preview: String = "", equipped: Array = []) -> void:
	_shop_visible = true
	_shop_panel.visible = true

	for i in 4:
		_shop_slots[i].text = ""
		_shop_slots[i].disabled = false
		_shop_slots[i].modulate = Color.WHITE

	for i in mini(offerings.size(), 4):
		var offer: Dictionary = offerings[i]
		var item: Resource = offer.get(&"item")
		var name_str: String = String(item.id) if item != null and "id" in item else "Unknown"
		var price: int = offer.get(&"price", 0)
		var is_sold: bool = offer.get(&"sold", false)
		if is_sold:
			_shop_slots[i].text = "[%d] SOLD" % (i + 1)
			_shop_slots[i].disabled = true
			_shop_slots[i].modulate = Color(0.4, 0.4, 0.4)
		else:
			var can_afford := money >= price
			_shop_slots[i].text = "[%d] %s  (%d gold)" % [i + 1, name_str, price]
			_shop_slots[i].disabled = not can_afford
			_shop_slots[i].modulate = Color(1, 1, 0.5) if can_afford else Color(0.5, 0.5, 0.5)

	# Boss 预告
	_shop_boss_label.text = "⚠ 下一轮 BOSS：" + boss_preview
	_shop_boss_label.visible = boss_preview != ""

	# Reroll 按钮
	if reroll_cost < 0:
		_shop_reroll_btn.visible = false
	else:
		_shop_reroll_btn.visible = true
		_shop_reroll_btn.text = "Reroll  (%d gold)" % reroll_cost
		_shop_reroll_btn.disabled = money < reroll_cost
		_shop_reroll_btn.modulate = Color(0.7, 1, 1) if money >= reroll_cost else Color(0.5, 0.5, 0.5)

	# 已装备触发器卖出按钮
	for i in 5:
		if i < equipped.size():
			var e: Dictionary = equipped[i]
			_shop_sell_btns[i].text = "卖 %s  (+%d gold)" % [String(e.get(&"id", &"?")), int(e.get(&"sell", 0))]
			_shop_sell_btns[i].visible = true
			_shop_sell_btns[i].disabled = false
		else:
			_shop_sell_btns[i].visible = false

	# 满槽提示
	_shop_hint.text = "触发器已满（5），卖一个再买" if equipped.size() >= 5 else ""
```

- [ ] **Step 4: 场景冒烟**
写 `/tmp/sh.gd`（同前：load+instantiate `res://scenes/board.tscn`，print BOARD_OK/FAIL，quit），跑：
`/d/Program/Godot/godot --headless --path . -s /tmp/sh.gd 2>&1 | grep -iE "BOARD_OK|BOARD_FAIL|Parse Error|SCRIPT ERROR"`
预期 `BOARD_OK`，无新增 Parse/SCRIPT error。`rm -f /tmp/sh.gd`。
全套仍 **266**（HUD 无单测，旧 2-arg show_shop 调用因默认值仍工作）。

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add view/hud.gd
git -C D:/NeonPinball/game commit -m "feat: shop HUD — reroll button, boss telegraph, equipped sell buttons"
```

---

## Task 3：board_view 接线 + 修 buy bug

**Files:** Modify `view/board_view.gd`

- [ ] **Step 1: 加成员** —— 找到 `var _active_shop: Shop = null`，在其**后**加：
```gdscript
var _shop_reroll_count := 0
```

- [ ] **Step 2: `_ready` 接新信号** —— 找到：
```gdscript
	$Hud.shop_slot_pressed.connect(buy_shop_slot)
	$Hud.shop_continue_pressed.connect(leave_shop)
```
在其**后**加：
```gdscript
	$Hud.shop_reroll_pressed.connect(reroll_shop)
	$Hud.shop_sell_trigger_pressed.connect(sell_equipped_trigger)
```

- [ ] **Step 3: `_show_shop_ui` 重置 reroll 计数 + 用统一刷新** —— 把整个 `_show_shop_ui()` 替换为：
```gdscript
func _show_shop_ui() -> void:
	_live_target = 0.0
	_score_ticker.reset()
	_shop_reroll_count = 0
	_active_shop = Shop.new()
	_active_shop.roll(
		RunMan.state[&"master_seed"],
		RunMan.state[&"ante"],
		RunMan.state[&"round_in_ante"],
		_shop_reroll_count,
	)
	_refresh_shop_hud()
	_sync_hud()
```

- [ ] **Step 4: 加 `_refresh_shop_hud` + `reroll_shop` + `sell_equipped_trigger`** —— 在 `_show_shop_ui` 之后插入：
```gdscript
# 统一组装商店 HUD（offerings + money + reroll 花费 + boss 预告 + 已装备卖价）。
func _refresh_shop_hud() -> void:
	if _active_shop == null:
		return
	var ante: int = RunMan.state[&"ante"]
	var reroll_cost: int = Shop.reroll_cost(_shop_reroll_count)
	var boss_preview: String = ""
	if int(RunMan.state[&"round_in_ante"]) == 2:
		boss_preview = RunManagerScript.boss_mod_label(
			RunManagerScript.boss_mod_for(int(RunMan.state[&"master_seed"]), ante))
	var equipped: Array = []
	for tid in RunMan.state[&"equipped_triggers"]:
		var sell: int = 1
		if GameDB.triggers.has(tid):
			sell = Shop.sell_value(GameDB.triggers[tid], ante)
		equipped.append({&"id": tid, &"sell": sell})
	$Hud.show_shop(_active_shop.offerings, RunMan.state[&"money"], reroll_cost, boss_preview, equipped)

func reroll_shop() -> void:
	if _active_shop == null:
		return
	var cost: int = Shop.reroll_cost(_shop_reroll_count)
	if int(RunMan.state[&"money"]) < cost:
		return
	RunMan.state[&"money"] = int(RunMan.state[&"money"]) - cost
	_shop_reroll_count += 1
	_active_shop.roll(
		RunMan.state[&"master_seed"],
		RunMan.state[&"ante"],
		RunMan.state[&"round_in_ante"],
		_shop_reroll_count,
	)
	_refresh_shop_hud()
	_sync_hud()

func sell_equipped_trigger(index: int) -> void:
	if _active_shop == null:
		return
	var equipped: Array = RunMan.state[&"equipped_triggers"]
	if index < 0 or index >= equipped.size():
		return
	var tid = equipped[index]
	var ante: int = RunMan.state[&"ante"]
	if GameDB.triggers.has(tid):
		RunMan.state[&"money"] = int(RunMan.state[&"money"]) + Shop.sell_value(GameDB.triggers[tid], ante)
	equipped.remove_at(index)
	_refresh_equipped()
	_refresh_shop_hud()
	_sync_hud()
```

- [ ] **Step 5: 修 `buy_shop_slot`（满槽拦截 + 统一刷新）** —— 把整个 `buy_shop_slot(slot)` 替换为：
```gdscript
func buy_shop_slot(slot: int) -> void:
	if _active_shop == null:
		return
	if slot < 0 or slot >= _active_shop.offerings.size():
		return
	var offer: Dictionary = _active_shop.offerings[slot]
	var item: Resource = offer.get(&"item")
	# 触发器满 5 槽：先拦截，不扣钱（修静默丢弃 bug）；提示先卖
	if item is TriggerDef and (RunMan.state[&"equipped_triggers"] as Array).size() >= 5:
		_refresh_shop_hud()
		return
	var money_ref := [RunMan.state[&"money"]]
	var inv := {&"items": []}
	var ok := _active_shop.buy(slot, inv, money_ref)
	if not ok:
		return
	RunMan.state[&"money"] = money_ref[0]
	for it in inv[&"items"]:
		if it is TriggerDef:
			(RunMan.state[&"equipped_triggers"] as Array).append(it.id)
		elif it is GateDef:
			RunMan.state[&"equipped_gate"] = it.id
	_refresh_shop_hud()
	_sync_hud()
```

- [ ] **Step 6: 验证场景加载 + 全套**
(a) 场景冒烟（同 T2 的 `/tmp/sh.gd`）→ 期望 `BOARD_OK`，无新增 Parse/SCRIPT error，然后 `rm -f /tmp/sh.gd`。
(b) `grep -n "show_shop" view/board_view.gd` → 确认所有调用都已走 `_refresh_shop_hud()`（无残留旧 `$Hud.show_shop(offerings, money)` 两参调用）。
(c) 全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit` → 期望 **266** 全绿。若失败/解析错，修到全绿。

> 实机验收（用户人工）：① 商店有 Reroll 按钮、花钱重掷、代价递增、钱不够禁用 ② 买触发器满 5 槽不再静默扣钱、显示"已满"提示 ③ 已装备触发器可点击卖出回收一半金钱、腾位 ④ boss 轮前一个商店显示 ⚠ 下一轮 BOSS 词条、非 boss 轮前不显示 ⑤ 买/卖/重掷后金钱、装备、gate 标签即时更新。

- [ ] **Step 7: 提交**
```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: wire shop reroll + sell-equipped + boss telegraph; fix full-slot silent drop"
```

---

## 自检清单

- [ ] **Spec 覆盖**：Reroll 接线(T2 按钮/信号 + T3 reroll_shop) ✓；满槽拦截修 bug(T3 Step5 守卫) ✓；卖出回钱(T1 sell_value + T2 卖出按钮 + T3 sell_equipped_trigger) ✓；Boss 预告(T1 boss_mod_for/label + T3 round_in_ante==2 计算 + T2 label) ✓；纯函数单测(T1) ✓；boss_mod 行为不变(T1 _roll_boss_mod 委托) ✓；零侵入 sim ✓
- [ ] **占位符扫描**：每步完整代码 + 确切命令 ✓
- [ ] **类型/签名一致性**：
  - `Shop.price_for(item, ante)` / `sell_value(item, ante)` —— 定义(T1)、测试(T1)、调用(T3 _refresh_shop_hud/sell) 一致 ✓
  - `RunManagerScript.boss_mod_for(seed, ante)` / `boss_mod_label(bm)` —— 定义(T1)、测试(T1)、调用(T3) 一致 ✓
  - `show_shop(offerings, money, reroll_cost=-1, boss_preview="", equipped=[])` —— 定义(T2)、调用(T3 _refresh_shop_hud 五参) 一致；默认值保证 T2→T3 间旧调用不破 ✓
  - 信号 `shop_reroll_pressed`/`shop_sell_trigger_pressed(index)` —— 声明(T2)、emit(T2 按钮)、connect(T3 _ready) 一致 ✓
  - `_shop_reroll_count` 声明(T3 Step1)、重置(Step3)、用(reroll_shop/_refresh_shop_hud) 闭环 ✓
  - `equipped` 元素 `{id, sell}` —— T3 组装、T2 渲染(`e.get("id")`/`e.get("sell")`) 一致 ✓
- [ ] **范围**：仅商店三件事；门不单独卖、不动 reroll/价格曲线、不做醒目 boss 图标 留 Backlog ✓

---

## 备注 / 已知行为
- 卖价 = 当前 ante 价的一半（不记买入价），简化无需记账（spec 已定）。
- HUD 面板尺寸调到 420×480 容纳新控件；实机若溢出再调（balance/UI）。
- T2 的 `show_shop` 新 param 带默认值 → T2 单独提交后、T3 未接前，旧 2-arg 调用仍工作（reroll/boss/equipped 隐藏），中间状态干净。
- reroll 后已售槽刷新为全新 4 槽（标准 roguelike 行为）；已花的钱不退。
- 满槽拦截走 `_refresh_shop_hud()` 让"已满"提示即时显示；不扣钱。
- 数值（reroll 代价、sellback 比例、价格）记 `docs/superpowers/balance-tunables.md`，实机调。
