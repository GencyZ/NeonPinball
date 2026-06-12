# 霓虹边框 + 连击追逐光 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 board 场景加真辉光（WorldEnvironment Glow），把四周边界做成霓虹边框，并由"时间衰减热度"驱动一圈追逐光（跑马灯）循环流动——越连越多越快越亮、色相越烫（青→热粉，不褪白）。

**Architecture:** 纯函数映射与几何放 `juice/neon_frame.gd`（可单测）；辉光环境用代码构建 `Environment`（枚举常量编译期校验，比手写 .tres 稳）放 `view/neon_environment.gd`；`board_view.gd` 加时间衰减热度 `_wall_heat`、相位 `_neon_phase`，在 `_draw()` 叠加霓虹边框。对确定性 sim/计分零侵入。

**Tech Stack:** Godot 4.6.3 纯 GDScript（Forward+），GUT 9.x，2D Glow（WorldEnvironment + `rendering/viewport/hdr_2d`）。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
  （`godot` 不在 PATH，Git Bash 用 `/d/Program/Godot/godot`；单文件用 `-gselect=<file>`。）
- 当前基线：**207 个测试全部通过，32 个脚本**。
- 缩进用 **TAB**（`juice/`、`view/`、`tests/`）。每个任务只提交自己改动的文件。**不要 push**（用户单独确认）。**不要新建分支**（在 main 上做，与本仓库一贯流程一致）。
- board 场景 `scenes/board.tscn`：`BoardView`(Node2D) + `Hud`(CanvasLayer) + `InputController` + `Camera2D`。无 WorldEnvironment。背景纯黑。
- `view/board_view.gd` 关键锚点（行号近似，**按内容匹配**）：
  - `func _ready()`：第 67 行 `_juice = JuiceControllerScript.new()`，紧接第 74–75 行 `_sfx = SfxControllerScript.new()` / `add_child(_sfx)`。
  - 顶部 const 区：第 13 行 `const JuiceControllerScript := preload(...)`，第 14–15 行 `const SfxControllerScript := preload(...)` / `const COMBO_DISPLAY_DUR := 0.6`。
  - 状态 var 区：第 47–50 行 `var _combo`、`var _last_hit_pos`、`var _combo_display_ttl`、`var _sfx`。
  - PEG_HIT 充能点：`_combo_display_ttl = COMBO_DISPLAY_DUR`（PEG_HIT 块开头，prior 特性加的）。
  - `_process` 衰减点：`if _combo_display_ttl > 0.0:` / `\t\t_combo_display_ttl -= delta`（不依赖 `_has_ball` 的那段）。
  - `_draw()`：第 699 行 `_draw_walls()` 调用；`func _draw_walls()` 定义在第 617 行。
- `_rect = Rect2(135, 225, 540, 900)`；漏斗局部点 `(0,780)→(240,900)`、`(540,780)→(300,900)`。

---

## 文件结构

**新建：**
- `juice/neon_frame.gd` — 纯逻辑 + 几何：heat→颜色/脉冲参数、热度衰减、边框弧长采样。常量 `IDLE/HOT/HEAT_PER_HIT/DECAY_RATE`。
- `view/neon_environment.gd` — `static make_environment() -> Environment`：代码构建开启 Glow 的 Environment。
- `tests/test_neon_frame.gd` — neon_frame 纯函数测试。
- `tests/test_neon_environment.gd` — Environment 配置测试。

**修改：**
- `project.godot` — `[rendering]` 加 `viewport/hdr_2d=true`。
- `view/board_view.gd` — _ready 挂 WorldEnvironment；加 `_wall_heat`/`_neon_phase`；PEG_HIT 充能；_process 衰减+推进相位；_draw 叠加 `_draw_neon_frame()`。

---

## Task 1：neon_frame.gd — 纯函数与几何

**Files:**
- Create: `juice/neon_frame.gd`
- Test: `tests/test_neon_frame.gd`

- [ ] **Step 1: 写失败测试** `tests/test_neon_frame.gd`（TAB 缩进）

