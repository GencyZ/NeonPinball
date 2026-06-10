# Milestone 5 — Juice / Game-Feel Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 NeonPinball 加全套"手感"反馈：屏震、命中粒子、得分飘字、慢动作，统一由 JuiceController 编排，接入 BoardView 事件。

**Architecture:** 每种效果是一个独立的、纯逻辑可单测的小类（screen_shake / particle_burst / floaters / slow_mo），状态更新与数值计算和引擎应用（Camera2D.offset / Engine.time_scale / draw）分离。JuiceController 持有这四者并暴露 on_peg_hit / on_settle 等语义入口；BoardView 在其固定步事件循环中调用，并每帧应用相机偏移、时间缩放、绘制粒子与飘字。

**Tech Stack:** Godot 4.6.3 GDScript, GUT 测试框架。

---

## Background

读这一节，理解你要改的代码长什么样。

- **项目根目录:** `D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- **测试命令**（godot 不在 PATH，必须用真实二进制路径）:

  ```bash
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- **基线:** M5 开始前应有 **111 个测试通过**。每个任务做完后必须重新跑全套，确认基线没破。
- **Git:** 用 `git -C D:/NeonPinball/game ...`。每个任务**只提交自己新增/修改的文件**。**不要 push**（由 controller 在最后统一 push）。
- **Autoloads:** `GameDB`、`RunMan`。

### 场景树（`scenes/board.tscn`，主场景）

```
BoardView (Node2D, root)           # script: view/board_view.gd
├── Hud (CanvasLayer)              # script: view/hud.gd
├── InputController (Node)         # script: view/input_controller.gd, board_path=".."
└── Camera2D                       # position (270, 450) = board center; NO script
```

所以在 board_view.gd 里，相机是 `$Camera2D`，屏震就是设 `$Camera2D.offset`。

### board_view.gd 当前结构（集成目标）

- 顶部常量：`DT := 1.0/120.0`、`GATE_DIST`、`PEG_ANIM_DUR`、`PEG_ANIM_SCALE`，以及 preload `RunManagerScript`、`SaveSystemScript`。
- 固定步模拟：`_process(delta)` 做 `if _has_ball: _acc += delta; while _acc >= DT: <step + event loop>; <每帧衰减 flashes/peg_anims>`，然后**永远**在最后（`if _has_ball` 之外）调 `queue_redraw()`。
- while 内的事件循环（已是现状，逐字对照）：

  ```gdscript
  while _event_cursor < _events.size():
      var e: Dictionary = _events[_event_cursor]
      if e[&"type"] == SimEvent.PEG_HIT:
          _score_ctx.pegs_hit += 1
          var hit_peg_id: int = e[&"peg_id"]
          if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
              _peg_anims[hit_peg_id] = PEG_ANIM_DUR
              var hit_type: PegType = _pegs[hit_peg_id].get(&"type")
              if hit_type != null and hit_type.behavior == PegType.Behavior.MULT:
                  _score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
          _flashes.append({&"pos": e[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15,
              &"color": Color.from_hsv(randf(), 0.85, 1.0)})
      elif e[&"type"] == SimEvent.BOUNCE:
          _score_ctx.bounce_count += 1
      for rt in _trigger_runtimes:
          rt.on_event(e, _score_ctx)
      _event_cursor += 1
  ```

- `_on_all_settled()`（所有球死亡时调用）：算 `var score: float = result[0]`，`$Hud.add_score(score)`，`RunMan.add_launch_score(score)`，清理球状态，`_sync_hud()`，可能推进 phase。这里是触发"+score"飘字 + 收尾慢动作的地方。落点：从事件循环里捕获 `SimEvent.SETTLED`（常量值 `&"ball_settled"`，事件带 `&"pos"`）到一个字段 `_last_settle_pos`。
- `_draw()` 当前依次画：pegs（带 `_peg_anims` 的弹跳缩放）、gate（无球时）、prediction 线、balls、flashes。**新的粒子 + 飘字绘制放在 `_draw()` 末尾**，渲染在最上层。
- 已有的 juice 风格（新代码要对齐）：`_flashes` 是 `Array`，元素 dict `{pos, ttl, max_ttl, color}`，每帧衰减 ttl；`_peg_anims` 是 `Dictionary` peg_id→ttl。

> 已核实事实（已对源码确认，直接照用）：
> - `SimEvent.PEG_HIT == &"peg_hit"`、`SimEvent.BOUNCE == &"bounce"`、`SimEvent.SETTLED == &"ball_settled"`；`settled()` / `peg_hit()` 事件均带 `&"pos"` 字段。
> - `RunMan.launches_exhausted() -> bool` 存在（返回 `state[&"launches_left"] <= 0`）。
> - `_on_all_settled()` 内 `var score: float = result[0]` 已存在。
> - 测试文件用 `extends GutTest`，**Tab 缩进**。
> - 目前**没有** `juice/` 目录，需要新建（写文件时父目录自动创建）。

