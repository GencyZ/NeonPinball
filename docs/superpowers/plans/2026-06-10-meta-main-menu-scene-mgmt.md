# 局外主菜单 + 场景管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 加一个局外主页场景（标题/最高分/开始/退出）和一个 SceneManager（Autoload `SceneMan`），实现局外主菜单 ↔ 局内游戏的场景切换；游戏结束可重开或回主页。

**Architecture:** 用 Godot 内置 `change_scene_to_file()` 切换整棵场景树；跑局状态全在 Autoload（RunMan / SaveSystem / GameDB），不随场景销毁，所以切换零状态丢失。SceneManager 薄封装切换入口（goto_menu / start_run）。主菜单 UI 沿用项目既有的"程序化建 UI"风格（与 hud.gd 一致），不手写复杂 .tscn 节点树。

**Tech Stack:** Godot 4.6.3 GDScript, GUT。

---

## Background（代码库上下文）

- 项目根目录：`D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- 测试命令（godot 不在 PATH 上 —— 用真实二进制路径）：

  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- 基线：111 个测试通过。
- 每个任务只提交它自己改动的文件，用 `git -C D:/NeonPinball/game ...`。**不要 push。**
- `project.godot` 中 `[autoload]` 已注册：

  ```
  GameDB="*res://data/game_database.gd"
  RunMan="*res://run/run_manager.gd"
  ```

- `project.godot` 主场景行：`run/main_scene="uid://drrdpjtrhjtij"`（当前是 board.tscn）。

### 既有场景 `scenes/board.tscn`

```
[gd_scene format=3 uid="uid://drrdpjtrhjtij"]
[ext_resource type="Script" uid="..." path="res://view/board_view.gd" id="1_tx6nw"]
[ext_resource type="Script" uid="..." path="res://view/hud.gd" id="2_nglv8"]
[ext_resource type="Script" uid="..." path="res://view/input_controller.gd" id="3_nglv8"]
[node name="BoardView" type="Node2D" ...]
script = ExtResource("1_tx6nw")
[node name="Hud" type="CanvasLayer" parent="."] ...
[node name="InputController" type="Node" parent="."] board_path = NodePath("..")
[node name="Camera2D" type="Camera2D" parent="."] position = Vector2(270, 450)
```

### RunManager (`run/run_manager.gd`) 相关部分

```gdscript
class_name RunManager extends Node
enum Phase { BOOT, RUN_START, ROUND, BOSS_ROUND, ANTE_CLEAR, SHOP, RUN_WIN, RUN_LOSE }
var state: Dictionary = { &"master_seed": 0, &"phase": Phase.BOOT, ... }  # default phase=BOOT, master_seed=0
func _ready() -> void:
    assert(state.hash() == _make_default_state().hash(), "...")
static func _make_default_state() -> Dictionary: ...
func advance(input: Dictionary = {}) -> void: ...   # RUN_WIN/RUN_LOSE arm calls _reset()
func _reset() -> void:
    state = _make_default_state()    # phase=BOOT, master_seed=0, etc.
```

当前 **没有** 公开的 reset 方法 —— `_reset()` 是私有的。Task 1 增加 `func reset_run() -> void: _reset()`。

### board_view.gd `_ready()` 跑局生命周期（重要）

```gdscript
func _ready() -> void:
    ...
    if int(RunMan.state[&"master_seed"]) == 0:
        RunMan.state[&"master_seed"] = SaveSystemScript.daily_seed()
    if RunMan.state[&"phase"] == RunManager.Phase.BOOT:
        RunMan.advance()   # BOOT → RUN_START
        RunMan.advance()   # RUN_START → ROUND
    ...
