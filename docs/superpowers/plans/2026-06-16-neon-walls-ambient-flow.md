# 霓虹墙常驻流光 + 连击提速变色 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 内外双线 + 灯泡始终跑缓慢明暗行波 + 缓慢循环变色（不击中也动），同步；墙更宽(24)、灯更密(32)、对比更强；连击提速 + 加速变色 + 加宽色域 + 加亮 + 内外都叠热脉冲；绝对速度比现在略慢。

**Architecture:** NeonFrame 调慢 `speed_for_heat` 并加纯函数 `frame_hue`/`ambient_value`/`frame_color`（行波亮度 + 随时间循环的色相带）；board_view 加 `_neon_hue_phase`，把 `_draw_neon_frame` 改为"按弧长采样的行波双线 + 灯泡 + 内外热脉冲"，并退役 `bulb_color`。复用 `_wall_heat`/`_neon_phase`，零侵入 sim。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
- 基线：**254 测试全绿，37 脚本**。缩进 TAB。每任务只提交自己的文件。**不要 push**。**不要新建分支**（main）。
- `juice/neon_frame.gd`（NeonFrame）现有：consts `IDLE/HOT/HEAT_PER_HIT/DECAY_RATE/COOL_HUE(0.5)/COOL_SPREAD(0.1)/FULL_SPREAD(0.5)`；`heat_color`、`pulse_count_for_heat`、`speed_for_heat`（**现 `lerpf(0.15,0.8,…)`**）、`brightness_for_heat`、`decay_heat`、`point_at`、`hue_spread_for_heat`、`bulb_color(p,phase,heat)`。
- `tests/test_neon_frame.gd`：含 `test_speed_monotonic_and_range`（断言 0.15/0.8）、`test_hue_spread_curve`、以及 4 个 bulb_color 测试（`test_bulb_color_cool_band_when_idle`/`_widens_with_heat`/`_brightness_rises_and_hdr`/`_saturated`）。
- `view/board_view.gd`：consts `NEON_GAP 12 / BULB_SPACING 40 / BULB_RADIUS 2.5 / HALF_PULSE_LEN 0.04`；`_wall_heat`/`_neon_phase`；`_process` regardless-of-ball 段有
  ```gdscript
  		_wall_heat = NeonFrameScript.decay_heat(_wall_heat, delta)
  		_neon_phase = fmod(_neon_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat), 1.0)
  ```
  `_neon_perimeter()` / `_neon_inner_perimeter()`；`_draw_neon_frame()`（双线扁平 + 灯泡 `bulb_color` + 仅外线热脉冲）。

---

## 文件结构
**修改：** `juice/neon_frame.gd`、`tests/test_neon_frame.gd`、`view/board_view.gd`

---

## Task 1：NeonFrame 调速 + 行波/变色纯函数

**Files:** Modify `juice/neon_frame.gd`, `tests/test_neon_frame.gd`

- [ ] **Step 1: 改 `speed_for_heat` 的测试断言（红）** — 在 `tests/test_neon_frame.gd`，找到 `test_speed_monotonic_and_range`，把其中：
```gdscript
	assert_almost_eq(NeonFrameScript.speed_for_heat(0.0), 0.15, 1e-4, "平静流速 0.15")
	assert_almost_eq(NeonFrameScript.speed_for_heat(1.0), 0.8, 1e-4, "满热流速 0.8")
```
改为：
```gdscript
	assert_almost_eq(NeonFrameScript.speed_for_heat(0.0), 0.10, 1e-4, "平静流速 0.10")
	assert_almost_eq(NeonFrameScript.speed_for_heat(1.0), 0.60, 1e-4, "满热流速 0.60")
```

- [ ] **Step 2: 追加新函数的失败测试** 到 `tests/test_neon_frame.gd` 末尾（TAB 缩进）

