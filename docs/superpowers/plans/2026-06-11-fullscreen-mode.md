# 全屏模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在主菜单加全屏切换按钮，点击后游戏全屏/窗口模式互切，设置持久化，下次启动自动恢复。

**依赖：** 本计划复用 `run/settings_system.gd`（分辨率计划 `2026-06-11-resolution-settings.md` 的产物）。如果分辨率计划尚未执行，先执行那一份；如果已执行，直接在 SettingsSystem 里追加全屏字段。

**Architecture:**
- `SettingsSystem` 新增 `load_fullscreen() -> bool` / `save_fullscreen(v: bool)`
- 主菜单加 "Fullscreen: ON/OFF" 切换按钮，点击调用 `DisplayServer.window_set_mode()` 并保存
- 启动时在 `_apply_saved_window_size()` 内同时应用全屏状态

**Tech Stack:** Godot 4.6.3 GDScript, GUT。

---

## Background（代码库上下文）

- 项目根目录：`D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**150 个测试**（执行分辨率计划后为 155 个）全部通过。
- 每个任务只提交它自己改动的文件。**不要 push。**

### DisplayServer 全屏 API

```gdscript
# 进入全屏
DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# 退出全屏（回到窗口）
DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# 读取当前模式
var mode := DisplayServer.window_get_mode()
var is_fs := (mode == DisplayServer.WINDOW_MODE_FULLSCREEN
           or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
```

> headless 模式下调用 window_set_mode 不报错，只是无效果，测试里只测数据逻辑。

### SettingsSystem（分辨率计划产物）

```gdscript
# run/settings_system.gd  ← 本计划在此追加全屏字段
static func load_window_size() -> Vector2i: ...
static func save_window_size(size: Vector2i) -> void: ...
static func preset_label(size: Vector2i) -> String: ...
```

### main_menu.gd 当前结构（分辨率计划执行后）

```
Title "NEON PINBALL"    @ (120, 120)
Label "Best: N"         @ (120, 200)
Button "Start Run"      @ (120, 280)
Button "Quit"           @ (120, 344)
Label "Window Size"     @ (120, 430)
Button Small/Med/Large  @ (120, 460-564)
```

全屏按钮接在分辨率区之后（y ≈ 640）。

---

## Task 1：SettingsSystem 追加全屏持久化

- [ ] **修改** `run/settings_system.gd`：在文件末尾追加两个静态方法：

  ```gdscript
  static func load_fullscreen() -> bool:
      var cfg := ConfigFile.new()
      if cfg.load(SETTINGS_PATH) != OK:
          return false   # 默认窗口模式
      return cfg.get_value("display", "fullscreen", false)

  static func save_fullscreen(enabled: bool) -> void:
      var cfg := ConfigFile.new()
      cfg.load(SETTINGS_PATH)
      cfg.set_value("display", "fullscreen", enabled)
      cfg.save(SETTINGS_PATH)
  ```

- [ ] **追加测试**到 `tests/test_settings_system.gd`：

  ```gdscript
  func test_fullscreen_default_false() -> void:
      assert_false(SettingsSystemScript.load_fullscreen(), "无存档时默认非全屏")

  func test_fullscreen_save_load_round_trip() -> void:
      SettingsSystemScript.save_fullscreen(true)
      assert_true(SettingsSystemScript.load_fullscreen(), "保存 true 后读取为 true")
      SettingsSystemScript.save_fullscreen(false)
      assert_false(SettingsSystemScript.load_fullscreen(), "保存 false 后读取为 false")
  ```

- [ ] **运行测试**，预期 +2（若分辨率计划已执行则从 155 → 157，否则从 150 → 152）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add run/settings_system.gd tests/test_settings_system.gd
  git -C D:/NeonPinball/game commit -m "feat: SettingsSystem — persist fullscreen state"
  ```

---

## Task 2：主菜单加全屏切换按钮

- [ ] **修改** `view/main_menu.gd`：

  `_apply_saved_window_size()` 里追加全屏恢复逻辑（在窗口尺寸应用之后）：

  ```gdscript
  func _apply_saved_window_size() -> void:
      # ... 原有窗口尺寸逻辑 ...
      if SettingsSystemScript.load_fullscreen():
          DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
  ```

  > 若分辨率计划尚未执行（没有 `_apply_saved_window_size()`），在 `_ready()` 开头加：
  > ```gdscript
  > if SettingsSystemScript.load_fullscreen():
  >     DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
  > ```

  `_build_ui()` 末尾，分辨率按钮区之后追加全屏切换区（y 值根据实际布局微调）：

  ```gdscript
  # ---- 全屏切换 ----
  var fs_label := Label.new()
  fs_label.text = "Display"
  fs_label.add_theme_font_size_override(&"font_size", 18)
  fs_label.position = Vector2(120, 640)
  add_child(fs_label)

  var fs_btn := Button.new()
  var is_fs := SettingsSystemScript.load_fullscreen()
  fs_btn.text = "Fullscreen: %s" % ("ON" if is_fs else "OFF")
  fs_btn.position = Vector2(120, 668)
  fs_btn.custom_minimum_size = Vector2(240, 44)
  fs_btn.pressed.connect(_on_fullscreen_toggled)
  add_child(fs_btn)
  ```

  追加回调方法：

  ```gdscript
  func _on_fullscreen_toggled() -> void:
      var currently_fs := SettingsSystemScript.load_fullscreen()
      var new_fs := not currently_fs
      SettingsSystemScript.save_fullscreen(new_fs)
      if new_fs:
          DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
      else:
          DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
          # 退出全屏后恢复保存的窗口尺寸
          var sz := SettingsSystemScript.load_window_size()
          DisplayServer.window_set_size(sz)
          var screen_size := DisplayServer.screen_get_size()
          DisplayServer.window_set_position((screen_size - sz) / 2)
      # 重载主菜单刷新按钮文字
      SceneMan.goto_menu()
  ```

- [ ] **运行测试**，预期测试数不变（主菜单改动无新纯逻辑测试）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/main_menu.gd
  git -C D:/NeonPinball/game commit -m "feat: fullscreen toggle button in main menu (persisted)"
  ```

---

## 文件结构

**修改（共 3 个文件）：**

| 文件 | 改动内容 |
|------|---------|
| `run/settings_system.gd` | 追加 `load_fullscreen()` / `save_fullscreen()` |
| `tests/test_settings_system.gd` | 追加 2 个测试 |
| `view/main_menu.gd` | 启动时恢复全屏状态；加全屏切换按钮 |

---

## 自检清单

- [ ] 新增测试全部通过（+2 个）
- [ ] 主菜单显示 "Fullscreen: OFF"（默认）
- [ ] 点击后变 "Fullscreen: ON"，游戏进入全屏
- [ ] 再次点击退出全屏，恢复窗口尺寸，主菜单刷新
- [ ] 退出并重启游戏 → 恢复上次全屏/窗口状态
- [ ] 无回归

---

## 已知局限 / 留待后续

- 全屏与分辨率档位组合：进入全屏后分辨率档位按钮仍可点击，但全屏时窗口尺寸由系统控制，退出全屏后恢复。当前实现已处理退出全屏时恢复保存的档位尺寸。
- 不支持无边框全屏（WINDOW_MODE_EXCLUSIVE_FULLSCREEN）；后续可加第三档
- Alt+Enter 快捷键未处理；后续可在 input_controller 里监听
