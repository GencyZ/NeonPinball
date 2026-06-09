# 里程碑 1：弹球物理原型（go/no-go）GDScript 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出一个可玩原型——从三条边任意位置瞄准、看预测线、发射一颗确定性弹球在钉阵中弹跳、累计基础分——验证"发射手感"是否成立。

**Architecture:** 纯 GDScript 确定性模拟层（`sim/` 目录，只用 Godot 内置 Vector2，不操作节点树）+ Godot 渲染层（`view/` 目录，读模拟状态做插值与输入）+ GUT 单元测试（`tests/` 目录，headless 运行）。模拟与渲染严格分离：关掉渲染逻辑结果不变。

**Tech Stack:** Godot 4.x（**标准版**，非 .NET 版）、GDScript、GUT 9.x（Godot 4 单测框架）、Git。

**配套文档：** 设计 `2026-06-09-neon-pinball-roguelike-deckbuilder-design.md`；技术 `2026-06-09-neon-pinball-tech-design-gdscript.md`（§5 物理 / §8 计分）。

**里程碑 1 不含**：门/触发器/球种/商店/区轮/随机。只做：确定性单球物理 + 三边入口 + 瞄准 + 预测线 + 每钉基础分 + 命中闪光。

---

## 文件结构

```
D:/NeonPinball/game/               ← Godot 项目根
  project.godot                    ← Godot 创建，勿手写
  .gutconfig.json                  ← GUT headless 配置
  addons/gut/                      ← GUT 插件（从 AssetLib 安装）
  sim/
    ball_state.gd                  ← BallState class（含 clone()）
    sim_event.gd                   ← 事件 StringName 常量 + 工厂函数
    collision.gd                   ← swept_circle / swept_walls / reflect（静态）
    peg_grid.gd                    ← 宽相位空间网格
    ball_simulation.gd             ← 定步长 CCD 步进 + 事件产出
    entry_resolver.gd              ← (edge,t)+瞄准 → BallState
    trajectory_predictor.gd        ← 无渲染前瞻 → 预测线点列
    scorer.gd                      ← 从事件流累计基础分
  tests/
    test_smoke.gd                  ← GUT 冒烟（验证框架可用）
    test_collision.gd
    test_peg_grid.gd
    test_ball_simulation.gd
    test_entry_resolver.gd
    test_trajectory_predictor.gd
    test_scorer.gd
    test_determinism.gd
  view/
    board_view.gd                  ← Node2D：主循环 + accumulator + 插值绘制
    input_controller.gd            ← 鼠标 → 入口/瞄准/预测线/发射
    hud.gd                         ← CanvasLayer：分数标签
  scenes/
    board.tscn                     ← 主场景（Godot 编辑器创建）
```

> **约定**：`class_name` 让所有 `sim/` 脚本全局可用，无需 `preload()`。`Vector2` 全程用 Godot 内置，无需在边界转换（GDScript 优势之一）。

---

## Task -1：环境准备（开工前一次性）

**Files:** 无（安装与目录约定）

- [ ] **Step 1：安装 Godot 4.x 标准版**

  下载页：https://godotengine.org/download/ → 选 **Godot 4.x（标准版，不带 .NET）**。
  建议固定版本（如 4.4），解压到固定目录（如 `D:\Tools\Godot_4.4\`），把可执行文件目录加入 PATH：

  ```
  PATH 添加：D:\Tools\Godot_4.4\
  ```

  验证安装：
  ```bash
  godot --version
  ```
  Expected: `4.4.stable` 或类似（**不应含 `mono`**，那是 .NET 版）。

- [ ] **Step 2：在 Godot 编辑器创建项目**

  打开 Godot，Project → New Project：
  - Project Name: `NeonPinball`
  - Project Path: `D:/NeonPinball/game`
  - Renderer: 2D（Forward+）
  - Version Control: 勿勾（Git 已在上级目录管理）

  点 Create & Edit，编辑器打开后**不做任何其他操作**，关闭编辑器。

  验证：
  ```bash
  ls D:/NeonPinball/game/project.godot
  ```
  Expected: 文件存在。

- [ ] **Step 3：安装 GUT 插件**

  在 Godot 编辑器：AssetLib 标签页 → 搜索 **"GUT"** → 选 *GUT - Godot Unit Testing*（作者 bitwes）→ Download → Install。

  安装完毕后在 Project → Project Settings → Plugins 里启用 GUT。

  备用（手动安装）：下载 https://github.com/bitwes/Gut/releases/latest 的 zip，解压后将 `addons/gut/` 复制到 `D:/NeonPinball/game/addons/gut/`。

  验证：
  ```bash
  ls D:/NeonPinball/game/addons/gut/gut_cmdln.gd
  ```
  Expected: 文件存在。

- [ ] **Step 4：创建目录结构**

  ```bash
  cd D:/NeonPinball/game
  mkdir -p sim tests view scenes
  ```

- [ ] **Step 5：创建 GUT headless 配置**

  `D:/NeonPinball/game/.gutconfig.json`:
  ```json
  {
    "dirs": ["res://tests/"],
    "prefix": "test_",
    "should_exit": true,
    "log_level": 1
  }
  ```

---

## Task 0：GUT 冒烟测试（验证工具链）

**Files:**
- Create: `game/tests/test_smoke.gd`

- [ ] **Step 1：写冒烟测试**

  `game/tests/test_smoke.gd`:
  ```gdscript
  extends GutTest

  func test_gut_works() -> void:
      assert_eq(1 + 1, 2, "GUT is working")

  func test_vector2_built_in() -> void:
      var v := Vector2(1, 0).rotated(PI / 2)
      assert_almost_eq(v.x, 0.0, 1e-4, "rotated x")
      assert_almost_eq(v.y, 1.0, 1e-4, "rotated y")
  ```

- [ ] **Step 2：headless 跑测试**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd
  ```
  Expected:
  ```
  All tests passed.  2 passed, 0 failed
  ```