### 确定性说明（必须遵守）

- Juice 的随机（屏震方向、粒子速度、flash 色相）用**全局 RNG**（`randf()`、`randf_range()`），**不是**游戏用的 `DeterministicRng`。纯视觉，不影响 sim/scoring，所以不影响确定性测试。
- 慢动作设 `Engine.time_scale`。因为 sim 用固定 DT 累加器，降低 time_scale 只是让每实秒跑更少的 sim 步（视觉变慢），sim 逻辑完全一致。**无慢动作时必须把 `Engine.time_scale` 复位为 1.0。** 纯 SlowMo 类只返回标量，由 board_view 应用。

### GDScript 坑（本项目全踩过，务必照做）

- GUT 测试文件里引用新类**必须用 `preload()` const**，例如 `const ScreenShakeScript := preload("res://juice/screen_shake.gd")` —— **不要**用裸 `class_name`（autoload / 新类符号在测试解析期解析不到，新 class_name 也不在 headless 全局缓存里）。
- 非测试代码（board_view）里引用新 class_name 脚本**也用 preload const**（headless 缓存安全），例如 `const JuiceControllerScript := preload("res://juice/juice_controller.gd")`。
- 文件缩进是 **Tab**。
- Array 字面量索引会破坏类型推断，**显式标注类型**。
- `draw_string` 需要 Font：用 `ThemeDB.fallback_font` 和一个 int 字号。
- `Color.from_hsv(h, s, v)` 是彩虹色的 API。

---

## 文件结构

**新建文件:**

```
game/juice/screen_shake.gd          # Task 1
game/juice/particle_burst.gd        # Task 2
game/juice/floaters.gd              # Task 3
game/juice/slow_mo.gd               # Task 4
game/juice/juice_controller.gd      # Task 5
game/tests/test_screen_shake.gd     # Task 1
game/tests/test_particle_burst.gd   # Task 2
game/tests/test_floaters.gd         # Task 3
game/tests/test_slow_mo.gd          # Task 4
game/tests/test_juice_controller.gd # Task 5
```

**修改文件:**

```
game/view/board_view.gd             # Task 5 (wiring)
```

---

## JuiceController API 契约（全局唯一真相 —— Task 5 必须严格遵守）

> 这是本计划**最易出错**的部分。下面定下唯一的 API 形状，Task 5 的控制器实现、board_view 接线、`_draw` 循环**全部**照此引用，不得偏离。

`JuiceController` 公开：

| 成员 | 类型 | 说明 |
|------|------|------|
| `shake` | `ScreenShake` 实例 | 通过 `_juice.shake` 可访问 |
| `particles` | `ParticleBurst` 实例 | 粒子列表在 `_juice.particles.particles` |
| `floaters` | `Floaters` 实例 | 飘字列表在 `_juice.floaters.items`；alpha 用 `_juice.floaters.alpha_of(item)` |
| `slowmo` | `SlowMo` 实例 | —— |
| `on_peg_hit(pos, color, big)` | `-> void` | 加 trauma + 发粒子 |
| `on_settle(pos, score, is_final_launch)` | `-> void` | 加飘字 + （收尾）请求慢动作 + 加 trauma |
| `update(delta)` | `-> void` | **一次更新全部四者**，并把本帧相机偏移、时间缩放缓存到内部字段 |
| `camera_offset()` | `-> Vector2` | 返回 `update` 算出的本帧相机偏移 |
| `time_scale()` | `-> float` | 返回 `update` 算出的本帧时间缩放（无慢动作时为 1.0） |

**关键不变量:**
- `update(delta)` 内部调 `shake.update(delta)`（其返回值存进 `_cam_offset`）、`slowmo.update(delta)`（返回值存进 `_time_scale`）、`particles.update(delta)`、`floaters.update(delta)`。
- `camera_offset()` / `time_scale()` 只返回缓存值，**不**重新计算（避免每帧多次推进 RNG / 计时器）。
- board_view 每帧调用顺序：`_juice.update(delta)` → `$Camera2D.offset = _juice.camera_offset()` → `Engine.time_scale = _juice.time_scale()`。
- `_draw` 通过 `_juice.particles.particles` 和 `_juice.floaters.items` 直接读列表，用 `_juice.floaters.alpha_of(item)` 取 alpha。

---

## Task 1: ScreenShake（基于 trauma）

