# 场景淡入淡出过渡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主菜单 ↔ 局内游戏切换时加黑色淡入淡出过渡，消除硬切的突兀感。点击按钮后先淡出（变黑），换场景，新场景加载后再淡入（黑→透明）。

**Architecture:**
- 新 Autoload `FadeMan`（`run/fade_manager.gd`）：持有全屏 ColorRect 的 CanvasLayer，用 Tween 控制透明度
- `FadeMan.fade_to(callable)` —— 淡出结束后执行 callable（内含 `change_scene_to_file`），再淡入
- `SceneMan` 的 `goto_menu()` / `start_run()` 改为经由 `FadeMan.fade_to()` 触发场景切换
- 新场景 `_ready()` 触发时 FadeMan 自动执行淡入（信号 `scene_changed` 或在 `fade_to` 内部链式处理）

**Tech Stack:** Godot 4.6.3 GDScript, Tween, GUT。

---

## Background（代码库上下文）

- 项目根目录：`D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**150 个测试**全部通过。
- 每个任务只提交它自己改动的文件。**不要 push。**

### 当前场景切换路径（SceneMan）

```gdscript
# run/scene_manager.gd
func goto_menu() -> void:
    get_tree().change_scene_to_file(MENU_SCENE)   # ← 硬切

func start_run() -> void:
    RunMan.reset_run()
    get_tree().change_scene_to_file(GAME_SCENE)   # ← 硬切
```

### 目标切换路径

```
[用户点击 Start / Quit / Restart / Menu]
    → SceneMan.goto_menu() / start_run()
        → FadeMan.fade_to(callable)
            → 淡出（0.0 → 1.0 alpha，0.3s）
            → callable()  ← change_scene_to_file
            → 淡入（1.0 → 0.0 alpha，0.3s）
```

### Autoload 注册现状（project.godot）

```ini
[autoload]
GameDB="*res://data/game_database.gd"
RunMan="*res://run/run_manager.gd"
SceneMan="*res://run/scene_manager.gd"
```

---

## Task 1：FadeManager Autoload

- [ ] **新建** `run/fade_manager.gd`（TAB 缩进）：

  ```gdscript
  extends CanvasLayer
  # Autoload: FadeMan — full-screen black fade for scene transitions.

  const FADE_DURATION := 0.3

  var _rect: ColorRect

  func _ready() -> void:
      layer = 128        # 渲染在所有 UI 之上
      _rect = ColorRect.new()
      _rect.color = Color(0, 0, 0, 0)
      _rect.set_anchors_preset(Control.PRESET_FULL_RECT)
      _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
      add_child(_rect)
      # 每次场景加载完毕后自动淡入
      get_tree().node_added.connect(_on_node_added)

  func _on_node_added(node: Node) -> void:
      # 场景根节点加入树时触发淡入（过滤掉非根节点）
      if node.get_parent() == get_tree().root and node != self:
          fade_in()

  func fade_to(action: Callable) -> void:
      # 淡出 → 执行 action（change_scene_to_file）→ 淡入由 _on_node_added 触发
      _rect.mouse_filter = Control.MOUSE_FILTER_STOP   # 淡出期间屏蔽输入
      var tw := create_tween()
      tw.tween_property(_rect, "color:a", 1.0, FADE_DURATION)
      tw.tween_callback(action)

  func fade_in() -> void:
      _rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
      var tw := create_tween()
      tw.tween_property(_rect, "color:a", 0.0, FADE_DURATION)
  ```

  > `layer = 128` 确保黑幕在所有游戏 UI（CanvasLayer 默认 layer=1）之上。
  > `mouse_filter = STOP` 在淡出阶段屏蔽输入，防止重复点击。
  > `_on_node_added` 监听根节点子节点变化，新场景根加入时自动淡入，无需各场景自行调用。

- [ ] **注册 Autoload**：在 `project.godot` `[autoload]` 块末尾追加：

  ```ini
  FadeMan="*res://run/fade_manager.gd"
  ```

  > 排在 SceneMan 之后。

- [ ] **运行测试**，确认新 Autoload 不破坏既有测试：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
  **预期：** 150 个测试全部通过，退出码 0。

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add run/fade_manager.gd project.godot
  git -C D:/NeonPinball/game commit -m "feat: FadeManager autoload — full-screen black fade primitive"
  ```

---

## Task 2：SceneMan 经由 FadeMan 切换场景

- [ ] **修改** `run/scene_manager.gd`：

  **改前：**
  ```gdscript
  func goto_menu() -> void:
      get_tree().change_scene_to_file(MENU_SCENE)

  func start_run() -> void:
      RunMan.reset_run()
      get_tree().change_scene_to_file(GAME_SCENE)
  ```

  **改后：**
  ```gdscript
  func goto_menu() -> void:
      FadeMan.fade_to(func(): get_tree().change_scene_to_file(MENU_SCENE))

  func start_run() -> void:
      RunMan.reset_run()
      FadeMan.fade_to(func(): get_tree().change_scene_to_file(GAME_SCENE))
  ```

  > `FadeMan` 是 Autoload，可直接引用。`fade_to` 接受 Callable，Lambda 捕获 `get_tree()` / 路径常量（均在 SceneMan 作用域内可访问）。

- [ ] **追加冒烟测试**到已有 `tests/test_scene_flow.gd`：

  ```gdscript
  func test_fade_manager_script_loads() -> void:
      assert_not_null(load("res://run/fade_manager.gd"), "FadeManager 脚本可加载/解析")
  ```

  > 不测实际淡出动画（Tween 在 headless 模式无可视效果），只验证脚本无语法错误。

- [ ] **运行测试**，预期 150 → 151：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add run/scene_manager.gd tests/test_scene_flow.gd
  git -C D:/NeonPinball/game commit -m "feat: SceneMan transitions via FadeMan (fade-out → switch → fade-in)"
  ```

---

## 文件结构

**新建：**
- `run/fade_manager.gd` — FadeMan Autoload，CanvasLayer + ColorRect + Tween

**修改：**
- `project.godot` — 注册 FadeMan Autoload
- `run/scene_manager.gd` — goto_menu / start_run 经由 FadeMan 切换
- `tests/test_scene_flow.gd` — 1 个冒烟测试

---

## 自检清单

- [ ] 150 个基线测试仍全部通过（+1 冒烟测试 = 151）
- [ ] 主菜单点 "Start Run" → 黑色淡出（0.3s）→ 局内场景加载 → 淡入（0.3s）
- [ ] 局内 WIN/LOSE 点 "Main Menu" / Esc → 同样淡出淡入
- [ ] 局内 WIN/LOSE 点 "Restart" / R → 淡出淡入重开
- [ ] 淡出期间点击无效（mouse_filter=STOP 屏蔽）
- [ ] 无回归：商店、HUD、弹球逻辑正常

---

## 已知局限 / 留待后续

- 淡出时长固定 0.3s；后续可暴露 `FADE_DURATION` 为常量或参数
- `_on_node_added` 监听所有根级节点，理论上动态添加的根节点也会触发淡入（实际游戏中只有场景切换时才有根级子节点加入，影响极小）
- 无色彩自定义（目前固定黑色）；后续可改为白色闪光或其他风格
