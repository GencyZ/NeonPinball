# 局内击中反馈爽感（Hit-Feedback Juice）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给局内撞钉加上 Peggle 式音高爬升音效、逐击微顿帧、连击 escalation（震/光/音/顿帧 + 屏上数字），让"每一下都脆、一长串越撞越上头"。

**Architecture:** 爽感全部活在 view 层，对确定性物理 sim 零侵入。新增两个 juice 模块（程序化合成音 `sfx_synth.gd` + 播放节点 `sfx_controller.gd`），扩展 `juice_controller.gd` / `slow_mo.gd` 的连击曲线与逐击顿帧，最后在 `board_view.gd` 的 PEG_HIT 处接线。combo 仅驱动表现，**不进计分管线**。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x 测试，程序化音频（`AudioStreamWAV` + `pitch_scale`，零素材）。

---

## Background（代码库上下文）

- 项目根 `D:/NeonPinball/game/`。测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gsuffix=.gd -gexit
  ```
  （`godot` 不在 PATH。Git Bash 下可用 `/d/Program/Godot/godot`。）
- 当前基线：**188 个测试全部通过，30 个脚本**。
- **缩进用 TAB**（`juice/`、`view/`、`tests/` 全是 TAB；唯独 `data/game_database.gd` 用空格，本计划不涉及它）。
- 每个任务只提交它自己改动的文件。**不要 push**（用户会在计划完成后单独确认 push）。

### 现有 juice 结构

- `juice/screen_shake.gd`：`var trauma`；`add(amount)` 累加并 clamp 到 [0,1]；`update(delta) -> Vector2`。
- `juice/slow_mo.gd`：`request(scale, duration)`（当前直接覆盖）；`update(delta) -> float`；`is_active()`。
- `juice/juice_controller.gd`（`class_name JuiceController extends RefCounted`）：聚合 shake/particles/floaters/slowmo。
  - `on_peg_hit(pos, color, big)` → `shake.add(0.3 if big else 0.12)`，`particles.emit(pos, color, 14 if big else 6)`
  - `on_settle(pos, score, is_final_launch)`、`update(delta)`、`camera_offset()`、`time_scale()`
- `juice/particle_burst.gd`：`emit(pos, color, count)`，成员 `particles: Array`。

### 现有击中接线点 `view/board_view.gd`

- 第 67 行 `_ready()`：`_juice = JuiceControllerScript.new()`
- 第 322 行 `launch(ball)`：第 334 行 `_score_ctx.clear_for_launch()`
- 第 381–450 行：事件循环；`if e[&"type"] == SimEvent.PEG_HIT:` 在 383 行
  - 第 435–437 行：生成彩虹光环（`r1 = radius + HALO_EXPAND`）
  - 第 438、442 行：两处 `_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)`
- 第 481–483 行：`_juice.update(delta)`；`$Camera2D.offset = _juice.camera_offset()`；`Engine.time_scale = _juice.time_scale()`
- 第 486 行 `_on_all_settled()`：第 489 行 `_juice.on_settle(...)`
- 第 620 行附近 `_draw()`：已有光环/闪光绘制，末尾 `_draw_walls()`

### 枚举/常量（已存在，供参考）

- `SimEvent.PEG_HIT`、`SimEvent.SETTLED`、`SimEvent.BOUNCE`
- board_view 顶部 const：`HALO_EXPAND := 38.0`、`HALO_DUR := 0.45`

---

## 文件结构

**新建：**
- `juice/sfx_synth.gd` — 纯逻辑：连击→音高映射 + 程序化"叮"波形生成
- `juice/sfx_controller.gd`（`extends Node`）— `AudioStreamPlayer` 池，按档位播音
- `tests/test_sfx_synth.gd` — 音高映射 + 波形测试
- `tests/test_slow_mo.gd` — slow_mo 的"更强者胜/延长"语义测试
- `tests/test_sfx_controller.gd` — 池创建 + play_hit 设音高

**修改：**
- `juice/slow_mo.gd` — `request()` 改为"更强(更慢)/更长者胜"，逐击顿帧与最后一球慢动作不打架
- `juice/juice_controller.gd` — 新增静态连击曲线 + `on_peg_hit_combo()`
- `tests/test_juice_controller.gd` — 补连击曲线 + `on_peg_hit_combo` 测试
- `view/board_view.gd` — 接线：combo 计数、播音、连击放大、屏上数字

---

## Task 1：SfxSynth — 音高映射 + 程序化波形

**Files:**
- Create: `juice/sfx_synth.gd`
- Test: `tests/test_sfx_synth.gd`

- [ ] **Step 1: 写失败测试** `tests/test_sfx_synth.gd`（TAB 缩进）

```gdscript
extends GutTest