```gdscript
extends GutTest

const NeonFrameScript := preload("res://juice/neon_frame.gd")

func test_heat_color_endpoints() -> void:
	assert_eq(NeonFrameScript.heat_color(0.0), NeonFrameScript.IDLE, "heat 0 = 霓虹青")
	assert_eq(NeonFrameScript.heat_color(1.0), NeonFrameScript.HOT, "heat 1 = 热粉")

func test_heat_color_not_white_at_max() -> void:
	var c := NeonFrameScript.heat_color(1.0)
	assert_lt(c.g, 0.5, "最烫不褪白：绿分量低")
	assert_lt(c.b, 0.9, "最烫不褪白：蓝分量不高")

func test_heat_color_trend() -> void:
	# 青→粉：R 升、B 降
	assert_lt(NeonFrameScript.heat_color(0.0).r, NeonFrameScript.heat_color(1.0).r, "R 随热度升")
	assert_gt(NeonFrameScript.heat_color(0.0).b, NeonFrameScript.heat_color(1.0).b, "B 随热度降")

func test_pulse_count_zero_when_calm() -> void:
	assert_eq(NeonFrameScript.pulse_count_for_heat(0.0), 0, "平静无脉冲")
	assert_eq(NeonFrameScript.pulse_count_for_heat(0.04), 0, "低于阈值无脉冲")

func test_pulse_count_monotonic_and_capped() -> void:
	assert_gte(NeonFrameScript.pulse_count_for_heat(0.05), 1, "过阈值至少 1 条")
	for n in range(0, 20):
		var lo := NeonFrameScript.pulse_count_for_heat(float(n) / 20.0)
		var hi := NeonFrameScript.pulse_count_for_heat(float(n + 1) / 20.0)
		assert_true(hi >= lo, "脉冲数单调不降 @%d" % n)
	assert_eq(NeonFrameScript.pulse_count_for_heat(1.0), 4, "封顶 4 条")

func test_speed_monotonic_and_range() -> void:
	assert_almost_eq(NeonFrameScript.speed_for_heat(0.0), 0.15, 1e-4, "平静流速 0.15")
	assert_almost_eq(NeonFrameScript.speed_for_heat(1.0), 0.8, 1e-4, "满热流速 0.8")
	assert_gt(NeonFrameScript.speed_for_heat(1.0), NeonFrameScript.speed_for_heat(0.0), "流速随热度升")

func test_brightness_monotonic_and_range() -> void:
	assert_almost_eq(NeonFrameScript.brightness_for_heat(0.0), 1.2, 1e-4, "平静亮度 1.2")
	assert_almost_eq(NeonFrameScript.brightness_for_heat(1.0), 3.0, 1e-4, "满热亮度 3.0")
	assert_gt(NeonFrameScript.brightness_for_heat(1.0), NeonFrameScript.brightness_for_heat(0.0), "亮度随热度升")

func test_decay_heat() -> void:
	assert_almost_eq(NeonFrameScript.decay_heat(1.0, 2.0), 0.0, 1e-4, "满热 2 秒冷却到 0")
	assert_eq(NeonFrameScript.decay_heat(0.0, 1.0), 0.0, "不为负")
	assert_lt(NeonFrameScript.decay_heat(0.5, 0.1), 0.5, "随时间下降")

func test_point_at_square() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	assert_eq(NeonFrameScript.point_at(sq, 0.0), Vector2(0, 0), "s=0 起点")
	var p25 := NeonFrameScript.point_at(sq, 0.25)
	assert_almost_eq(p25.x, 1.0, 1e-4, "s=0.25 → (1,0).x")
	assert_almost_eq(p25.y, 0.0, 1e-4, "s=0.25 → (1,0).y")
	var p50 := NeonFrameScript.point_at(sq, 0.5)
	assert_almost_eq(p50.x, 1.0, 1e-4, "s=0.5 → (1,1).x")
	assert_almost_eq(p50.y, 1.0, 1e-4, "s=0.5 → (1,1).y")

func test_point_at_wraps() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	assert_eq(NeonFrameScript.point_at(sq, 1.0), NeonFrameScript.point_at(sq, 0.0), "s=1 绕回 s=0")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_frame.gd -gexit`
Expected: FAIL（类不存在 / 函数未定义）

- [ ] **Step 3: 实现** `juice/neon_frame.gd`（TAB 缩进）