- [ ] **Step 3：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/
  git commit -m "chore(game): Godot project + GUT smoke test"
  ```

---

## Task 1：数据结构（BallState + SimEvent）

**Files:**
- Create: `game/sim/ball_state.gd`
- Create: `game/sim/sim_event.gd`
- Create: `game/tests/test_ball_state.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_ball_state.gd`:
  ```gdscript
  extends GutTest

  func test_ball_state_init() -> void:
      var b := BallState.new(Vector2(10, 20), Vector2(1, 2), 5.0)
      assert_eq(b.pos, Vector2(10, 20), "pos set")
      assert_eq(b.vel, Vector2(1, 2), "vel set")
      assert_almost_eq(b.radius, 5.0, 1e-6, "radius set")
      assert_eq(b.bounce_count, 0, "bounce_count starts 0")
      assert_true(b.alive, "alive starts true")

  func test_ball_state_clone_is_independent() -> void:
      var a := BallState.new(Vector2(1, 2), Vector2(3, 4), 5.0)
      var b := a.clone()
      b.pos = Vector2(99, 99)
      assert_eq(a.pos, Vector2(1, 2), "original pos unchanged after clone mutation")

  func test_sim_event_peg_hit() -> void:
      var e := SimEvent.peg_hit(3, Vector2(10, 20))
      assert_eq(e[&"type"], SimEvent.PEG_HIT, "type is PEG_HIT")
      assert_eq(e[&"peg_id"], 3, "peg_id correct")
      assert_eq(e[&"pos"], Vector2(10, 20), "pos correct")

  func test_sim_event_non_peg_has_minus_one_id() -> void:
      var e := SimEvent.bounce(Vector2.ZERO)
      assert_eq(e[&"peg_id"], -1, "non-peg events have peg_id -1")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_ball_state.gd -gexit
  ```
  Expected: FAIL（`BallState`/`SimEvent` 不存在）

- [ ] **Step 3：实现 BallState**

  `game/sim/ball_state.gd`:
  ```gdscript
  class_name BallState

  var pos: Vector2
  var vel: Vector2
  var radius: float
  var bounce_count: int
  var alive: bool

  func _init(p: Vector2, v: Vector2, r: float) -> void:
      pos = p; vel = v; radius = r
      bounce_count = 0; alive = true

  func clone() -> BallState:
      var b := BallState.new(pos, vel, radius)
      b.bounce_count = bounce_count
      b.alive = alive
      return b
  ```

- [ ] **Step 4：实现 SimEvent**

  `game/sim/sim_event.gd`:
  ```gdscript
  class_name SimEvent

  const LAUNCH   := &"launch"
  const PEG_HIT  := &"peg_hit"
  const BOUNCE   := &"bounce"
  const WALL_HIT := &"wall_hit"
  const SETTLED  := &"ball_settled"

  static func peg_hit(id: int, p: Vector2) -> Dictionary:
      return {&"type": PEG_HIT, &"peg_id": id, &"pos": p}

  static func bounce(p: Vector2) -> Dictionary:
      return {&"type": BOUNCE, &"peg_id": -1, &"pos": p}

  static func wall_hit(p: Vector2) -> Dictionary:
      return {&"type": WALL_HIT, &"peg_id": -1, &"pos": p}

  static func settled(p: Vector2) -> Dictionary:
      return {&"type": SETTLED, &"peg_id": -1, &"pos": p}

  static func launch(p: Vector2) -> Dictionary:
      return {&"type": LAUNCH, &"peg_id": -1, &"pos": p}
  ```

- [ ] **Step 5：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_ball_state.gd -gexit
  ```
  Expected: `4 passed, 0 failed`