const SfxSynthScript := preload("res://juice/sfx_synth.gd")

func test_first_hit_is_base_pitch() -> void:
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(1), 1.0, 1e-5,
		"第一击为基准音 pitch_scale=1.0")

func test_pitch_monotonic_non_decreasing() -> void:
	for n in range(1, 16):
		assert_true(SfxSynthScript.pitch_scale_for_combo(n + 1)
			>= SfxSynthScript.pitch_scale_for_combo(n),
			"音高随连击单调不降 @%d" % n)

func test_pitch_within_range() -> void:
	for n in range(1, 60):
		var p := SfxSynthScript.pitch_scale_for_combo(n)
		assert_between(p, 1.0, 4.0, "音高落在 [1.0,4.0] @%d" % n)

func test_pitch_second_step_is_pentatonic() -> void:
	# 第二档 = 大调五声第二音 = 2 个半音 = 2^(2/12)
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(2),
		pow(2.0, 2.0 / 12.0), 1e-5, "第二档为五声第二音")

func test_pitch_caps_at_top() -> void:
	# 表长 11，封顶在最高档 24 半音 = 2^(24/12) = 4.0
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(50),
		SfxSynthScript.pitch_scale_for_combo(11), 1e-5, "超表长封顶")
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(50), 4.0, 1e-5,
		"封顶值为 4.0（两个八度）")

func test_make_ping_returns_nonempty_wav() -> void:
	var s := SfxSynthScript.make_ping()
	assert_true(s is AudioStreamWAV, "返回 AudioStreamWAV")
	assert_gt(s.data.size(), 0, "波形数据非空")
	assert_eq(s.mix_rate, 22050, "默认采样率 22050")
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_sfx_synth.gd -gexit`
Expected: FAIL（`Could not preload` 或类不存在）

- [ ] **Step 3: 实现** `juice/sfx_synth.gd`（TAB 缩进）

```gdscript
class_name SfxSynth extends RefCounted

# 大调五声音阶（跨两个八度），单位：半音。任意长度的连击序列都不会刺耳。
const PENTATONIC := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]

# 连击序号 n（从 1 起）→ pitch_scale。第 1 击 = 基准音 1.0；超表长封顶。
static func pitch_scale_for_combo(n: int) -> float:
	var idx := clampi(n - 1, 0, PENTATONIC.size() - 1)
	return pow(2.0, float(PENTATONIC[idx]) / 12.0)

# 程序化生成一个短促"叮"：正弦载波 + 快速指数衰减包络（霓虹合成器味）。
static func make_ping(sample_rate := 22050) -> AudioStreamWAV:
	var dur := 0.14
	var count := int(sample_rate * dur)
	var data := PackedByteArray()
	data.resize(count * 2)   # 16-bit = 2 bytes/sample
	var base_freq := 660.0
	for i in count:
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 22.0)
		var sample := sin(TAU * base_freq * t) * env
		var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_sfx_synth.gd -gexit`
Expected: PASS（6/6）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/sfx_synth.gd tests/test_sfx_synth.gd
git -C D:/NeonPinball/game commit -m "feat: SfxSynth — pentatonic pitch mapping + procedural ping waveform"
```

---

## Task 2：连击曲线 + 逐击顿帧

**Files:**
- Modify: `juice/slow_mo.gd`
- Modify: `juice/juice_controller.gd`
- Test: `tests/test_slow_mo.gd`（新建）、`tests/test_juice_controller.gd`（追加）

### 2a：slow_mo "更强者胜/更长者延长"

- [ ] **Step 1: 写失败测试** `tests/test_slow_mo.gd`（TAB 缩进）

```gdscript
extends GutTest

const SlowMoScript := preload("res://juice/slow_mo.gd")

func test_inactive_returns_one() -> void:
	var s := SlowMoScript.new()
	assert_almost_eq(s.update(0.016), 1.0, 1e-4, "空闲时 time_scale=1.0")

func test_stronger_wins_over_weaker() -> void:
	var s := SlowMoScript.new()
	s.request(0.05, 0.04)   # 强（更慢）
	s.request(0.5, 0.04)    # 弱
	assert_almost_eq(s.update(0.0), 0.05, 1e-4, "更强(更低)的目标胜出")

func test_longer_duration_extends() -> void:
	var s := SlowMoScript.new()
	s.request(0.2, 0.1)
	s.request(0.2, 0.3)     # 更长
	s.update(0.15)
	assert_true(s.is_active(), "计时被延长到更长那个")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_slow_mo.gd -gexit`
