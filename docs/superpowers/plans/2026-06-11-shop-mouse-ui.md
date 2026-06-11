# 商店鼠标 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将商店的 1-4 键购买 / Space 继续改为可点击按钮，同时保留原有键盘快捷键，实现鼠标+键盘双支持。

**Architecture:**
- 购买逻辑当前写在 `input_controller._handle_shop_key()` 里，鼠标按钮无法复用它 → **先把购买逻辑迁移到 `board_view.buy_shop_slot(slot)` 公共方法**，input_controller 变成薄委托
- `hud.gd` 商店面板：4 个 `Label` 改为 4 个 `Button`，新增 `Button "Continue →"`；通过信号 `shop_slot_pressed(slot)` / `shop_continue_pressed` 通知 board_view
- `board_view` 在 `_ready()` 里连接 HUD 信号，无需 HUD 持有 board_view 引用（依赖方向不反转）
- 键盘路径（input_controller）保持不变，只改为调用 `_board.buy_shop_slot(slot)` / `_board.leave_shop()`

**Tech Stack:** Godot 4.6.3 GDScript, GUT。

---

## Background（代码库上下文）

- 项目根目录：`D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**150 个测试**全部通过。
- 每个任务只提交它自己改动的文件。**不要 push。**

### 当前商店数据流

```
board_view._show_shop_ui()
    → _active_shop = Shop.new(); _active_shop.roll(...)
    → $Hud.show_shop(_active_shop.offerings, money)   # 显示 4 个 Label

input_controller._handle_shop_key(keycode)
    → shop = _board._active_shop
    → shop.buy(slot, inv, money_ref)                   # 购买逻辑
    → RunMan.state[&"money"] = money_ref[0]
    → for item in inv: 更新 equipped_triggers/gate
    → _board.get_node("Hud").show_shop(...)            # 刷新 HUD
    → _board._sync_hud()

    KEY_SPACE → _board.leave_shop()
        → $Hud.hide_shop(); RunMan.advance(); 重建 board
```

**问题：** 购买逻辑藏在 input_controller 里，HUD 按钮触发时找不到入口。

### 目标数据流（改后）

```
board_view._show_shop_ui()
    → 同上，shop 面板由 HUD 用 Button 显示

[鼠标] Hud Button.pressed → emit shop_slot_pressed(slot)
    → board_view.buy_shop_slot(slot)   ← 统一入口

[键盘] input_controller._handle_shop_key → _board.buy_shop_slot(slot)  ← 同一入口

board_view.buy_shop_slot(slot)
    → shop.buy(slot, inv, money_ref)
    → 更新 RunMan state
    → $Hud.show_shop(...)   # 刷新按钮文字 / 禁用状态
    → _sync_hud()

[鼠标] Hud Continue Button.pressed → emit shop_continue_pressed
    → board_view.leave_shop()

[键盘] input_controller KEY_SPACE → _board.leave_shop()  ← 同上
```

### 现有关键 API

**`hud.gd`**
```gdscript
var _shop_slots: Array[Label] = []   # ← 改为 Array[Button]

func show_shop(offerings: Array, money: int) -> void:
    # 当前：刷新 Label 的 .text 和 .modulate
    # 改后：刷新 Button 的 .text / .disabled / .modulate

func hide_shop() -> void:
func is_shop_visible() -> bool:
```

**`board_view.gd`**
```gdscript
var _active_shop: Shop = null

func _show_shop_ui() -> void:   # 开启商店
func leave_shop() -> void:      # 关闭商店，进入下一轮
func _sync_hud() -> void:       # 刷新 HUD 标签
```

**`input_controller.gd`**
```gdscript
func _handle_shop_key(keycode: Key) -> void:
    # KEY_1-4 → buy logic（待迁移）
    # KEY_SPACE → _board.leave_shop()
```

**`Shop` (`run/shop.gd`)**
```gdscript
func buy(slot: int, inventory: Dictionary, money_ref: Array) -> bool:
    # money_ref 是 [money_value] 包装，买成功后 money_ref[0] 减少