- [ ] **Step 6：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/ball_state.gd game/sim/sim_event.gd game/tests/test_ball_state.gd
  git commit -m "feat(sim): BallState class + SimEvent factories"
  ```

---

## Task 2：圆-圆扫掠碰撞（swept_circle）

**Files:**
- Create: `game/sim/collision.gd`
- Create: `game/tests/test_collision.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_collision.gd`:
  ```gdscript
  extends GutTest

  func test_swept_circle_head_on() -> void:
      # p=(0,0) 沿 d=(10,0) 运动，目标圆心 c=(10,0)，合半径 R=5
      # → m=(-10,0), a=100, b=-200, cc=75, disc=10000, root=0.5
      var t := Collision.swept_circle(Vector2.ZERO, Vector2(10, 0), Vector2(10, 0), 5.0)
      assert_almost_eq(t, 0.5, 1e-4, "head-on hit at t=0.5")

  func test_swept_circle_miss_offside() -> void:
      var t := Collision.swept_circle(Vector2.ZERO, Vector2(10, 0), Vector2(5, 100), 5.0)
      assert_eq(t, -1.0, "should miss when target is far off-axis")

  func test_swept_circle_too_short() -> void:
      # 位移长度 1，但目标在距离 5 处 → root=5 > 1 → miss
      var t := Collision.swept_circle(Vector2.ZERO, Vector2(1, 0), Vector2(10, 0), 5.0)
      assert_eq(t, -1.0, "should miss when displacement too short")

  func test_swept_circle_already_overlapping() -> void:
      # 已重叠（球心距 < R），root 为负 → miss（避免重复碰撞）
      var t := Collision.swept_circle(Vector2(9, 0), Vector2(1, 0), Vector2(10, 0), 5.0)
      assert_eq(t, -1.0, "already overlapping, root negative → miss")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_collision.gd -gexit
  ```
  Expected: FAIL（`Collision` 不存在）

- [ ] **Step 3：实现 swept_circle**

  `game/sim/collision.gd`:
  ```gdscript
  class_name Collision

  # 圆-圆扫掠 TOI：点 p 沿位移 d，与以 c 为心合半径 R 的圆求最早交叉。
  # 命中返回 t∈[0,1]，否则返回 -1。
  static func swept_circle(p: Vector2, d: Vector2, c: Vector2, R: float) -> float:
      var m := p - c
      var a := d.dot(d)
      if a < 1e-12:
          return -1.0
      var b := 2.0 * m.dot(d)
      var cc := m.dot(m) - R * R
      var disc := b * b - 4.0 * a * cc
      if disc < 0.0:
          return -1.0
      var root := (-b - sqrt(disc)) / (2.0 * a)
      if root < 0.0 or root > 1.0:
          return -1.0
      return root
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_collision.gd -gexit
  ```
  Expected: `4 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/collision.gd game/tests/test_collision.gd
  git commit -m "feat(sim): swept circle-circle TOI"
  ```

---

## Task 3：轴对齐墙 TOI + 反射

**Files:**
- Modify: `game/sim/collision.gd`（追加两个静态函数）
- Modify: `game/tests/test_collision.gd`（追加测试）

- [ ] **Step 1：追加失败测试**

  在 `game/tests/test_collision.gd` 末尾追加：
  ```gdscript
  func test_swept_walls_right_wall() -> void:
      # 球在 x=4，沿 +x 走 d.x=10，半径 1
      # 右墙有效线 x = rect.end.x - r = 10 - 1 = 9 → t = (9-4)/10 = 0.5
      var rect := Rect2(0, 0, 10, 100)
      var result := Collision.swept_walls(Vector2(4, 50), Vector2(10, 0), 1.0, rect)
      assert_false(result.is_empty(), "should hit right wall")
      assert_almost_eq(result[&"t"], 0.5, 1e-4, "right wall at t=0.5")
      assert_eq(result[&"normal"], Vector2(-1, 0), "normal points left")

  func test_swept_walls_top_wall() -> void:
      # 球在 y=5，沿 -y 走 d.y=-10，半径 1
      # 顶墙有效线 y = rect.position.y + r = 0 + 1 = 1 → t = (1-5)/(-10) = 0.4
      var rect := Rect2(0, 0, 100, 100)
      var result := Collision.swept_walls(Vector2(50, 5), Vector2(0, -10), 1.0, rect)
      assert_false(result.is_empty(), "should hit top wall")
      assert_almost_eq(result[&"t"], 0.4, 1e-4, "top wall at t=0.4")
      assert_eq(result[&"normal"], Vector2(0, 1), "normal points down")

  func test_swept_walls_no_bottom_wall() -> void:
      # 底部开口，球向下穿出不应命中
      var rect := Rect2(0, 0, 100, 100)
      var result := Collision.swept_walls(Vector2(50, 95), Vector2(0, 10), 1.0, rect)
      assert_true(result.is_empty(), "bottom is open, no hit")

  func test_reflect_off_right_wall() -> void:
      # 速度 (3, 2) 撞右墙法线 (-1,0)，完全弹性
      var v := Collision.reflect(Vector2(3, 2), Vector2(-1, 0), 1.0, 1.0)
      assert_almost_eq(v.x, -3.0, 1e-4, "x component flipped")
      assert_almost_eq(v.y, 2.0, 1e-4, "y component unchanged")

  func test_reflect_with_restitution() -> void:
      # restitution=0.8，法向分量乘以 0.8
      var v := Collision.reflect(Vector2(0, 4), Vector2(0, -1), 0.8, 1.0)
      assert_almost_eq(v.y, -3.2, 1e-4, "normal component scaled by restitution")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_collision.gd -gexit
  ```
  Expected: FAIL（`swept_walls`/`reflect` 不存在）

- [ ] **Step 3：追加实现**

  在 `game/sim/collision.gd` 的 `class_name Collision` 声明之后追加：
  ```gdscript
  # 轴对齐三墙（左/右/顶；底部开口，球从底部落出）。
  # 返回最早命中的 {t, normal}，无命中返回 {}。
  static func swept_walls(p: Vector2, d: Vector2, r: float, rect: Rect2) -> Dictionary:
      var best_t := INF
      var best_n := Vector2.ZERO
      var found := false

      if d.x < 0.0:
          var t := (rect.position.x + r - p.x) / d.x
          if t >= 0.0 and t <= 1.0 and t < best_t:
              best_t = t; best_n = Vector2(1, 0); found = true
      if d.x > 0.0:
          var t := (rect.end.x - r - p.x) / d.x
          if t >= 0.0 and t <= 1.0 and t < best_t:
              best_t = t; best_n = Vector2(-1, 0); found = true
      if d.y < 0.0:
          var t := (rect.position.y + r - p.y) / d.y
          if t >= 0.0 and t <= 1.0 and t < best_t:
              best_t = t; best_n = Vector2(0, 1); found = true

      if not found:
          return {}
      return {&"t": best_t, &"normal": best_n}

  # 弹性反射：restitution 控制法向保留，tangent_keep 控制切向保留。
  static func reflect(v: Vector2, n: Vector2, restitution: float, tangent_keep: float) -> Vector2:
      var vn := v.dot(n) * n
      var vt := v - vn
      return vt * tangent_keep - vn * restitution
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_collision.gd -gexit
  ```
  Expected: `9 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/collision.gd game/tests/test_collision.gd
  git commit -m "feat(sim): axis-aligned wall TOI + reflection"
  ```

---

## Task 4：宽相位空间网格（PegGrid）

**Files:**
- Create: `game/sim/peg_grid.gd`
- Create: `game/tests/test_peg_grid.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_peg_grid.gd`:
  ```gdscript
  extends GutTest

  func _make_pegs() -> Array:
      return [
          {&"id": 0, &"pos": Vector2(10, 10), &"radius": 5.0, &"base_score": 1.0},
          {&"id": 1, &"pos": Vector2(500, 500), &"radius": 5.0, &"base_score": 1.0},
      ]

  func test_query_returns_near_not_far() -> void:
      var grid := PegGrid.new()
      grid.build(_make_pegs(), Rect2(0, 0, 600, 600), 50.0)
      var near := grid.query_near(Vector2(12, 12), 20.0)
      assert_true(0 in near, "peg 0 should be near (12,12)")
      assert_false(1 in near, "peg 1 at (500,500) should be far")

  func test_query_sorted_ascending() -> void:
      var pegs := [
          {&"id": 0, &"pos": Vector2(25, 25), &"radius": 5.0, &"base_score": 1.0},
          {&"id": 1, &"pos": Vector2(30, 25), &"radius": 5.0, &"base_score": 1.0},
          {&"id": 2, &"pos": Vector2(35, 25), &"radius": 5.0, &"base_score": 1.0},
      ]
      var grid := PegGrid.new()
      grid.build(pegs, Rect2(0, 0, 200, 200), 50.0)
      var near := grid.query_near(Vector2(30, 25), 30.0)
      assert_eq(near.size(), 3, "all three pegs in range")
      assert_eq(near[0], 0, "sorted: id 0 first")
      assert_eq(near[1], 1, "sorted: id 1 second")
      assert_eq(near[2], 2, "sorted: id 2 third")

  func test_query_empty_when_no_pegs_nearby() -> void:
      var grid := PegGrid.new()
      grid.build(_make_pegs(), Rect2(0, 0, 600, 600), 50.0)
      var near := grid.query_near(Vector2(300, 300), 10.0)
      assert_eq(near.size(), 0, "no pegs near center")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_peg_grid.gd -gexit
  ```
  Expected: FAIL

- [ ] **Step 3：实现 PegGrid**

  `game/sim/peg_grid.gd`:
  ```gdscript
  class_name PegGrid

  var _rect: Rect2
  var _cell: float
  var _cols: int
  var _rows: int
  var _cells: Array  # Array of Array[int]（pegId 列表）

  func build(pegs: Array, rect: Rect2, cell_size: float) -> void:
      _rect = rect; _cell = cell_size
      _cols = maxi(1, ceili(rect.size.x / cell_size))
      _rows = maxi(1, ceili(rect.size.y / cell_size))
      _cells.resize(_cols * _rows)
      for i in _cells.size():
          _cells[i] = []
      for peg in pegs:
          var cx := clampi(int((peg[&"pos"].x - rect.position.x) / cell_size), 0, _cols - 1)
          var cy := clampi(int((peg[&"pos"].y - rect.position.y) / cell_size), 0, _rows - 1)
          _cells[cy * _cols + cx].append(peg[&"id"])

  # 返回 center 附近 radius 范围格子内的 peg_id，按 id 升序（保证确定性遍历）。
  func query_near(center: Vector2, radius: float) -> Array[int]:
      var result: Array[int] = []
      var min_cx := clampi(int((center.x - radius - _rect.position.x) / _cell), 0, _cols - 1)
      var max_cx := clampi(int((center.x + radius - _rect.position.x) / _cell), 0, _cols - 1)
      var min_cy := clampi(int((center.y - radius - _rect.position.y) / _cell), 0, _rows - 1)
      var max_cy := clampi(int((center.y + radius - _rect.position.y) / _cell), 0, _rows - 1)
      for cy in range(min_cy, max_cy + 1):
          for cx in range(min_cx, max_cx + 1):
              for id in _cells[cy * _cols + cx]:
                  result.append(id)
      result.sort()   # 确定遍历顺序，不依赖 Dictionary 哈希序
      return result
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_peg_grid.gd -gexit
  ```
  Expected: `4 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/peg_grid.gd game/tests/test_peg_grid.gd
  git commit -m "feat(sim): broadphase spatial grid"
  ```

---

## Task 5：弹球模拟步进（BallSimulation）

**Files:**
- Create: `game/sim/ball_simulation.gd`
- Create: `game/tests/test_ball_simulation.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_ball_simulation.gd`:
  ```gdscript
  extends GutTest

  func _make_sim(pegs: Array) -> BallSimulation:
      var rect := Rect2(0, 0, 200, 400)
      var cfg := {
          &"gravity": Vector2(0, 500),
          &"max_speed": 2000.0,
          &"restitution": 0.8,
          &"tangent_keep": 1.0,
          &"dt": 1.0 / 120.0,
      }
      return BallSimulation.new(rect, pegs, cfg)

  func test_ball_falls_and_settles() -> void:
      var sim := _make_sim([])
      var ball := BallState.new(Vector2(100, 10), Vector2.ZERO, 5.0)
      var events: Array = []
      for _i in 600:
          if not ball.alive: break
          sim.step(ball, events)
      assert_false(ball.alive, "ball should become inactive after settling")
      var settled := events.filter(func(e): return e[&"type"] == SimEvent.SETTLED)
      assert_gt(settled.size(), 0, "SETTLED event must be emitted")

  func test_ball_hits_peg_directly_above() -> void:
      var pegs := [{&"id": 0, &"pos": Vector2(100, 100), &"radius": 8.0, &"base_score": 5.0}]
      var sim := _make_sim(pegs)
      var ball := BallState.new(Vector2(100, 10), Vector2.ZERO, 5.0)
      var events: Array = []
      for _i in 600:
          if not ball.alive: break
          sim.step(ball, events)
      var peg_hits := events.filter(func(e): return e[&"type"] == SimEvent.PEG_HIT and e[&"peg_id"] == 0)
      assert_gt(peg_hits.size(), 0, "should emit PEG_HIT for peg 0")

  func test_no_tunneling_at_high_speed() -> void:
      # 高初速（3000px/s），单步位移远超钉直径；CCD 必须仍能命中
      var pegs := [{&"id": 0, &"pos": Vector2(100, 200), &"radius": 8.0, &"base_score": 5.0}]
      var sim := _make_sim(pegs)
      var ball := BallState.new(Vector2(100, 10), Vector2(0, 3000), 5.0)
      var events: Array = []
      for _i in 600:
          if not ball.alive: break
          sim.step(ball, events)
      var hits := events.filter(func(e): return e[&"type"] == SimEvent.PEG_HIT and e[&"peg_id"] == 0)
      assert_gt(hits.size(), 0, "CCD must catch high-speed ball")

  func test_bounce_event_emitted_on_wall() -> void:
      var sim := _make_sim([])
      # 球从左侧向左运动，必然碰左墙产生 WALL_HIT + BOUNCE
      var ball := BallState.new(Vector2(5, 200), Vector2(-500, 0), 5.0)
      var events: Array = []
      for _i in 30:
          if not ball.alive: break
          sim.step(ball, events)
      var wall_hits := events.filter(func(e): return e[&"type"] == SimEvent.WALL_HIT)
      assert_gt(wall_hits.size(), 0, "wall hit event emitted")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_ball_simulation.gd -gexit
  ```
  Expected: FAIL（`BallSimulation` 不存在）

- [ ] **Step 3：实现 BallSimulation**

  `game/sim/ball_simulation.gd`:
  ```gdscript
  class_name BallSimulation

  const MAX_BOUNCES_PER_STEP := 8
  const EPSILON := 1e-5

  var _rect: Rect2
  var _pegs: Array
  var _grid: PegGrid
  var _cfg: Dictionary

  func _init(rect: Rect2, pegs: Array, cfg: Dictionary) -> void:
      _rect = rect; _pegs = pegs; _cfg = cfg
      _grid = PegGrid.new()
      _grid.build(pegs, rect, 50.0)

  # 推进一个固定步；产出事件追加到 out_events。
  func step(ball: BallState, out_events: Array) -> void:
      if not ball.alive:
          return
      # 半隐式欧拉积分 + 限速
      ball.vel += _cfg[&"gravity"] * _cfg[&"dt"]
      var speed := ball.vel.length()
      if speed > _cfg[&"max_speed"]:
          ball.vel = ball.vel * (_cfg[&"max_speed"] / speed)
      # CCD 步进
      _integrate_ccd(ball, out_events, _cfg[&"dt"])
      # 底部开口：球心超出底边 → 落袋
      if ball.pos.y - ball.radius > _rect.end.y:
          ball.alive = false
          out_events.append(SimEvent.settled(ball.pos))

  func _integrate_ccd(ball: BallState, out_events: Array, dt: float) -> void:
      var remaining := dt
      var guard := 0
      while remaining > EPSILON and guard < MAX_BOUNCES_PER_STEP:
          guard += 1
          var d := ball.vel * remaining
          var hit := _find_earliest(ball.pos, d, ball.radius)
          if hit.is_empty():
              ball.pos += d
              break
          ball.pos += d * hit[&"t"]
          if hit[&"peg_id"] >= 0:
              out_events.append(SimEvent.peg_hit(hit[&"peg_id"], ball.pos))
          else:
              out_events.append(SimEvent.wall_hit(ball.pos))
          out_events.append(SimEvent.bounce(ball.pos))
          ball.vel = Collision.reflect(
              ball.vel, hit[&"normal"], _cfg[&"restitution"], _cfg[&"tangent_keep"])
          ball.bounce_count += 1
          remaining *= (1.0 - hit[&"t"])

  # 求本段位移内最早碰撞（TOI 最小；同 TOI 按 peg_id 升序决胜）。
  func _find_earliest(p: Vector2, d: Vector2, r: float) -> Dictionary:
      var best := {}
      var best_t := INF
      var search_r := d.length() + r + 32.0
      for peg_id in _grid.query_near(p, search_r):
          var peg: Dictionary = _pegs[peg_id]
          var t := Collision.swept_circle(p, d, peg[&"pos"], r + peg[&"radius"])
          if t >= 0.0:
              if t < best_t or (is_equal_approx(t, best_t) and peg_id < best.get(&"peg_id", INF)):
                  best_t = t
                  var contact := p + d * t
                  best = {&"t": t, &"peg_id": peg_id,
                          &"normal": (contact - peg[&"pos"]).normalized()}
      var wall := Collision.swept_walls(p, d, r, _rect)
      if not wall.is_empty() and wall[&"t"] < best_t:
          best = {&"t": wall[&"t"], &"peg_id": -1, &"normal": wall[&"normal"]}
      return best
  ```

  > **注意**：`_pegs` 以 `id` 作为数组下标，因此建棋盘时必须保证 `peg[&"id"] == 数组索引`。

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_ball_simulation.gd -gexit
  ```
  Expected: `4 passed, 0 failed`（含高速无隧穿）

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/ball_simulation.gd game/tests/test_ball_simulation.gd
  git commit -m "feat(sim): fixed-step CCD ball simulation with events"
  ```

---

## Task 6：入口解析（EntryResolver）

**Files:**
- Create: `game/sim/entry_resolver.gd`
- Create: `game/tests/test_entry_resolver.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_entry_resolver.gd`:
  ```gdscript
  extends GutTest

  const RECT := Rect2(0, 0, 200, 400)

  func test_top_edge_mid_pos_and_normal() -> void:
      var r := EntryResolver.resolve(EntryResolver.BoardEdge.TOP, 0.5, RECT)
      assert_eq(r[&"pos"], Vector2(100, 0), "top edge mid → pos at (100,0)")
      assert_eq(r[&"normal"], Vector2.DOWN, "top normal points down")

  func test_right_edge_quarter() -> void:
      var r := EntryResolver.resolve(EntryResolver.BoardEdge.RIGHT, 0.25, RECT)
      assert_eq(r[&"pos"], Vector2(200, 100), "right edge t=0.25 → (200,100)")
      assert_eq(r[&"normal"], Vector2.LEFT, "right normal points left")

  func test_left_edge_three_quarter() -> void:
      var r := EntryResolver.resolve(EntryResolver.BoardEdge.LEFT, 0.75, RECT)
      assert_eq(r[&"pos"], Vector2(0, 300), "left edge t=0.75 → (0,300)")
      assert_eq(r[&"normal"], Vector2.RIGHT, "left normal points right")

  func test_make_ball_zero_aim_points_inward() -> void:
      var ball := EntryResolver.make_ball(
          EntryResolver.BoardEdge.TOP, 0.5, 0.0, 100.0, 5.0, RECT)
      assert_almost_eq(ball.vel.x, 0.0, 1e-3, "zero aim → no lateral drift")
      assert_gt(ball.vel.y, 0.0, "velocity points into board (down)")
      assert_almost_eq(ball.vel.length(), 100.0, 1e-3, "speed == 100")

  func test_make_ball_clamps_extreme_aim() -> void:
      # aim_offset = 999 应被夹紧到 ±80°（±1.396 rad）
      var ball := EntryResolver.make_ball(
          EntryResolver.BoardEdge.TOP, 0.5, 999.0, 100.0, 5.0, RECT)
      # 夹紧后方向仍朝棋盘内（y > 0）
      assert_gt(ball.vel.y, 0.0, "even extreme aim stays inward")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_entry_resolver.gd -gexit
  ```
  Expected: FAIL

- [ ] **Step 3：实现 EntryResolver**

  `game/sim/entry_resolver.gd`:
  ```gdscript
  class_name EntryResolver

  enum BoardEdge { TOP, LEFT, RIGHT }

  # (edge, t∈[0,1]) → {pos, normal}，t 沿边归一化。
  static func resolve(edge: int, t: float, rect: Rect2) -> Dictionary:
      t = clampf(t, 0.0, 1.0)
      match edge:
          BoardEdge.TOP:
              return {
                  &"pos": Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y),
                  &"normal": Vector2.DOWN
              }
          BoardEdge.LEFT:
              return {
                  &"pos": Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, t)),
                  &"normal": Vector2.RIGHT
              }
          _:  # RIGHT
              return {
                  &"pos": Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t)),
                  &"normal": Vector2.LEFT
              }

  # 瞄准：法线旋转 aim_offset 弧度，夹紧在 ±80° 朝内锥角内。
  static func make_ball(edge: int, t: float, aim_offset: float,
                        speed: float, radius: float, rect: Rect2) -> BallState:
      var r := resolve(edge, t, rect)
      var clamped := clampf(aim_offset, -1.396, 1.396)  # ±80°
      var dir: Vector2 = r[&"normal"].rotated(clamped)
      return BallState.new(r[&"pos"], dir * speed, radius)
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_entry_resolver.gd -gexit
  ```
  Expected: `5 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/entry_resolver.gd game/tests/test_entry_resolver.gd
  git commit -m "feat(sim): three-edge entry resolver + aim clamping"
  ```

---

## Task 7：轨迹预测（TrajectoryPredictor）

**Files:**
- Create: `game/sim/trajectory_predictor.gd`
- Create: `game/tests/test_trajectory_predictor.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_trajectory_predictor.gd`:
  ```gdscript
  extends GutTest

  func _make_sim_with_peg() -> BallSimulation:
      var pegs := [{&"id": 0, &"pos": Vector2(100, 150), &"radius": 8.0, &"base_score": 5.0}]
      var cfg := {
          &"gravity": Vector2(0, 500), &"max_speed": 2000.0,
          &"restitution": 0.8, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
      }
      return BallSimulation.new(Rect2(0, 0, 200, 400), pegs, cfg)

  func test_prediction_matches_actual_path() -> void:
      var sim := _make_sim_with_peg()
      var start := EntryResolver.make_ball(
          EntryResolver.BoardEdge.TOP, 0.5, 0.2, 300.0, 5.0, Rect2(0, 0, 200, 400))

      var predicted := TrajectoryPredictor.predict(sim, start, 40)

      # 以相同起点实际跑 40 步
      var ball := start.clone()
      var actual: Array[Vector2] = []
      var ev: Array = []
      for _i in 40:
          if not ball.alive: break
          sim.step(ball, ev)
          actual.append(ball.pos)

      assert_eq(actual.size(), predicted.size(), "path length must match")
      for i in actual.size():
          assert_almost_eq(predicted[i].x, actual[i].x, 1e-4,
                           "x[%d] predicted == actual" % i)
          assert_almost_eq(predicted[i].y, actual[i].y, 1e-4,
                           "y[%d] predicted == actual" % i)

  func test_prediction_does_not_mutate_sim_state() -> void:
      var sim := _make_sim_with_peg()
      var start := EntryResolver.make_ball(
          EntryResolver.BoardEdge.TOP, 0.5, 0.0, 300.0, 5.0, Rect2(0, 0, 200, 400))
      # 跑两次预测，结果应一致（说明 sim 内部状态未被污染）
      var a := TrajectoryPredictor.predict(sim, start, 30)
      var b := TrajectoryPredictor.predict(sim, start, 30)
      for i in a.size():
          assert_eq(a[i], b[i], "predict[%d] same on second call" % i)
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_trajectory_predictor.gd -gexit
  ```
  Expected: FAIL

- [ ] **Step 3：实现 TrajectoryPredictor**

  `game/sim/trajectory_predictor.gd`:
  ```gdscript
  class_name TrajectoryPredictor

  # 用同一套 BallSimulation 无渲染前瞻，返回每步球心位置。
  # 完全确定 → 返回值 == 真实弹道（直到混沌发散）。
  # 使用 BallState.clone() 防止污染真实球状态或 sim 内部状态。
  static func predict(sim: BallSimulation, start: BallState, steps: int) -> Array[Vector2]:
      var pts: Array[Vector2] = []
      var ball := start.clone()
      var scratch: Array = []   # 丢弃事件，不外泄
      for _i in steps:
          if not ball.alive:
              break
          scratch.clear()
          sim.step(ball, scratch)
          pts.append(ball.pos)
      return pts
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_trajectory_predictor.gd -gexit
  ```
  Expected: `2 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/trajectory_predictor.gd game/tests/test_trajectory_predictor.gd
  git commit -m "feat(sim): trajectory predictor (matches actual path)"
  ```

---

## Task 8：基础计分（Scorer）

**Files:**
- Create: `game/sim/scorer.gd`
- Create: `game/tests/test_scorer.gd`

- [ ] **Step 1：写失败测试**

  `game/tests/test_scorer.gd`:
  ```gdscript
  extends GutTest

  func _make_pegs() -> Array:
      return [
          {&"id": 0, &"pos": Vector2.ZERO, &"radius": 5.0, &"base_score": 3.0},
          {&"id": 1, &"pos": Vector2.ZERO, &"radius": 5.0, &"base_score": 7.0},
      ]

  func test_sum_base_score_per_peg_hit() -> void:
      var scorer := Scorer.new(_make_pegs())
      var events := [
          SimEvent.peg_hit(0, Vector2.ZERO),  # +3
          SimEvent.peg_hit(1, Vector2.ZERO),  # +7
          SimEvent.peg_hit(0, Vector2.ZERO),  # +3
          SimEvent.bounce(Vector2.ZERO),       # 非计分，忽略
      ]
      assert_almost_eq(scorer.score_launch(events), 13.0, 1e-4, "3+7+3=13")

  func test_non_peg_events_ignored() -> void:
      var scorer := Scorer.new(_make_pegs())
      var events := [
          SimEvent.bounce(Vector2.ZERO),
          SimEvent.wall_hit(Vector2.ZERO),
          SimEvent.settled(Vector2.ZERO),
          SimEvent.launch(Vector2.ZERO),
      ]
      assert_almost_eq(scorer.score_launch(events), 0.0, 1e-4, "no peg hits → 0 score")

  func test_invalid_peg_id_skipped() -> void:
      var scorer := Scorer.new(_make_pegs())
      var events := [
          SimEvent.peg_hit(99, Vector2.ZERO),  # out of bounds
          SimEvent.peg_hit(-1, Vector2.ZERO),  # -1 sentinel
      ]
      assert_almost_eq(scorer.score_launch(events), 0.0, 1e-4, "invalid ids → 0 score")
  ```

- [ ] **Step 2：跑测试验证失败**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_scorer.gd -gexit
  ```
  Expected: FAIL