```

所以一次全新跑局要求 board.tscn 加载时 `phase == BOOT`。`reset_run()`（→ `_reset()` → phase=BOOT、master_seed=0）保证了这一点，**并且**会重新应用每日种子（因为 master_seed 变回 0，board_view 会从 `daily_seed()` 重新播种）。这条链路务必在计划中说明。

### input_controller.gd 当前 WIN/LOSE 处理

```gdscript
const RunManagerScript := preload("res://run/run_manager.gd")
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        var cur_phase: int = RunMan.state[&"phase"]
        if cur_phase == RunManager.Phase.SHOP:
            _handle_shop_key(event.keycode); return
        if event.keycode == KEY_R and (cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE):
            RunMan.advance()   # WIN/LOSE → _reset() → BOOT
            _board.get_tree().reload_current_scene()
            return
        match event.keycode:
            KEY_TAB: _edge = (_edge + 1) % 3
            ...
```

`_board` 是 BoardView 节点（通过 board_path 设置）。`get_tree()` 可经它访问。

### SaveSystem (`run/save_system.gd`)

```gdscript
class_name SaveSystem extends RefCounted
static func load_data() -> Dictionary   # {best_score, runs_completed, last_date, daily_completed}
static func today_string() -> String
static func daily_seed() -> int
```

### HUD 程序化 UI 模式 (`view/hud.gd`) —— 主菜单沿用此风格

hud.gd 全部在代码里构建 UI（例如 `_make_label(pos, size, color)` 里 `Label.new()`、设字号 override、`add_child`）。主菜单应同样在 `_ready()` 里构建 Button/Label，而不是在 .tscn 里手写节点。按钮信号在代码里连接：`button.pressed.connect(_on_start_pressed)`。

### GDScript / headless 注意事项（需写进计划）

- GUT 测试文件通过 `preload()` const 引用新类（**不要**用裸 class_name）：`const SceneManagerScript := preload("res://run/scene_manager.gd")`。
- 非测试代码引用新 class_name 时也用 preload const，确保 headless 缓存安全。
- 缩进用 **TAB**。
- 手写 `.tscn`：用 `format=3`，通过 **PATH-based** ext_resource 引用脚本（`path="res://view/main_menu.gd"`），并在场景头和 ext_resource 上 **省略 `uid=`**（避免 headless uid 缓存问题；Godot 导入时会重新生成 uid）。把 `project.godot` 的 `run/main_scene` 设成纯路径 `res://scenes/main_menu.tscn`（路径形式，非 uid）。
- `change_scene_to_file()` 在 SceneTree 上调用：从 Autoload Node 里用 `get_tree().change_scene_to_file(path)`。

---

## Task 1: RunManager.reset_run() 公开方法

- [ ] **修改** `run/run_manager.gd`：增加公开方法

  ```gdscript
  func reset_run() -> void:
      _reset()
  ```

  放在 `_reset()` 附近（紧挨在 `_reset()` 之上或之下均可）。该方法只是把私有 `_reset()` 暴露给 SceneManager 调用，行为完全等同：`state = _make_default_state()`（phase=BOOT、master_seed=0、ante=1、money=0 等）。

- [ ] **新建测试文件** `tests/test_scene_flow.gd`（TAB 缩进；用 preload const 引用类，**不要**裸 class_name）：

  ```gdscript
  extends GutTest

  const RunManagerScript := preload("res://run/run_manager.gd")

  func test_reset_run_restores_boot() -> void:
      var mgr := RunManagerScript.new()
      mgr.state[&"phase"] = RunManagerScript.Phase.RUN_WIN
      mgr.state[&"ante"] = 3
      mgr.state[&"money"] = 99
      mgr.state[&"master_seed"] = 123456
      mgr.reset_run()
      assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOOT, "phase 回到 BOOT")
      assert_eq(int(mgr.state[&"ante"]), 1, "ante 回到 1")
      assert_eq(int(mgr.state[&"money"]), 0, "money 回到 0")
      assert_eq(int(mgr.state[&"master_seed"]), 0, "master_seed 回到 0")
      mgr.free()

  func test_reset_run_matches_default() -> void:
      var mgr := RunManagerScript.new()
      mgr.state[&"phase"] = RunManagerScript.Phase.SHOP
      mgr.state[&"ante"] = 5
      mgr.reset_run()
      assert_eq(mgr.state.hash(), RunManagerScript._make_default_state().hash(),
          "reset_run 后 state 与默认 state 完全一致")
      mgr.free()
  ```

  > 说明：`mgr` 是用脚本 `.new()` 创建、未加入场景树的 `RunManager` Node。因为没进树，所以 `_ready()` 不会触发（避免 `_ready()` 里的 assert）；用 `mgr.free()` 立即释放即可。
  > `ante` 默认值：若实际默认 `state` 中 ante 键名/默认值不同，实施时以 `RunManagerScript._make_default_state()` 的真实内容为准微调断言（保持 phase/master_seed 两条核心断言不变）。先运行测试确认默认值，再写死断言数字。