- [ ] **1.1 写失败测试** `game/tests/test_screen_shake.gd`：

  ```gdscript
  extends GutTest

  const ScreenShakeScript := preload("res://juice/screen_shake.gd")

  func test_add_clamps_to_one() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(5.0)
  	assert_almost_eq(s.trauma, 1.0, 0.0001)

  func test_add_sets_trauma() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(0.5)
  	assert_almost_eq(s.trauma, 0.5, 0.0001)

  func test_update_decays_trauma() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(1.0)
  	s.update(0.2)
  	assert_lt(s.trauma, 1.0)
  	assert_gt(s.trauma, 0.0)

  func test_trauma_never_below_zero() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(0.1)
  	s.update(10.0)
  	assert_almost_eq(s.trauma, 0.0, 0.0001)
  	assert_false(s.is_active())

  func test_zero_trauma_offset_is_zero() -> void:
  	var s = ScreenShakeScript.new()
  	var off: Vector2 = s.update(0.016)
  	assert_eq(off, Vector2.ZERO)
  	assert_false(s.is_active())

  func test_offset_magnitude_within_max() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(1.0)
  	for i in 50:
  		var off: Vector2 = s.update(0.0)
  		assert_lte(off.length(), s.MAX_OFFSET * 1.5)

  func test_is_active_when_trauma_positive() -> void:
  	var s = ScreenShakeScript.new()
  	s.add(0.3)
  	assert_true(s.is_active())
  ```

  > 注：`MAX_OFFSET * 1.5` 是因为 `shake = trauma*trauma`，X 与 Y 各取 `[-1,1]`，合矢量长度上界约 `MAX_OFFSET*sqrt(2)*shake`，trauma=1 时 shake=1，长度上界 `MAX_OFFSET*sqrt(2) ≈ 22.6 < MAX_OFFSET*1.5 = 24`。

- [ ] **1.2 跑测试确认失败**（文件不存在 → 解析/运行报错）：

  ```bash
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

  预期：`test_screen_shake.gd` 无法加载 / 报错（因为 `res://juice/screen_shake.gd` 不存在）。

- [ ] **1.3 实现** `game/juice/screen_shake.gd`（Tab 缩进）：

  ```gdscript
  class_name ScreenShake
  extends RefCounted

  const MAX_OFFSET := 16.0
  const DECAY := 1.5   # trauma units per second

  var trauma := 0.0

  func add(amount: float) -> void:
  	trauma = clampf(trauma + amount, 0.0, 1.0)

  func update(delta: float) -> Vector2:
  	trauma = maxf(0.0, trauma - DECAY * delta)
  	if trauma <= 0.0:
  		return Vector2.ZERO
  	var shake := trauma * trauma
  	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * MAX_OFFSET

  func is_active() -> bool:
  	return trauma > 0.0
  ```

- [ ] **1.4 跑测试确认通过**（同上命令）。预期：全部测试通过，总数 = 111 + 7（screen_shake）= **118 通过**。

- [ ] **1.5 提交**（只提交本任务文件）：

  ```bash
  git -C D:/NeonPinball/game add juice/screen_shake.gd tests/test_screen_shake.gd
  git -C D:/NeonPinball/game commit -m "feat: trauma-based ScreenShake juice primitive"
  ```

---

## Task 2: ParticleBurst（绘制型粒子）

- [ ] **2.1 写失败测试** `game/tests/test_particle_burst.gd`：

  ```gdscript
  extends GutTest

  const ParticleBurstScript := preload("res://juice/particle_burst.gd")

  func test_emit_adds_exact_count() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2(10, 10), Color.RED, 8)
  	assert_eq(pb.particles.size(), 8)

  func test_emit_zero_adds_none() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2(10, 10), Color.RED, 0)
  	assert_eq(pb.particles.size(), 0)

  func test_emitted_particles_have_positive_ttl() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2.ZERO, Color.WHITE, 5)
  	for p in pb.particles:
  		assert_gt(float(p[&"ttl"]), 0.0)
  		assert_gt(float(p[&"max_ttl"]), 0.0)

  func test_update_integrates_position() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2(100, 100), Color.WHITE, 6)
  	var before: Array = []
  	for p in pb.particles:
  		before.append(p[&"pos"])
  	pb.update(0.05)
  	var moved := false
  	for i in pb.particles.size():
  		if (pb.particles[i][&"pos"] as Vector2) != (before[i] as Vector2):
  			moved = true
  	assert_true(moved)

  func test_update_decrements_ttl() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2.ZERO, Color.WHITE, 4)
  	var ttl0: float = pb.particles[0][&"ttl"]
  	pb.update(0.1)
  	assert_lt(float(pb.particles[0][&"ttl"]), ttl0)

  func test_dead_particles_removed() -> void:
  	var pb = ParticleBurstScript.new()
  	pb.emit(Vector2.ZERO, Color.WHITE, 10)
  	for i in 100:
  		pb.update(0.1)
  	assert_eq(pb.particles.size(), 0)
  ```

- [ ] **2.2 跑测试确认失败**（命令同 1.2）。预期：`test_particle_burst.gd` 报错（脚本不存在）。