- [ ] **Step 3：实现 Scorer**

  `game/sim/scorer.gd`:
  ```gdscript
  class_name Scorer

  var _pegs: Array

  func _init(pegs: Array) -> void:
      _pegs = pegs

  # 里程碑 1 仅基础分：每个 PEG_HIT 加该钉的 base_score。
  # 触发器/倍率在里程碑 2 接入（见技术文档 §8）。
  func score_launch(events: Array) -> float:
      var total := 0.0
      for e in events:
          if e[&"type"] == SimEvent.PEG_HIT:
              var id: int = e[&"peg_id"]
              if id >= 0 and id < _pegs.size():
                  total += _pegs[id][&"base_score"]
      return total
  ```

- [ ] **Step 4：跑测试验证通过**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd -- -gtest=res://tests/test_scorer.gd -gexit
  ```
  Expected: `3 passed, 0 failed`

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/sim/scorer.gd game/tests/test_scorer.gd
  git commit -m "feat(sim): base scorer from event stream"
  ```

---

## Task 9：确定性回放守卫测试

**Files:**
- Create: `game/tests/test_determinism.gd`

- [ ] **Step 1：写守卫测试（同输入 → 逐位一致）**

  `game/tests/test_determinism.gd`:
  ```gdscript
  extends GutTest

  func _run_once() -> Array:
      var rect := Rect2(0, 0, 200, 400)
      var pegs := [
          {&"id": 0, &"pos": Vector2(60, 120), &"radius": 8.0, &"base_score": 5.0},
          {&"id": 1, &"pos": Vector2(140, 160), &"radius": 8.0, &"base_score": 5.0},
          {&"id": 2, &"pos": Vector2(100, 220), &"radius": 8.0, &"base_score": 5.0},
      ]
      var cfg := {
          &"gravity": Vector2(0, 500), &"max_speed": 2000.0,
          &"restitution": 0.85, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0
      }
      var sim := BallSimulation.new(rect, pegs, cfg)
      var scorer := Scorer.new(pegs)
      var ball := EntryResolver.make_ball(
          EntryResolver.BoardEdge.TOP, 0.42, 0.15, 280.0, 5.0, rect)
      var path: Array[Vector2] = []
      var events: Array = []
      for _i in 1000:
          if not ball.alive: break
          sim.step(ball, events)
          path.append(ball.pos)
      return [path, scorer.score_launch(events)]

  func test_same_inputs_produce_identical_result() -> void:
      var a := _run_once()
      var b := _run_once()
      # 得分逐位相等（float ==，无需 almost_eq）
      assert_eq(a[1], b[1], "score must match exactly bit-for-bit")
      var pa: Array = a[0]; var pb: Array = b[0]
      assert_eq(pa.size(), pb.size(), "path length must match")
      for i in pa.size():
          assert_eq(pa[i], pb[i], "pos[%d] must match exactly" % i)
  ```

