# UnlockManager — 解锁系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现基于累计进度的解锁系统：玩家完成 N 场跑局后解锁新触发器/门/钉子类型，解锁内容出现在商店池中，主菜单显示解锁进度。

**Architecture:**
- `run/unlock_manager.gd`（静态工具类）：定义解锁表（unlock_table），检查 SaveSystem 数据判断哪些内容已解锁
- `data/game_database.gd`：`_ready()` 里调用 `UnlockManager.apply_unlocks(self)` 动态注入已解锁的触发器/门/钉
- `view/main_menu.gd`：显示解锁进度提示（"X/Y 已解锁，再打 N 局解锁下一个"）
- 商店和棋盘无需修改：GameDB 已注册的内容会自动进入商店池和棋盘布局

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

### PegType（`data/peg_type.gd`）已定义但未使用的 Behavior

```gdscript
enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB }
```

`CHAIN`、`SPAWN`、`BOMB` 已在枚举中，可作为解锁目标（配合更多钉子类型计划）。

### GameDB（`data/game_database.gd`）当前注册内容

**初始可用（已注册）：**
- Peg: `normal`、`mult`
- Trigger: `peg_bonus`、`bounce_mult`、`big_hit`、`chain_bonus`、`double_mult`
- Gate: `normal`、`accel`、`scatter_angle`、`scatter_split`

> 当前所有内容从一开始就可用，本计划让部分内容变为「需解锁」。

### SaveSystem 进度数据

```gdscript
static func load_data() -> Dictionary:
    # { &"best_score": int, &"runs_completed": int, &"last_date": str, &"daily_completed": bool }
```

`runs_completed` 是核心解锁条件。

---

## 解锁表设计

| 解锁条件（runs_completed ≥） | 解锁内容 | 类型 | 说明 |
|---|---|---|---|
| 0（初始）| normal、mult peg | peg | 始终可用 |
| 0（初始）| peg_bonus、bounce_mult、big_hit | trigger | 基础触发器，初始可用 |
| 0（初始）| normal、accel gate | gate | 基础门，初始可用 |
| **3** | chain_bonus trigger | trigger | 商店可见 |
| **5** | scatter_angle gate | gate | 商店可见 |
| **8** | double_mult trigger | trigger | 商店可见 |
| **12** | scatter_split gate | gate | 商店可见 |

> 上述条件可在实现后通过常量调整，数值仅为参考。

---

## Task 1：UnlockManager 静态类

- [ ] **新建** `run/unlock_manager.gd`（TAB 缩进）：

  ```gdscript
  class_name UnlockManager extends RefCounted
  # 解锁系统：基于 runs_completed 判断哪些内容可用

  # 每条记录：{ id: StringName, type: "trigger"/"gate"/"peg", required_runs: int }
  const UNLOCK_TABLE: Array = [
      { "id": &"chain_bonus",    "type": "trigger", "required_runs": 3  },
      { "id": &"scatter_angle",  "type": "gate",    "required_runs": 5  },
      { "id": &"double_mult",    "type": "trigger", "required_runs": 8  },
      { "id": &"scatter_split",  "type": "gate",    "required_runs": 12 },
  ]

  static func unlocked_ids(runs_completed: int) -> Array[StringName]:
      var result: Array[StringName] = []
      for entry in UNLOCK_TABLE:
          if runs_completed >= int(entry["required_runs"]):
              result.append(entry["id"] as StringName)
      return result

  static func next_unlock(runs_completed: int) -> Dictionary:
      # 返回下一个未解锁的条目，空字典表示全部已解锁
      for entry in UNLOCK_TABLE:
          if runs_completed < int(entry["required_runs"]):
              return entry
      return {}

  static func apply_unlocks(db: Node, runs_completed: int) -> void:
      # 从 GameDB 移除尚未解锁的内容
      for entry in UNLOCK_TABLE:
          if runs_completed < int(entry["required_runs"]):
              var id := entry["id"] as StringName
              match entry["type"]:
                  "trigger": db.triggers.erase(id)
                  "gate":    db.gate_defs.erase(id)
                  "peg":     db.peg_types.erase(id)
  ```

- [ ] **新建测试文件** `tests/test_unlock_manager.gd`（TAB 缩进）：

  ```gdscript
  extends GutTest
  const UnlockManagerScript := preload("res://run/unlock_manager.gd")

  func test_zero_runs_no_extra_unlocks() -> void:
      var ids := UnlockManagerScript.unlocked_ids(0)
      assert_false(ids.has(&"chain_bonus"), "0 局时 chain_bonus 未解锁")
      assert_false(ids.has(&"scatter_angle"), "0 局时 scatter_angle 未解锁")

  func test_three_runs_unlocks_chain_bonus() -> void:
      var ids := UnlockManagerScript.unlocked_ids(3)
      assert_true(ids.has(&"chain_bonus"), "3 局时 chain_bonus 已解锁")
      assert_false(ids.has(&"scatter_angle"), "3 局时 scatter_angle 未解锁")

  func test_twelve_runs_all_unlocked() -> void:
      var ids := UnlockManagerScript.unlocked_ids(12)
      assert_true(ids.has(&"chain_bonus"))
      assert_true(ids.has(&"scatter_angle"))
      assert_true(ids.has(&"double_mult"))
      assert_true(ids.has(&"scatter_split"))

  func test_next_unlock_at_zero() -> void:
      var nxt := UnlockManagerScript.next_unlock(0)
      assert_false(nxt.is_empty(), "0 局时有下一个解锁目标")
      assert_eq(nxt["required_runs"], 3)

  func test_next_unlock_fully_unlocked() -> void:
      var nxt := UnlockManagerScript.next_unlock(99)
      assert_true(nxt.is_empty(), "99 局时全部解锁，next 为空")
  ```