- [ ] **2.3 实现** `game/juice/particle_burst.gd`（Tab 缩进）：

  ```gdscript
  class_name ParticleBurst
  extends RefCounted

  const GRAVITY := 600.0

  var particles: Array = []

  func emit(pos: Vector2, color: Color, count: int = 8) -> void:
  	for i in count:
  		var angle := randf_range(0.0, TAU)
  		var speed := randf_range(80.0, 220.0)
  		var vel := Vector2(cos(angle), sin(angle)) * speed
  		particles.append({
  			&"pos": pos,
  			&"vel": vel,
  			&"ttl": 0.35,
  			&"max_ttl": 0.35,
  			&"color": color,
  		})

  func update(delta: float) -> void:
  	for i in range(particles.size() - 1, -1, -1):
  		var p: Dictionary = particles[i]
  		p[&"vel"] = (p[&"vel"] as Vector2) + Vector2(0.0, GRAVITY * delta)
  		p[&"pos"] = (p[&"pos"] as Vector2) + (p[&"vel"] as Vector2) * delta
  		p[&"ttl"] = float(p[&"ttl"]) - delta
  		if float(p[&"ttl"]) <= 0.0:
  			particles.remove_at(i)
  ```

- [ ] **2.4 跑测试确认通过**。预期：总数 = 118 + 6 = **124 通过**。

- [ ] **2.5 提交**：

  ```bash
  git -C D:/NeonPinball/game add juice/particle_burst.gd tests/test_particle_burst.gd
  git -C D:/NeonPinball/game commit -m "feat: ParticleBurst hit-particle system"
  ```

---

## Task 3: Floaters（飘升得分文字）

- [ ] **3.1 写失败测试** `game/tests/test_floaters.gd`：

  ```gdscript
  extends GutTest

  const FloatersScript := preload("res://juice/floaters.gd")

  func test_add_appends_item() -> void:
  	var f = FloatersScript.new()
  	f.add(Vector2(50, 50), "+100", 0.9)
  	assert_eq(f.items.size(), 1)
  	assert_eq(String(f.items[0][&"text"]), "+100")
  	assert_almost_eq(float(f.items[0][&"ttl"]), 0.9, 0.0001)
  	assert_almost_eq(float(f.items[0][&"max_ttl"]), 0.9, 0.0001)

  func test_update_moves_up_and_decrements() -> void:
  	var f = FloatersScript.new()
  	f.add(Vector2(50, 100), "+5")
  	var y0: float = f.items[0][&"pos"].y
  	var ttl0: float = f.items[0][&"ttl"]
  	f.update(0.1)
  	assert_lt(float(f.items[0][&"pos"].y), y0)
  	assert_lt(float(f.items[0][&"ttl"]), ttl0)

  func test_alpha_full_at_spawn() -> void:
  	var f = FloatersScript.new()
  	f.add(Vector2.ZERO, "+1", 1.0)
  	assert_almost_eq(f.alpha_of(f.items[0]), 1.0, 0.0001)

  func test_alpha_low_near_death() -> void:
  	var f = FloatersScript.new()
  	f.add(Vector2.ZERO, "+1", 1.0)
  	f.update(0.95)
  	assert_lt(f.alpha_of(f.items[0]), 0.1)

  func test_expired_removed() -> void:
  	var f = FloatersScript.new()
  	f.add(Vector2.ZERO, "+1", 0.5)
  	for i in 20:
  		f.update(0.1)
  	assert_eq(f.items.size(), 0)
  ```

- [ ] **3.2 跑测试确认失败**（命令同 1.2）。预期：`test_floaters.gd` 报错。

- [ ] **3.3 实现** `game/juice/floaters.gd`（Tab 缩进）：

  ```gdscript
  class_name Floaters
  extends RefCounted

  const RISE := 40.0   # pixels per second upward

  var items: Array = []

  func add(pos: Vector2, text: String, ttl: float = 0.9) -> void:
  	items.append({
  		&"pos": pos,
  		&"text": text,
  		&"ttl": ttl,
  		&"max_ttl": ttl,
  	})

  func update(delta: float) -> void:
  	for i in range(items.size() - 1, -1, -1):
  		var it: Dictionary = items[i]
  		it[&"pos"] = (it[&"pos"] as Vector2) - Vector2(0.0, RISE * delta)
  		it[&"ttl"] = float(it[&"ttl"]) - delta
  		if float(it[&"ttl"]) <= 0.0:
  			items.remove_at(i)

  func alpha_of(item: Dictionary) -> float:
  	return clampf(float(item[&"ttl"]) / float(item[&"max_ttl"]), 0.0, 1.0)
  ```

- [ ] **3.4 跑测试确认通过**。预期：总数 = 124 + 5 = **129 通过**。