```gdscript
func test_frame_hue_cool_band_idle() -> void:
	for p in [0.0, 0.25, 0.5, 0.75]:
		var h: float = NeonFrameScript.frame_hue(p, 0.0, 0.0, 0.0)
		assert_between(h, 0.39, 0.61, "平静窄冷带 @%.2f" % p)

func test_frame_hue_widens_with_heat() -> void:
	var h0: float = NeonFrameScript.frame_hue(0.0, 0.0, 0.0, 1.0)
	var h5: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.0, 1.0)
	assert_gt(absf(h0 - h5), 0.3, "满热跨多色相")

func test_frame_hue_cycles_with_hue_phase() -> void:
	var a: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.0, 0.0)
	var b: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.25, 0.0)
	assert_gt(absf(a - b), 0.2, "hue_phase 推进 → 色带中心移动（变色）")

func test_ambient_value_range_and_hdr() -> void:
	var seen_hi := 0.0
	for i in 40:
		var p := float(i) / 40.0
		var v0 := NeonFrameScript.ambient_value(p, 0.0, 0.0)
		assert_between(v0, 0.34, 1.51, "idle 值域 @%.2f" % p)
		seen_hi = maxf(seen_hi, NeonFrameScript.ambient_value(p, 0.0, 1.0))
	assert_gt(seen_hi, 1.0, "满热峰值 HDR >1")

func test_ambient_value_wave_moves() -> void:
	var a := NeonFrameScript.ambient_value(0.0, 0.0, 1.0)
	var b := NeonFrameScript.ambient_value(0.0, 0.25, 1.0)
	assert_gt(absf(a - b), 0.01, "波随相位移动")

func test_frame_color_saturated() -> void:
	assert_almost_eq(NeonFrameScript.frame_color(0.3, 0.1, 0.2, 0.5).s, 1.0, 1e-3, "饱和度 1")
```

- [ ] **Step 3: 运行确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_frame.gd -gexit`
（speed 两断言 + 6 个新测试失败；其余通过）

- [ ] **Step 4: 改 `speed_for_heat` + 加常量与函数** — 在 `juice/neon_frame.gd`：
(a) 找到：
```gdscript
static func speed_for_heat(heat: float) -> float:
	return lerpf(0.15, 0.8, clampf(heat, 0.0, 1.0))
```
改为：
```gdscript
static func speed_for_heat(heat: float) -> float:
	return lerpf(0.10, 0.60, clampf(heat, 0.0, 1.0))   # idle 慢 → 满热提速（比旧 0.15/0.8 略慢）
```
(b) 在 `hue_spread_for_heat` 函数之后加（TAB 缩进）：
```gdscript
const WAVE_COUNT := 5.0       # 行波波峰数（"多几处"）
const HUE_CYCLE := 0.5        # 变色相位相对流动的速率比（缓慢变色）

# 色相：以 hue_phase 缓慢循环的色带中心 + 位置展开（连击越热色带越宽）。
static func frame_hue(p: float, flow_phase: float, hue_phase: float, heat: float) -> float:
	var center := fposmod(COOL_HUE + hue_phase, 1.0)
	var local := fposmod(p + flow_phase, 1.0)
	var spread := hue_spread_for_heat(heat)
	return fposmod(center + (local - 0.5) * 2.0 * spread, 1.0)

# 明暗行波亮度：多波峰随 flow_phase 移动；波谷/波峰随热度变亮，峰值 >1 触发 bloom。
static func ambient_value(p: float, flow_phase: float, heat: float) -> float:
	var w := 0.5 + 0.5 * sin(TAU * (p * WAVE_COUNT - flow_phase))
	var h := clampf(heat, 0.0, 1.0)
	return lerpf(lerpf(0.35, 0.7, h), lerpf(1.5, 2.6, h), w)

# 线/灯泡共用：行波色（色相 + 行波亮度）。
static func frame_color(p: float, flow_phase: float, hue_phase: float, heat: float) -> Color:
	return Color.from_hsv(frame_hue(p, flow_phase, hue_phase, heat), 1.0, ambient_value(p, flow_phase, heat))
```
> 不动 `bulb_color`（Task 2 才退役），其 4 个测试本任务保持通过。

- [ ] **Step 5: 运行确认通过**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_frame.gd -gexit`
全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`（期望 **260**：254 + 6 新）

- [ ] **Step 6: 提交**

```bash
git -C D:/NeonPinball/game add juice/neon_frame.gd tests/test_neon_frame.gd
git -C D:/NeonPinball/game commit -m "feat: NeonFrame slower speed + frame_hue/ambient_value/frame_color (ambient flow + hue cycle)"
```

---

## Task 2：board_view 行波双线 + 内外脉冲 + 退役 bulb_color

**Files:** Modify `view/board_view.gd`, `juice/neon_frame.gd`, `tests/test_neon_frame.gd`

> board_view 无单测；靠场景加载检查 + 全套保持绿 + 实机确认。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 改常量** — `view/board_view.gd`，把：
```gdscript
const NEON_GAP := 12.0          # 内外线间距
const BULB_SPACING := 40.0      # 灯泡间距(px)
```
改为：
```gdscript
const NEON_GAP := 24.0          # 内外线间距
const BULB_SPACING := 32.0      # 灯泡间距(px)
```

- [ ] **Step 2: 加变色相位状态** — 找到 `var _neon_phase := 0.0`，在其后加：
```gdscript
var _neon_hue_phase := 0.0
```

- [ ] **Step 3: _process 推进变色相位** — 找到：
```gdscript
		_neon_phase = fmod(_neon_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat), 1.0)
