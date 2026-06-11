# 分辨率设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在主菜单加分辨率选择（小/中/大三档），玩家点选后窗口立即变大/小，设置持久化到磁盘，下次启动自动恢复。游戏逻辑和 UI 坐标完全不变——只靠 Godot `canvas_items` 拉伸模式自动等比缩放。

**Architecture:**
- 基准分辨率保持 **540×900**（所有游戏逻辑/UI 坐标不变）
- `project.godot` 开启 `stretch/mode=canvas_items` + `stretch/aspect=keep`：Godot 自动将 540×900 的内容等比缩放到实际窗口，全部现有代码零改动
- 三档窗口尺寸：Small 540×900 / Medium 810×1350（默认）/ Large 1080×1800
- `run/settings_system.gd`：静态工具类，用 ConfigFile 持久化到 `user://settings.cfg`
- `main_menu.gd`：加分辨率选择区，启动时从 SettingsSystem 读取并应用窗口尺寸

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

### 当前 project.godot `[display]` 节

```ini
[display]
window/size/viewport_width=540
window/size/viewport_height=900
```

无拉伸模式配置，窗口固定 540×900。

### 当前 main_menu.gd 结构

```gdscript
extends Control
const SaveSystemScript := preload("res://run/save_system.gd")

func _ready() -> void:
    var saved := SaveSystemScript.load_data()
    _build_ui(saved)

func _build_ui(saved: Dictionary) -> void:
    # Title "NEON PINBALL"  @ (120, 120)
    # Label "Best: N"       @ (120, 200)
    # Button "Start Run"    @ (120, 280)  size (200, 48)
    # Button "Quit"         @ (120, 344)  size (200, 48)
```

### SaveSystem 参考（SettingsSystem 同风格）

```gdscript
class_name SaveSystem extends RefCounted
const SAVE_PATH := "user://neon_pinball.cfg"

static func load_data() -> Dictionary:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return _default_data()
    return { &"best_score": cfg.get_value("game","best_score",0), ... }

static func save(data: Dictionary) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("game","best_score", data.get(&"best_score",0))
    cfg.save(SAVE_PATH)
```

### DisplayServer API（窗口尺寸）

```gdscript
# 读取
var sz: Vector2i = DisplayServer.window_get_size()

# 设置（立即生效）
DisplayServer.window_set_size(Vector2i(810, 1350))

# 居中（可选，设置后调用）
DisplayServer.window_set_position(
    DisplayServer.screen_get_position() +
    (DisplayServer.screen_get_size() - DisplayServer.window_get_size()) / 2
)
```

> headless 模式下 `DisplayServer.window_set_size` 不报错但无实际效果，测试里只测 SettingsSystem 的数据逻辑，不测窗口 API。

---

## Task 1：project.godot 开启拉伸模式

- [ ] **修改** `project.godot` 的 `[display]` 节：

  **改前：**
  ```ini
  [display]
  window/size/viewport_width=540
  window/size/viewport_height=900
  ```

  **改后：**
  ```ini
  [display]
  window/size/viewport_width=540
  window/size/viewport_height=900
  window/size/window_width_override=810
  window/size/window_height_override=1350
  window/stretch/mode="canvas_items"
  window/stretch/aspect="keep"
  ```

  > - `viewport_width/height`：逻辑分辨率（不变），所有代码仍以 540×900 为坐标系
  > - `window_width/height_override`：初始窗口物理大小（中档 810×1350）
  > - `stretch/mode=canvas_items`：Godot 把 540×900 内容等比缩放到实际窗口
  > - `stretch/aspect=keep`：保持宽高比，两侧留黑边（不拉伸变形）