- [ ] **运行测试**：

  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

  **预期输出**：所有测试通过，总数从 111 增加到 113（本任务新增 2 个测试），GUT 末尾打印类似 `113 passing` / `0 failing`，进程退出码 0。

- [ ] **提交**（只提交本任务文件）：

  ```
  git -C D:/NeonPinball/game add run/run_manager.gd tests/test_scene_flow.gd
  git -C D:/NeonPinball/game commit -m "feat: RunManager.reset_run() public reset for new run"
  ```

---

## Task 2: SceneManager Autoload

- [ ] **新建** `run/scene_manager.gd`（TAB 缩进）：

  ```gdscript
  extends Node
  # Autoload: SceneMan — switches between menu (局外) and game (局内).

  const MENU_SCENE := "res://scenes/main_menu.tscn"
  const GAME_SCENE := "res://scenes/board.tscn"

  func goto_menu() -> void:
      get_tree().change_scene_to_file(MENU_SCENE)

  func start_run() -> void:
      RunMan.reset_run()                         # fresh state -> phase BOOT, daily seed re-applied by board_view
      get_tree().change_scene_to_file(GAME_SCENE)
  ```

  > `RunMan` 是已注册的 Autoload，可直接在 SceneManager 里引用。`start_run()` 先 `reset_run()` 把 RunMan 重置到 phase=BOOT、master_seed=0，再切到 board.tscn —— board_view `_ready()` 检测到 master_seed==0 就从 `daily_seed()` 重新播种、检测到 phase==BOOT 就 advance 两次进入 ROUND，于是从 Ante 1 干净开局。

- [ ] **注册 Autoload**：编辑 `project.godot` 的 `[autoload]` 块。

  **改前：**

  ```
  [autoload]

  GameDB="*res://data/game_database.gd"
  RunMan="*res://run/run_manager.gd"
  ```

  **改后：**

  ```
  [autoload]

  GameDB="*res://data/game_database.gd"
  RunMan="*res://run/run_manager.gd"
  SceneMan="*res://run/scene_manager.gd"
  ```

  > 注意：`SceneMan` 排在 `RunMan` 之后，保证 RunMan 先初始化（虽然此处只在方法调用时用到 RunMan，顺序非强依赖，但保持依赖在前是好习惯）。

- [ ] **追加测试**到 `tests/test_scene_flow.gd`（顶部新增 preload const）：

  在文件顶部 const 区追加：

  ```gdscript
  const SceneManagerScript := preload("res://run/scene_manager.gd")
  ```

  追加测试函数：

  ```gdscript
  func test_scene_manager_script_loads() -> void:
      assert_not_null(load("res://run/scene_manager.gd"), "SceneManager 脚本可加载/解析无误")

  func test_game_scene_path_exists() -> void:
      assert_true(ResourceLoader.exists("res://scenes/board.tscn"), "board.tscn 存在")
  ```

  > **不要**在本任务断言 `res://scenes/main_menu.tscn` 存在 —— 该文件 Task 3 才创建。`test_menu_scene_path_exists` 的断言放到 **Task 3**（文件存在之后）。
  > `goto_menu()` / `start_run()` 会调用 `change_scene_to_file` 切换整棵场景树 —— 这在游戏中手动验证（在测试运行器里实际切场景会破坏 GUT 运行环境，故不做单元测试）。`reset_run()` 的委托行为已由 Task 1 覆盖，无需重复。