var offerings: Array   # Array[Dictionary{item, price, sold}]
```

---

## Task 1：购买逻辑迁移至 board_view

**改动：** `board_view.gd`、`input_controller.gd`

- [ ] **修改 `board_view.gd`**：新增 `buy_shop_slot(slot: int) -> void` 公共方法，把购买逻辑从 input_controller 搬过来。

  在 `leave_shop()` 附近插入：

  ```gdscript
  func buy_shop_slot(slot: int) -> void:
      if _active_shop == null:
          return
      var money_ref := [RunMan.state[&"money"]]
      var inv := {&"items": []}
      var ok := _active_shop.buy(slot, inv, money_ref)
      if not ok:
          return
      RunMan.state[&"money"] = money_ref[0]
      for item in inv[&"items"]:
          if item is TriggerDef:
              var equipped: Array = RunMan.state[&"equipped_triggers"]
              if equipped.size() < 5:
                  equipped.append(item.id)
          elif item is GateDef:
              RunMan.state[&"equipped_gate"] = item.id
      $Hud.show_shop(_active_shop.offerings, RunMan.state[&"money"])
      _sync_hud()
  ```

- [ ] **修改 `input_controller.gd`**：`_handle_shop_key()` 改为薄委托，删除原购买逻辑。

  **改前：**
  ```gdscript
  func _handle_shop_key(keycode: Key) -> void:
      var shop: Shop = _board._active_shop
      if shop == null:
          return
      var slot := -1
      match keycode:
          KEY_1: slot = 0
          KEY_2: slot = 1
          KEY_3: slot = 2
          KEY_4: slot = 3
          KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
              _board.leave_shop()
              return
      if slot < 0:
          return
      var money_ref := [RunMan.state[&"money"]]
      var inv := {&"items": []}
      var ok := shop.buy(slot, inv, money_ref)
      if ok:
          RunMan.state[&"money"] = money_ref[0]
          for item in inv[&"items"]:
              if item is TriggerDef:
                  var equipped: Array = RunMan.state[&"equipped_triggers"]
                  if equipped.size() < 5:
                      equipped.append(item.id)
              elif item is GateDef:
                  RunMan.state[&"equipped_gate"] = item.id
          _board.get_node("Hud").show_shop(shop.offerings, RunMan.state[&"money"])
          _board._sync_hud()
  ```

  **改后：**
  ```gdscript
  func _handle_shop_key(keycode: Key) -> void:
      match keycode:
          KEY_1: _board.buy_shop_slot(0)
          KEY_2: _board.buy_shop_slot(1)
          KEY_3: _board.buy_shop_slot(2)
          KEY_4: _board.buy_shop_slot(3)
          KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
              _board.leave_shop()
  ```

- [ ] **运行测试**，确认购买逻辑迁移后行为不变：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
  **预期：** 150 个测试全部通过，退出码 0。

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd view/input_controller.gd
  git -C D:/NeonPinball/game commit -m "refactor: move shop buy logic to board_view.buy_shop_slot()"
  ```

---

## Task 2：hud.gd 商店面板改用按钮 + 信号

**改动：** `hud.gd`