- [ ] **Step 2：跑全量测试确认全部通过（无需新代码）**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd
  ```
  Expected: 全部 PASS（含 `test_determinism.gd`）。若失败说明引入了非确定性，须排查。

- [ ] **Step 3：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/tests/test_determinism.gd
  git commit -m "test(sim): determinism replay guard"
  ```

---

## Task 10：Godot 场景 + BoardView（主循环 + 渲染）

**Files:**
- Create: `game/view/board_view.gd`
- Create: `game/view/hud.gd`（空壳，Task 12 补全）
- Create: `game/scenes/board.tscn`（Godot 编辑器创建）

> ⚠️ **从本 Task 起需要打开 Godot 编辑器。** GDScript 改完编辑器立刻热重载，无需 Build。

- [ ] **Step 1：创建主场景结构（Godot 编辑器）**

  在 Godot 编辑器：
  1. Scene → New Scene，根节点选 `Node2D`，改名为 `BoardView`，挂脚本 `view/board_view.gd`。
  2. 在 `BoardView` 下添加子节点 `CanvasLayer`，改名为 `Hud`，挂脚本 `view/hud.gd`。
  3. 在 `BoardView` 下添加子节点 `Node`，改名为 `InputController`（Task 11 挂脚本）。
  4. 在 `BoardView` 下添加子节点 `Camera2D`（用于 shake juice）。
  5. 保存为 `scenes/board.tscn`，在 Project → Project Settings → Application → Run → Main Scene 设为此场景。