- [ ] **运行测试**：

  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

  **预期输出**：所有测试通过，总数 113 → 115（本任务新增 2 个）。退出码 0。

- [ ] **提交**：

  ```
  git -C D:/NeonPinball/game add run/scene_manager.gd project.godot tests/test_scene_flow.gd
  git -C D:/NeonPinball/game commit -m "feat: SceneManager autoload (goto_menu / start_run)"
  ```

---

## Task 3: MainMenu 场景 + 脚本（程序化 UI）

- [ ] **新建** `view/main_menu.gd`（TAB 缩进）：

  ```gdscript
  extends Control
  const SaveSystemScript := preload("res://run/save_system.gd")

  func _ready() -> void:
      var saved := SaveSystemScript.load_data()
      _build_ui(saved)

  func _build_ui(saved: Dictionary) -> void:
      var title := Label.new()
      title.text = "NEON PINBALL"
      title.add_theme_font_size_override(&"font_size", 48)
      title.position = Vector2(120, 120)
      add_child(title)

      var best := Label.new()
      best.text = best_text(saved)
      best.add_theme_font_size_override(&"font_size", 22)
      best.position = Vector2(120, 200)
      add_child(best)

      var start_btn := Button.new()
      start_btn.text = "Start Run"
      start_btn.position = Vector2(120, 280)
      start_btn.custom_minimum_size = Vector2(200, 48)
      start_btn.pressed.connect(_on_start_pressed)
      add_child(start_btn)

      var quit_btn := Button.new()
      quit_btn.text = "Quit"
      quit_btn.position = Vector2(120, 344)
      quit_btn.custom_minimum_size = Vector2(200, 48)
      quit_btn.pressed.connect(_on_quit_pressed)
      add_child(quit_btn)

  func best_text(saved: Dictionary) -> String:
      return "Best: %d" % int(saved.get(&"best_score", 0))

  func _on_start_pressed() -> void:
      SceneMan.start_run()

  func _on_quit_pressed() -> void:
      get_tree().quit()
  ```

  > `best_text()` 是纯文本格式化辅助函数（无副作用），专门拆出来做真单元测试。`_on_start_pressed` 调用 Autoload `SceneMan.start_run()`。

- [ ] **新建** `scenes/main_menu.tscn`（path-based ext_resource，**无 uid**）：

  ```
  [gd_scene format=3]

  [ext_resource type="Script" path="res://view/main_menu.gd" id="1"]

  [node name="MainMenu" type="Control"]
  layout_mode = 3
  anchors_preset = 15
  anchor_right = 1.0
  anchor_bottom = 1.0
  script = ExtResource("1")
  ```

  > 场景头和 ext_resource 都不写 `uid=`；Godot 首次导入会自动生成。脚本用 `path=` 形式引用。