```
在其后加：
```gdscript
		_neon_hue_phase = fmod(_neon_hue_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat) * NeonFrameScript.HUE_CYCLE, 1.0)
```

- [ ] **Step 4: 加两个绘制助手** — 在 `func _draw_neon_frame() -> void:` 定义**之前**插入：
```gdscript
# 沿一条闭合线按弧长采样上色（行波明暗 + 变色）。
func _draw_flow_line(line: PackedVector2Array, seg_count: int) -> void:
	var prev := NeonFrameScript.point_at(line, 0.0)
	for k in range(1, seg_count + 1):
		var pt := NeonFrameScript.point_at(line, float(k) / float(seg_count))
		var mid_s := (float(k) - 0.5) / float(seg_count)
		draw_line(prev, pt, NeonFrameScript.frame_color(mid_s, _neon_phase, _neon_hue_phase, _wall_heat), 2.5)
		prev = pt

# 在一条线上画一条热脉冲高光（中心 center，颜色 pcol）。
func _draw_pulse_on(line: PackedVector2Array, center: float, pcol: Color) -> void:
	var start_s := center - HALF_PULSE_LEN
	var prev := NeonFrameScript.point_at(line, fposmod(start_s, 1.0))
	for k in range(1, 7):
		var frac := float(k) / 6.0
		var pt := NeonFrameScript.point_at(line, fposmod(start_s + 2.0 * HALF_PULSE_LEN * frac, 1.0))
		var fall := 1.0 - absf(frac - 0.5) * 2.0
		draw_line(prev, pt, Color(pcol.r, pcol.g, pcol.b, 0.4 + 0.6 * fall), 3.0)
		prev = pt
```

- [ ] **Step 5: 改写 `_draw_neon_frame`** — 把整个 `_draw_neon_frame()` 函数体替换为：
```gdscript
# 中空双线（行波明暗+变色）+ 缝中灯泡环 + 内外热脉冲；全由 _wall_heat/_neon_phase/_neon_hue_phase 驱动。
func _draw_neon_frame() -> void:
	var poly := _neon_perimeter()
	var inner := _neon_inner_perimeter()
	var pn := poly.size()
	if pn < 2:
		return
	var total := 0.0
	for i in pn:
		total += poly[i].distance_to(poly[(i + 1) % pn])
	var seg_count := maxi(8, int(total / 10.0))
	# 内外双线：行波明暗 + 变色（同 s/相位 → 同步）
	_draw_flow_line(poly, seg_count)
	_draw_flow_line(inner, seg_count)
	# 缝中一圈小灯泡（奇偶错相，交替）
	var n_bulbs := maxi(1, int(total / BULB_SPACING))
	for i in n_bulbs:
		var bp := float(i) / float(n_bulbs)
		var bphase := _neon_phase if (i % 2 == 0) else _neon_phase + 0.5
		var mid := (NeonFrameScript.point_at(poly, bp) + NeonFrameScript.point_at(inner, bp)) * 0.5
		draw_circle(mid, BULB_RADIUS, NeonFrameScript.frame_color(bp, bphase, _neon_hue_phase, _wall_heat))
	# 热脉冲（连击叠加，内外两线同相位 → 同步）
	var n := NeonFrameScript.pulse_count_for_heat(_wall_heat)
	if n <= 0:
		return
	var bright := NeonFrameScript.brightness_for_heat(_wall_heat)
	var hc := NeonFrameScript.heat_color(_wall_heat)
	var pcol := Color(hc.r * bright, hc.g * bright, hc.b * bright)
	for i in n:
		var center := fmod(_neon_phase + float(i) / float(n), 1.0)
		_draw_pulse_on(poly, center, pcol)
		_draw_pulse_on(inner, center, pcol)