- [ ] **Step 2：实现 hud.gd（空壳）**

  `game/view/hud.gd`:
  ```gdscript
  extends CanvasLayer

  var _score := 0.0
  var _label: Label

  func _ready() -> void:
      _label = Label.new()
      _label.position = Vector2(20, 20)
      _label.add_theme_font_size_override(&"font_size", 28)
      add_child(_label)
      _update()

  func add_score(s: float) -> void:
      _score += s
      _update()

  func _update() -> void:
      _label.text = "SCORE  %d" % int(_score)
  ```

- [ ] **Step 3：实现 board_view.gd**

  `game/view/board_view.gd`:
  ```gdscript
  extends Node2D

  const DT := 1.0 / 120.0

  var _rect: Rect2
  var _pegs: Array = []
  var _sim: BallSimulation
  var _scorer: Scorer

  var _ball: BallState
  var _has_ball := false
  var _prev_pos := Vector2.ZERO
  var _curr_pos := Vector2.ZERO
  var _events: Array = []
  var _acc := 0.0

  var _flashes: Array = []    # Array of {pos: Vector2, ttl: float}
  var _event_cursor := 0

  var prediction_pts: Array[Vector2] = []

  # 供 InputController 读取
  var rect: Rect2:
      get: return _rect
  var sim: BallSimulation:
      get: return _sim

  func _ready() -> void:
      _rect = Rect2(0, 0, 540, 900)
      _pegs = _build_honeycomb()
      var cfg := {
          &"gravity": Vector2(0, 1400),
          &"max_speed": 4000.0,
          &"restitution": 0.82,
          &"tangent_keep": 0.98,
          &"dt": DT,
      }
      _sim = BallSimulation.new(_rect, _pegs, cfg)
      _scorer = Scorer.new(_pegs)

  func _build_honeycomb() -> Array:
      var list := []
      var id := 0
      var rows := 8; var cols := 7
      var spacing := 64.0; var margin := 60.0
      for r in rows:
          var y := margin + 140.0 + r * spacing
          var x_off := (r % 2) * spacing * 0.5
          for c in cols:
              var x := margin + x_off + c * spacing
              if x < _rect.end.x - margin:
                  list.append({&"id": id, &"pos": Vector2(x, y),
                                &"radius": 10.0, &"base_score": 5.0})
                  id += 1
      return list

  # 由 InputController 调用：发射一颗球
  func launch(ball: BallState) -> void:
      _ball = ball; _has_ball = true
      _prev_pos = ball.pos; _curr_pos = ball.pos
      _events.clear(); _event_cursor = 0; _flashes.clear()

  func _process(delta: float) -> void:
      if _has_ball:
          _acc += delta
          while _acc >= DT:
              _prev_pos = _ball.pos
              _sim.step(_ball, _events)
              _curr_pos = _ball.pos
              _acc -= DT
              # 收集命中闪光事件
              while _event_cursor < _events.size():
                  var e: Dictionary = _events[_event_cursor]
                  if e[&"type"] == SimEvent.PEG_HIT:
                      _flashes.append({&"pos": e[&"pos"], &"ttl": 0.15})
                  _event_cursor += 1
              if not _ball.alive:
                  var score := _scorer.score_launch(_events)
                  $Hud.add_score(score)
                  _has_ball = false; _acc = 0.0; break
          # 衰减闪光
          for i in range(_flashes.size() - 1, -1, -1):
              _flashes[i][&"ttl"] -= delta
              if _flashes[i][&"ttl"] <= 0.0:
                  _flashes.remove_at(i)
      queue_redraw()

  func _draw() -> void:
      # 钉子
      for peg in _pegs:
          draw_circle(peg[&"pos"], peg[&"radius"], Color(0.2, 0.9, 1.0))
      # 预测线
      for i in range(1, prediction_pts.size()):
          draw_line(prediction_pts[i - 1], prediction_pts[i], Color(1, 1, 1, 0.4), 2.0)
      # 球（accumulator 插值，消除定步长卡顿）
      if _has_ball:
          var alpha := _acc / DT
          var draw_pos := _prev_pos.lerp(_curr_pos, alpha)
          draw_circle(draw_pos, _ball.radius, Color(1.0, 0.3, 0.8))
      # 命中闪光
      for f in _flashes:
          var a := f[&"ttl"] / 0.15
          draw_circle(f[&"pos"], 16.0, Color(1.0, 1.0, 0.6, a * 0.8))
  ```