- [ ] **追加测试**到 `tests/test_scene_flow.gd`（顶部新增 preload const）：

  在文件顶部 const 区追加：

  ```gdscript
  const MainMenuScript := preload("res://view/main_menu.gd")
  ```

  追加测试函数：

  ```gdscript
  func test_best_text_format() -> void:
      var mm = MainMenuScript.new()
      assert_eq(mm.best_text({&"best_score": 4200}), "Best: 4200", "有 best_score 时格式正确")
      assert_eq(mm.best_text({}), "Best: 0", "无 best_score 时默认 0")
      mm.free()

  func test_menu_scene_loads_without_error() -> void:
      var packed = load("res://scenes/main_menu.tscn")
      assert_not_null(packed, "main_menu.tscn 可加载")
      var inst = packed.instantiate()
      add_child_autofree(inst)   # 加入树 → 触发 _ready → 构建 UI；若有错误测试会失败
      assert_not_null(inst, "实例化成功，_ready 构建 UI 无报错")

  func test_menu_scene_path_exists() -> void:
      assert_true(ResourceLoader.exists("res://scenes/main_menu.tscn"), "main_menu.tscn 存在")
  ```

  > - `test_best_text_format`：用 `MainMenuScript.new()` 实例化（未入树，`_ready()` 不触发），只调用纯函数 `best_text()`，再 `mm.free()`（继承 Control/Node，未入树用 `free()` 即可）。
  > - `test_menu_scene_loads_without_error`：冒烟测试。`add_child_autofree(inst)` 会把实例加入测试树 → 触发 `_ready()` → 走 `_build_ui()` 真正建 Label/Button/连信号；任何 parse/runtime 错误都会让测试失败。若该 GUT 版本没有 `add_child_autofree`，改用 `add_child(inst)` 然后 `inst.queue_free()`。**不要写假断言**；这是真实的"无错误加载"验证。
  > - `test_menu_scene_path_exists`：现在文件已存在，断言路径存在（此断言放在 Task 3，不是 Task 2）。

- [ ] **运行测试**：

  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

  **预期输出**：所有测试通过，总数 115 → 118（本任务新增 3 个）。退出码 0。

  > 首次运行 Godot 会导入新建的 `.tscn` 并为其生成 `.import` / uid —— 这是正常的，提交时只提交计划列出的源文件（见下）。

- [ ] **提交**：

  ```
  git -C D:/NeonPinball/game add view/main_menu.gd scenes/main_menu.tscn tests/test_scene_flow.gd
  git -C D:/NeonPinball/game commit -m "feat: main menu scene with programmatic UI (start/quit, best score)"
  ```

---

## Task 4: 接上主场景 + 局内退出按键

- [ ] **修改** `project.godot`：把主场景指向主菜单。

  **改前：**

  ```
  run/main_scene="uid://drrdpjtrhjtij"
  ```

  **改后：**

  ```
  run/main_scene="res://scenes/main_menu.tscn"
  ```

  > 用 res:// 路径形式（非 uid），与手写 .tscn 的无-uid 策略一致，避免 headless uid 缓存问题。

- [ ] **修改** `view/input_controller.gd` 的 WIN/LOSE 处理。

  **当前需要被替换的代码块：**

  ```gdscript
  if event.keycode == KEY_R and (cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE):
      RunMan.advance()   # WIN/LOSE → _reset() → BOOT
      _board.get_tree().reload_current_scene()
      return
  ```

  **替换为：**

  ```gdscript
  if cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE:
      if event.keycode == KEY_R:
          SceneMan.start_run()      # restart a fresh run
          return
      if event.keycode == KEY_ESCAPE:
          SceneMan.goto_menu()      # back to main menu
          return
  ```

  替换后该函数的整体结构应为（确保 SHOP 检查仍在上方、正常 TAB/1-4 的 `match` 仍在下方供在玩阶段使用）：

  ```gdscript
  func _unhandled_input(event: InputEvent) -> void:
      if event is InputEventKey and event.pressed:
          var cur_phase: int = RunMan.state[&"phase"]
          if cur_phase == RunManager.Phase.SHOP:
              _handle_shop_key(event.keycode); return
          if cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE:
              if event.keycode == KEY_R:
                  SceneMan.start_run()      # restart a fresh run
                  return
              if event.keycode == KEY_ESCAPE:
                  SceneMan.goto_menu()      # back to main menu
                  return
          match event.keycode:
              KEY_TAB: _edge = (_edge + 1) % 3
              ...
  ```

  > `SceneMan.start_run()` 内部先 `RunMan.reset_run()` 再切 board.tscn —— 因此不再需要本地 `RunMan.advance()` + `reload_current_scene()`。`SceneMan.goto_menu()` 切回主菜单。`SceneMan` 是 Autoload，可在 input_controller 里直接引用（无需 preload）。