- [ ] **修改 `hud.gd`**：

  **声明区**：把 Label 数组改为 Button 数组，新增信号和 Continue 按钮变量：

  ```gdscript
  # ---- Shop panel ----
  var _shop_panel: PanelContainer
  var _shop_title: Label
  var _shop_slots: Array[Button] = []   # ← Label 改 Button
  var _shop_continue_btn: Button        # ← 新增
  var _shop_visible := false

  signal shop_slot_pressed(slot: int)   # ← 新增
  signal shop_continue_pressed          # ← 新增
  ```

  **`_build_shop_panel()`**：把 4 个 Label 改为 4 个 Button，删除旧 hint Label，添加 Continue 按钮：

  ```gdscript
  func _build_shop_panel() -> void:
      _shop_panel = PanelContainer.new()
      _shop_panel.position = Vector2(60, 160)
      _shop_panel.custom_minimum_size = Vector2(420, 320)
      _shop_panel.visible = false
      add_child(_shop_panel)

      var vbox := VBoxContainer.new()
      _shop_panel.add_child(vbox)

      _shop_title = Label.new()
      _shop_title.text = "=== SHOP ==="
      _shop_title.add_theme_font_size_override(&"font_size", 24)
      _shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      vbox.add_child(_shop_title)

      for i in 4:
          var btn := Button.new()
          btn.add_theme_font_size_override(&"font_size", 17)
          btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
          var slot_idx := i   # 捕获循环变量
          btn.pressed.connect(func(): shop_slot_pressed.emit(slot_idx))
          vbox.add_child(btn)
          _shop_slots.append(btn)

      _shop_continue_btn = Button.new()
      _shop_continue_btn.text = "Continue →  (Space)"
      _shop_continue_btn.add_theme_font_size_override(&"font_size", 16)
      _shop_continue_btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
      _shop_continue_btn.pressed.connect(func(): shop_continue_pressed.emit())
      vbox.add_child(_shop_continue_btn)
  ```

  **`show_shop()`**：改为更新 Button 的 text、disabled、modulate：

  ```gdscript
  func show_shop(offerings: Array, money: int) -> void:
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
  ```

  > - 买得起：按钮正常可点、黄色
  > - 买不起：`disabled = true`、灰色（无法点击）
  > - 已购买：`disabled = true`、深灰 + "SOLD" 文字

- [ ] **运行测试**：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
  **预期：** 150 个测试全部通过（hud 改动无纯逻辑新测试，冒烟由既有 board 测试覆盖）。

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/hud.gd
  git -C D:/NeonPinball/game commit -m "feat: shop panel uses Button slots with signals (shop_slot_pressed / shop_continue_pressed)"
  ```

---

## Task 3：board_view 连接 HUD 信号

**改动：** `board_view.gd`

- [ ] **修改 `board_view.gd` 的 `_ready()`**：连接 HUD 商店信号。

  在 `_ready()` 末尾追加：

  ```gdscript
  func _ready() -> void:
      # ... 原有代码 ...
      $Hud.shop_slot_pressed.connect(buy_shop_slot)
      $Hud.shop_continue_pressed.connect(leave_shop)
  ```

  > `buy_shop_slot` 和 `leave_shop` 都是 `board_view` 的方法，`connect` 直接传方法引用即可，无需 lambda。

- [ ] **运行测试**：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
  **预期：** 150 个测试全部通过，退出码 0。

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: connect HUD shop signals to board_view (mouse buy/continue)"
  ```

---

## 文件结构

**修改（共 3 个文件）：**

| 文件 | 改动内容 |
|------|---------|
| `view/board_view.gd` | 新增 `buy_shop_slot(slot)`；`_ready()` 里连接 HUD 信号 |
| `view/input_controller.gd` | `_handle_shop_key()` 改为薄委托（3 行） |
| `view/hud.gd` | Label 槽位改 Button；新增 Continue 按钮；新增两个信号 |

**无新文件，无新测试文件**（现有冒烟测试已覆盖场景加载与 HUD 实例化）。

---

## 自检清单

- [ ] 150 个基线测试全部通过（无回归）
- [ ] 商店阶段：4 个物品槽显示为按钮，点击可购买
- [ ] 买得起的物品：按钮可点、黄色；买不起：灰色禁用；已购买：灰色 SOLD
- [ ] "Continue →" 按钮点击后进入下一轮
- [ ] 键盘 1-4 / Space 仍然生效（input_controller 委托路径正常）
- [ ] 购买后按钮状态立即刷新（show_shop 重调）
- [ ] 无回归：局内弹球、商店键盘、WIN/LOSE 按钮等原有功能正常

---

## 已知局限 / 留待后续

- 商店没有 Reroll 按钮（Shop.reroll_cost() 已实现，后续可加 "Reroll (R)" 按钮）
- 按钮样式使用 Godot 默认主题；后续可自定义 StyleBox 做霓虹风格
- 买不起时按钮完全禁用，没有悬停提示说明原因（后续可加 tooltip）
