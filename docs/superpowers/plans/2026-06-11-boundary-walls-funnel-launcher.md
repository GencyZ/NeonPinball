# Boundary Walls, Funnel & Launcher System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add physical boundary walls (left/right/top bounce, funnel bottom), three fixed launcher positions with open/close gate mechanics, and dual mouse + keyboard aim control.

**Architecture:** Extend `Collision` with swept_segment CCD; replace rect-based wall collision in `BallSimulation` with a configurable wall-segment list (enables gate gaps and custom restitution per segment); board_view builds and manages the segment list; input_controller gains fixed launcher positions, A/D rotation, and Space-to-fire.

**Tech Stack:** Godot 4.6.3, GDScript, GUT 9.x

---

## File Map

| File | Change |
|---|---|
| `sim/collision.gd` | Add `swept_segment()` static method |
| `sim/ball_simulation.gd` | Replace `swept_walls` call with `_wall_segs` list; add `set_wall_segs()` |
| `sim/entry_resolver.gd` | Add `LAUNCHER_T` and `LAUNCHER_POS` constants |
| `view/board_view.gd` | New `_rect`, fix `_build_honeycomb`, funnel/gate helpers, gate open/close, `_draw_walls()` |
| `view/input_controller.gd` | Fixed launcher, A/D rotation, Space fire, mouse angle from gate position |
| `tests/test_collision.gd` | Add swept_segment tests |
| `tests/test_ball_simulation.gd` | Add wall-seg bounce and funnel tests |
| `tests/test_gate_physics.gd` | New — gate open/close physics tests |

---

### Task 1: swept_segment in collision.gd

**Files:**
- Modify: `sim/collision.gd`
- Modify: `tests/test_collision.gd`

- [ ] **Step 1: Add failing tests for swept_segment**

Append to `tests/test_collision.gd`:

```gdscript
func test_swept_segment_hits_left_face():
	# Ball moving right, hits the left face of a vertical segment
	var hit := Collision.swept_segment(
		Vector2(10, 50), Vector2(200, 0), 5.0,
		Vector2(100, 0), Vector2(100, 100))
	assert_false(hit.is_empty(), "should hit")
	# contact when ball right-edge reaches x=100: t = (100-10-5)/200 = 0.425
	assert_almost_eq(hit[&"t"], 0.425, 0.001)
	assert_eq(hit[&"normal"], Vector2(-1, 0))

func test_swept_segment_hits_wall_from_inside():
	# Ball inside rect moving left, hits left-wall segment at x=0
	var hit := Collision.swept_segment(
		Vector2(50, 100), Vector2(-200, 0), 8.0,
		Vector2(0, 0), Vector2(0, 300))
	assert_false(hit.is_empty(), "should hit left wall")
	assert_almost_eq(hit[&"t"], (50.0 - 8.0) / 200.0, 0.001)
	assert_eq(hit[&"normal"], Vector2(1, 0))

func test_swept_segment_parallel_miss():
	# Ball path never intersects segment
	var hit := Collision.swept_segment(
		Vector2(0, 50), Vector2(200, 0), 5.0,
		Vector2(50, 100), Vector2(50, 200))
	assert_true(hit.is_empty())

func test_swept_segment_endpoint_cap():
	# Ball path misses the flat face but catches the segment endpoint
	# seg_a=(50,15) is just above the ball's y=10 path
	var hit := Collision.swept_segment(
		Vector2(0, 10), Vector2(200, 0), 8.0,
		Vector2(50, 15), Vector2(50, 100))
	assert_false(hit.is_empty(), "endpoint cap should catch")
	assert_true(hit[&"t"] > 0.0 and hit[&"t"] <= 1.0)

func test_swept_segment_moving_away_miss():
	# Ball moving away from segment — should miss
	var hit := Collision.swept_segment(
		Vector2(50, 50), Vector2(-200, 0), 5.0,
		Vector2(100, 0), Vector2(100, 100))
	assert_true(hit.is_empty())
```