- [ ] **追加测试**到 `tests/test_scene_flow.gd`（场景切换是手动验证；这里只加一个冒烟测试确认相关脚本/场景仍能加载/解析）：

  ```gdscript
  func test_board_scene_still_loads() -> void:
      assert_true(ResourceLoader.exists("res://scenes/board.tscn"), "board.tscn 仍存在")
      assert_not_null(load("res://view/input_controller.gd"),
          "input_controller.gd 编辑后仍能解析")
  ```

  > **不要**在测试里实例化 board.tscn（它需要完整 autoload + Camera 设置，在 GUT 里实例化可能有副作用）—— 只做 load/exists 检查。

- [ ] **运行测试**：

  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

  **预期输出**：所有测试通过，总数 118 → 119（本任务新增 1 个）。退出码 0。

- [ ] **手动验证清单**（在游戏里实际跑一遍）：
  - 启动游戏 → 主菜单显示，标题 "NEON PINBALL"，"Best: N" 显示存档最高分，有 "Start Run" / "Quit" 两个按钮。
  - 点 "Start Run" → board 加载，跑局从 Ante 1 开始（每日种子生效）。
  - 打到 win/lose → 按 **R** → 重开一局全新跑局（回到 Ante 1）。
  - win/lose → 按 **Esc** → 回到主菜单。
  - 在主菜单再点 "Start Run" → 第二局正确开局（从 Ante 1，证明 `reset_run()` 生命周期没问题，没有残留上一局状态）。
  - 点 "Quit" → 游戏退出。

- [ ] **提交**：

  ```
  git -C D:/NeonPinball/game add project.godot view/input_controller.gd tests/test_scene_flow.gd
  git -C D:/NeonPinball/game commit -m "feat: boot to main menu; R=restart Esc=menu on run end"
  ```

---

## 文件结构

**新建：**

- `run/scene_manager.gd` —— SceneManager Autoload（`SceneMan`），`goto_menu()` / `start_run()`。
- `view/main_menu.gd` —— 主菜单 Control 脚本，程序化建 UI，`best_text()` 辅助函数。
- `scenes/main_menu.tscn` —— 主菜单场景（path-based ext_resource，无 uid）。
- `tests/test_scene_flow.gd` —— 本特性全部测试（GUT）。

**修改：**

- `run/run_manager.gd` —— 新增公开方法 `reset_run()`。
- `project.godot` —— `[autoload]` 增加 `SceneMan`；`run/main_scene` 改为 `res://scenes/main_menu.tscn`。
- `view/input_controller.gd` —— WIN/LOSE 处理改为 R=重开（`SceneMan.start_run()`）/ Esc=回主菜单（`SceneMan.goto_menu()`）。

---

## 自检清单

- [ ] 111 个基线测试仍全部通过。
- [ ] 新增测试全部通过（约 111 + 8 个新测试 ≈ 119 个，全绿）。
- [ ] 主菜单作为第一个场景启动（`run/main_scene` = main_menu.tscn）。
- [ ] 主菜单显示标题、"Best: N" 最高分、Start / Quit 按钮。
- [ ] Start → 全新跑局，从 Ante 1 开始（每日种子）。
- [ ] win/lose 时按 R 重开一局全新跑局。
- [ ] win/lose 时按 Esc 回到主菜单。
- [ ] 从主菜单第二次 Start 正确开局（证明 `reset_run()` 生命周期清空了上一局状态）。
- [ ] 没有确定性回归 / 其它回归（既有测试不受影响）。

---

## 已知局限 / 留待后续

- 无淡入淡出过渡（场景切换是硬切 —— 后续可加一个 CanvasLayer fade Autoload）。
- 只有单一 "Start" 模式（每日种子）；随机种子 / 模式选择留待后续。
- 主菜单只显示最高分；完整统计 / 解锁内容留待后续。
- 每日种子 "Daily #N / DONE" 标签仍在 board_view 的 HUD 里显示（后续可移到主菜单）。
