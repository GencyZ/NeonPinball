# 图片/美术资源 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for marking.

**Goal:** 将游戏内的程序化绘制（`draw_circle`）替换为图片贴图，并加入背景图，提升视觉表现力。球、普通钉、MULT 钉分别用独立图片，背景用全屏贴图。其余钉类型（CHAIN、BOMB）视资源情况追加。

**前提：** 用户需自行准备以下 PNG 图片（透明背景）后再执行本计划：

| 文件路径 | 建议尺寸 | 内容 |
|----------|---------|------|
| `game/assets/background.png` | 540×900 | 游戏背景 |
| `game/assets/peg_normal.png` | 64×64 | 普通钉（圆形，透明背景） |
| `game/assets/peg_mult.png` | 64×64 | MULT 钉（橙色圆形） |
| `game/assets/ball.png` | 64×64 | 球（圆形，透明背景） |

可选（有则用，无则退化为 draw_circle）：
- `game/assets/peg_chain.png`（蓝紫）
- `game/assets/peg_bomb.png`（红色）

**Architecture:**
- `board_view.gd` 顶部 preload 图片常量；`_draw()` 中用 `draw_texture_rect` 替换 `draw_circle`
- 背景：`_ready()` 中以 `Sprite2D`（或 `TextureRect`）子节点加入，排在所有子节点最前，渲染在最底层
- 图片不存在时（资源路径无效）静默退回 `draw_circle`，不崩溃

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

### 当前 `_draw()` 绘制方式

```gdscript
# 钉子
draw_circle(peg[&"pos"], radius, col)

# 球
draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))

# 粒子、飘字等保持 draw_circle/draw_string 不变
```

### Godot draw_texture_rect 用法

```gdscript
# 在 Node2D._draw() 内使用
var tex: Texture2D = preload("res://assets/peg_normal.png")
var size := Vector2(radius * 2, radius * 2)
# 居中到 pos：Rect2(左上角, 大小)
draw_texture_rect(tex, Rect2(pos - size / 2, size), false)
# 带调色（modulate）
draw_texture_rect(tex, Rect2(pos - size / 2, size), false, col)
```

### 背景贴图（Node2D 子节点）

```gdscript
# 在 _ready() 最开始加入，确保在所有子节点之前渲染
var bg := Sprite2D.new()
bg.texture = preload("res://assets/background.png")
bg.position = Vector2(270, 450)   # 画布中心（540/2, 900/2）
bg.z_index = -1                   # 渲染在最底层
add_child(bg)
```

---

## Task 1：准备资源目录 + 安全加载工具

- [ ] **创建** `assets/` 目录（用户手动放入 PNG 文件，或先放占位符）：
  ```
  game/assets/
    background.png
    peg_normal.png
    peg_mult.png
    ball.png
  ```
  若图片不存在，Task 2/3 的代码会静默退回 draw_circle，不崩溃。

- [ ] **修改** `view/board_view.gd` 顶部，追加图片加载常量：

  ```gdscript
  # ---- Art assets (null if file not found) ----
  const _TEX_BG     := "res://assets/background.png"
  const _TEX_NORMAL := "res://assets/peg_normal.png"
  const _TEX_MULT   := "res://assets/peg_mult.png"
  const _TEX_CHAIN  := "res://assets/peg_chain.png"
  const _TEX_BOMB   := "res://assets/peg_bomb.png"
  const _TEX_BALL   := "res://assets/ball.png"

  var _tex_normal: Texture2D = null
  var _tex_mult:   Texture2D = null
  var _tex_chain:  Texture2D = null
  var _tex_bomb:   Texture2D = null
  var _tex_ball:   Texture2D = null
  ```

  在 `_ready()` 开头加载（ResourceLoader.exists 判断存在性）：

  ```gdscript
  func _ready() -> void:
      _load_textures()
      # ... 原有代码 ...

  func _load_textures() -> void:
      if ResourceLoader.exists(_TEX_NORMAL): _tex_normal = load(_TEX_NORMAL)
      if ResourceLoader.exists(_TEX_MULT):   _tex_mult   = load(_TEX_MULT)
      if ResourceLoader.exists(_TEX_CHAIN):  _tex_chain  = load(_TEX_CHAIN)
      if ResourceLoader.exists(_TEX_BOMB):   _tex_bomb   = load(_TEX_BOMB)
      if ResourceLoader.exists(_TEX_BALL):   _tex_ball   = load(_TEX_BALL)
  ```