- [ ] **运行测试**，预期 150 → 155（+5 个）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add run/unlock_manager.gd tests/test_unlock_manager.gd
  git -C D:/NeonPinball/game commit -m "feat: UnlockManager — run-count-gated unlock table with tests"
  ```

---

## Task 2：GameDB 应用解锁过滤

- [ ] **修改** `data/game_database.gd` 的 `_ready()`：在注册完所有默认内容后，调用 UnlockManager 移除未解锁内容。

  在 `_register_defaults()` 调用之后追加：

  ```gdscript
  func _ready() -> void:
      _register_defaults()
      _apply_unlocks()

  func _apply_unlocks() -> void:
      var saved := SaveSystem.load_data()
      var runs := int(saved.get(&"runs_completed", 0))
      UnlockManager.apply_unlocks(self, runs)
  ```

  > 注意：`UnlockManager` 是 class_name，可直接引用；`SaveSystem` 同理。GameDB 是 Autoload，其 `_ready()` 在场景加载前执行，此时 SaveSystem 已可用（ConfigFile 无需场景树）。

- [ ] **新建冒烟测试**追加到 `tests/test_unlock_manager.gd`：

  ```gdscript
  func test_apply_unlocks_removes_locked_items() -> void:
      # 用一个假 DB 字典模拟 GameDB
      var fake_db := Node.new()
      fake_db.set_script(load("res://data/game_database.gd"))
      # 手动构建 triggers 字典（不经过 GameDB._ready()，避免 SaveSystem 副作用）
      fake_db.triggers = {
          &"chain_bonus": true,
          &"double_mult": true,
      }
      fake_db.gate_defs = {}
      fake_db.peg_types = {}
      UnlockManagerScript.apply_unlocks(fake_db, 0)   # 0 局 → 全部锁定
      assert_false(fake_db.triggers.has(&"chain_bonus"), "0 局时 chain_bonus 被移除")
      assert_false(fake_db.triggers.has(&"double_mult"), "0 局时 double_mult 被移除")
      fake_db.free()
  ```

- [ ] **运行测试**，预期 155 → 156（+1 个）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add data/game_database.gd tests/test_unlock_manager.gd
  git -C D:/NeonPinball/game commit -m "feat: GameDB applies unlock filter on _ready (runs_completed gated)"
  ```

---

## Task 3：主菜单显示解锁进度

- [ ] **修改** `view/main_menu.gd`：在 `_build_ui()` 末尾追加解锁进度提示。

  顶部 preload 区追加：
  ```gdscript
  const UnlockManagerScript := preload("res://run/unlock_manager.gd")
  ```

  `_build_ui()` 末尾追加：
  ```gdscript
  # ---- 解锁进度 ----
  var runs := int(saved.get(&"runs_completed", 0))
  var nxt := UnlockManagerScript.next_unlock(runs)
  var unlock_lbl := Label.new()
  if nxt.is_empty():
      unlock_lbl.text = "All content unlocked!"
  else:
      var need: int = int(nxt["required_runs"]) - runs
      unlock_lbl.text = "Next unlock in %d run%s" % [need, "s" if need > 1 else ""]
  unlock_lbl.add_theme_font_size_override(&"font_size", 16)
  unlock_lbl.modulate = Color(0.6, 1.0, 0.7)
  unlock_lbl.position = Vector2(120, 760)   # 根据实际布局微调
  add_child(unlock_lbl)
  ```

- [ ] **运行测试**，预期测试数不变（无新纯逻辑测试）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/main_menu.gd
  git -C D:/NeonPinball/game commit -m "feat: main menu shows next unlock progress"
  ```

---

## 文件结构

**新建：**
- `run/unlock_manager.gd` — 解锁表 + 静态方法
- `tests/test_unlock_manager.gd` — 6 个测试

**修改：**
- `data/game_database.gd` — `_ready()` 调用 `_apply_unlocks()`
- `view/main_menu.gd` — 显示解锁进度

---

## 自检清单

- [ ] 150 个基线测试 + 6 个新测试 = 156 个，全部通过
- [ ] 新存档（0 场）：chain_bonus、scatter_angle 等不出现在商店
- [ ] 完成 3 场后：chain_bonus 出现在商店池
- [ ] 完成 12 场后：所有内容解锁，商店池完整
- [ ] 主菜单显示 "Next unlock in N runs"（正确倒计时）
- [ ] 全部解锁后显示 "All content unlocked!"
- [ ] 无回归

---

## 已知局限 / 留待后续

- 解锁内容固定在 UNLOCK_TABLE 常量里；后续可迁移到 `.tres` 资源文件（对应 .tres 迁移计划）
- 目前只解锁触发器和门，钉子类型解锁需配合更多钉子类型计划
- 无解锁动画/弹窗提示；后续可在进入主菜单时检测新解锁并弹出提示