- [ ] **运行测试**，确认拉伸模式不破坏任何已有测试：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
  **预期：** 150 个测试全部通过，退出码 0。

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add project.godot
  git -C D:/NeonPinball/game commit -m "feat: enable canvas_items stretch mode, default window 810x1350"
  ```

---

## Task 2：SettingsSystem — 持久化窗口尺寸

- [ ] **新建** `run/settings_system.gd`（TAB 缩进）：

  ```gdscript
  class_name SettingsSystem extends RefCounted
  # Persists display / gameplay settings to user://settings.cfg

  const SETTINGS_PATH := "user://settings.cfg"

  # Supported window size presets (logical units; actual px = these values)
  const PRESETS: Array = [
      Vector2i(540, 900),
      Vector2i(810, 1350),
      Vector2i(1080, 1800),
  ]
  const DEFAULT_PRESET_INDEX := 1   # Medium (810x1350)

  static func load_window_size() -> Vector2i:
      var cfg := ConfigFile.new()
      if cfg.load(SETTINGS_PATH) != OK:
          return PRESETS[DEFAULT_PRESET_INDEX]
      var w: int = cfg.get_value("display", "window_width",  PRESETS[DEFAULT_PRESET_INDEX].x)
      var h: int = cfg.get_value("display", "window_height", PRESETS[DEFAULT_PRESET_INDEX].y)
      return Vector2i(w, h)

  static func save_window_size(size: Vector2i) -> void:
      var cfg := ConfigFile.new()
      cfg.load(SETTINGS_PATH)   # 若已有其它 section 不丢失
      cfg.set_value("display", "window_width",  size.x)
      cfg.set_value("display", "window_height", size.y)
      cfg.save(SETTINGS_PATH)

  static func preset_label(size: Vector2i) -> String:
      match size:
          Vector2i(540,  900):  return "Small  (540×900)"
          Vector2i(810,  1350): return "Medium (810×1350)"
          Vector2i(1080, 1800): return "Large  (1080×1800)"
      return "%d×%d" % [size.x, size.y]
  ```

- [ ] **新建测试文件** `tests/test_settings_system.gd`（TAB 缩进）：

  ```gdscript
  extends GutTest
  const SettingsSystemScript := preload("res://run/settings_system.gd")

  func test_default_window_size() -> void:
      # No file exists → should return default preset
      var sz := SettingsSystemScript.load_window_size()
      assert_eq(sz, SettingsSystemScript.PRESETS[SettingsSystemScript.DEFAULT_PRESET_INDEX],
          "无存档时返回默认中档尺寸")

  func test_save_and_load_round_trip() -> void:
      var target := Vector2i(1080, 1800)
      SettingsSystemScript.save_window_size(target)
      var loaded := SettingsSystemScript.load_window_size()
      assert_eq(loaded, target, "保存后读取返回相同尺寸")

  func test_preset_label_small() -> void:
      assert_eq(SettingsSystemScript.preset_label(Vector2i(540, 900)),
          "Small  (540×900)")

  func test_preset_label_medium() -> void:
      assert_eq(SettingsSystemScript.preset_label(Vector2i(810, 1350)),
          "Medium (810×1350)")

  func test_preset_label_large() -> void:
      assert_eq(SettingsSystemScript.preset_label(Vector2i(1080, 1800)),
          "Large  (1080×1800)")
  ```

  > `test_save_and_load_round_trip` 会写 `user://settings.cfg`（headless 模式下路径在系统临时目录），测试完无需清理，GUT 环境隔离。