- [ ] **运行测试**，预期 150 个测试全部通过（仅加常量/变量，无逻辑变化）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: art asset loading infrastructure (safe preload with fallback)"
  ```

---

## Task 2：背景图 + 钉子贴图替换

- [ ] **修改** `view/board_view.gd` 的 `_ready()`：在 `_load_textures()` 之后加背景 Sprite2D：

  ```gdscript
  if ResourceLoader.exists(_TEX_BG):
      var bg := Sprite2D.new()
      bg.texture = load(_TEX_BG)
      bg.position = Vector2(270, 450)
      bg.z_index = -1
      add_child(bg)
  ```

- [ ] **修改** `_draw()` 中的钉子绘制，替换 `draw_circle`：

  **改前：**
  ```gdscript
  draw_circle(peg[&"pos"], radius, col)
  ```

  **改后：**
  ```gdscript
  var peg_tex := _peg_texture_for(pt)
  if peg_tex != null:
      var sz := Vector2(radius * 2, radius * 2)
      draw_texture_rect(peg_tex, Rect2(peg[&"pos"] - sz / 2, sz), false, col)
  else:
      draw_circle(peg[&"pos"], radius, col)   # 无图片时退回
  ```

  追加辅助方法（在 `_draw` 附近）：

  ```gdscript
  func _peg_texture_for(pt: PegType) -> Texture2D:
      if pt == null:
          return _tex_normal
      match pt.behavior:
          PegType.Behavior.MULT:  return _tex_mult
          PegType.Behavior.CHAIN: return _tex_chain
          PegType.Behavior.BOMB:  return _tex_bomb
          _: return _tex_normal
  ```

- [ ] **运行测试**，预期 150 个全部通过：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: draw pegs with texture (fallback to draw_circle if no asset)"
  ```

---

## Task 3：球体贴图替换

- [ ] **修改** `_draw()` 中球的绘制：

  **改前：**
  ```gdscript
  draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))
  ```

  **改后：**
  ```gdscript
  if _tex_ball != null:
      var r: float = _active_balls[i].radius
      draw_texture_rect(_tex_ball, Rect2(dp - Vector2(r, r), Vector2(r * 2, r * 2)), false)
  else:
      draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))
  ```

- [ ] **运行测试**，预期 150 个全部通过：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **手动验证：**
  - 放入图片后背景正确显示、不遮挡钉子和球
  - 钉子显示对应图片，无图片时退回 draw_circle（程序化颜色）
  - 球显示图片，动画（弹跳、插值）正常
  - 粒子、飘字、闪光不受影响

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: draw ball with texture (fallback to draw_circle if no asset)"
  ```

---

## 文件结构

**新建（用户手动）：**
- `assets/background.png`、`assets/peg_normal.png`、`assets/peg_mult.png`、`assets/ball.png`

**修改：**
- `view/board_view.gd` — 资源加载 + `_peg_texture_for()` + 三处 draw 替换

**无新测试文件**（视觉功能 headless 无法验证；资源存在性由 `ResourceLoader.exists` 保护，无崩溃风险）。

---

## 自检清单

- [ ] 150 个基线测试全部通过（无回归）
- [ ] 放入图片后：背景显示、钉子显示图片、球显示图片
- [ ] 不放图片：游戏正常运行，退回 draw_circle
- [ ] 钉子图片大小与碰撞半径视觉匹配（64×64 图片 = 物理半径 ~16-18px，根据实际图片调整 `radius * 2` 系数）
- [ ] 无游戏逻辑回归

---

## 已知局限 / 留待后续

- 图片尺寸与物理半径需手动匹配；后续可在 PegType 上加 `texture_scale` 字段
- 钉子动画（sin 弹跳）目前通过 radius 参数放大，换成贴图后 radius 不变，贴图大小跟着缩放（`sz = radius * 2`），视觉动画仍正确
- 未处理 Retina / DPI 缩放；高 DPI 屏上图片可能模糊，后续可用 2× 图片
- 钉子图片用 `col` 做 modulate，仍可叠加颜色效果（命中闪光等）
