# 中空霓虹墙 + 灯泡 + 连击彩虹铺开 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把霓虹边框升级为中空双线光管 + 缝中一圈小灯泡（缓慢交替流动），平静时几种冷色、连击越高色域越宽（青→满彩虹流光），高连击叠加现有热脉冲。

**Architecture:** 扩 `juice/neon_frame.gd` 加纯函数 `hue_spread_for_heat`/`bulb_color`（可测）；改写 board_view 的 `_draw_neon_frame`（内+外双线 + 灯泡环 + 现有脉冲），加 `_neon_inner_perimeter`。复用 `_wall_heat`/`_neon_phase`，不新增状态，对 sim/确定性零侵入。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  /d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit
  ```
- 基线：**249 测试全绿，37 脚本**。缩进 TAB。每任务只提交自己的文件。**不要 push**。**不要新建分支**（main）。
- `juice/neon_frame.gd`（NeonFrame）已有：`IDLE/HOT/HEAT_PER_HIT/DECAY_RATE` 常量；`heat_color/pulse_count_for_heat/speed_for_heat/brightness_for_heat/decay_heat/point_at`。本任务**追加** `COOL_HUE/COOL_SPREAD/FULL_SPREAD` 常量 + `hue_spread_for_heat`/`bulb_color`，不动现有函数。
- `view/board_view.gd` 现有（约 761–800 行）：
  ```gdscript
  func _neon_perimeter() -> PackedVector2Array:
  	var o := _rect.position
  	return PackedVector2Array([
  		o + Vector2(0, 0), o + Vector2(540, 0), o + Vector2(540, 780),
  		o + Vector2(300, 900), o + Vector2(240, 900), o + Vector2(0, 780),
  	])

  func _draw_neon_frame() -> void:
  	var poly := _neon_perimeter()
  	var pn := poly.size()
  	if pn < 2:
  		return
  	var col := NeonFrameScript.heat_color(_wall_heat)
  	var base := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9)
  	for i in pn:
  		draw_line(poly[i], poly[(i + 1) % pn], base, 2.5)
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
  			var fall := 1.0 - absf(frac - 0.5) * 2.0
  			draw_line(prev, p, Color(pcol.r, pcol.g, pcol.b, 0.4 + 0.6 * fall), 3.0)
  			prev = p
  ```
  顶部 const 区已有 `const NeonFrameScript := preload("res://juice/neon_frame.gd")` 与 `const HALF_PULSE_LEN := 0.04`。`_rect = Rect2(135,225,540,900)`。`_wall_heat`/`_neon_phase` 已有。
- **GDScript 注意**：`var` 在函数内是函数级作用域，同名 `var` 在同一函数里声明两次会报"already declared"。改写后的 `_draw_neon_frame` 里灯泡循环用 `bp`，脉冲循环保留 `p`（两者不可同名）。for 循环计数器 `i` 可跨多个 for 复用（非显式 var），无碍。

---

## 文件结构

**修改：** `juice/neon_frame.gd`（+2 纯函数 +3 常量）、`tests/test_neon_frame.gd`（+5 测试）、`view/board_view.gd`（改写 `_draw_neon_frame` + 加 `_neon_inner_perimeter` + 3 常量）

---

## Task 1：NeonFrame 加色带/灯泡色纯函数

**Files:** Modify `juice/neon_frame.gd`, `tests/test_neon_frame.gd`

- [ ] **Step 1: 追加失败测试** 到 `tests/test_neon_frame.gd` 末尾（TAB 缩进；文件已有 `const NeonFrameScript := preload(...)`）

```gdscript
func test_hue_spread_curve() -> void:
	assert_almost_eq(NeonFrameScript.hue_spread_for_heat(0.0), 0.1, 1e-4, "平静色带 0.1")
	assert_almost_eq(NeonFrameScript.hue_spread_for_heat(1.0), 0.5, 1e-4, "满热色带 0.5")
	assert_gt(NeonFrameScript.hue_spread_for_heat(1.0), NeonFrameScript.hue_spread_for_heat(0.0), "色带随热度变宽")

func test_bulb_color_cool_band_when_idle() -> void:
	for p in [0.0, 0.25, 0.5, 0.75]:
		var h: float = NeonFrameScript.bulb_color(p, 0.0, 0.0).h
		assert_between(h, 0.39, 0.61, "平静色相落冷带 @%.2f" % p)

func test_bulb_color_widens_with_heat() -> void:
	# 满热时不同位置色相差很大（颜色变多）
	var h0: float = NeonFrameScript.bulb_color(0.0, 0.0, 1.0).h
	var h5: float = NeonFrameScript.bulb_color(0.5, 0.0, 1.0).h
	assert_gt(absf(h0 - h5), 0.3, "满热跨多色相")