Expected: FAIL（`test_stronger_wins_over_weaker` — 当前 `request` 直接覆盖，返回 0.5）

- [ ] **Step 3: 修改** `juice/slow_mo.gd` 的 `request()`

把：
```gdscript
func request(scale: float, duration: float) -> void:
	_target = scale
	_timer = duration
```
改为：
```gdscript
func request(scale: float, duration: float) -> void:
	# 更强(更慢=更低 scale)者胜；计时取更长者，逐击顿帧与最后一球慢动作不打架。
	if _timer <= 0.0 or scale < _target:
		_target = scale
	_timer = maxf(_timer, duration)
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_slow_mo.gd -gexit`
Expected: PASS（3/3）

### 2b：JuiceController 连击曲线 + on_peg_hit_combo

- [ ] **Step 5: 追加失败测试到** `tests/test_juice_controller.gd`（文件末尾，TAB 缩进）

```gdscript
func test_shake_mag_monotonic_and_capped() -> void:
	assert_almost_eq(JuiceControllerScript.shake_mag_for_combo(1), 0.12, 1e-4,
		"combo 1 屏震=0.12（与原小击一致）")
	for n in range(1, 30):
		assert_true(JuiceControllerScript.shake_mag_for_combo(n + 1)
			>= JuiceControllerScript.shake_mag_for_combo(n), "屏震单调不降 @%d" % n)
	assert_almost_eq(JuiceControllerScript.shake_mag_for_combo(99), 0.4, 1e-4,
		"屏震封顶 0.4")

func test_hitstop_monotonic_and_within_range() -> void:
	for n in range(1, 30):
		var d := JuiceControllerScript.hitstop_duration_for_combo(n)
		assert_between(d, 0.025, 0.090, "顿帧时长落在 [0.025,0.090] @%d" % n)
		assert_true(JuiceControllerScript.hitstop_duration_for_combo(n + 1)
			>= JuiceControllerScript.hitstop_duration_for_combo(n), "顿帧单调不降 @%d" % n)

func test_combo_hit_higher_combo_more_trauma() -> void:
	var a := JuiceControllerScript.new()
	var b := JuiceControllerScript.new()
	a.on_peg_hit_combo(Vector2.ZERO, Color.RED, 1)
	b.on_peg_hit_combo(Vector2.ZERO, Color.RED, 8)
	assert_gt(b.shake.trauma, a.shake.trauma, "连击越高屏震越强")

func test_combo_hit_requests_hitstop() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_peg_hit_combo(Vector2.ZERO, Color.RED, 3)
	jc.update(0.016)
	assert_lt(jc.time_scale(), 1.0, "逐击产生顿帧（time_scale<1）")

func test_combo_hit_emits_particles() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_peg_hit_combo(Vector2.ZERO, Color.RED, 5)
	assert_gt(jc.particles.particles.size(), 0, "逐击迸射粒子")
```

- [ ] **Step 6: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_juice_controller.gd -gexit`
Expected: FAIL（`shake_mag_for_combo` / `on_peg_hit_combo` 不存在）

- [ ] **Step 7: 修改** `juice/juice_controller.gd`，在 `on_peg_hit(...)` 之后加入

```gdscript
# 连击 → 屏震幅度（combo 1 与原小击 0.12 一致，封顶 0.4）
static func shake_mag_for_combo(n: int) -> float:
	return minf(0.12 + 0.02 * float(n - 1), 0.4)

# 连击 → 逐击顿帧时长（秒，封顶 0.090）
static func hitstop_duration_for_combo(n: int) -> float:
	return minf(0.025 + 0.006 * float(n - 1), 0.090)

# 连击感知的击中反馈：屏震/顿帧/粒子随 combo 放大。
func on_peg_hit_combo(pos: Vector2, color: Color, combo: int) -> void:
	shake.add(shake_mag_for_combo(combo))
	particles.emit(pos, color, 6 + mini(combo, 12))
	slowmo.request(0.05, hitstop_duration_for_combo(combo))
```

- [ ] **Step 8: 运行全部 juice 测试，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_juice_controller.gd -gexit`
Expected: PASS（原 9 个 + 新 5 个 = 14/14）

- [ ] **Step 9: 提交**