- [ ] **Step 4：手动验证（临时发球）**

  在 `board_view.gd` 的 `_ready()` 末尾临时加一行：
  ```gdscript
  launch(EntryResolver.make_ball(EntryResolver.BoardEdge.TOP, 0.5, 0.0, 1500.0, 8.0, _rect))
  ```
  按 F5 运行，验证：球从顶部落下、撞钉弹跳、落底消失、右上角分数增加、画面顺滑无抖动。
  验证完毕后**删除该临时行**。

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/view/board_view.gd game/view/hud.gd game/scenes/board.tscn
  git commit -m "feat(game): board rendering + fixed-step loop with interpolation"
  ```

---

## Task 11：InputController（三边入口 + 瞄准 + 预测线 + 发射）

**Files:**
- Create: `game/view/input_controller.gd`
- Modify: `game/scenes/board.tscn`（挂脚本 + 配 BoardPath）

- [ ] **Step 1：实现 InputController**

  `game/view/input_controller.gd`:
  ```gdscript
  extends Node

  @export var board_path: NodePath

  var _board: Node2D
  var _edge: int = EntryResolver.BoardEdge.TOP
  var _t := 0.5
  var _aim := 0.0
  const SPEED := 1500.0
  const BALL_RADIUS := 8.0

  func _ready() -> void:
      _board = get_node(board_path)

  func _process(_delta: float) -> void:
      var m := _board.get_local_mouse_position()
      var r: Rect2 = _board.rect
      # 鼠标 x 映射到入口位置 t；偏离中心映射到瞄准偏移（原型期，后续可细化）
      _t = clampf((m.x - r.position.x) / r.size.x, 0.0, 1.0)
      _aim = clampf((m.x - r.get_center().x) / (r.size.x * 0.5), -1.0, 1.0) * 1.2
      var start := EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r)
      _board.prediction_pts = TrajectoryPredictor.predict(_board.sim, start, 60)

  func _unhandled_input(event: InputEvent) -> void:
      if event is InputEventKey and event.pressed:
          match event.keycode:
              KEY_TAB:
                  # Tab 键切换三边入口
                  _edge = (_edge + 1) % 3
      if event is InputEventMouseButton and event.pressed:
          if event.button_index == MOUSE_BUTTON_LEFT:
              var r: Rect2 = _board.rect
              _board.launch(
                  EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r))
  ```

- [ ] **Step 2：在 Godot 编辑器接线**

  在 Godot 编辑器：
  1. 选中 `InputController` 节点 → Inspector → 挂脚本 `view/input_controller.gd`。
  2. 在 Inspector 的 `Board Path` 属性里，拖入 `BoardView` 根节点（或填 `"."`）。
  3. 保存场景。

- [ ] **Step 3：手动验证（预测线 + 三边发射）**

  按 F5 运行：
  - 移动鼠标，看白色虚线预测线实时更新。
  - 按 Tab 切换入口边（顶/左/右），每次切换后鼠标位置映射到对应边。
  - 左键发射，球应**沿预测线轨迹**飞行（确定性 → 实际 = 预测）。
  Expected: 预测线与实际弹道一致；三边均可正常切换发射。

- [ ] **Step 4：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/view/input_controller.gd game/scenes/board.tscn
  git commit -m "feat(game): edge entry + aim + live prediction line + launch"
  ```