func test_bulb_color_brightness_rises_and_hdr() -> void:
	var lo := NeonFrameScript.bulb_color(0.0, 0.0, 0.0)
	var hi := NeonFrameScript.bulb_color(0.0, 0.0, 1.0)
	var lo_max := maxf(maxf(lo.r, lo.g), lo.b)
	var hi_max := maxf(maxf(hi.r, hi.g), hi.b)
	assert_gt(hi_max, lo_max, "亮度随热度升")
	assert_gt(hi_max, 1.0, "满热 HDR (>1 触发 bloom)")

func test_bulb_color_saturated() -> void:
	assert_almost_eq(NeonFrameScript.bulb_color(0.3, 0.2, 0.5).s, 1.0, 1e-3, "饱和度 1")
```

- [ ] **Step 2: 运行确认失败**

`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_neon_frame.gd -gexit`

- [ ] **Step 3: 实现** — 在 `juice/neon_frame.gd` 现有 `decay_heat` 之后（`point_at` 之前或之后均可，放 `point_at` 前）追加（TAB 缩进）：

```gdscript
# 灯泡色相 = 以青为中心的一段色带。色带宽度随热度从冷窄带铺到全频谱。
const COOL_HUE := 0.5          # 青（HSV 色相）
const COOL_SPREAD := 0.1       # 平静色带半宽（青附近几种冷色）
const FULL_SPREAD := 0.5       # 满热色带半宽（±0.5 = 整圈彩虹）

# 色带半宽：热度越高色域越宽（冷色窄带 → 全频谱）
static func hue_spread_for_heat(heat: float) -> float:
	return lerpf(COOL_SPREAD, FULL_SPREAD, clampf(heat, 0.0, 1.0))

# 环位置 p∈[0,1) + 流动相位 + 热度 → 灯泡颜色。
# 色相 = 青 ± 色带，沿环铺开；平静窄冷带、满热全彩虹。亮度随热度（>1 触发 bloom）。
static func bulb_color(p: float, phase: float, heat: float) -> Color:
	var local := fposmod(p + phase, 1.0)
	var spread := hue_spread_for_heat(heat)
	var hue := fposmod(COOL_HUE + (local - 0.5) * 2.0 * spread, 1.0)
	var val := lerpf(0.9, 2.4, clampf(heat, 0.0, 1.0))
	return Color.from_hsv(hue, 1.0, val)
```

> 实现后确认 `Color.from_hsv(h, 1.0, 2.4)` 产出的通道 >1（Godot 4 不 clamp value）——`test_bulb_color_brightness_rises_and_hdr` 的 `hi_max > 1.0` 即在校验这点。若该断言失败（说明此版本 from_hsv 截断到 1），改为 `var c := Color.from_hsv(hue, 1.0, 1.0); return Color(c.r*val, c.g*val, c.b*val)` 并重跑。

- [ ] **Step 4: 运行确认通过**（test_neon_frame 全过：原 12 + 新 5 = 17）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/neon_frame.gd tests/test_neon_frame.gd
git -C D:/NeonPinball/game commit -m "feat: NeonFrame hue_spread_for_heat + bulb_color (cool band -> rainbow)"
```

---

## Task 2：board_view 中空双线 + 灯泡环

**Files:** Modify `view/board_view.gd`

> board_view 无单测；靠场景加载检查 + 全套保持绿 + 实机确认。按内容匹配锚点；找不到就停下报告。

- [ ] **Step 1: 加常量** — 顶部 const 区，找到：
`const HALF_PULSE_LEN := 0.04   # 脉冲沿边框的归一化半宽`
在其后加：
```gdscript
const NEON_GAP := 12.0          # 内外线间距
const BULB_SPACING := 40.0      # 灯泡间距(px)
const BULB_RADIUS := 2.5        # 灯泡半径
```

- [ ] **Step 2: 加内线折线助手** — 在 `func _neon_perimeter() -> PackedVector2Array:` 函数定义**之后**插入：
```gdscript
# 内线：外线各点朝板心偏移 NEON_GAP，与外线构成中空缝。
func _neon_inner_perimeter() -> PackedVector2Array:
	var center := _rect.get_center()
	var inner := PackedVector2Array()
	for pt in _neon_perimeter():
		inner.append(pt + (center - pt).normalized() * NEON_GAP)
	return inner
```