- [ ] **运行测试**，预期 150 → 155（新增 5 个）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add run/settings_system.gd tests/test_settings_system.gd
  git -C D:/NeonPinball/game commit -m "feat: SettingsSystem — persist window size to settings.cfg"
  ```

---

## Task 3：主菜单加分辨率选择

- [ ] **修改** `view/main_menu.gd`：

  在文件顶部 preload 区追加：
  ```gdscript
  const SettingsSystemScript := preload("res://run/settings_system.gd")
  ```

  `_ready()` 里，在 `_build_ui(saved)` 之前先应用已保存的窗口尺寸：
  ```gdscript
  func _ready() -> void:
      _apply_saved_window_size()
      var saved := SaveSystemScript.load_data()
      _build_ui(saved)

  func _apply_saved_window_size() -> void:
      var sz := SettingsSystemScript.load_window_size()
      DisplayServer.window_set_size(sz)
      # 居中显示
      var screen_size := DisplayServer.screen_get_size()
      var win_size   := DisplayServer.window_get_size()
      DisplayServer.window_set_position((screen_size - win_size) / 2)
  ```

  `_build_ui()` 末尾，在 Quit 按钮之后追加分辨率选择区：
  ```gdscript
  func _build_ui(saved: Dictionary) -> void:
      # ... 原有 Title / Best / Start / Quit ...

      # ---- 分辨率 ----
      var res_label := Label.new()
      res_label.text = "Window Size"
      res_label.add_theme_font_size_override(&"font_size", 18)
      res_label.position = Vector2(120, 430)
      add_child(res_label)

      var current_sz := SettingsSystemScript.load_window_size()
      var btn_y := 460
      for preset in SettingsSystemScript.PRESETS:
          var btn := Button.new()
          btn.text = SettingsSystemScript.preset_label(preset)
          btn.position = Vector2(120, btn_y)
          btn.custom_minimum_size = Vector2(280, 44)
          if preset == current_sz:
              btn.disabled = true   # 当前已选中的档位禁用（视觉反馈）
          btn.pressed.connect(_on_resolution_pressed.bind(preset))
          add_child(btn)
          btn_y += 52
  ```

  追加回调方法：
  ```gdscript
  func _on_resolution_pressed(size: Vector2i) -> void:
      SettingsSystemScript.save_window_size(size)
      DisplayServer.window_set_size(size)
      var screen_size := DisplayServer.screen_get_size()
      var win_size   := DisplayServer.window_get_size()
      DisplayServer.window_set_position((screen_size - win_size) / 2)
      # 重新加载主菜单以刷新按钮选中状态
      SceneMan.goto_menu()
  ```

  > 点击分辨率档位后：①保存设置 ②立即改变窗口 ③ `goto_menu()` 重载主菜单刷新选中状态（Disabled 按钮高亮当前档）。

- [ ] **运行测试**，预期仍为 155（主菜单改动无新纯逻辑测试，冒烟用既有 `test_menu_scene_loads_without_error`）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/main_menu.gd
  git -C D:/NeonPinball/game commit -m "feat: resolution picker in main menu (S/M/L presets, persisted)"
  ```

---

## 文件结构

**新建：**
- `run/settings_system.gd` — 分辨率设置持久化（ConfigFile `user://settings.cfg`）
- `tests/test_settings_system.gd` — 5 个单元测试

**修改：**
- `project.godot` — 开启 canvas_items 拉伸、初始窗口 810×1350
- `view/main_menu.gd` — 加 `_apply_saved_window_size()`、分辨率选择按钮区

---

## 自检清单

- [ ] 150 个基线测试仍全部通过
- [ ] 新增 5 个测试全部通过（共 155）
- [ ] 游戏启动进入主菜单，窗口为上次保存的尺寸（默认 810×1350）
- [ ] 主菜单显示三个分辨率按钮，当前档位为 Disabled 状态
- [ ] 点击其他档位 → 窗口立即变大/小 → 主菜单刷新 → 新档位 Disabled
- [ ] 退出游戏重新启动 → 恢复上次选择的分辨率
- [ ] 局内游戏画面比例正确（540×900 内容等比缩放，不变形）
- [ ] 无回归（既有测试全绿）

---

## 已知局限 / 留待后续

- 分辨率选择仅在主菜单；局内无法切换（切换需重载场景，主菜单是合适的时机）
- `keep` 模式两侧/上下可能有黑边；若想填满可改 `stretch/aspect="keep_width"` 或 `"expand"`，但后者需要 UI 自适应改造
- 不支持全屏模式（后续可加 `DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)`）
