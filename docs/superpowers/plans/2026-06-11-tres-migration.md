# GameDB .tres 资源迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `game_database.gd` 中硬编码的触发器、门、钉子类型定义迁移到 `.tres` 资源文件，让设计师/策划可以在 Godot 编辑器中直接修改数值，无需改代码。

**Architecture:**
- 为每个 `TriggerDef`、`GateDef`、`PegType` 实例创建对应 `.tres` 文件，存放在 `res://data/resources/` 下
- `game_database.gd` 的 `_register_defaults()` 改为遍历目录 / 使用 preload 列表加载 `.tres` 文件
- `PegType`、`TriggerDef`、`GateDef` 已继承 `Resource`，天然支持 `.tres` 序列化

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

### 当前资源类定义（已继承 Resource，可直接序列化为 .tres）

```gdscript
# data/peg_type.gd
class_name PegType extends Resource
enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB }
@export var id: StringName
@export var behavior: Behavior
@export var base_score: float
@export var mult_add: float
@export var one_shot: bool
@export var glow: Color

# data/trigger_def.gd  (类似结构，@export 字段)
# data/gate_def.gd     (类似结构，@export 字段)
```

### 当前 GameDB 注册方式（硬编码）

```gdscript
func _register_defaults() -> void:
    var pn := PegType.new()
    pn.id = &"normal"; pn.behavior = PegType.Behavior.NORMAL
    pn.base_score = 5.0; pn.glow = Color(0.2, 0.9, 1.0, 1.0)
    peg_types[pn.id] = pn
    # ... 以下所有 TriggerDef / GateDef 均类似 ...
```

### .tres 文件格式示例（headless 安全，无 uid）

```ini
[gd_resource type="PegType" format=3]
[resource]
id = &"normal"
behavior = 0
base_score = 5.0
glow = Color(0.2, 0.9, 1.0, 1.0)
```

> 属性名与 `@export var` 字段名一致；`behavior` 用枚举整数值（NORMAL=0, MULT=1, CHAIN=2...）。

---

## Task 1：创建 .tres 资源文件

为现有所有定义各创建一个 `.tres` 文件，存放到 `data/resources/` 目录。

- [ ] **创建目录结构：**
  ```
  data/resources/
    pegs/
      peg_normal.tres
      peg_mult.tres
    triggers/
      trigger_peg_bonus.tres
      trigger_bounce_mult.tres
      trigger_big_hit.tres
      trigger_chain_bonus.tres
      trigger_double_mult.tres
    gates/
      gate_normal.tres
      gate_accel.tres
      gate_scatter_angle.tres
      gate_scatter_split.tres
  ```

- [ ] **新建** `data/resources/pegs/peg_normal.tres`：
  ```ini
  [gd_resource type="PegType" format=3]
  [resource]
  id = &"normal"
  behavior = 0
  base_score = 5.0
  mult_add = 0.0
  one_shot = false
  glow = Color(0.2, 0.9, 1.0, 1.0)
  ```

- [ ] **新建** `data/resources/pegs/peg_mult.tres`：
  ```ini
  [gd_resource type="PegType" format=3]
  [resource]
  id = &"mult"
  behavior = 1
  base_score = 8.0
  mult_add = 0.5
  one_shot = false
  glow = Color(1.0, 0.5, 0.1, 1.0)
  ```

- [ ] **新建** `data/resources/triggers/trigger_peg_bonus.tres`：
  ```ini
  [gd_resource type="TriggerDef" format=3]
  [resource]
  id = &"peg_bonus"
  listen_mask = 1
  effect = 0
  value = 3.0
  rarity = 0
  condition = 0
  condition_threshold = 0
  ```

- [ ] **新建** `data/resources/triggers/trigger_bounce_mult.tres`：
  ```ini
  [gd_resource type="TriggerDef" format=3]
  [resource]
  id = &"bounce_mult"
  listen_mask = 2
  effect = 1
  value = 0.2
  rarity = 0
  condition = 0
  condition_threshold = 0
  ```

- [ ] **新建** `data/resources/triggers/trigger_big_hit.tres`：
  ```ini
  [gd_resource type="TriggerDef" format=3]
  [resource]
  id = &"big_hit"
  listen_mask = 4
  effect = 2
  value = 1.5
  rarity = 1
  condition = 1
  condition_threshold = 5
  ```

- [ ] **新建** `data/resources/triggers/trigger_chain_bonus.tres`：
  ```ini
  [gd_resource type="TriggerDef" format=3]
  [resource]
  id = &"chain_bonus"
  listen_mask = 4
  effect = 0
  value = 10.0
  rarity = 1
  condition = 1
  condition_threshold = 3
  ```

- [ ] **新建** `data/resources/triggers/trigger_double_mult.tres`：
  ```ini
  [gd_resource type="TriggerDef" format=3]
  [resource]
  id = &"double_mult"
  listen_mask = 4
  effect = 2
  value = 2.0
  rarity = 2
  condition = 2
  condition_threshold = 10
  ```

- [ ] **新建** `data/resources/gates/gate_normal.tres`：
  ```ini
  [gd_resource type="GateDef" format=3]
  [resource]
  id = &"normal"
  kind = 0
  rarity = 0
  speed_mul = 1.0
  scatter_angle = 0.0
  split_count = 2
  ```

- [ ] **新建** `data/resources/gates/gate_accel.tres`：
  ```ini
  [gd_resource type="GateDef" format=3]
  [resource]
  id = &"accel"
  kind = 1
  rarity = 0
  speed_mul = 1.5
  scatter_angle = 0.0
  split_count = 2
  ```