```bash
git -C D:/NeonPinball/game add juice/slow_mo.gd juice/juice_controller.gd tests/test_slow_mo.gd tests/test_juice_controller.gd
git -C D:/NeonPinball/game commit -m "feat: combo escalation curves + per-hit hit-stop (slow_mo stronger-wins)"
```

---

## Task 3：SfxController — AudioStreamPlayer 池

**Files:**
- Create: `juice/sfx_controller.gd`
- Test: `tests/test_sfx_controller.gd`

- [ ] **Step 1: 写失败测试** `tests/test_sfx_controller.gd`（TAB 缩进）

```gdscript
extends GutTest

const SfxControllerScript := preload("res://juice/sfx_controller.gd")
const SfxSynthScript := preload("res://juice/sfx_synth.gd")

func test_pool_created_on_ready() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)   # 触发 _ready
	assert_eq(sfx._players.size(), SfxControllerScript.POOL_SIZE, "池按 POOL_SIZE 创建")

func test_play_hit_sets_pitch_from_combo() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_hit(1)   # 用掉 index 0
	assert_almost_eq(sfx._players[0].pitch_scale,
		SfxSynthScript.pitch_scale_for_combo(1), 1e-4, "play_hit 设置正确音高")

func test_play_hit_higher_combo_higher_pitch() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_hit(1)   # index 0
	sfx.play_hit(6)   # index 1
	assert_gt(sfx._players[1].pitch_scale, sfx._players[0].pitch_scale,
		"连击越高音高越高")

func test_play_settle_low_pitch() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_settle()
	assert_lt(sfx._players[0].pitch_scale, 1.0, "落定为低音")
```

- [ ] **Step 2: 运行，确认失败**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_sfx_controller.gd -gexit`
Expected: FAIL（类不存在）

- [ ] **Step 3: 实现** `juice/sfx_controller.gd`（TAB 缩进）

```gdscript
extends Node

const SfxSynthScript := preload("res://juice/sfx_synth.gd")
const POOL_SIZE := 8

var _players: Array = []
var _next := 0
var _ping: AudioStreamWAV

func _ready() -> void:
	_ping = SfxSynthScript.make_ping()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = _ping
		add_child(p)
		_players.append(p)

func _take() -> AudioStreamPlayer:
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	return p

func play_hit(combo: int) -> void:
	var p := _take()
	p.pitch_scale = SfxSynthScript.pitch_scale_for_combo(combo)
	p.play()

func play_settle() -> void:
	var p := _take()
	p.pitch_scale = 0.5
	p.play()
```

- [ ] **Step 4: 运行，确认通过**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_sfx_controller.gd -gexit`
Expected: PASS（4/4）

- [ ] **Step 5: 提交**

```bash
git -C D:/NeonPinball/game add juice/sfx_controller.gd tests/test_sfx_controller.gd
git -C D:/NeonPinball/game commit -m "feat: SfxController — pooled AudioStreamPlayer hit/settle playback"
```

---

## Task 4：接线进 board_view

**Files:**
- Modify: `view/board_view.gd`

> board_view 是场景节点，现有代码库无对其的单测；本任务靠"全套测试保持绿 + 实机跑一局"验证。

- [ ] **Step 1: 加常量与预载**

在 `view/board_view.gd` 第 13 行 `const JuiceControllerScript := preload("res://juice/juice_controller.gd")` 之后加：
```gdscript
const SfxControllerScript := preload("res://juice/sfx_controller.gd")
const COMBO_DISPLAY_DUR := 0.6
```

- [ ] **Step 2: 加状态变量**

在第 44 行 `var _last_settle_pos := Vector2.ZERO` 之后加：
```gdscript
var _combo: int = 0
var _last_hit_pos := Vector2.ZERO
var _combo_display_ttl := 0.0
var _sfx
```

- [ ] **Step 3: `_ready()` 创建 SfxController**

在第 67 行 `_juice = JuiceControllerScript.new()` 之后加：
```gdscript
	_sfx = SfxControllerScript.new()
	add_child(_sfx)
```

- [ ] **Step 4: `launch()` 重置 combo**

在第 334 行 `_score_ctx.clear_for_launch()` 之后加：
```gdscript
	_combo = 0
```

- [ ] **Step 5: PEG_HIT 处计数 + 播音**

把第 383 行：
```gdscript
				if e[&"type"] == SimEvent.PEG_HIT:
```
改为（紧随其后插入三行）：
```gdscript
				if e[&"type"] == SimEvent.PEG_HIT:
					_combo += 1
					_last_hit_pos = e[&"pos"]
					_sfx.play_hit(_combo)
					_combo_display_ttl = COMBO_DISPLAY_DUR
```