```gdscript
class_name NeonFrame extends RefCounted

# 热度色斜坡：青 → 饱和热粉，始终饱和不褪白。
const IDLE := Color(0.0, 0.9, 1.0)
const HOT  := Color(1.0, 0.15, 0.55)

const HEAT_PER_HIT := 0.12   # 每次击中充能
const DECAY_RATE   := 0.5    # 每秒冷却（满热约 2s 归零）

# 热度 → 颜色（线性插值，始终饱和）
static func heat_color(heat: float) -> Color:
	return IDLE.lerp(HOT, clampf(heat, 0.0, 1.0))

# 热度 → 追逐光脉冲条数（平静 0 条，过阈值 1 条起，封顶 4）
static func pulse_count_for_heat(heat: float) -> int:
	if heat < 0.05:
		return 0
	return 1 + floori(clampf(heat, 0.0, 1.0) * 3.0)

# 热度 → 流速（每秒绕框圈数）
static func speed_for_heat(heat: float) -> float:
	return lerpf(0.15, 0.8, clampf(heat, 0.0, 1.0))

# 热度 → 脉冲峰值亮度倍率（>1 触发 bloom）
static func brightness_for_heat(heat: float) -> float:
	return lerpf(1.2, 3.0, clampf(heat, 0.0, 1.0))

# 热度随时间冷却（不为负）
static func decay_heat(heat: float, delta: float) -> float:
	return maxf(heat - DECAY_RATE * delta, 0.0)

# 闭合折线按弧长采样：s∈[0,1) 绕一圈，首尾相连。
static func point_at(poly: PackedVector2Array, s: float) -> Vector2:
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return poly[0]
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	if total <= 0.0:
		return poly[0]
	var target := fposmod(s, 1.0) * total
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var l := a.distance_to(b)
		if target <= l or i == n - 1:
			var t := (target / l) if l > 0.0 else 0.0
			return a.lerp(b, clampf(t, 0.0, 1.0))
		target -= l
	return poly[0]
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_frame.gd -gexit`
Expected: PASS（10/10）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/neon_frame.gd tests/test_neon_frame.gd
git -C D:/NeonPinball/game commit -m "feat: NeonFrame — heat->color/pulse curves + perimeter arc sampling"
```

---

## Task 2：辉光环境（WorldEnvironment Glow）

**Files:**
- Create: `view/neon_environment.gd`
- Test: `tests/test_neon_environment.gd`
- Modify: `project.godot`
- Modify: `view/board_view.gd`（_ready 挂 WorldEnvironment）

- [ ] **Step 1: 写失败测试** `tests/test_neon_environment.gd`（TAB 缩进）

```gdscript
extends GutTest

const NeonEnvScript := preload("res://view/neon_environment.gd")

func test_make_environment_enables_glow() -> void:
	var env := NeonEnvScript.make_environment()
	assert_true(env is Environment, "返回 Environment")
	assert_true(env.glow_enabled, "Glow 已开启")

func test_make_environment_additive_threshold() -> void:
	var env := NeonEnvScript.make_environment()
	assert_eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_ADDITIVE, "加色混合")
	assert_almost_eq(env.glow_hdr_threshold, 1.0, 1e-4, "阈值 1.0（普通内容不糊）")

func test_make_environment_canvas_background() -> void:
	var env := NeonEnvScript.make_environment()
	assert_eq(env.background_mode, Environment.BG_CANVAS, "2D 用 Canvas 背景模式")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_environment.gd -gexit`
Expected: FAIL（类不存在）

- [ ] **Step 3: 实现** `view/neon_environment.gd`（TAB 缩进）

```gdscript
class_name NeonEnvironment extends RefCounted

# 代码构建开启 2D Glow 的 Environment（枚举常量编译期校验，比手写 .tres 稳）。
# 实际辉光强度需实机调，调整下面数值即可。
static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0
	env.glow_strength = 1.2
	env.glow_bloom = 0.2
	return env
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_environment.gd -gexit`
Expected: PASS（3/3）

- [ ] **Step 5: 开启 2D HDR** — 修改 `project.godot`，在 `[rendering]` 段把：
```ini
[rendering]

rendering_device/driver.windows="d3d12"
environment/defaults/default_clear_color=Color(0, 0, 0, 1)
```
改为：
```ini
[rendering]

rendering_device/driver.windows="d3d12"
environment/defaults/default_clear_color=Color(0, 0, 0, 1)
viewport/hdr_2d=true
```

- [ ] **Step 6: _ready 挂 WorldEnvironment** — 修改 `view/board_view.gd`。
先在顶部 const 区，找到：
`const SfxControllerScript := preload("res://juice/sfx_controller.gd")`
在其后加：
```gdscript
const NeonEnvScript := preload("res://view/neon_environment.gd")
```
再在 `_ready()` 里找到：
```gdscript
	_sfx = SfxControllerScript.new()
	add_child(_sfx)