---

## Task 12：HUD 完善 + 命中闪光 Juice

> `board_view.gd` 已在 Task 10 实现了命中闪光逻辑，本 Task 确认效果并完善 HUD 展示。

**Files:**
- Modify: `game/view/hud.gd`（追加发射数 / 本发得分提示）

- [ ] **Step 1：完善 HUD 显示**

  `game/view/hud.gd`（替换为完整版）:
  ```gdscript
  extends CanvasLayer

  var _total_score := 0.0
  var _last_score := 0.0
  var _label_total: Label
  var _label_last: Label

  func _ready() -> void:
      _label_total = Label.new()
      _label_total.position = Vector2(20, 20)
      _label_total.add_theme_font_size_override(&"font_size", 28)
      add_child(_label_total)

      _label_last = Label.new()
      _label_last.position = Vector2(20, 60)
      _label_last.add_theme_font_size_override(&"font_size", 18)
      _label_last.modulate = Color(1, 1, 0.5)
      add_child(_label_last)

      _update()

  func add_score(s: float) -> void:
      _last_score = s
      _total_score += s
      _update()

  func _update() -> void:
      _label_total.text = "SCORE  %d" % int(_total_score)
      _label_last.text = "+%d" % int(_last_score) if _last_score > 0 else ""
  ```

- [ ] **Step 2：手动验证（命中有反馈 + 分数正确）**

  按 F5 运行：
  - 发射后命中钉子有**黄色圆形闪光**。
  - 球落底后左上角 SCORE 增加正确数值（钉阵约 50 个钉 × 5 分，一发满命中约 250 分）。
  - 黄色小字显示本发得分。
  Expected: 有命中反馈；分数正确累加。

- [ ] **Step 3：Commit**

  ```bash
  cd D:/NeonPinball
  git add game/view/hud.gd
  git commit -m "feat(game): HUD total + per-launch score + hit-flash juice"
  ```

---

## Task 13：里程碑 1 验收（go/no-go 手感评估）

**Files:**
- Create: `MILESTONE1_VERDICT.md`（项目根）

- [ ] **Step 1：跑全量自动化测试**

  ```bash
  cd D:/NeonPinball/game
  godot --headless -s addons/gut/gut_cmdln.gd
  ```
  Expected: **全部 PASS**（含确定性守卫）。任何 FAIL 须在此步解决再继续。

- [ ] **Step 2：手感评估清单（手动，逐项 1–5 打分）**

  打开 Godot 按 F5，逐项评估：

  | 评估项 | 关注点 |
  |---|---|
  | 弹跳轨迹可读性 | 预测线是否真实帮到瞄准？弹道是否可学习？ |
  | 三边入口多样性 | Tab 切换后弹道几何是否有趣、不同？ |
  | 命中反馈脆度 | 闪光是否即时？有无打击感？ |
  | 再来一发冲动 | 发完一球后是否想立刻再发？ |

- [ ] **Step 3：调整手感参数（若评分不达标）**

  在 `board_view.gd` 的 `_ready()` 中找 `cfg` 字典，按下表调整：

  | 参数 | 球太飘/弹太久 | 球太沉/一两下死 | 瞄不准/预测失效 |
  |---|---|---|---|
  | `gravity.y` | ↑（1800） | ↓（1000） | — |
  | `restitution` | ↓（0.70） | ↑（0.90） | — |
  | 预测步数（InputController 里 `60`）| — | — | 缩短到 40 |
  | SPEED（InputController 里 `1500`）| — | ↓（1000） | ↓（让前段更可控）|

  每次改一个参数，F5 验证体感，找到最佳手感基线。

- [ ] **Step 4：记录 go/no-go 结论**

  在项目根创建 `MILESTONE1_VERDICT.md`，填写：
  ```markdown
  # 里程碑 1 验收结论

  **日期：** 2026-XX-XX
  **结论：** GO / NO-GO

  ## 手感评分（1–5）
  - 弹跳轨迹可读性：X
  - 三边入口多样性：X
  - 命中反馈脆度：X
  - 再来一发冲动：X

  ## 最终 SimConfig
  - gravity.y: XXXX
  - restitution: X.XX
  - tangent_keep: X.XX
  - speed: XXXX
  - 预测步数: XX

  ## 问题清单（若有）
  - ...

  ## 下一步
  GO → 进入里程碑 2：三类积木系统 + 门 + round loop
  NO-GO → 调整物理参数，继续打磨手感
  ```

- [ ] **Step 5：Commit**

  ```bash
  cd D:/NeonPinball
  git add MILESTONE1_VERDICT.md
  git commit -m "docs: milestone 1 go/no-go verdict"
  git push origin main
  ```

---

## 自检备注

**Spec 覆盖**：
- ✅ 确定性物理（Task 5 BallSimulation + CCD）
- ✅ 三边入口（Task 6 EntryResolver + Task 11 InputController）
- ✅ 瞄准预测线（Task 7 TrajectoryPredictor + Task 11）
- ✅ 基础计分（Task 8 Scorer）
- ✅ 命中 juice（Task 10 hit-flash + Task 12 HUD）
- ✅ 确定性守卫（Task 9 test_determinism）
- ✅ 门/触发器/商店/区轮 明确排除，留里程碑 2+

**类型一致性**：
- `BallState.new(pos, vel, radius)` / `ball.clone()` — Task 1 定义，Task 5/6/7/8/10/11 使用。
- `SimEvent.peg_hit(id, pos)` → `{&"type": SimEvent.PEG_HIT, &"peg_id": id, &"pos": pos}` — Task 1 定义，后续 Task 一致。
- `BallSimulation.new(rect, pegs, cfg)` / `sim.step(ball, events)` — Task 5 定义，Task 10/11 使用。
- `EntryResolver.make_ball(edge, t, aim, speed, radius, rect)` — Task 6 定义，Task 10/11 使用。
- `TrajectoryPredictor.predict(sim, start, steps)` — Task 7 定义，Task 11 使用。
- `Scorer.new(pegs)` / `scorer.score_launch(events)` — Task 8 定义，Task 10 使用。
- 钉 Dictionary 格式：`{&"id", &"pos", &"radius", &"base_score"}` — Task 5 定义，全链路一致。