- [ ] **Step 6: 光环按 combo 放大**

把第 436 行：
```gdscript
							&"r1": hit_peg[&"radius"] + HALO_EXPAND,
```
改为：
```gdscript
							&"r1": hit_peg[&"radius"] + HALO_EXPAND * (1.0 + minf(float(_combo) * 0.1, 1.0)),
```

- [ ] **Step 7: 两处 on_peg_hit → on_peg_hit_combo**

把第 438 行：
```gdscript
						_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)
```
改为：
```gdscript
						_juice.on_peg_hit_combo(e[&"pos"], flash_color, _combo)
```
把第 442 行（无效 peg_id 分支）：
```gdscript
						_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)
```
改为：
```gdscript
						_juice.on_peg_hit_combo(e[&"pos"], flash_color, _combo)
```

- [ ] **Step 8: combo 数字计时（regardless-of-ball 段）**

在第 480 行 `_peg_halos.remove_at(i)` 所在循环之后、第 481 行 `_juice.update(delta)` 之前加：
```gdscript
	if _combo_display_ttl > 0.0:
		_combo_display_ttl -= delta
```

- [ ] **Step 9: `_on_all_settled()` 播落定音 + 归零**

在第 489 行 `_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())` 之后加：
```gdscript
	_sfx.play_settle()
	_combo = 0
```

- [ ] **Step 10: `_draw()` 画屏上 combo 数字**

在 `_draw()` 函数里、`_draw_walls()` 调用**之前**加（紧跟现有光环绘制循环之后）：
```gdscript
	if _combo >= 2 and _combo_display_ttl > 0.0:
		var f := ThemeDB.fallback_font
		var frac := _combo_display_ttl / COMBO_DISPLAY_DUR
		var fsize := 28 + mini(_combo, 20) * 2
		var col := Color(1.0, 1.0, 1.0, frac)
		draw_string(f, _last_hit_pos + Vector2(-14, -22), "x%d" % _combo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
```

- [ ] **Step 11: 跑全套测试，确认无回归**

Run: `/d/Program/Godot/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -gexit`
Expected: `All tests passed!`，总数约 188 + 18 = **206**，0 失败，0 资源/脚本错误。

- [ ] **Step 12: 实机跑一局确认手感**

Run: `/d/Program/Godot/godot --path .`（非 headless）
确认：撞钉有声且音高随连击上行；密集撞击有微顿帧不卡死；连击时屏震/光环/屏上数字一起放大；落定有低音"咚"且 combo 归零。

- [ ] **Step 13: 提交**

```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "feat: wire hit-feedback (combo audio + hit-stop + escalation) into board_view"
```

---

## 自检清单

- [ ] **Spec 覆盖**：合成音(T1) ✓、音高爬升(T1) ✓、落定音(T3 play_settle + T4) ✓、逐击顿帧(T2) ✓、连击 escalation 震/光/音/顿帧/数字(T2+T4) ✓、纯函数全可测(T1/T2) ✓、零素材(T1 合成) ✓、对 sim 零侵入(全 view 层) ✓
- [ ] **占位符扫描**：无 TBD/TODO；每个改代码步骤都给出完整代码 ✓
- [ ] **类型/签名一致性**：
  - `SfxSynth.pitch_scale_for_combo(n)` 在 T1 定义、T3 SfxController、T2 测试一致引用 ✓
  - `JuiceController.on_peg_hit_combo(pos, color, combo)` 在 T2 定义、T4 调用签名一致 ✓
  - `SfxController.play_hit(combo)` / `play_settle()` 在 T3 定义、T4 调用一致 ✓
  - combo 全程 **1-based**（首击=1→基准音）；board_view `_combo` 从 0 起、击中先 +1 再传 ✓
- [ ] **范围**：仅"击中反馈"，combo 不进计分；Backlog 项（Balatro tally / 连锁 / 构筑 / peg pop / 球拖尾 / combo 影响分数 / 特殊钉专属音）均不在本计划 ✓

---

## 备注

- `-gselect=<file>` 跑单文件加速 TDD；最终 Task 4 用 `-gdir` 跑全套。
- headless 用 Dummy 音频驱动，`AudioStreamPlayer.play()` 不出声也不报错，故 T3 可测。
- combo 仅 view 层状态，不入 `ScoreContext`、不持久化、不影响确定性回放——188 基线不受影响。