```

- [ ] **Step 6: 退役 `bulb_color`** — board_view 已不再调用它。
(a) `juice/neon_frame.gd`：删除整个 `bulb_color` 函数（连同其上方注释）。
(b) `tests/test_neon_frame.gd`：删除这 4 个测试函数：`test_bulb_color_cool_band_when_idle`、`test_bulb_color_widens_with_heat`、`test_bulb_color_brightness_rises_and_hdr`、`test_bulb_color_saturated`。
先确认无其他引用：`grep -rn "bulb_color" D:/NeonPinball/game --include=*.gd`（应只剩——删除后——0 处）。若 board_view 仍有 `bulb_color` 引用，说明 Step 5 没替换干净，回去修。

- [ ] **Step 7: 验证场景加载 + 全套**
创建 `/tmp/af.gd`（extends SceneTree；load+instantiate `res://scenes/board.tscn`；print BOARD_OK/FAIL；quit），运行：
`/d/Program/Godot/godot --headless --path . -s /tmp/af.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
期望 `BOARD_OK`，无 NEW Parse Error/SCRIPT ERROR。然后 `rm -f /tmp/af.gd`。
`grep -rn "bulb_color" D:/NeonPinball/game --include=*.gd` → 期望空（无残留引用）。
全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit` → All tests passed，总数 **256**（260 − 4 删除的 bulb_color 测试）。

> 实机验收（用户人工）：不击中也内外双线+灯泡缓慢跑明暗行波+缓慢变色、内外同步、对比明显；连击提速+加速变色+颜色变多+变亮+内外热脉冲。

- [ ] **Step 8: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd juice/neon_frame.gd tests/test_neon_frame.gd
git -C D:/NeonPinball/game commit -m "feat: ambient flow walls (sampled wave both lines + bulbs + dual pulses); retire bulb_color"
```

---

## 自检清单

- [ ] **Spec 覆盖**：墙宽 24/灯距 32(T2 Step1) ✓；常驻行波双线+灯泡(T2 _draw_flow_line + frame_color) ✓；缓慢变色 `_neon_hue_phase`(T1 frame_hue + T2 Step2/3) ✓；内外同步(同 s/相位 + 内外脉冲) ✓；连击提速(speed 0.10→0.60)+加速变色(hue_phase 按 speed 推进)+宽色域(hue_spread)+加亮(ambient peak)+热脉冲(T2) ✓；对比(ambient trough/peak) ✓；纯函数单测(T1) ✓；零侵入 sim ✓
- [ ] **占位符扫描**：每步完整代码与确切命令 ✓
- [ ] **类型/签名一致性**：
  - `frame_hue(p,flow_phase,hue_phase,heat)` / `ambient_value(p,flow_phase,heat)` / `frame_color(p,flow_phase,hue_phase,heat)` —— T1 定义、T1 测试、T2 调用一致 ✓
  - `speed_for_heat` 调值，测试断言同步改(T1 Step1/4) ✓
  - `_draw_flow_line(line, seg_count)` / `_draw_pulse_on(line, center, pcol)` 定义(T2 Step4)、调用(T2 Step5)一致 ✓
  - `_neon_hue_phase` 声明(T2 Step2)、推进(Step3)、使用(Step5 via frame_color)一致 ✓
  - bulb_color 删除后无残留引用(T2 Step6 grep) ✓
  - 函数内无同名 `var` 冲突：脉冲绘制移入 `_draw_pulse_on`，`_draw_neon_frame` 内只 `bp`/`center` ✓
- [ ] **范围**：仅墙流光升级；墙重影/灯泡命中炸亮/漏斗角补偿 留 Backlog ✓

---

## 备注
- T1 保留 `bulb_color`（+其测试）→ 每个中间状态都干净（board 可加载、全绿）；T2 切到 `frame_color` 后再退役它。
- 线按 ~10px 采样（外线 ~316 段 ×2 + 内线）→ draw_line 数增多但 2D 可接受；若卡顿把 `int(total/10.0)` 的 10 调大。
- `_neon_hue_phase` 按 `speed_for_heat·HUE_CYCLE` 推进 → 连击变色更快；idle 持续慢变色。
- `ambient_value` 峰值 idle 1.5 / 满热 2.6（>1 bloom），波谷 0.35→0.7：对比明显且随热度整体变亮。
- 数值（GAP/间距/速度/对比/波峰/采样密度/HUE_CYCLE）首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