- [ ] **新建** `data/resources/gates/gate_scatter_angle.tres`：
  ```ini
  [gd_resource type="GateDef" format=3]
  [resource]
  id = &"scatter_angle"
  kind = 2
  rarity = 1
  speed_mul = 1.0
  scatter_angle = 0.3
  split_count = 2
  ```

- [ ] **新建** `data/resources/gates/gate_scatter_split.tres`：
  ```ini
  [gd_resource type="GateDef" format=3]
  [resource]
  id = &"scatter_split"
  kind = 3
  rarity = 1
  speed_mul = 1.0
  scatter_angle = 0.4
  split_count = 3
  ```

  > `.tres` 中 enum 整数值须与 GDScript 定义顺序一致；实施前用 `print(TriggerDef.Effect.ADD_BASE)` 等确认各枚举值。

- [ ] **提交（仅 .tres 文件，GameDB 代码暂不改）：**
  ```
  git -C D:/NeonPinball/game add data/resources/
  git -C D:/NeonPinball/game commit -m "feat: add .tres resource files for all pegs, triggers, gates"
  ```

---

## Task 2：GameDB 改为从 .tres 加载

- [ ] **修改** `data/game_database.gd`：将 `_register_defaults()` 改为从 `.tres` 文件加载。

  **改后 `_register_defaults()`：**

  ```gdscript
  func _register_defaults() -> void:
      _load_resources_from_dir("res://data/resources/pegs/",     peg_types)
      _load_resources_from_dir("res://data/resources/triggers/",  triggers)
      _load_resources_from_dir("res://data/resources/gates/",     gate_defs)

  func _load_resources_from_dir(dir_path: String, target: Dictionary) -> void:
      var dir := DirAccess.open(dir_path)
      if dir == null:
          push_error("GameDB: cannot open " + dir_path)
          return
      dir.list_dir_begin()
      var fname := dir.get_next()
      while fname != "":
          if fname.ends_with(".tres"):
              var res := load(dir_path + fname)
              if res != null and "id" in res:
                  target[res.id] = res
          fname = dir.get_next()
      dir.list_dir_end()
  ```

  > `DirAccess.open()` 在 headless 模式下可正常工作（访问 `res://` 目录）。
  > 资源文件须有 `id` 字段（`@export var id: StringName`），PegType/TriggerDef/GateDef 均已有。

- [ ] **新建测试文件** `tests/test_gamedb_tres.gd`（TAB 缩进）：

  ```gdscript
  extends GutTest

  func test_pegs_loaded_from_tres() -> void:
      assert_true(GameDB.peg_types.has(&"normal"), "normal peg 从 .tres 加载")
      assert_true(GameDB.peg_types.has(&"mult"),   "mult peg 从 .tres 加载")

  func test_triggers_loaded_from_tres() -> void:
      assert_true(GameDB.triggers.has(&"peg_bonus"),    "peg_bonus 从 .tres 加载")
      assert_true(GameDB.triggers.has(&"bounce_mult"),  "bounce_mult 从 .tres 加载")
      assert_true(GameDB.triggers.has(&"chain_bonus"),  "chain_bonus 从 .tres 加载")
      assert_true(GameDB.triggers.has(&"double_mult"),  "double_mult 从 .tres 加载")

  func test_gates_loaded_from_tres() -> void:
      assert_true(GameDB.gate_defs.has(&"normal"),        "normal gate 从 .tres 加载")
      assert_true(GameDB.gate_defs.has(&"scatter_split"), "scatter_split 从 .tres 加载")

  func test_peg_values_correct() -> void:
      var pt: PegType = GameDB.peg_types[&"mult"]
      assert_eq(pt.behavior, PegType.Behavior.MULT)
      assert_eq(pt.mult_add, 0.5)

  func test_trigger_values_correct() -> void:
      var td = GameDB.triggers[&"big_hit"]
      assert_eq(td.condition_threshold, 5)
  ```

- [ ] **运行测试**，预期 150 → 155（+5 个）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add data/game_database.gd tests/test_gamedb_tres.gd
  git -C D:/NeonPinball/game commit -m "refactor: GameDB loads definitions from .tres files (remove hardcoded)"
  ```

---

## 文件结构

**新建：**
- `data/resources/pegs/` — 2 个 .tres（peg_normal, peg_mult）
- `data/resources/triggers/` — 5 个 .tres
- `data/resources/gates/` — 4 个 .tres
- `tests/test_gamedb_tres.gd` — 5 个测试

**修改：**
- `data/game_database.gd` — `_register_defaults()` 改为 DirAccess 加载

---

## 自检清单

- [ ] 150 个基线测试全部通过
- [ ] 新增 5 个测试全部通过（共 155）
- [ ] GameDB 中 peg_types / triggers / gate_defs 数量与迁移前一致
- [ ] 数值正确（mult_add=0.5，big_hit threshold=5 等）
- [ ] 在编辑器中打开 .tres 文件可见各字段，可直接修改
- [ ] 修改 .tres 数值后游戏行为跟着变（无需改代码）
- [ ] 无回归（商店、计分、物理正常）

---

## 已知局限 / 留待后续

- `DirAccess` 加载顺序取决于文件系统，字典顺序可能不确定；商店抽取依赖 rarity 权重，与注册顺序无关，无影响
- 新增定义只需放入 `.tres` 文件即可，GameDB 无需修改 —— 这是本次迁移的核心价值
- `.tres` 文件可在编辑器的 Inspector 里图形化编辑，比改代码友好
- 枚举整数值与 GDScript 定义耦合：若 enum 顺序变化，.tres 值需同步更新（这是 .tres 的已知局限）