- [ ] **3.5 提交**：

  ```bash
  git -C D:/NeonPinball/game add juice/floaters.gd tests/test_floaters.gd
  git -C D:/NeonPinball/game commit -m "feat: Floaters floating score-text system"
  ```

---

## Task 4: SlowMo（时间缩放包络）

> **设计取舍（写进代码注释）：** 计时器跑在**缩放时间**里（board_view 传给 `update` 的 `delta` 已被 `Engine.time_scale` 缩放）。这意味着慢动作窗口是 `duration` 缩放秒，不是实秒。对于一次短暂的收尾顿帧，这完全可接受，且实现最简。明确记录此局限。

- [ ] **4.1 写失败测试** `game/tests/test_slow_mo.gd`：

  ```gdscript
  extends GutTest

  const SlowMoScript := preload("res://juice/slow_mo.gd")

  func test_default_returns_one() -> void:
  	var sm = SlowMoScript.new()
  	assert_almost_eq(sm.update(0.016), 1.0, 0.0001)
  	assert_false(sm.is_active())

  func test_request_holds_target_in_window() -> void:
  	var sm = SlowMoScript.new()
  	sm.request(0.3, 0.5)
  	assert_almost_eq(sm.update(0.1), 0.3, 0.0001)
  	assert_true(sm.is_active())

  func test_returns_to_one_after_window() -> void:
  	var sm = SlowMoScript.new()
  	sm.request(0.3, 0.5)
  	for i in 10:
  		sm.update(0.1)
  	assert_almost_eq(sm.update(0.1), 1.0, 0.0001)
  	assert_false(sm.is_active())

  func test_is_active_reflects_state() -> void:
  	var sm = SlowMoScript.new()
  	assert_false(sm.is_active())
  	sm.request(0.5, 0.2)
  	assert_true(sm.is_active())
  	sm.update(0.5)   # exhaust timer
  	assert_false(sm.is_active())
  ```

- [ ] **4.2 跑测试确认失败**（命令同 1.2）。预期：`test_slow_mo.gd` 报错。

- [ ] **4.3 实现** `game/juice/slow_mo.gd`（Tab 缩进）：

  ```gdscript
  class_name SlowMo
  extends RefCounted

  # NOTE: _timer runs in SCALED time (board_view passes the scaled frame delta).
  # The slow-mo window is therefore `duration` scaled-seconds, not real-seconds.
  # Acceptable for a brief juice dip; documented as a known limitation.

  var _timer := 0.0
  var _target := 1.0

  func request(scale: float, duration: float) -> void:
  	_target = scale
  	_timer = duration

  func update(delta: float) -> float:
  	if _timer > 0.0:
  		_timer -= delta
  		return _target
  	return 1.0

  func is_active() -> bool:
  	return _timer > 0.0
  ```

  > 注意 `update` 顺序：先判 `_timer > 0.0` 再扣减并返回 `_target`，所以**请求当帧**与窗口内每帧返回目标值；只有当某帧进入时 `_timer <= 0.0` 才返回 1.0。`test_returns_to_one_after_window` 跑 10 次 `update(0.1)`（共扣 1.0 缩放秒，远超 0.5）后 `_timer` 已 ≤0，第 11 次 update 返回 1.0。

- [ ] **4.4 跑测试确认通过**。预期：总数 = 129 + 4 = **133 通过**。

- [ ] **4.5 提交**：

  ```bash
  git -C D:/NeonPinball/game add juice/slow_mo.gd tests/test_slow_mo.gd
  git -C D:/NeonPinball/game commit -m "feat: SlowMo time-scale envelope primitive"
  ```

---

## Task 5: JuiceController + BoardView 接线

> 严格遵守上面的 **JuiceController API 契约**。控制器、board_view 接线、`_draw` 循环必须一致。

### 5a. JuiceController 类