- [ ] **Step 3: 改写 `_draw_neon_frame`** — 把现有整个 `_draw_neon_frame()` 函数体替换为：
```gdscript
# 中空双线 + 缝中灯泡环 + 热追逐光脉冲；色/数/速/亮由 _wall_heat 驱动。
func _draw_neon_frame() -> void:
	var poly := _neon_perimeter()
	var inner := _neon_inner_perimeter()
	var pn := poly.size()
	if pn < 2:
		return
	var col := NeonFrameScript.heat_color(_wall_heat)
	# 内外双线（暗光成光管，靠 bloom 发光）
	var base := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.9)
	for i in pn:
		draw_line(poly[i], poly[(i + 1) % pn], base, 2.5)
		draw_line(inner[i], inner[(i + 1) % pn], base, 2.5)
	# 缝中一圈小灯泡（奇偶错相，交替缓慢流动）
	var total := 0.0
	for i in pn:
		total += poly[i].distance_to(poly[(i + 1) % pn])
	var n_bulbs := maxi(1, int(total / BULB_SPACING))
	for i in n_bulbs:
		var bp := float(i) / float(n_bulbs)
		var bphase := _neon_phase if (i % 2 == 0) else _neon_phase + 0.5
		var mid := (NeonFrameScript.point_at(poly, bp) + NeonFrameScript.point_at(inner, bp)) * 0.5
		draw_circle(mid, BULB_RADIUS, NeonFrameScript.bulb_color(bp, bphase, _wall_heat))
	# 热追逐光脉冲（高连击亮色高光，叠在最上）
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
			var fall := 1.0 - absf(frac - 0.5) * 2.0
			draw_line(prev, p, Color(pcol.r, pcol.g, pcol.b, 0.4 + 0.6 * fall), 3.0)
			prev = p
```
（关键：灯泡循环用 `bp`，脉冲循环保留 `p`，避免同名 `var` 冲突。）

- [ ] **Step 4: 验证场景加载 + 全套**
创建 `/tmp/hb.gd`（extends SceneTree；load+instantiate `res://scenes/board.tscn`；print BOARD_OK/FAIL；quit），运行：
`/d/Program/Godot/godot --headless --path . -s /tmp/hb.gd 2>&1 | grep -iE "BOARD_OK|FAIL|Parse Error|SCRIPT ERROR"`
期望 `BOARD_OK`，无 NEW Parse Error/SCRIPT ERROR（预存 GameDB/RunMan/SceneMan autoload-absent 报错无关）。然后 `rm -f /tmp/hb.gd`。
全套：`/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`，期望 All tests passed，总数 **254**（249 + 5；board_view 无新单测）。

> 实机验收（用户人工）：中空双线 + 缝中灯泡交替流动；平静几种冷色；连击越高颜色越多铺成流动彩虹 + 提速变亮；满热叠加热脉冲沸腾。

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: hollow double-line neon wall + alternating bulb ring"
```

---

## 自检清单

- [ ] **Spec 覆盖**：中空双线(T2 内/外 draw_line) ✓；缝中灯泡环 + 奇偶交替(T2 bulb loop) ✓；平静几种冷色 / 连击颜色变多(T1 bulb_color + hue_spread) ✓；流速/亮度随热度(复用 speed/bright + bulb val) ✓；热脉冲叠加(T2 保留脉冲层) ✓；纯函数单测(T1) ✓；零侵入 sim ✓
- [ ] **占位符扫描**：每步完整代码与确切命令 ✓
- [ ] **类型/签名一致性**：
  - `NeonFrame.hue_spread_for_heat(heat)` / `bulb_color(p, phase, heat)` —— T1 定义、T1 测试、T2 调用一致 ✓
  - `_neon_inner_perimeter()` 定义(T2 Step2)、调用(T2 Step3) 一致 ✓
  - 常量 `NEON_GAP/BULB_SPACING/BULB_RADIUS`、`COOL_HUE/COOL_SPREAD/FULL_SPREAD` 一致 ✓
  - `_draw_neon_frame` 内 `bp`(灯泡) vs `p`(脉冲) 不同名，避免 GDScript 函数级 var 冲突 ✓
- [ ] **范围**：仅中空墙+灯泡+彩虹铺开；灯泡命中炸亮/内外线反向流动/灯泡密度随热 留 Backlog ✓

---

## 备注

- `Color.from_hsv` value>1 的 HDR 行为由 T1 的 `hi_max > 1.0` 断言强制校验；若该版本截断则按 Step3 备注改乘法版。
- 内线用"朝板心偏移"近似，桶形非凸处 ~12px 视觉可接受；实机调 `NEON_GAP`。
- 灯泡每帧重算位置（n≤~70 个 `draw_circle`），开销可忽略。
- 数值（GAP/间距/半径/色带/亮度）首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
- 平静色带中心固定青（COOL_HUE 0.5），热度只展宽不平移——保证"从冷色铺开"。