```
在其后加：
```gdscript
	var _we := WorldEnvironment.new()
	_we.environment = NeonEnvScript.make_environment()
	add_child(_we)
```

- [ ] **Step 7: 验证场景加载 + 全套测试**
创建 `/tmp/env_check.gd`：
```gdscript
extends SceneTree
func _init():
	var ps = load("res://scenes/board.tscn")
	if ps == null: print("SCENE_LOAD_FAIL"); quit(); return
	var inst = ps.instantiate()
	print("BOARD_OK" if inst != null else "INSTANTIATE_FAIL")
	if inst != null: inst.free()
	quit()
```
Run: `/d/Program/Godot/godot --headless --path . -s /tmp/env_check.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
Expected: `BOARD_OK`，无 Parse Error / SCRIPT ERROR。然后 `rm -f /tmp/env_check.gd`。
再跑全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
Expected: All tests passed，总数 207 + 13 = **220**。

> 实机辉光视觉（亮色是否溢光）需带 GUI 跑一局确认，属用户人工验收；headless 测不了。若实机无辉光：优先尝试 `glow_blend_mode = SCREEN`、降低 `glow_hdr_threshold`、确认 `hdr_2d` 已生效。

- [ ] **Step 8: 提交**

```bash
git -C D:/NeonPinball/game add view/neon_environment.gd tests/test_neon_environment.gd project.godot view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: WorldEnvironment 2D glow on board (hdr_2d + additive bloom)"
```

---

## Task 3：board_view 接线热度 + 追逐光边框

**Files:**
- Modify: `view/board_view.gd`

> board_view 是场景脚本，无单测；本任务靠"场景加载检查 + 全套测试保持绿 + 实机确认"验证。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 加常量** — 顶部 const 区，找到上一步加的：
`const NeonEnvScript := preload("res://view/neon_environment.gd")`
在其后加：
```gdscript
const NeonFrameScript := preload("res://juice/neon_frame.gd")
const HALF_PULSE_LEN := 0.04   # 脉冲沿边框的归一化半宽
```

- [ ] **Step 2: 加状态变量** — 找到：
`var _sfx`
在其后加：
```gdscript
var _wall_heat := 0.0
var _neon_phase := 0.0
```

- [ ] **Step 3: PEG_HIT 充能** — 找到 PEG_HIT 块里的：
`					_combo_display_ttl = COMBO_DISPLAY_DUR`
在其后加（同缩进，注意是 5 个 TAB）：
```gdscript
					_wall_heat = minf(_wall_heat + NeonFrameScript.HEAT_PER_HIT, 1.0)
```

- [ ] **Step 4: _process 冷却 + 推进相位** — 找到（不依赖 `_has_ball` 的那段）：
```gdscript
	if _combo_display_ttl > 0.0:
		_combo_display_ttl -= delta
```
在其后加（1 个 TAB）：
```gdscript
	_wall_heat = NeonFrameScript.decay_heat(_wall_heat, delta)
	_neon_phase = fmod(_neon_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat), 1.0)
```

- [ ] **Step 5: _draw 调用霓虹边框** — 找到 `_draw()` 里的：
`	_draw_walls()`
在其后加（1 个 TAB）：
```gdscript
	_draw_neon_frame()
```