- [ ] **5.1 写失败测试** `game/tests/test_juice_controller.gd`：

  ```gdscript
  extends GutTest

  const JuiceControllerScript := preload("res://juice/juice_controller.gd")

  func test_big_hit_adds_more_trauma_than_small() -> void:
  	var jc_small = JuiceControllerScript.new()
  	jc_small.on_peg_hit(Vector2.ZERO, Color.WHITE, false)
  	var jc_big = JuiceControllerScript.new()
  	jc_big.on_peg_hit(Vector2.ZERO, Color.WHITE, true)
  	assert_gt(jc_big.shake.trauma, jc_small.shake.trauma)

  func test_peg_hit_emits_particles() -> void:
  	var jc = JuiceControllerScript.new()
  	assert_eq(jc.particles.particles.size(), 0)
  	jc.on_peg_hit(Vector2(5, 5), Color.RED, false)
  	assert_gt(jc.particles.particles.size(), 0)

  func test_big_hit_emits_more_particles() -> void:
  	var jc_small = JuiceControllerScript.new()
  	jc_small.on_peg_hit(Vector2.ZERO, Color.WHITE, false)
  	var jc_big = JuiceControllerScript.new()
  	jc_big.on_peg_hit(Vector2.ZERO, Color.WHITE, true)
  	assert_gt(jc_big.particles.particles.size(), jc_small.particles.particles.size())

  func test_settle_adds_floater_with_plus_text() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.on_settle(Vector2(100, 200), 250.0, false)
  	assert_eq(jc.floaters.items.size(), 1)
  	assert_eq(String(jc.floaters.items[0][&"text"]), "+250")

  func test_final_launch_with_score_triggers_slowmo() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.on_settle(Vector2.ZERO, 100.0, true)
  	jc.update(0.016)
  	assert_lt(jc.time_scale(), 1.0)
  	assert_true(jc.slowmo.is_active())

  func test_non_final_launch_no_slowmo() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.on_settle(Vector2.ZERO, 100.0, false)
  	jc.update(0.016)
  	assert_almost_eq(jc.time_scale(), 1.0, 0.0001)

  func test_final_launch_zero_score_no_slowmo() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.on_settle(Vector2.ZERO, 0.0, true)
  	jc.update(0.016)
  	assert_almost_eq(jc.time_scale(), 1.0, 0.0001)

  func test_update_advances_particles_and_floaters() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.on_peg_hit(Vector2(50, 50), Color.WHITE, true)
  	jc.on_settle(Vector2(50, 50), 10.0, false)
  	var px0: float = jc.particles.particles[0][&"pos"].x
  	var fy0: float = jc.floaters.items[0][&"pos"].y
  	jc.update(0.05)
  	var moved := (jc.particles.particles[0][&"pos"].x != px0) or (jc.floaters.items[0][&"pos"].y != fy0)
  	assert_true(moved)

  func test_camera_offset_zero_when_idle() -> void:
  	var jc = JuiceControllerScript.new()
  	jc.update(0.016)
  	assert_eq(jc.camera_offset(), Vector2.ZERO)
  ```

- [ ] **5.2 跑测试确认失败**（命令同 1.2）。预期：`test_juice_controller.gd` 报错（脚本不存在）。

- [ ] **5.3 实现** `game/juice/juice_controller.gd`（Tab 缩进，四个原语用 preload const 实例化，headless 安全）：

  ```gdscript
  class_name JuiceController
  extends RefCounted

  const ScreenShakeScript := preload("res://juice/screen_shake.gd")
  const ParticleBurstScript := preload("res://juice/particle_burst.gd")
  const FloatersScript := preload("res://juice/floaters.gd")
  const SlowMoScript := preload("res://juice/slow_mo.gd")

  var shake := ScreenShakeScript.new()
  var particles := ParticleBurstScript.new()
  var floaters := FloatersScript.new()
  var slowmo := SlowMoScript.new()

  var _cam_offset := Vector2.ZERO
  var _time_scale := 1.0

  func on_peg_hit(pos: Vector2, color: Color, big: bool) -> void:
  	shake.add(0.3 if big else 0.12)
  	particles.emit(pos, color, 14 if big else 6)

  func on_settle(pos: Vector2, score: float, is_final_launch: bool) -> void:
  	floaters.add(pos, "+%d" % int(score))
  	shake.add(0.2)
  	if is_final_launch and score > 0.0:
  		slowmo.request(0.35, 0.25)

  func update(delta: float) -> void:
  	_cam_offset = shake.update(delta)
  	_time_scale = slowmo.update(delta)
  	particles.update(delta)
  	floaters.update(delta)

  func camera_offset() -> Vector2:
  	return _cam_offset

  func time_scale() -> float:
  	return _time_scale
  ```

  > `test_camera_offset_zero_when_idle`：trauma=0 → `shake.update` 返回 ZERO → `_cam_offset == ZERO`。
  > `test_final_launch_with_score_triggers_slowmo`：`on_settle(.., true)` 请求 slowmo(0.35, 0.25)；`update(0.016)` 内 `slowmo.update(0.016)` 返回 0.35（窗口内）→ `time_scale()==0.35 < 1.0`。

- [ ] **5.4 跑测试确认通过**。预期：总数 = 133 + 9 = **142 通过**。

- [ ] **5.5 提交（仅控制器 + 其测试）**：

  ```bash
  git -C D:/NeonPinball/game add juice/juice_controller.gd tests/test_juice_controller.gd
  git -C D:/NeonPinball/game commit -m "feat: JuiceController orchestration (shake/particles/floaters/slowmo)"
  ```

### 5b. BoardView 接线

> 这部分没有新单测（绘制 / 引擎应用不在 headless 单测范围），靠"全套 111+ 测试不破 + 手动核对"验证。逐字按下面改 `game/view/board_view.gd`，Tab 缩进。