- [ ] **Step 2: Run tests — verify they fail**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gsuffix=test_collision.gd -gexit
```

Expected: FAIL — `swept_segment` not defined.

- [ ] **Step 3: Implement swept_segment in collision.gd**

Add at the end of `sim/collision.gd`:

```gdscript
# 扫掠圆 (radius r, start p, displacement d) vs 有限线段 (seg_a..seg_b)。
# 命中返回 {t∈[0,1], normal}，未命中返回 {}。
static func swept_segment(p: Vector2, d: Vector2, r: float,
		seg_a: Vector2, seg_b: Vector2) -> Dictionary:
	var ab := seg_b - seg_a
	var ab_len_sq := ab.dot(ab)
	if ab_len_sq < 1e-10:
		var t := swept_circle(p, d, seg_a, r)
		if t < 0.0:
			return {}
		return {&"t": t, &"normal": (p + d * t - seg_a).normalized()}

	var ab_len := sqrt(ab_len_sq)
	var ab_n := ab / ab_len
	var ab_perp := Vector2(-ab_n.y, ab_n.x)

	var mp := p - seg_a
	var d0 := mp.dot(ab_perp)
	var dd := d.dot(ab_perp)

	var best_t := INF
	var best_n := Vector2.ZERO
	var found := false

	# 平面碰撞（两侧）
	for sign_f in [1.0, -1.0]:
		if abs(dd) < 1e-9:
			continue
		var t := (sign_f * r - d0) / dd
		if t < 0.0 or t > 1.0:
			continue
		var contact := p + d * t
		var proj := (contact - seg_a).dot(ab_n)
		if proj < 0.0 or proj > ab_len:
			continue
		if t < best_t:
			best_t = t
			best_n = ab_perp * sign_f
			found = true

	# 端点 cap
	for cap in [seg_a, seg_b]:
		var t := swept_circle(p, d, cap, r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_n = (p + d * t - cap).normalized()
			found = true

	if not found:
		return {}
	return {&"t": best_t, &"normal": best_n}
```

- [ ] **Step 4: Run tests — verify they pass**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gsuffix=test_collision.gd -gexit
```

Expected: all collision tests pass.

- [ ] **Step 5: Commit**

```bash
cd /d/NeonPinball
git add sim/collision.gd tests/test_collision.gd
git commit -m "feat: add Collision.swept_segment CCD for finite wall segments"
```

---

### Task 2: wall_segs replacing swept_walls in BallSimulation

**Files:**
- Modify: `sim/ball_simulation.gd`
- Modify: `tests/test_ball_simulation.gd`

- [ ] **Step 1: Add failing tests**

Append to `tests/test_ball_simulation.gd`:

```gdscript
func test_ball_bounces_off_wall_segment():
	# Custom wall segment at x=200; ball moving right should bounce with given restitution
	var sim := BallSimulation.new(Rect2(0, 0, 540, 900), [], {
		&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
		&"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0})
	sim.set_wall_segs([
		{&"a": Vector2(200, 0), &"b": Vector2(200, 300), &"restitution": 0.5}
	])
	var ball := BallState.new(Vector2(100, 100), Vector2(1200, 0), 8.0)
	# After one step the ball should hit x=200 and bounce back with restitution 0.5
	var events: Array = []
	sim.step(ball, events)
	assert_true(ball.vel.x < 0.0, "ball should bounce left")

func test_wall_seg_low_restitution():
	# Funnel-like segment: ball should barely bounce
	var sim := BallSimulation.new(Rect2(0, 0, 540, 900), [], {
		&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
		&"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0})
	sim.set_wall_segs([
		{&"a": Vector2(200, 0), &"b": Vector2(200, 300), &"restitution": 0.05}
	])
	var ball := BallState.new(Vector2(100, 100), Vector2(1200, 0), 8.0)
	var events: Array = []
	sim.step(ball, events)
	# Speed after bounce should be ~5% of incoming normal speed
	assert_true(ball.vel.x > -100.0, "very low bounce with restitution 0.05")
	assert_true(ball.vel.x < 0.0, "still bounces back")
```

- [ ] **Step 2: Run — verify fail**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gsuffix=test_ball_simulation.gd -gexit
```

Expected: FAIL — `set_wall_segs` not defined.

- [ ] **Step 3: Update ball_simulation.gd**

**3a.** Add field after `var _cfg: Dictionary`:
```gdscript
var _wall_segs: Array = []
```

**3b.** Add `_init` default wall segs — replace the existing `_init` body:
```gdscript
func _init(rect: Rect2, pegs: Array, cfg: Dictionary) -> void:
	_rect = rect; _pegs = pegs; _cfg = cfg
	_grid = PegGrid.new()
	_grid.build(pegs, rect, 50.0)
	# Default: full rect walls as segments (left, right, top). Bottom stays open.
	var rest: float = cfg.get(&"restitution", 0.82)
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var bl := Vector2(rect.position.x, rect.end.y)
	var br := rect.end
	_wall_segs = [
		{&"a": tl, &"b": bl, &"restitution": rest},  # left
		{&"a": tr, &"b": br, &"restitution": rest},  # right
		{&"a": tl, &"b": tr, &"restitution": rest},  # top
	]
```

**3c.** Add public setter after `_init`:
```gdscript
func set_wall_segs(segs: Array) -> void:
	_wall_segs = segs
```

**3d.** In `_find_earliest`, replace the `swept_walls` block:

Old:
```gdscript
	var wall := Collision.swept_walls(p, d, r, _rect)
	if not wall.is_empty() and wall[&"t"] < best_t:
		best = {&"t": wall[&"t"], &"peg_id": -1, &"normal": wall[&"normal"]}
	return best
```

New:
```gdscript
	for seg in _wall_segs:
		var sh := Collision.swept_segment(p, d, r, seg[&"a"], seg[&"b"])
		if not sh.is_empty() and sh[&"t"] < best_t:
			best_t = sh[&"t"]
			best = {&"t": sh[&"t"], &"peg_id": -1, &"normal": sh[&"normal"],
					&"restitution": seg[&"restitution"]}
	return best
```

**3e.** In `_integrate_ccd`, use per-segment restitution — replace:
```gdscript
		ball.vel = Collision.reflect(
			ball.vel, hit[&"normal"], _cfg[&"restitution"], _cfg[&"tangent_keep"])
```
With:
```gdscript
		var rest: float = hit.get(&"restitution", _cfg[&"restitution"])
		ball.vel = Collision.reflect(
			ball.vel, hit[&"normal"], rest, _cfg[&"tangent_keep"])
```

- [ ] **Step 4: Run full test suite — verify no regressions**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all existing + 2 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add sim/ball_simulation.gd tests/test_ball_simulation.gd
git commit -m "feat: replace swept_walls with configurable wall-segment list in BallSimulation"
```

---

### Task 3: Board rect repositioning + _build_honeycomb fix

**Files:**
- Modify: `view/board_view.gd`

No new tests needed — visual change only; full suite run confirms no regression.

- [ ] **Step 1: Update `_rect` in `_ready()`**

Old:
```gdscript
	_rect = Rect2(0, 0, 540, 900)
```
New:
```gdscript
	_rect = Rect2(135, 225, 540, 900)
```

- [ ] **Step 2: Fix `_build_honeycomb` to use `_rect.position` offset**

Old inner loop (the y/x assignment lines):
```gdscript
			var y := margin + 140.0 + r * spacing
			...
			var x := margin + x_off + c * spacing
```
New:
```gdscript
			var y := _rect.position.y + margin + 140.0 + r * spacing
			...
			var x := _rect.position.x + margin + x_off + c * spacing
```

- [ ] **Step 3: Run full test suite**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all tests still pass (unit tests create their own rects; integration tests test run-state not positions).

- [ ] **Step 4: Commit**

```bash
git add view/board_view.gd
git commit -m "feat: center board rect at (135,225) in 810x1350 canvas; fix honeycomb offsets"
```

---

### Task 4: Funnel + gated wall segments

**Files:**
- Modify: `view/board_view.gd`
- Create: `tests/test_gate_physics.gd`

- [ ] **Step 1: Write failing tests**

Create `tests/test_gate_physics.gd`:

```gdscript
extends GutTest

const BallSimulation := preload("res://sim/ball_simulation.gd")
const BallState := preload("res://sim/ball_state.gd")

var _cfg := {
	&"gravity": Vector2.ZERO, &"max_speed": 4000.0,
	&"restitution": 0.82, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
}
var _rect := Rect2(0, 0, 540, 900)

func _make_sim(segs: Array) -> BallSimulation:
	var sim := BallSimulation.new(_rect, [], _cfg)
	sim.set_wall_segs(segs)
	return sim

func test_funnel_wall_low_bounce():
	# Ball hits left funnel wall (0,780)→(240,900) and barely bounces
	var sim := _make_sim([
		{&"a": Vector2(0, 780), &"b": Vector2(240, 900), &"restitution": 0.05}
	])
	var ball := BallState.new(Vector2(50, 750), Vector2(0, 500), 8.0)
	var events: Array = []
	for _i in 60:
		sim.step(ball, events)
	# After hitting funnel, ball should be deflected toward center (positive x)
	assert_true(ball.vel.x > 0.0, "funnel redirects ball toward center")

func test_gate_closed_blocks_ball():
	# Gate segment at x=0, y=100..140; ball moving left should bounce
	var gate_seg := {&"a": Vector2(0, 100), &"b": Vector2(0, 140), &"restitution": 0.82}
	# Also include left wall above and below gate
	var sim := _make_sim([
		{&"a": Vector2(0, 0), &"b": Vector2(0, 100), &"restitution": 0.82},
		gate_seg,
		{&"a": Vector2(0, 140), &"b": Vector2(0, 900), &"restitution": 0.82},
	])
	var ball := BallState.new(Vector2(50, 120), Vector2(-500, 0), 8.0)
	var events: Array = []
	sim.step(ball, events)
	assert_true(ball.vel.x > 0.0, "gate closed: ball bounces right")

func test_gate_open_ball_passes():
	# Gate is open (gap in wall at y=100..140); ball at y=120 passes through x=0
	var sim := _make_sim([
		{&"a": Vector2(0, 0), &"b": Vector2(0, 100), &"restitution": 0.82},
		# gate segment NOT included — open
		{&"a": Vector2(0, 140), &"b": Vector2(0, 900), &"restitution": 0.82},
	])
	var ball := BallState.new(Vector2(50, 120), Vector2(-500, 0), 8.0)
	var events: Array = []
	sim.step(ball, events)
	# Ball should have crossed x=0 (or be very close without bouncing)
	assert_true(ball.vel.x < 0.0, "gate open: ball continues left")
```

- [ ] **Step 2: Run — verify fail**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gsuffix=test_gate_physics.gd -gexit
```

Expected: FAIL (file not found or tests fail — gate physics not wired yet).

- [ ] **Step 3: Add wall-segment helpers to board_view.gd**

Add these methods after `_make_sim()` in `view/board_view.gd`:

```gdscript
# Wall restitution constant (matches pegs/walls)
const WALL_REST := 0.82
const FUNNEL_REST := 0.05

# Gate local positions (relative to _rect.position)
const _GATE_LOCAL := {
	EntryResolver.BoardEdge.LEFT:  [Vector2(0, 115),   Vector2(0, 155)],
	EntryResolver.BoardEdge.RIGHT: [Vector2(540, 115),  Vector2(540, 155)],
	EntryResolver.BoardEdge.TOP:   [Vector2(195, 0),    Vector2(255, 0)],
}

func _funnel_segs() -> Array:
	var o := _rect.position
	return [
		{&"a": o + Vector2(0, 780),   &"b": o + Vector2(240, 900), &"restitution": FUNNEL_REST},
		{&"a": o + Vector2(540, 780), &"b": o + Vector2(300, 900), &"restitution": FUNNEL_REST},
	]

func _wall_segs_for_edge(edge: int) -> Array:
	# Returns the two wall segments (above and below gate) for one edge
	var o := _rect.position
	var g: Array = _GATE_LOCAL[edge]
	match edge:
		EntryResolver.BoardEdge.LEFT:
			return [
				{&"a": o + Vector2(0, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(0, 780), &"restitution": WALL_REST},
			]
		EntryResolver.BoardEdge.RIGHT:
			return [
				{&"a": o + Vector2(540, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(540, 780), &"restitution": WALL_REST},
			]
		_:  # TOP
			return [
				{&"a": o + Vector2(0, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(540, 0), &"restitution": WALL_REST},
			]

func _gate_seg(edge: int) -> Dictionary:
	var o := _rect.position
	var g: Array = _GATE_LOCAL[edge]
	return {&"a": o + g[0], &"b": o + g[1], &"restitution": WALL_REST}

func _rebuild_wall_segs(close_active_gate: bool) -> void:
	var segs: Array = _funnel_segs()
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		segs.append_array(_wall_segs_for_edge(edge))
		if close_active_gate or edge != _entry_edge:
			segs.append(_gate_seg(edge))
	_sim.set_wall_segs(segs)
```

- [ ] **Step 4: Call `_rebuild_wall_segs` at init and after every `_make_sim`**

In `_ready()`, after `_sim = _make_sim(_pegs)`:
```gdscript
	_rebuild_wall_segs(false)  # active gate open, others closed
```

Find every other call to `_make_sim` in `board_view.gd` (in `_apply_boss_mod`, `_trigger_bomb`, `leave_shop`, portal trigger) and add after each:
```gdscript
	_rebuild_wall_segs(_gate_applied)
```

- [ ] **Step 5: Run test suite**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass including new gate_physics tests.

- [ ] **Step 6: Commit**

```bash
git add view/board_view.gd tests/test_gate_physics.gd
git commit -m "feat: funnel wall segments + gated wall helpers in board_view"
```

---

### Task 5: Gate open/close wired into launch flow

**Files:**
- Modify: `view/board_view.gd`

- [ ] **Step 1: Open gate at launch start**

In `board_view.gd`, find `func launch(ball: BallState) -> void`.  
Add just before `_gate_applied = false`:
```gdscript
	_rebuild_wall_segs(false)  # open active gate for new ball
```

- [ ] **Step 2: Close gate when ball crosses threshold**

In `_process`, find the block:
```gdscript
				if crossed:
					_active_balls = _gate_chain.process(b)
					_gate_applied = true
```

Add after `_gate_applied = true`:
```gdscript
					_rebuild_wall_segs(true)  # seal gate
```

- [ ] **Step 3: Run full suite**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add view/board_view.gd
git commit -m "feat: gate opens on launch, closes on ball entry"
```

---

### Task 6: Fixed launcher positions + dual control

**Files:**
- Modify: `sim/entry_resolver.gd`
- Modify: `view/input_controller.gd`

- [ ] **Step 1: Add launcher constants to entry_resolver.gd**

After the `BoardEdge` enum, add:

```gdscript
# Fixed t values for each launcher gate center
const LAUNCHER_T := {
	BoardEdge.LEFT:  0.150,   # local y=135 / 900
	BoardEdge.RIGHT: 0.150,
	BoardEdge.TOP:   0.417,   # local x=225 / 540
}

# Launcher canvas positions (fixed; outside _rect)
const LAUNCHER_POS := {
	BoardEdge.LEFT:  Vector2(55.0, 255.0),
	BoardEdge.TOP:   Vector2(405.0, 112.0),
	BoardEdge.RIGHT: Vector2(755.0, 255.0),
}
```

- [ ] **Step 2: Rewrite input_controller.gd `_process`**

Replace the existing `_process` method entirely:

```gdscript
func _process(delta: float) -> void:
	if _board._has_ball:
		_board.prediction_pts.clear()
		_board.prediction_fans.clear()
		return

	var r: Rect2 = _board.rect
	var t: float = EntryResolver.LAUNCHER_T[_edge]
	var entry: Dictionary = EntryResolver.resolve(_edge, t, r)
	var gate_pos: Vector2 = entry[&"pos"]
	var inward_n: Vector2 = entry[&"normal"]

	# Mouse sets aim angle (angle from inward normal to mouse direction)
	var mouse: Vector2 = _board.get_local_mouse_position()
	var to_mouse := mouse - gate_pos
	if to_mouse.length_squared() > 1.0:
		_aim = inward_n.angle_to(to_mouse.normalized())

	# A/D fine-tunes
	if Input.is_key_pressed(KEY_A):
		_aim -= deg_to_rad(90.0) * delta
	if Input.is_key_pressed(KEY_D):
		_aim += deg_to_rad(90.0) * delta

	_aim = clampf(_aim, -PI / 3.0, PI / 3.0)

	_board.set_entry(_edge, t)

	var start := EntryResolver.make_ball(_edge, t, _aim, SPEED, BALL_RADIUS, r)
	var axis: int = _board.gate_axis()
	var threshold: float = _board.gate_threshold()
	var pre := TrajectoryPredictor.predict_to_gate(_board.sim, start, axis, threshold, 30)
	_board.prediction_pts = pre[&"pts"]

	var gate_ball: BallState = pre[&"ball"]
	_board.prediction_fans.clear()
	var gate_def: GateDef = _board.active_gate_def
	match gate_def.kind:
		GateDef.Kind.ACCEL:
			var fast := BallState.new(gate_ball.pos, gate_ball.vel * gate_def.speed_mul, gate_ball.radius)
			_board.prediction_fans = [TrajectoryPredictor.predict(_board.sim, fast, 60)]
		GateDef.Kind.SCATTER_ANGLE:
			_board.prediction_fans = TrajectoryPredictor.predict_fan(
				_board.sim, gate_ball, gate_def.scatter_angle, 5, 60)
		GateDef.Kind.SCATTER_SPLIT:
			for k in gate_def.split_count:
				var frac := float(k) / maxf(gate_def.split_count - 1, 1) - 0.5
				var nb := BallState.new(gate_ball.pos,
										gate_ball.vel.rotated(frac * gate_def.scatter_angle),
										gate_ball.radius)
				_board.prediction_fans.append(TrajectoryPredictor.predict(_board.sim, nb, 60))
		_:
			_board.prediction_fans = [TrajectoryPredictor.predict(_board.sim, gate_ball.clone(), 60)]
```

- [ ] **Step 3: Add Space key to fire in `_unhandled_input`**

Find the existing `InputEventMouseButton` block and add before it:

```gdscript
	if event is InputEventKey and event.pressed:
		# ... existing key handling ...
		# ADD inside the match block, after KEY_TAB:
		# (Space fires only during ROUND/BOSS_ROUND, same guard as mouse click)
```

Find the `match event.keycode:` block and add a new branch:

```gdscript
			KEY_SPACE:
				if RunMan.state[&"phase"] == RunManager.Phase.ROUND or \
				   RunMan.state[&"phase"] == RunManager.Phase.BOSS_ROUND:
					var rr: Rect2 = _board.rect
					var t2: float = EntryResolver.LAUNCHER_T[_edge]
					_board.launch(EntryResolver.make_ball(_edge, t2, _aim, SPEED, BALL_RADIUS, rr))
```

Also update the existing mouse click launch to use fixed `t`:

Old:
```gdscript
			_board.launch(EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r))
```
New:
```gdscript
			var rr: Rect2 = _board.rect
			var t3: float = EntryResolver.LAUNCHER_T[_edge]
			_board.launch(EntryResolver.make_ball(_edge, t3, _aim, SPEED, BALL_RADIUS, rr))
```

- [ ] **Step 4: Run full suite**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add sim/entry_resolver.gd view/input_controller.gd
git commit -m "feat: fixed launcher positions, A/D rotation, Space-to-fire"
```

---

### Task 7: Draw updates — walls, funnel, gates, channels, launcher indicator

**Files:**
- Modify: `view/board_view.gd`

No unit tests — visually verify by running the game.

- [ ] **Step 1: Add `_draw_walls()` method**

Add after `_draw_gate()` in `board_view.gd`:

```gdscript
func _draw_walls() -> void:
	var cyan   := Color(0.0, 0.9, 1.0, 0.9)
	var g_open := Color(0.0, 1.0, 0.5, 0.9)
	var orange := Color(1.0, 0.55, 0.0, 0.9)
	var o := _rect.position

	# Draw each edge wall (two segments around its gate)
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		var segs: Array = _wall_segs_for_edge(edge)
		for seg in segs:
			draw_line(seg[&"a"], seg[&"b"], cyan, 2.5)

	# Draw funnel walls
	draw_line(o + Vector2(0, 780),   o + Vector2(240, 900), orange, 2.5)
	draw_line(o + Vector2(540, 780), o + Vector2(300, 900), orange, 2.5)

	# Draw gates (green=open, cyan=closed)
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		var is_open: bool = (edge == _entry_edge and not _gate_applied)
		var col := g_open if is_open else cyan
		var seg := _gate_seg(edge)
		draw_line(seg[&"a"], seg[&"b"], col, 3.0)

	# Draw channel lines (visual only) for active launcher
	var lp: Vector2 = EntryResolver.LAUNCHER_POS[_entry_edge]
	var glocal: Array = _GATE_LOCAL[_entry_edge]
	draw_line(o + glocal[0], lp, Color(cyan, 0.4), 1.5)
	draw_line(o + glocal[1], lp, Color(cyan, 0.4), 1.5)

	# Draw launcher indicator (crosshair circle)
	draw_circle(lp, 8.0, Color(1.0, 0.3, 1.0, 0.9))
	draw_circle(lp, 5.0, Color(0.1, 0.0, 0.15, 1.0))
```

- [ ] **Step 2: Replace `_draw_gate()` call in `_draw()` with `_draw_walls()`**

Old:
```gdscript
	if not _has_ball:
		_draw_gate()
```
New:
```gdscript
	_draw_walls()
```

(Walls are always drawn regardless of ball state; gate color changes based on `_gate_applied`.)

- [ ] **Step 3: Run the game and verify visually**

```
D:/Program/Godot/godot.exe --path D:/NeonPinball/game
```

Check:
- Left, right, top walls visible in cyan
- Orange funnel walls at bottom
- Active launcher: green gate (open), other two: cyan gates (closed)
- After launching: active gate turns cyan
- Short channel lines and launcher indicator visible

- [ ] **Step 4: Run full test suite**

```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```

Expected: all ~174 tests pass.

- [ ] **Step 5: Commit**

```bash
git add view/board_view.gd
git commit -m "feat: draw boundary walls, funnel, gate open/close visual, channel + launcher indicator"
```

---

## Self-Review

**Spec coverage:**
- ✅ swept_segment physics (Task 1)
- ✅ wall_segs in BallSimulation (Task 2)
- ✅ Board rect repositioning / honeycomb fix (Task 3)
- ✅ Funnel wall segments, restitution 0.05 (Task 4)
- ✅ Gate open on launch, close on ball entry (Task 5)
- ✅ Fixed launcher positions, mouse angle, A/D rotation, Space fire (Task 6)
- ✅ Draw walls/funnel/gates/channels/launcher (Task 7)
- ✅ Ball recycling: no change needed (existing `alive=false` logic unchanged)
- ✅ Future/Phase 2 (channel ball-travel) documented in spec, not in plan

**No placeholders found.**

**Type consistency:** `_gate_seg()` returns `Dictionary` matching `_wall_segs` element shape `{a, b, restitution}`. `_wall_segs_for_edge()` returns `Array[Dictionary]`. `set_wall_segs()` takes `Array`. All consistent.

---

> **Future / Phase 2:** If the visual channel feels disconnected, upgrade to Option 2: ball spawns at launcher position, channel walls added to `_wall_segs` while gate is open. Requires handling out-of-rect ball start (single-sided wall flag or delayed rect activation).