- [ ] **Step 6: 新增边框折线与绘制函数** — 在 `func _draw_walls() -> void:` 整个函数定义**之后**（即 `_draw_walls` 结束、`func _draw()` 之前）插入：
```gdscript
# 桶形边界闭合折线（顶左→顶右→右墙底→右漏斗内→左漏斗内→左墙底→回起点）。
func _neon_perimeter() -> PackedVector2Array:
	var o := _rect.position
	return PackedVector2Array([
		o + Vector2(0, 0),
		o + Vector2(540, 0),
		o + Vector2(540, 780),
		o + Vector2(300, 900),
		o + Vector2(240, 900),
		o + Vector2(0, 780),
	])

# 沿边框画暗底光 + N 条追逐光脉冲；颜色/条数/亮度/流速由 _wall_heat 驱动。
func _draw_neon_frame() -> void:
	var poly := _neon_perimeter()
	var pn := poly.size()
	if pn < 2:
		return
	var col := NeonFrameScript.heat_color(_wall_heat)
	# 暗底框
	var base := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9)
	for i in pn:
		draw_line(poly[i], poly[(i + 1) % pn], base, 2.5)
	# 追逐光脉冲
	var n := NeonFrameScript.pulse_count_for_heat(_wall_heat)
	if n <= 0:
		return
	var bright := NeonFrameScript.brightness_for_heat(_wall_heat)
	var pcol := Color(col.r * bright, col.g * bright, col.b * bright)
	var samples := 6
	for i in n:
		var center := fmod(_neon_phase + float(i) / float(n), 1.0)
		var start_s := center - HALF_PULSE_LEN
		var prev := NeonFrameScript.point_at(poly, fposmod(start_s, 1.0))
		for k in range(1, samples + 1):
			var frac := float(k) / float(samples)
			var s := fposmod(start_s + 2.0 * HALF_PULSE_LEN * frac, 1.0)
			var p := NeonFrameScript.point_at(poly, s)
			var fall := 1.0 - absf(frac - 0.5) * 2.0   # 中间最亮，两端淡出
			draw_line(prev, p, Color(pcol.r, pcol.g, pcol.b, 0.4 + 0.6 * fall), 3.0)
			prev = p
```

- [ ] **Step 7: 验证场景加载 + 全套测试**
创建 `/tmp/neon_check.gd`：
```gdscript
extends SceneTree
func _init():
	var ps = load("res://scenes/board.tscn")
	if ps == null: print("SCENE_LOAD_FAIL"); quit(); return
	var inst = ps.instantiate()
	print("BOARD_OK" if inst != null else "INSTANTIATE_FAIL")
	if inst != null: inst.free()
	quit()
```
Run: `/d/Program/Godot/godot --headless --path . -s /tmp/neon_check.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
Expected: `BOARD_OK`，无 Parse Error / SCRIPT ERROR。然后 `rm -f /tmp/neon_check.gd`。
再跑全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
Expected: All tests passed，总数 **220**（不变；board_view 无新单测）。

> 实机验收（用户人工）：撞钉时边框出现追逐光、连击越多越快越亮越烫，停手约 2 秒冷却回暗青常亮。

- [ ] **Step 8: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: heat-driven neon chase-light frame wired into board_view"
```

---

## 自检清单

- [ ] **Spec 覆盖**：WorldEnvironment 辉光(T2) ✓；hdr_2d(T2) ✓；heat_color 青→热粉不褪白(T1+测试) ✓；脉冲数/速度/亮度随热度(T1) ✓；热度时间衰减(T1 decay + T3 _process) ✓；PEG_HIT 充能(T3) ✓；边框折线+追逐光绘制(T3) ✓；HUD 注意(T2 threshold 1.0 + Backlog) ✓；纯函数全单测(T1/T2) ✓；对 sim 零侵入(全 view/渲染层) ✓
- [ ] **占位符扫描**：无 TBD/TODO；每个改代码步骤给出完整代码 ✓
- [ ] **类型/签名一致性**：
  - `NeonFrame.heat_color/pulse_count_for_heat/speed_for_heat/brightness_for_heat/decay_heat/point_at` 与常量 `IDLE/HOT/HEAT_PER_HIT` —— T1 定义、T1 测试、T3 调用一致 ✓
  - `NeonEnvironment.make_environment()` —— T2 定义、T2 测试、board_view 调用一致 ✓
  - preload 变量名：`NeonFrameScript`、`NeonEnvScript` 全程一致 ✓
  - heat 全程 `[0,1]`，PEG_HIT 用 `minf(... ,1.0)` 封顶 ✓
- [ ] **范围**：仅"霓虹边框+追逐光+辉光"；Backlog 项（主菜单辉光、钉/球调色、门缺口精修、HUD 隔离、热度联动其他元素、hit-stop 平滑版）不在本计划 ✓

---

## 备注

- 辉光是实机视觉，headless 测不了；T2/T3 的"实机验收"交用户。纯函数与 Environment 配置已单测。
- `point_at` 边框采样在 s 跨 0/1 接缝时由 `fposmod` 正确环绕。
- `_wall_heat` 仅 view 层状态，不入 `ScoreContext`、不持久化、不影响确定性回放——207 基线不受影响。
- 若实机 HUD 文字被 glow 糊：提 `glow_hdr_threshold` 或把 HUD 放独立 viewport（Backlog）。