- [ ] **5.6 加 preload const + 字段。** 在顶部常量区，`SaveSystemScript` 那行之后加一行：

  找到：

  ```gdscript
  const RunManagerScript := preload("res://run/run_manager.gd")
  const SaveSystemScript := preload("res://run/save_system.gd")
  ```

  改成：

  ```gdscript
  const RunManagerScript := preload("res://run/run_manager.gd")
  const SaveSystemScript := preload("res://run/save_system.gd")
  const JuiceControllerScript := preload("res://juice/juice_controller.gd")
  ```

  然后在 `var _launch_count := 0` 那行之后加两个字段：

  找到：

  ```gdscript
  var _launch_count := 0
  ```

  改成：

  ```gdscript
  var _launch_count := 0

  var _juice := JuiceControllerScript.new()
  var _last_settle_pos := Vector2.ZERO
  ```

- [ ] **5.7 在 PEG_HIT 分支接入 on_peg_hit，并把 flash 颜色重构成局部变量。**

  找到事件循环里的 PEG_HIT 分支（`_flashes.append(...)` 内联了 `Color.from_hsv(randf(), 0.85, 1.0)`）：

  ```gdscript
  			if e[&"type"] == SimEvent.PEG_HIT:
  				_score_ctx.pegs_hit += 1
  				var hit_peg_id: int = e[&"peg_id"]
  				if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
  					_peg_anims[hit_peg_id] = PEG_ANIM_DUR
  					var hit_type: PegType = _pegs[hit_peg_id].get(&"type")
  					if hit_type != null and hit_type.behavior == PegType.Behavior.MULT:
  						_score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
  				_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15,
  					&"color": Color.from_hsv(randf(), 0.85, 1.0)})
  ```

  改成（提取 `flash_color`，在 flash dict 与 juice 调用里复用；`big` 用 `_score_ctx.pegs_hit >= 5`）：

  ```gdscript
  			if e[&"type"] == SimEvent.PEG_HIT:
  				_score_ctx.pegs_hit += 1
  				var hit_peg_id: int = e[&"peg_id"]
  				if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
  					_peg_anims[hit_peg_id] = PEG_ANIM_DUR
  					var hit_type: PegType = _pegs[hit_peg_id].get(&"type")
  					if hit_type != null and hit_type.behavior == PegType.Behavior.MULT:
  						_score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
  				var flash_color := Color.from_hsv(randf(), 0.85, 1.0)
  				_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15,
  					&"color": flash_color})
  				_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)
  ```

- [ ] **5.8 捕获 settle 位置。** 在事件循环里 `elif e[&"type"] == SimEvent.BOUNCE:` 分支之后加一个 SETTLED 分支。

  找到：

  ```gdscript
  			elif e[&"type"] == SimEvent.BOUNCE:
  				_score_ctx.bounce_count += 1
  			for rt in _trigger_runtimes:
  ```

  改成：

  ```gdscript
  			elif e[&"type"] == SimEvent.BOUNCE:
  				_score_ctx.bounce_count += 1
  			elif e[&"type"] == SimEvent.SETTLED:
  				_last_settle_pos = e[&"pos"]
  			for rt in _trigger_runtimes:
  ```

- [ ] **5.9 在 _on_all_settled 调 on_settle。** 找到：

  ```gdscript
  func _on_all_settled() -> void:
  	var result := _engine.settle(_score_ctx)
  	var score: float = result[0]
  	$Hud.add_score(score)
  	RunMan.add_launch_score(score)
  ```

  改成（在 `RunMan.add_launch_score` 之后加一行；注意 `launches_exhausted()` 此刻读的是**已扣减后**的 launches_left —— 即"这是不是本回合最后一发"）：

  ```gdscript
  func _on_all_settled() -> void:
  	var result := _engine.settle(_score_ctx)
  	var score: float = result[0]
  	$Hud.add_score(score)
  	RunMan.add_launch_score(score)
  	_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())
  ```

- [ ] **5.10 每帧应用相机偏移 + 时间缩放。** 找到 `_process` 末尾的 `queue_redraw()`：

  ```gdscript
  		for pid in _peg_anims.keys():
  			_peg_anims[pid] -= delta
  			if _peg_anims[pid] <= 0.0:
  				_peg_anims.erase(pid)
  	queue_redraw()
  ```

  改成（juice 更新与应用放在 `if _has_ball` **之外**，确保无球时屏震/慢动作也能衰减归位）：

  ```gdscript
  		for pid in _peg_anims.keys():
  			_peg_anims[pid] -= delta
  			if _peg_anims[pid] <= 0.0:
  				_peg_anims.erase(pid)
  	_juice.update(delta)
  	$Camera2D.offset = _juice.camera_offset()
  	Engine.time_scale = _juice.time_scale()
  	queue_redraw()
  ```

  > 缩进对齐：`for pid ...` 块在 `if _has_ball:` 之内（两层缩进）；`_juice.update(delta)` 这三行与 `queue_redraw()` 同级（函数体一层缩进，**在** `if _has_ball:` 之外）。

- [ ] **5.11 在 _draw 末尾画粒子 + 飘字。** 找到 `_draw()` 最后的 flashes 循环：

  ```gdscript
  	for f in _flashes:
  		var a: float = f[&"ttl"] / f[&"max_ttl"]
  		var base_col: Color = f.get(&"color", Color(1.0, 1.0, 0.6))
  		draw_circle(f[&"pos"], 16.0, Color(base_col.r, base_col.g, base_col.b, a * 0.8))
  ```

  在它之后追加（粒子 + 飘字渲染在最上层）：

  ```gdscript
  	for f in _flashes:
  		var a: float = f[&"ttl"] / f[&"max_ttl"]
  		var base_col: Color = f.get(&"color", Color(1.0, 1.0, 0.6))
  		draw_circle(f[&"pos"], 16.0, Color(base_col.r, base_col.g, base_col.b, a * 0.8))
  	for p in _juice.particles.particles:
  		var p_life: float = float(p[&"ttl"]) / float(p[&"max_ttl"])
  		var pc: Color = p[&"color"]
  		draw_circle(p[&"pos"], 3.0 * p_life + 1.0, Color(pc.r, pc.g, pc.b, p_life))
  	for item in _juice.floaters.items:
  		draw_string(ThemeDB.fallback_font, item[&"pos"], String(item[&"text"]),
  			HORIZONTAL_ALIGNMENT_CENTER, -1, 20,
  			Color(1.0, 1.0, 1.0, _juice.floaters.alpha_of(item)))
  ```

- [ ] **5.12 跑全套确认无回归**（命令同 1.2）。预期：**142 通过**（111 基线 + 31 新增；board_view 改动不引入新测试，但也不能破坏任何现有测试，尤其 `test_run_loop.gd` / `test_determinism.gd`）。

- [ ] **5.13 提交（仅 board_view）**：

  ```bash
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: wire JuiceController into BoardView (shake/particles/floaters/slowmo)"
  ```

---

## 自检清单

执行完全部任务后逐项核对：

- [ ] **测试总数:** 111 基线 + 31 新增 = **142 通过，0 失败**。新增分布：screen_shake 7、particle_burst 6、floaters 5、slow_mo 4、juice_controller 9。
- [ ] **屏震复位:** 无球 / trauma 耗尽时 `$Camera2D.offset` 回到 `Vector2.ZERO`（`ScreenShake.update` 在 trauma≤0 返回 ZERO，且 `_juice.update` 在 `if _has_ball` 之外每帧跑）。
- [ ] **时间缩放复位:** 无慢动作时 `Engine.time_scale == 1.0`（`SlowMo.update` 在 `_timer<=0` 返回 1.0，每帧应用）。
- [ ] **绘制层级:** 粒子与飘字在 `_draw()` 末尾绘制，渲染在 pegs/balls/flashes 之上。
- [ ] **无确定性回归:** `test_determinism.gd` 与 `test_run_loop.gd` 仍通过；juice 只用全局 `randf*`，不碰 `DeterministicRng`，不进 sim/scoring。
- [ ] **每个 commit 只含自身文件:** 用 `git -C D:/NeonPinball/game show --stat HEAD~N` 抽查；**全程未 push**。
- [ ] **手动游戏核对**（启动 `D:/Program/Godot/godot.exe --path D:/NeonPinball/game`，发球观察）：
  - 命中一个 peg → 出现粒子爆发 + 轻微屏震。
  - 单发累计命中 5+ peg 后的命中 → 更强屏震 + 更多粒子。
  - 本回合最后一发落定（launches 耗尽）→ 落点出现 "+N" 飘字上升 + 短暂慢动作顿帧，随后 `Engine.time_scale` 恢复 1.0。

---

## 已知局限 / 留待后续

- **飘字用 fallback 字体**（`ThemeDB.fallback_font`），无自定义字形 / 描边 / 颜色分级。后续可换项目主题字体并按分数大小调字号 / 颜色。
- **粒子数量固定**（小命中 6，大命中 14），未做对象池；高频命中时会有少量分配开销。后续可加池化。
- **慢动作计时器跑在缩放时间里**（窗口是 `duration` 缩放秒，非实秒）。短顿帧无感知问题；若以后需要精确实秒窗口，应在 board_view 把 `delta / Engine.time_scale` 传给 `SlowMo.update`，或让 SlowMo 用 `Time.get_ticks_msec()` 自计时。
- **on_settle 用单次 `shake.add(0.2)`**，每发落定都震；若觉得非收尾发太吵，后续可只在 `is_final_launch` 时加 trauma。
