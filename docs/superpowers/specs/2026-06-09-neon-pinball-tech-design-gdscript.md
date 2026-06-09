# 技术设计文档：霓虹弹珠 × Roguelike 构筑（纯 Godot 4 / GDScript）

- **日期**：2026-06-09
- **配套游戏设计文档**：`2026-06-09-neon-pinball-roguelike-deckbuilder-design.md`
- **技术栈**：Godot 4.x（标准版）+ GDScript + Git
- **本文目标**：与 C# 版技术文档（`2026-06-09-neon-pinball-tech-design.md`）覆盖同等内容，但改用纯 GDScript 实现——适合不想引入 .NET 运行时、或目标平台包含 **Web / iOS** 的场景。

---

## 0. 为什么选纯 GDScript 而非 C#

| 维度 | GDScript | C#（.NET）|
|---|---|---|
| 平台覆盖 | **全平台**（Web/iOS/Android/Desktop）| Desktop/Android 可用；Web/iOS **不支持** |
| 热重载 | ✅ 改完即生效，无需重编译 | ❌ 改完必须 Build 再 F5 |
| 工具链 | 仅需 Godot 标准版编辑器 | 需额外装 .NET SDK + Rider |
| 性能 | **弹球物理为纯数学，GDScript 完全够用**（见 §2）| 理论更快，但热路径 GC 需手动规避 |
| 生态 | 社区插件/示例以 GDScript 为主，直接复用 | 插件相对少，需自行转换 |
| 风险 | 几乎无 | C# 热重载弱、Web/iOS 导出不支持 |

**结论**：本作弹球物理简单（少量球 vs 静态钉），GDScript 性能完全满足。换取全平台导出与更轻量的工具链是合算的。

---

## 1. 顶层架构原则（与 C# 版一致，实现手段不同）

四条贯穿全局的原则：

1. **模拟 / 渲染分离（Sim/View Separation）**：游戏逻辑跑在**定步长**的纯 GDScript 模拟层（`sim/` 目录下，不直接操作节点树），渲染层只「读状态 + 插值 + 播 juice」，永不反向影响逻辑。
2. **确定性优先（Determinism First）**：相同 `seed + 输入序列` ⇒ 相同结果。**不使用** `RigidBody2D`（非确定性），改用自写定步长弹球物理。GDScript 浮点与 C# 一样遵循 IEEE 754，同平台下结果确定。
3. **数据驱动（Data-Driven）**：钉子 / 球种 / 触发器 / 门 / 棋盘模板全部是 Godot `Resource`（`.tres`），在 Inspector 里编辑，加内容 / 调平衡**不改脚本**。
4. **事件化计分（Event-Driven Scoring）**：物理模拟只产出**事件字典数组**，计分与触发器是这条流的订阅者管线。

---

## 2. GDScript 性能分析（弹球物理够不够）

弹球物理热路径：每物理帧（120Hz 模拟）：1 颗球 × 最多 8 次碰撞求解（TOI 数学），每次查询空间网格，做圆-圆 / 圆-墙解析解。钉子数约 50–100 个，空间网格后每步只查询 5–15 个候选。

在 Godot 4 的 GDScript（JIT 编译）下，这个量级**远低于瓶颈**。实测同类弹球游戏均以 GDScript 搞定物理，60fps 有余。

**需要注意的性能规避点**：

| 坑 | 规避方式 |
|---|---|
| 热路径反复 `new Dictionary` / `Array` | 预分配事件池，`clear()` 复用而非重建 |
| 大量节点 `get_node()` 调用 | 缓存到变量，`@onready var` 只取一次 |
| 粒子用 CPUParticles2D | 改用 `GPUParticles2D`，shader 驱动 |
| 霓虹辉光逐帧 CPU 计算 | 用 `CanvasItem` shader + 后处理 bloom |

---

## 3. 项目结构

```
/project.godot
/sim/                            # 纯 GDScript 模拟层（不操作场景树/节点）
  ball_simulation.gd             # 定步长 CCD 步进 + 事件产出
  ball_state.gd                  # 球状态（GDScript class）
  peg_grid.gd                    # 宽相位空间网格
  collision.gd                   # 圆-圆 / 圆-墙 TOI + 反射（静态函数）
  entry_resolver.gd              # (edge,t)+瞄准 → 球初始状态
  trajectory_predictor.gd        # 无渲染前瞻 → 预测线
  sim_event.gd                   # 事件常量 + 工厂函数
  deterministic_rng.gd           # 种子化 PRNG（xorshift128+）
/scoring/
  scoring_engine.gd              # base/mult 账本结算
  trigger_runtime.gd             # 触发器运行时实例
  score_context.gd               # 一发球的计分上下文
/run/
  run_manager.gd                 # 跑局状态机（区/轮/quota/胜负）
  economy.gd                     # 金钱/利息
  shop.gd                        # 商店生成/购买/刷新/移除
  board_builder.gd               # 模板 + 程序化填充生成棋盘
  gate_runtime.gd                # 门变换 + 串联
  gate_chain.gd                  # 门链管线
/meta/
  save_system.gd                 # 存档（JSON → user://）
  unlock_manager.gd
  daily_seed.gd
/data/                           # Resource 子类定义（GDScript）
  peg_type.gd  orb_type.gd  trigger_def.gd  gate_def.gd  board_template.gd
  game_database.gd               # Autoload：全局数据注册表
/resources/                      # 实际 .tres 资源（策划编辑）
  pegs/  orbs/  triggers/  gates/  boards/
/scenes/                         # Godot 场景（View 层）
  board.tscn  hud.tscn  shop.tscn
/view/                           # View 脚本：读 Sim 状态 + juice
  board_view.gd  juice_controller.gd  input_controller.gd  hud.gd
/tests/                          # GUT 单元测试
  test_collision.gd  test_scoring.gd  test_determinism.gd
  test_entry_resolver.gd  test_ball_simulation.gd
/addons/gut/                     # GUT 测试框架
/assets/                         # 美术/音频
```

---

## 4. GDScript 数据结构（无 struct，用 class + Dictionary）

GDScript 没有值类型 `struct`。弹球状态用**轻量 GDScript class**，事件用 `Dictionary` 传递。

### 4.1 球状态

```gdscript
# sim/ball_state.gd
class_name BallState

var pos: Vector2
var vel: Vector2
var radius: float
var bounce_count: int
var alive: bool

func _init(p: Vector2, v: Vector2, r: float) -> void:
    pos = p; vel = v; radius = r; bounce_count = 0; alive = true

func clone() -> BallState:
    var b := BallState.new(pos, vel, radius)
    b.bounce_count = bounce_count; b.alive = alive
    return b
```

> 由于没有 struct，传参是引用语义。预测线等需要克隆状态时，调用 `ball.clone()`。

### 4.2 钉运行时（Dictionary）

```gdscript
# 运行时钉（从 PegType Resource 生成）
{
    "id": 0,           # 数组下标，id == 索引
    "pos": Vector2,
    "radius": float,
    "type": PegType,   # Resource 引用
    "exhausted": false # 一次性钉是否已触发
}
```

### 4.3 事件（StringName 常量 + 工厂）

```gdscript
# sim/sim_event.gd
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

---

## 5. 确定性弹球物理（核心）

### 5.1 定步长主循环（accumulator + 渲染插值）

```gdscript
# view/board_view.gd
const DT := 1.0 / 120.0
var _acc := 0.0
var _prev_pos := Vector2.ZERO
var _curr_pos := Vector2.ZERO

func _process(delta: float) -> void:
    if _has_ball:
        _acc += delta
        while _acc >= DT:
            _prev_pos = _ball.pos
            _sim.step(_ball, _events)
            _curr_pos = _ball.pos
            _acc -= DT
            if not _ball.alive:
                _on_ball_settled()
                _acc = 0.0
                break
    queue_redraw()

func _draw() -> void:
    # 视觉插值：消除定步长卡顿
    var alpha := _acc / DT
    var draw_pos := _prev_pos.lerp(_curr_pos, alpha)
    draw_circle(draw_pos, _ball.radius, Color(1.0, 0.3, 0.8))
```

### 5.2 积分（半隐式欧拉 + 限速）

```gdscript
# sim/ball_simulation.gd
func step(ball: BallState, out_events: Array) -> void:
    if not ball.alive:
        return
    ball.vel += _cfg.gravity * _cfg.dt
    var speed := ball.vel.length()
    if speed > _cfg.max_speed:
        ball.vel = ball.vel * (_cfg.max_speed / speed)
    _integrate_ccd(ball, out_events, _cfg.dt)
    if ball.pos.y - ball.radius > _rect.end.y:
        ball.alive = false
        out_events.append(SimEvent.settled(ball.pos))
```

### 5.3 CCD / TOI（扫掠连续碰撞，防隧穿）

```gdscript
const MAX_BOUNCES_PER_STEP := 8

func _integrate_ccd(ball: BallState, out_events: Array, dt: float) -> void:
    var remaining := dt
    var guard := 0
    while remaining > 1e-5 and guard < MAX_BOUNCES_PER_STEP:
        guard += 1
        var d := ball.vel * remaining
        var hit := _find_earliest(ball.pos, d, ball.radius)
        if hit.is_empty():
            ball.pos += d
            break
        ball.pos += d * hit.t
        if hit.peg_id >= 0:
            out_events.append(SimEvent.peg_hit(hit.peg_id, ball.pos))
        else:
            out_events.append(SimEvent.wall_hit(ball.pos))
        out_events.append(SimEvent.bounce(ball.pos))
        ball.vel = Collision.reflect(ball.vel, hit.normal, _cfg.restitution, _cfg.tangent_keep)
        ball.bounce_count += 1
        remaining *= (1.0 - hit.t)

# 求本段位移内最早碰撞（TOI 最小；同 TOI 按 peg_id 升序决胜）
func _find_earliest(p: Vector2, d: Vector2, r: float) -> Dictionary:
    var best := {}
    var best_t := INF
    var search_r := d.length() + r + 32.0
    for peg_id in _grid.query_near(p, search_r):
        var peg: Dictionary = _pegs[peg_id]
        var t := Collision.swept_circle(p, d, peg.pos, r + peg.radius)
        if t >= 0.0 and (t < best_t or (t == best_t and peg_id < best.get(&"peg_id", INF))):
            best_t = t
            var contact := p + d * t
            best = {&"t": t, &"peg_id": peg_id,
                    &"normal": (contact - peg.pos).normalized()}
    var wall := Collision.swept_walls(p, d, r, _rect)
    if not wall.is_empty() and wall.t < best_t:
        best = {&"t": wall.t, &"peg_id": -1, &"normal": wall.normal}
    return best
```

### 5.4 碰撞数学（静态工具类）

```gdscript
# sim/collision.gd
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

# 轴对齐三墙（左/右/顶；底部开口落球）
static func swept_walls(p: Vector2, d: Vector2, r: float, rect: Rect2) -> Dictionary:
    var best_t := INF
    var best_n := Vector2.ZERO
    var found := false
    # [条件, t值, 法线]
    var checks := [
        [d.x < 0.0, (rect.position.x + r - p.x) / d.x if d.x != 0.0 else INF, Vector2(1, 0)],
        [d.x > 0.0, (rect.end.x - r - p.x) / d.x      if d.x != 0.0 else INF, Vector2(-1, 0)],
        [d.y < 0.0, (rect.position.y + r - p.y) / d.y  if d.y != 0.0 else INF, Vector2(0, 1)],
    ]
    for c in checks:
        if c[0] and c[1] >= 0.0 and c[1] <= 1.0 and c[1] < best_t:
            best_t = c[1]; best_n = c[2]; found = true
    if not found:
        return {}
    return {&"t": best_t, &"normal": best_n}

# 反射：弹性 restitution（法向），切向保留 tangent_keep
static func reflect(v: Vector2, n: Vector2, restitution: float, tangent_keep: float) -> Vector2:
    var vn := v.dot(n) * n
    var vt := v - vn
    return vt * tangent_keep - vn * restitution
```

### 5.5 宽相位空间网格

```gdscript
# sim/peg_grid.gd
class_name PegGrid

var _rect: Rect2
var _cell: float
var _cols: int
var _rows: int
var _cells: Array  # Array of Array[int]

func build(pegs: Array, rect: Rect2, cell_size: float) -> void:
    _rect = rect; _cell = cell_size
    _cols = maxi(1, ceili(rect.size.x / cell_size))
    _rows = maxi(1, ceili(rect.size.y / cell_size))
    _cells.resize(_cols * _rows)
    for i in _cells.size():
        _cells[i] = []
    for peg in pegs:
        var cx := clampi(int((peg.pos.x - rect.position.x) / cell_size), 0, _cols - 1)
        var cy := clampi(int((peg.pos.y - rect.position.y) / cell_size), 0, _rows - 1)
        _cells[cy * _cols + cx].append(peg.id)

# 返回附近格子的 peg_id 列表，按 id 升序（保证确定性遍历）
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
    result.sort()
    return result
```

### 5.6 确定性检查清单

- GDScript 用单精度 `float`（IEEE 754），同编译平台下结果确定。PC 优先，MVP 够用。
- **禁止**在 Sim 层调用 `randf()`、`randi()`、`Time.get_unix_time_from_system()`——全部走 `DeterministicRng`。
- 碰撞遍历顺序固定（网格格子升序 + `result.sort()` 按 peg_id 升序），不依赖 `Dictionary` 遍历序。
- 不使用 `RigidBody2D` / `PhysicsServer2D`（非确定性）。
- 浮点比较带 `1e-5` EPS，避免边界抖动分叉。

---

## 6. 随机与种子策略

```gdscript
# sim/deterministic_rng.gd
class_name DeterministicRng

var _s0: int
var _s1: int

func _init(seed_val: int) -> void:
    _s0 = _splitmix64(seed_val)
    _s1 = _splitmix64(_s0)

func next_int() -> int:
    var s0 := _s0; var s1 := _s1
    var result := (s0 + s1) & 0x7FFFFFFFFFFFFFFF
    s1 ^= s0
    _s0 = (_rotl(s0, 24) ^ s1 ^ (s1 << 16)) & 0x7FFFFFFFFFFFFFFF
    _s1 = _rotl(s1, 37)
    return result

func next_float() -> float:
    return float(next_int() & 0xFFFFFF) / float(0x1000000)

func range_float(lo: float, hi: float) -> float:
    return lo + next_float() * (hi - lo)

func range_int(lo: int, hi: int) -> int:  # [lo, hi)
    return lo + (next_int() % (hi - lo))

# 从 master seed 派生独立子流（不共用游标，避免相关性）
static func derive(master: int, tag: int) -> DeterministicRng:
    return DeterministicRng.new(master ^ _splitmix64(tag))

static func _splitmix64(x: int) -> int:
    x = ((x ^ (x >> 30)) * 0xBF58476D1CE4E5B9) & 0x7FFFFFFFFFFFFFFF
    x = ((x ^ (x >> 27)) * 0x94D049BB133111EB) & 0x7FFFFFFFFFFFFFFF
    return x ^ (x >> 31)

static func _rotl(x: int, k: int) -> int:
    return ((x << k) | (x >> (64 - k))) & 0x7FFFFFFFFFFFFFFF
```

子流约定：`derive(master, 0)` 棋盘生成，`derive(master, 1)` 商店，`derive(master, 2)` 散射门，`derive(master, 3)` 事件随机……

---

## 7. 数据驱动定义（Godot Resource）

```gdscript
# data/peg_type.gd
class_name PegType extends Resource

enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB }

@export var id: StringName
@export var behavior: Behavior = Behavior.NORMAL
@export var base_score: float = 5.0
@export var mult_add: float = 0.0
@export var one_shot: bool = false
@export var glow: Color = Color.CYAN
```

```gdscript
# data/trigger_def.gd
class_name TriggerDef extends Resource

enum Effect { ADD_BASE, ADD_MULT, MUL_MULT, CUSTOM }
enum Condition { NONE, BOUNCE_GTE, PEGS_HIT_GTE }

@export var id: StringName
@export_flags("PegHit:1", "Bounce:2", "Settled:4", "Launch:8") var listen_mask: int
@export var effect: Effect = Effect.ADD_BASE
@export var value: float = 1.0
@export var condition: Condition = Condition.NONE
@export var condition_threshold: int = 0
@export var rarity: int = 1
```

```gdscript
# data/gate_def.gd
class_name GateDef extends Resource

enum Kind { NORMAL, ACCEL, SCATTER_ANGLE, SCATTER_SPLIT }

@export var id: StringName
@export var kind: Kind = Kind.NORMAL
@export var speed_mul: float = 1.5
@export var scatter_angle: float = 0.3
@export var split_count: int = 3
```

```gdscript
# data/board_template.gd
class_name BoardTemplate extends Resource

enum Prototype { HONEYCOMB, FUNNEL, TWIN_TOWER, SPIRAL }

@export var id: StringName
@export var prototype: Prototype = Prototype.HONEYCOMB
@export var explicit_anchors: Array[Vector2] = []
@export var base_density: float = 0.15
@export var funnel_zones: Array[Rect2] = []
```

**数据库 Autoload**（ProjectSettings → Autoload 注册为 `GameDB`）：

```gdscript
# data/game_database.gd
extends Node

var triggers: Dictionary = {}
var peg_types: Dictionary = {}
var orb_types: Dictionary = {}
var gate_defs: Dictionary = {}
var board_templates: Dictionary = {}

func _ready() -> void:
    _load_dir("res://resources/pegs/",      peg_types)
    _load_dir("res://resources/triggers/",  triggers)
    _load_dir("res://resources/gates/",     gate_defs)
    _load_dir("res://resources/boards/",    board_templates)
    _validate()

func _load_dir(path: String, into: Dictionary) -> void:
    var dir := DirAccess.open(path)
    if not dir: return
    dir.list_dir_begin()
    var f := dir.get_next()
    while f != "":
        if f.ends_with(".tres"):
            var res: Resource = load(path + f)
            into[res.id] = res
        f = dir.get_next()

func _validate() -> void:
    # 启动期 linter：id 唯一、数值在合理区间
    for id in triggers:
        var t: TriggerDef = triggers[id]
        assert(t.value > 0.0, "TriggerDef %s: value must be positive" % id)
```

---

## 8. 计分与触发器管线（系统的心脏）

### 8.1 ScoreContext（账本）

```gdscript
# scoring/score_context.gd
class_name ScoreContext

const KIND_ADD_BASE := 0
const KIND_ADD_MULT := 1
const KIND_MUL_MULT := 2

var ledger: Array = []
var bounce_count: int = 0
var pegs_hit: int = 0
var gate_used_accel: bool = false
var gate_used_scatter: bool = false
var launch_index: int = 0

func add(kind: int, value: float, source: StringName) -> void:
    ledger.append({&"kind": kind, &"value": value, &"source": source})

func clear_for_launch() -> void:
    ledger.clear()
    bounce_count = 0; pegs_hit = 0
    gate_used_accel = false; gate_used_scatter = false
```

### 8.2 触发器运行时

```gdscript
# scoring/trigger_runtime.gd
class_name TriggerRuntime

var _def: TriggerDef

func _init(def: TriggerDef) -> void:
    _def = def

func on_event(event: Dictionary, ctx: ScoreContext) -> void:
    if not _listens_to(event[&"type"]):
        return
    if not _condition_met(ctx):
        return
    match _def.effect:
        TriggerDef.Effect.ADD_BASE:
            ctx.add(ScoreContext.KIND_ADD_BASE, _def.value, _def.id)
        TriggerDef.Effect.ADD_MULT:
            ctx.add(ScoreContext.KIND_ADD_MULT, _def.value, _def.id)
        TriggerDef.Effect.MUL_MULT:
            ctx.add(ScoreContext.KIND_MUL_MULT, _def.value, _def.id)

func _listens_to(event_type: StringName) -> bool:
    var flag := {SimEvent.PEG_HIT: 1, SimEvent.BOUNCE: 2,
                 SimEvent.SETTLED: 4, SimEvent.LAUNCH: 8}.get(event_type, 0)
    return (_def.listen_mask & flag) != 0

func _condition_met(ctx: ScoreContext) -> bool:
    match _def.condition:
        TriggerDef.Condition.NONE:           return true
        TriggerDef.Condition.BOUNCE_GTE:     return ctx.bounce_count >= _def.condition_threshold
        TriggerDef.Condition.PEGS_HIT_GTE:   return ctx.pegs_hit >= _def.condition_threshold
    return true
```

### 8.3 结算（固定三层顺序：+base → +mult → ×mult）

```gdscript
# scoring/scoring_engine.gd
class_name ScoringEngine

# 返回 [score: float, settle_steps: Array]
# settle_steps 供 JuiceController 做逐项动画
func settle(ctx: ScoreContext) -> Array:
    var base := 0.0
    var mult_add := 0.0
    var mult := 1.0
    var steps := []

    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_ADD_BASE:
            base += c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"+base",
                          &"delta": c[&"value"], &"current": base})
    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_ADD_MULT:
            mult_add += c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"+mult",
                          &"delta": c[&"value"], &"current": 1.0 + mult_add})
    mult = 1.0 + mult_add
    for c in ctx.ledger:
        if c[&"kind"] == ScoreContext.KIND_MUL_MULT:
            mult *= c[&"value"]
            steps.append({&"source": c[&"source"], &"kind": &"×mult",
                          &"delta": c[&"value"], &"current": mult})

    return [base * mult, steps]
```

---

## 9. 入口通道与门系统

### 9.1 入口位置参数化（三边任意滑选）

```gdscript
# sim/entry_resolver.gd
class_name EntryResolver

enum BoardEdge { TOP, LEFT, RIGHT }

static func resolve(edge: int, t: float, rect: Rect2) -> Dictionary:
    t = clampf(t, 0.0, 1.0)
    match edge:
        BoardEdge.TOP:
            return {&"pos": Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y),
                    &"normal": Vector2.DOWN}
        BoardEdge.LEFT:
            return {&"pos": Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, t)),
                    &"normal": Vector2.RIGHT}
        _:
            return {&"pos": Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t)),
                    &"normal": Vector2.LEFT}

static func make_ball(edge: int, t: float, aim_offset: float,
                      speed: float, radius: float, rect: Rect2) -> BallState:
    var r := resolve(edge, t, rect)
    var clamped := clampf(aim_offset, -1.396, 1.396)  # ±80°
    var dir: Vector2 = r[&"normal"].rotated(clamped)
    return BallState.new(r[&"pos"], dir * speed, radius)
```

### 9.2 门变换

```gdscript
# run/gate_runtime.gd
class_name GateRuntime

var _def: GateDef
var _rng: DeterministicRng

func _init(def: GateDef, rng: DeterministicRng) -> void:
    _def = def; _rng = rng

# 作用于球集合（分裂门 1→N）
func apply(balls: Array) -> Array:
    var result := []
    for ball in balls:
        match _def.kind:
            GateDef.Kind.NORMAL:
                result.append(ball)
            GateDef.Kind.ACCEL:
                var speed := ball.vel.length()
                ball.vel = ball.vel * (_def.speed_mul * speed / max(speed, 1e-6))
                result.append(ball)
            GateDef.Kind.SCATTER_ANGLE:
                var angle := _rng.range_float(-_def.scatter_angle, _def.scatter_angle)
                ball.vel = ball.vel.rotated(angle)
                result.append(ball)
            GateDef.Kind.SCATTER_SPLIT:
                for k in _def.split_count:
                    var frac := float(k) / maxf(_def.split_count - 1, 1) - 0.5
                    var nb := ball.clone()
                    nb.vel = ball.vel.rotated(frac * _def.scatter_angle)
                    result.append(nb)
    return result
```

### 9.3 门链（单槽起步，多槽零改动扩展）

```gdscript
# run/gate_chain.gd
class_name GateChain

var _gates: Array[GateRuntime] = []  # MVP 长度 = 1

func process(entry_ball: BallState) -> Array:
    var balls := [entry_ball]
    for gate in _gates:
        balls = gate.apply(balls)
    return balls
```

### 9.4 预测线 + 扇形包络

```gdscript
# sim/trajectory_predictor.gd
class_name TrajectoryPredictor

static func predict(sim: BallSimulation, start: BallState, steps: int) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var ball := start.clone()
    var scratch := []
    for _i in steps:
        if not ball.alive: break
        scratch.clear()
        sim.step(ball, scratch)
        pts.append(ball.pos)
    return pts

# 散射门 → 扇形包络（采样若干角度各跑前瞻）
static func predict_fan(sim: BallSimulation, start: BallState,
                        scatter_rad: float, samples: int, steps: int) -> Array:
    var fans := []
    for i in samples:
        var a := lerpf(-scatter_rad, scatter_rad, float(i) / maxf(samples - 1, 1))
        var b := BallState.new(start.pos, start.vel.rotated(a), start.radius)
        fans.append(predict(sim, b, steps))
    return fans
```

---

## 10. 跑局状态机（RunManager）

```gdscript
# run/run_manager.gd
class_name RunManager extends Node

enum Phase {
    BOOT, MAIN_MENU, RUN_START, NODE_MAP,
    ROUND, BOSS_ROUND, SHOP, EVENT, TREASURE,
    ANTE_CLEAR, RUN_WIN, RUN_LOSE, META_UPDATE
}

var state := {
    &"master_seed": 0, &"phase": Phase.BOOT,
    &"ante": 1, &"round_in_ante": 0,
    &"round_score": 0.0, &"quota": 0.0,
    &"launches_left": 5, &"money": 0,
    &"input_log": []
}

func advance(input: Dictionary = {}) -> void:
    state[&"input_log"].append(input)
    match state[&"phase"]:
        Phase.RUN_START:
            state[&"quota"] = quota_of(state[&"ante"], state[&"round_in_ante"])
            state[&"phase"] = Phase.ROUND
        Phase.ROUND, Phase.BOSS_ROUND:
            if state[&"round_score"] >= state[&"quota"]:
                state[&"phase"] = Phase.ANTE_CLEAR
            else:
                state[&"phase"] = Phase.RUN_LOSE
        Phase.ANTE_CLEAR:
            _payout()
            state[&"round_in_ante"] += 1
            if state[&"round_in_ante"] > 2:
                state[&"round_in_ante"] = 0
                state[&"ante"] += 1
                if state[&"ante"] > 8:
                    state[&"phase"] = Phase.RUN_WIN; return
            state[&"phase"] = Phase.SHOP
        Phase.SHOP, Phase.EVENT, Phase.TREASURE:
            state[&"phase"] = Phase.NODE_MAP
        Phase.RUN_WIN, Phase.RUN_LOSE:
            state[&"phase"] = Phase.META_UPDATE

static func quota_of(ante: int, round_in_ante: int) -> float:
    var ante_base := 50.0 * pow(1.6, ante - 1)
    var mul := [1.0, 1.3, 1.8][round_in_ante]
    return round(ante_base * mul)

func _payout() -> void:
    var base_reward := 3 + state[&"ante"]
    var launch_bonus := state[&"launches_left"]
    var interest := mini(state[&"money"] / 5, 5)
    state[&"money"] += base_reward + launch_bonus + interest
```

---

## 11. 渲染与 Juice 解耦（View 层）

```gdscript
# view/juice_controller.gd
class_name JuiceController extends Node

@onready var _camera: Camera2D = $"../Camera2D"
var _original_cam_pos: Vector2

func on_sim_events(events: Array) -> void:
    for e in events:
        match e[&"type"]:
            SimEvent.PEG_HIT:
                _spawn_hit_particles(e[&"pos"])
                _play_hit_sfx()
            SimEvent.BOUNCE:
                _tiny_shake()

func on_settle(settle_steps: Array) -> void:
    _start_tally_animation(settle_steps)
    for s in settle_steps:
        if s[&"kind"] == &"×mult":
            _slow_mo(0.2)
            break

func _slow_mo(scale: float) -> void:
    # 只缩放视觉/音频时间轴；sim 的 DT 固定不变——确定性保持
    Engine.time_scale = scale
    await get_tree().create_timer(0.3, true, false, true).timeout
    Engine.time_scale = 1.0

func _tiny_shake() -> void:
    _camera.offset = Vector2(randf_range(-2, 2), randf_range(-2, 2))
    await get_tree().process_frame
    _camera.offset = Vector2.ZERO

# 原则：关掉所有 juice，游戏逻辑结果完全不变
```

---

## 12. 测试策略（GUT 框架）

安装：把 GUT 插件放入 `addons/gut/`，在 ProjectSettings → Plugins 启用。

```gdscript
# tests/test_collision.gd
extends GutTest

func test_swept_circle_head_on() -> void:
    var t := Collision.swept_circle(
        Vector2.ZERO, Vector2(10, 0), Vector2(10, 0), 5.0)
    assert_almost_eq(t, 0.5, 1e-4, "head-on hit at t=0.5")

func test_swept_circle_miss() -> void:
    var t := Collision.swept_circle(
        Vector2.ZERO, Vector2(10, 0), Vector2(5, 100), 5.0)
    assert_eq(t, -1.0, "should miss")

func test_reflect_off_vertical_wall() -> void:
    var v := Collision.reflect(Vector2(3, 2), Vector2(-1, 0), 1.0, 1.0)
    assert_almost_eq(v.x, -3.0, 1e-4)
    assert_almost_eq(v.y,  2.0, 1e-4)
```

```gdscript
# tests/test_determinism.gd
extends GutTest

func _run_sim() -> Array:
    var rect := Rect2(0, 0, 200, 400)
    var peg_data := [
        {&"id": 0, &"pos": Vector2(60, 120), &"radius": 8.0, &"type": null, &"exhausted": false},
        {&"id": 1, &"pos": Vector2(140, 160), &"radius": 8.0, &"type": null, &"exhausted": false},
    ]
    var cfg := {&"gravity": Vector2(0, 500), &"max_speed": 2000.0,
                &"restitution": 0.85, &"tangent_keep": 1.0, &"dt": 1.0 / 120.0}
    var sim := BallSimulation.new(rect, peg_data, cfg)
    var ball := EntryResolver.make_ball(EntryResolver.BoardEdge.TOP, 0.42, 0.15, 280.0, 5.0, rect)
    var events := []; var path := []
    for _i in 1000:
        if not ball.alive: break
        sim.step(ball, events)
        path.append(Vector2(ball.pos))
    return [path, events]

func test_same_seed_same_result() -> void:
    var a := _run_sim()
    var b := _run_sim()
    assert_eq(a[0].size(), b[0].size(), "path length must match")
    for i in a[0].size():
        assert_eq(a[0][i], b[0][i], "pos[%d] must match" % i)
```

**CI 跑法（无图形界面）**：

```bash
godot --headless --path /path/to/project \
      -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gexit
```

---

## 13. 存档与序列化

```gdscript
# meta/save_system.gd（Autoload: SaveSystem）
extends Node

const SAVE_PATH := "user://save.json"

var run_state: Dictionary = {}
var meta_state: Dictionary = {}

func save_run(state: Dictionary) -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify({&"run": state, &"meta": meta_state}, "\t"))

func load_all() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file:
        var parsed: Variant = JSON.parse_string(file.get_as_text())
        if parsed is Dictionary:
            run_state  = parsed.get(&"run",  {})
            meta_state = parsed.get(&"meta", {})
```

局快照只需存 `master_seed + input_log + 当前节点状态` → 天然支持续局与回放。

---

## 14. 性能注意（GDScript 热路径）

| 问题 | 解法 |
|---|---|
| 事件 Array 每发球反复 new | `_events.clear()` 复用同一实例 |
| `query_near` 每次 new Array | 预分配 `_query_buf: Array[int]`，clear 后 append |
| `Array.shuffle()` 用全局随机 | 替换为手写 Fisher-Yates + `DeterministicRng`（见附录 A）|
| 粒子用 CPUParticles2D | 改用 `GPUParticles2D` |
| 霓虹辉光 CPU 计算 | `CanvasItem` shader + 后处理 bloom（WorldEnvironment）|
| 同帧大量命中爆音 | 合并为一个渐强音效，节流触发 |

---

## 15. Godot 4 编辑器工作流

- **热重载**：GDScript 改完直接生效，无需 Build 步骤（GDScript vs C# 的核心优势）。
- **`@tool` 脚本**：棋盘模板可加 `@tool` 在编辑器里预览钉子布局，零运行时开销。
- **调试**：Godot 内置 Debugger，变量面板实时观察 Sim 状态；`print_debug()` 快速打印。
- **Profiler**：Godot 内置 Profiler 定位热函数，无需外部工具。
- **提交前**：headless 跑 GUT 确定性守卫测试，防止回归引入非确定性。

---

## 16. 技术里程碑（映射设计 §15）

| 设计里程碑 | 技术交付 |
|---|---|
| 1. 物理原型验手感（go/no-go）| `BallSimulation` + `BoardView` 插值 + 三边入口 + 预测线 + 基础计分 |
| 2. 积木系统 + round loop | Resource 数据层 + 触发器管线 + 球种 + 钉子改造 + 门（单槽）+ 一轮完整循环 |
| 3. run loop | `RunManager` 状态机 + 商店/经济 + Boss 词条 + 3 区 |
| 4. meta | `SaveSystem`/`UnlockManager` + 程序化棋盘扩充 + `DailySeed` |
| 5. 打磨/平衡 | `JuiceController` 全量 + 离线平衡模拟工具 + Steam Demo 构建 |
| 6. 上线 | EA→1.0；移动输入层（触控瞄准/微操）适配；Web 导出验证 |

---

## 17. 技术风险与缓解

| 风险 | 缓解 |
|---|---|
| 自写物理手感不达标 | 里程碑 1 即 go/no-go；优先打磨碰撞参数与预测线 |
| 非确定性悄悄混入 | GUT 回放测试入 CI；Sim 层严禁全局随机 |
| GDScript 性能瓶颈（意外）| 热路径 Array 复用 + PegGrid；Profiler 确认；极端情况将 `Collision` 改为 GDExtension |
| 触发器系统过度工程 | 数据+枚举覆盖 80%，长尾才写自定义逻辑 |
| `Array.shuffle()` 破坏确定性 | 全部换 Fisher-Yates + `DeterministicRng`，GUT 测试覆盖 |

---

## 18. 与 C# 版本关键差异对照

| 维度 | C# 版 | 本文（GDScript 版）|
|---|---|---|
| 数据结构 | `struct Ball`（值类型，零 GC）| `class BallState`（引用，`clone()` 复制）|
| 事件 | `readonly struct SimEvent` | `Dictionary`（StringName 键）|
| 随机 | xorshift128+（C# 实现）| xorshift128+（GDScript 实现，逻辑一致）|
| 测试框架 | xUnit（headless）| GUT（`godot --headless`）|
| 存档 | `System.Text.Json` | `JSON.stringify / parse_string` |
| 热重载 | 需手动 Build | 自动（GDScript 优势）|
| 平台覆盖 | Desktop / Android | **全平台含 Web / iOS** |
| 工具链 | .NET SDK + Rider + Godot .NET 版 | 仅需 Godot 标准版 |

---

## 附录 A：棋盘程序化生成（GDScript 版）

```gdscript
# run/board_builder.gd
class_name BoardBuilder

var _rect: Rect2

func generate(master_seed: int, ante: int, round_idx: int,
              tpl: BoardTemplate, run_mods: Dictionary, boss_mod: Dictionary) -> Array:
    var rng := DeterministicRng.derive(master_seed, ante * 100 + round_idx)
    var anchors: Array[Vector2] = (
        tpl.explicit_anchors.duplicate() if tpl.explicit_anchors.size() > 0
        else _generate_anchors(tpl, rng))
    var pegs := _fill(anchors, ante, rng)
    _apply_run_mods(pegs, run_mods)
    if not boss_mod.is_empty():
        _apply_boss(pegs, boss_mod, rng)
    if not _validate(pegs):
        return generate(master_seed + 1, ante, round_idx, tpl, run_mods, boss_mod)
    return pegs

func _fill(anchors: Array[Vector2], ante: int, rng: DeterministicRng) -> Array:
    var n := anchors.size()
    var budget := roundi(n * lerpf(0.08, 0.30, float(ante) / 8.0))
    var pegs := []
    for i in n:
        pegs.append({&"id": i, &"pos": anchors[i], &"radius": 10.0,
                     &"type": GameDB.peg_types[&"normal"], &"exhausted": false})
    # Fisher-Yates 洗牌（种子化，禁用 Array.shuffle()）
    var idx := range(n)
    for i in range(n - 1, 0, -1):
        var j := rng.range_int(0, i + 1)
        var tmp := idx[i]; idx[i] = idx[j]; idx[j] = tmp
    for k in budget:
        pegs[idx[k]][&"type"] = _roll_special(ante, rng)
    return pegs

func _validate(pegs: Array) -> bool:
    return pegs.size() >= 10  # 最简校验，后续扩展可达性检查
```

---

## 附录 B：连锁钉 BFS（确定性）

```gdscript
# 连锁引爆：显式队列 BFS + 按 peg_id 排序，禁递归 + 无序集合
func trigger_chain(start_id: int, pegs: Array, grid: PegGrid,
                   chain_radius: float, out_events: Array) -> void:
    var queue := [start_id]
    var visited := {}
    while not queue.is_empty():
        queue.sort()                                  # 每轮排序保证处理顺序确定
        var id: int = queue.pop_front()
        if id in visited: continue
        visited[id] = true
        out_events.append(SimEvent.peg_hit(id, pegs[id][&"pos"]))
        var neighbors := grid.query_near(pegs[id][&"pos"], chain_radius)
        for nid in neighbors:
            if nid not in visited:
                var t: PegType = pegs[nid][&"type"]
                if t and t.behavior == PegType.Behavior.CHAIN:
                    queue.append(nid)
```

---

## 附录 C：手感参数起步表

| 参数 | 起始值 | 含义 | 偏大/偏小体感 |
|---|---|---|---|
| `gravity.y` | 1400 | 下落加速度（px/s²）| 太大→球砸太快难读；太小→飘 |
| `max_speed` | 4000 | 限速上限 | 太大→易隧穿；太小→加速门无力 |
| `restitution` | 0.82 | 弹性（法向保留）| →1 越弹越久；过低→沉底没戏 |
| `tangent_keep` | 0.98 | 切向保留 | 低→黏滞；高→顺滑难控 |
| `dt` | 1/120 | 逻辑步长（不要动）| — |
| 发射初速 | 1500 | 入场速度 | 太大→少弹跳；太小→软绵 |
| 预测线步数 | 60 | 前瞻长度 | 太长→后段混沌误导；太短→瞄不准 |

---

## 附录 D：计分管线补充细节

### D.0 核心原则：「何时触发」与「数值怎么合」分离

飞行中按事件实时**记账**，落袋时按固定顺序**结算**。触发条件在事件当下判定（实时快照），数值延迟到落袋按 `+base → +mult → ×mult` 统一结算——顺序确定、可预期、可做逐项动画。

### D.1 三层作用域（Launch / Round / Run）

```gdscript
# scoring/score_context.gd（补充跨作用域字段）
class_name ScoreContext

# Launch 作用域（每发清空）
var ledger: Array = []
var bounce_count: int = 0
var pegs_hit: int = 0
var gate_used_accel: bool = false
var gate_used_scatter: bool = false
var launch_index: int = 0      # 本轮第几发（"每第N发"触发器用）

# Round 作用域（每轮累计，不在此清空）
# → 存在 RunManager.state["round_score"]

# Run 作用域（整局持久，触发器通过 run_scope 读写）
var run_scope: Dictionary = {
    &"total_launches": 0,      # 整局累计发射数
    &"gate_use_counts": {},    # gate_id → 使用次数
    &"money": 0,               # 当前金钱（利息触发器读）
}

func clear_for_launch(idx: int, run: Dictionary) -> void:
    ledger.clear()
    bounce_count = 0; pegs_hit = 0
    gate_used_accel = false; gate_used_scatter = false
    launch_index = idx
    run_scope = run   # 引用整局状态快照（触发器只读）

func add(kind: int, value: float, source: StringName) -> void:
    ledger.append({&"kind": kind, &"value": value, &"source": source})
```

**作用域生命周期**：
- **Launch**：`clear_for_launch()` 重置；`BallSettled` 后结算并汇入 `round_score`。
- **Round**：`round_score` 累加，轮末与 `quota` 比较；新轮开始时清零。
- **Run**：`run_scope` 整局存活，存入 `RunManager.state` 随存档持久化；触发器通过 `ctx.run_scope` 读写（如"每第5发触发"的计数器）。

### D.2 触发器遍历确定性

```gdscript
# scoring/scoring_engine.gd（补充路由逻辑）

# 按装备槽位 index 固定顺序路由事件，不用无序集合
func route_event(event: Dictionary, triggers: Array[TriggerRuntime], ctx: ScoreContext) -> void:
    # triggers 已按槽位 index 排好序（装备时维护）
    for tr in triggers:
        tr.on_event(event, ctx)

# Custom 策略类（长尾特例，如"下一次命中翻倍"）
# 在 ctx 上挂待生效修正，而非直接改未来事件
class PendingBuff:
    var remaining_triggers: int   # 还剩几次触发
    var mult_bonus: float

# Custom 触发器示例：下一次 PegHit +×2 倍率
class NextHitDoubleStrategy:
    var _pending: PendingBuff = null

    func apply(event: Dictionary, ctx: ScoreContext) -> void:
        if event[&"type"] == SimEvent.PEG_HIT:
            if _pending and _pending.remaining_triggers > 0:
                ctx.add(ScoreContext.KIND_MUL_MULT, _pending.mult_bonus, &"next_hit_double")
                _pending.remaining_triggers -= 1
        elif event[&"type"] == SimEvent.LAUNCH:
            _pending = PendingBuff.new()
            _pending.remaining_triggers = 1
            _pending.mult_bonus = 2.0
```

### D.3 确定性要点（管线侧）

- 触发器遍历按装备槽位 index，不用 Dictionary 遍历（顺序未保证）。
- 结算分三遍、层内按账本插入序（事件时间序）——Sim 确定 ⇒ 结算确定。
- Custom 策略禁 `randf()` / `randi()` / `Time`；随机走 `DeterministicRng`。
- 连锁钉引发的 `PegHit` 通过附录 B 的 BFS 队列进同一事件流，自然纳入账本，顺序确定。

### D.4 完整例子（端到端）

**场景**：分裂球（入场裂成 3 颗）+ 触发器「每弹跳 +0.2 倍率（AddMult）」+ 连锁钉 + 加速门。

```
① 加速门（AccelGate）提速 → 入场初速 ×1.5
② 分裂门（ScatterSplitGate）裂成 3 颗，扇形角度 k 升序加入球集合
③ 3 颗球依次飞行：
   - 每次 Bounce → 触发器记一条 AddMult(+0.2) 进账本
   - 每次 PegHit → 普通钉记 AddBase(+5)
   - 命中连锁钉 → BFS 按 peg_id 升序引爆相邻，每颗再生 PegHit → 继续记 AddBase
④ 3 颗球全部 BallSettled → ScoringEngine.settle():
   - 遍历一：所有 AddBase 累加 base_score（普通钉 + 连锁引爆钉）
   - 遍历二：所有 AddMult 累加 mult_add（= 0.2 × 总弹跳数）
   - 遍历三：所有 MulMult 翻乘（本例无）
   - 最终得分 = base_score × (1 + mult_add)
⑤ settle_steps 列表交给 JuiceController：逐项跳动 + 升调音效 → 满屏逐项瀑布
```

---

## 附录 E：门系统补充细节

### E.1 通道与时序

通道是入场前的一小段带壁走廊（也参与 CCD 物理，可扩加速带）。门效果在 `EnterGate` 时刻作用，之后球集合释放进主钉阵开始弹跳。

**完整事件次序**：
```
Launch → (每扇门) EnterGate → EnterField → PegHit/Bounce… → BallSettled
```
全部进同一事件流喂给计分管线。触发器用 `ctx.gate_used_accel / gate_used_scatter` 快照判断「是否经过加速/散射门」。

```gdscript
# run/gate_chain.gd（补充事件产出）
func process(entry_ball: BallState, out_events: Array) -> Array:
    var balls := [entry_ball]
    out_events.append(SimEvent.launch(entry_ball.pos))
    for gate in _gates:
        balls = gate.apply(balls)
        # 每扇门产出 EnterGate 事件（供触发器感知）
        for b in balls:
            out_events.append({&"type": &"enter_gate",
                               &"gate_id": gate.def.id, &"pos": b.pos})
    for b in balls:
        out_events.append({&"type": &"enter_field", &"pos": b.pos})
    return balls
```

### E.2 门侧确定性清单

- 散射/随机门只从 `gate_rng`（`DeterministicRng.derive(master, 2)`）取数，禁全局 `randf()`。
- 门链按装备序遍历（`_gates` 是有序 Array，不用 Dictionary）。
- 分裂门按 `k` 升序生成子球，加入 `balls` 列表——后续模拟与计分顺序确定。
- 预测线采样为纯展示，**不推进**真实 `gate_rng` 游标（创建独立克隆 rng 用于预测）：

```gdscript
# sim/trajectory_predictor.gd（预测时克隆 rng，不消耗真实子流）
static func predict_with_gate(sim: BallSimulation, entry: BallState,
                               gate_chain: GateChain, gate_rng_state: Array,
                               steps: int) -> Array[Vector2]:
    # 克隆 rng 状态（复制 _s0/_s1），不影响真实发射时的随机序列
    var rng_clone := DeterministicRng.new(0)
    rng_clone._s0 = gate_rng_state[0]
    rng_clone._s1 = gate_rng_state[1]
    var dummy_events := []
    var balls := gate_chain.process_with_rng(entry, rng_clone, dummy_events)
    if balls.is_empty():
        return []
    return TrajectoryPredictor.predict(sim, balls[0], steps)
```

### E.3 散射门设计含义

- **变角散射门（ScatterAngle）**：单球入场角度随机偏转——给玩家「变数」感，每发不完全可控，换来意外惊喜。
- **分裂散射门（ScatterSplit）**：1 球裂成扇形 N 球——给玩家「覆盖」感，扫面积而非精准瞄点。
- 两者都走种子化随机 → 每日种子/回放可复现；玩家感知为「随机」但实际确定。

---

## 附录 F：棋盘生成补充细节

### F.1 参数化生成器（纯函数，GDScript 版）

```gdscript
# run/board_builder.gd（补充各原型生成器）

func _generate_anchors(tpl: BoardTemplate, _rng: DeterministicRng) -> Array[Vector2]:
    match tpl.prototype:
        BoardTemplate.Prototype.HONEYCOMB:  return _honeycomb(tpl)
        BoardTemplate.Prototype.FUNNEL:     return _funnel(tpl)
        BoardTemplate.Prototype.TWIN_TOWER: return _twin_tower(tpl)
        BoardTemplate.Prototype.SPIRAL:     return _spiral(tpl)
    return []

# 蜂巢：偶数行偏移半格，形成六边形密铺
func _honeycomb(tpl: BoardTemplate) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var rows := 8; var cols := 7
    var spacing := 64.0; var margin := 60.0
    var top := _rect.position.y + margin + 100.0
    var left := _rect.position.x + margin
    for r in rows:
        var y := top + r * spacing
        var x_off := (r % 2) * spacing * 0.5
        for c in cols:
            var x := left + x_off + c * spacing
            if x < _rect.end.x - margin:
                pts.append(Vector2(x, y))
    return pts

# 漏斗：上宽下窄，引导球流向中央口袋
func _funnel(tpl: BoardTemplate) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var rows := 7; var margin := 50.0
    var w := _rect.size.x - margin * 2.0
    for r in rows:
        var t := float(r) / (rows - 1)
        var y := lerpf(_rect.position.y + margin + 80.0, _rect.end.y - margin - 60.0, t)
        var row_w := lerpf(w, w * 0.35, t)   # 越往下越窄
        var cols := maxi(2, roundi(lerpf(7, 3, t)))
        for c in cols:
            var x := _rect.position.x + margin + (w - row_w) * 0.5 + row_w * float(c) / (cols - 1)
            pts.append(Vector2(x, y))
    return pts

# 双塔：左右各一列高密度钉，中间留通道
func _twin_tower(tpl: BoardTemplate) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var rows := 10; var margin := 50.0; var spacing := 55.0
    var tower_x := [_rect.position.x + margin + 40.0,
                    _rect.end.x   - margin - 40.0]
    for r in rows:
        var y := _rect.position.y + margin + 80.0 + r * spacing
        for tx in tower_x:
            pts.append(Vector2(tx, y))
            if r % 3 == 0:   # 每三行加中间散钉
                pts.append(Vector2(_rect.get_center().x, y))
    return pts

# 螺旋：从外向内顺时针排列（用参数方程）
func _spiral(tpl: BoardTemplate) -> Array[Vector2]:
    var pts: Array[Vector2] = []
    var total := 48; var turns := 2.5
    var cx := _rect.get_center().x
    var cy := _rect.position.y + _rect.size.y * 0.45
    var r_max := minf(_rect.size.x, _rect.size.y) * 0.38
    for i in total:
        var frac := float(i) / (total - 1)
        var angle := frac * turns * TAU
        var r := lerpf(r_max, r_max * 0.15, frac)
        pts.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r * 1.3))
    return pts
```

### F.2 Boss 词条改棋盘（零美术成本）

Boss 关通过修改钉子类型/标记制造变化，无需新资源：

```gdscript
# run/board_builder.gd
func _apply_boss(pegs: Array, boss_mod: Dictionary, rng: DeterministicRng) -> void:
    match boss_mod[&"type"]:
        &"ban_mult":
            # 禁倍率钉：把所有 Mult 钉强制改回 Normal
            for peg in pegs:
                if peg[&"type"].behavior == PegType.Behavior.MULT:
                    peg[&"type"] = GameDB.peg_types[&"normal"]

        &"sparse":
            # 钉变稀：种子化随机移除 30% 的普通钉
            var to_remove := []
            for peg in pegs:
                if peg[&"type"].behavior == PegType.Behavior.NORMAL:
                    if rng.next_float() < 0.30:
                        to_remove.append(peg[&"id"])
            pegs = pegs.filter(func(p): return p[&"id"] not in to_remove)

        &"moving":
            # 移动钉：打标记，模拟层对有此标记的钉做确定性往复运动
            # ⚠️ 模拟层需支持动态碰撞体（CCD 用相对速度求 TOI），MVP 可后置
            for peg in pegs:
                if peg[&"type"].behavior == PegType.Behavior.NORMAL:
                    if rng.next_float() < 0.25:
                        peg[&"moving"] = true
                        peg[&"move_amp"] = rng.range_float(20.0, 50.0)
                        peg[&"move_speed"] = rng.range_float(0.5, 1.5)

        &"fogged":
            # 遮挡视野：仅 View 层遮罩，不影响物理，零逻辑改动
            for peg in pegs:
                if rng.next_float() < 0.40:
                    peg[&"fogged"] = true   # BoardView._draw() 检查此标记决定是否绘制
```

### F.3 可玩性校验（防退化）

```gdscript
func _validate(pegs: Array) -> bool:
    if pegs.size() < 10:
        push_warning("BoardBuilder: too few pegs (%d), rerolling" % pegs.size())
        return false
    # 特殊钉分布检查：确保不全堆在一个角落
    var special_count := 0
    var special_center := Vector2.ZERO
    for peg in pegs:
        if peg[&"type"].behavior != PegType.Behavior.NORMAL:
            special_count += 1
            special_center += peg[&"pos"]
    if special_count == 0:
        return true
    special_center /= special_count
    var board_center := _rect.get_center()
    # 特殊钉重心偏离棋盘中心不超过 40%（防全挤一侧）
    var deviation := (special_center - board_center).length() / (_rect.size.length() * 0.5)
    if deviation > 0.4:
        push_warning("BoardBuilder: special pegs too skewed (%.2f), rerolling" % deviation)
        return false
    return true
```

失败 → 派生下一子种子重生成（递归上限 5 次，超限用兜底安全模板）：

```gdscript
func generate(master_seed: int, ante: int, round_idx: int,
              tpl: BoardTemplate, run_mods: Dictionary, boss_mod: Dictionary,
              _attempt: int = 0) -> Array:
    if _attempt >= 5:
        push_warning("BoardBuilder: max rerolls reached, using fallback template")
        return _generate_fallback(ante)
    var rng := DeterministicRng.derive(master_seed + _attempt, ante * 100 + round_idx)
    # … 生成逻辑 …
    if not _validate(pegs):
        return generate(master_seed, ante, round_idx, tpl, run_mods, boss_mod, _attempt + 1)
    return pegs
```

### F.4 棋盘侧确定性清单

- `rng = DeterministicRng.derive(master_seed + attempt, ante * 100 + round_idx)` → 每张棋盘独立可复现。
- 生成器为纯函数（无副作用）；洗牌 / 抽类型只走 `rng`；叠加顺序固定（run_mods → boss → validate）。
- 重 roll 走 `_attempt` 递增派生种子，不共用同一游标。
- `Array.filter()` 返回新 Array，原 `pegs` 引用在移除后需重新赋值（GDScript 无原地 remove_if）。

### F.5 与「棋盘即引擎」的关系

玩家钉子改造存入 `run_mods`（`RunManager.state["run_mods"]`），整局常驻、逐区累积：

```gdscript
# run/run_manager.gd（补充 run_mods 管理）

# 玩家购买"钉子改造"时调用
func apply_peg_mod(peg_id: int, new_type_id: StringName) -> void:
    state[&"run_mods"][peg_id] = new_type_id   # 记录：哪个钉 → 改成什么类型

# BoardBuilder._apply_run_mods() 每区生成后套用
func _apply_run_mods(pegs: Array, run_mods: Dictionary) -> void:
    for peg in pegs:
        if peg[&"id"] in run_mods:
            peg[&"type"] = GameDB.peg_types[run_mods[peg[&"id"]]]
```

即便每区棋盘结构不同（模板可能换），玩家累积的改造通过 `_apply_run_mods` 重新套用——引擎**肉眼可见地长在战场上**，与 Balatro 把引擎放侧栏形成根本差异。

---

## 附录 G：商店与节点地图实现细节

### G.1 商店（生成 / 刷新 / 移除，种子化）

```gdscript
# run/shop.gd
class_name Shop

const SLOT_COUNT := 4
const BASE_REROLL_COST := 1
const REROLL_STEP := 1   # 每次刷新涨价 1

var offerings: Array = []   # Array of {item, price, sold}

# 刷新次数进种子 → 每次刷新结果可复现
func roll(master_seed: int, ante: int, node_cursor: int, reroll_count: int) -> void:
    var tag := ante * 10000 + node_cursor * 100 + reroll_count
    var rng := DeterministicRng.derive(master_seed, tag)
    offerings.clear()
    for _i in SLOT_COUNT:
        var category := _roll_category(rng, ante)
        var item := _roll_item(category, ante, rng)
        offerings.append({
            &"item": item,
            &"price": _price_of(item, ante),
            &"sold": false
        })

func reroll_cost(reroll_count: int) -> int:
    return BASE_REROLL_COST + reroll_count * REROLL_STEP

# 按区权重抽类别：深区提升触发器/门的概率
func _roll_category(rng: DeterministicRng, ante: int) -> StringName:
    var weights := {
        &"trigger":  40 + ante * 3,
        &"orb":      30,
        &"peg_mod":  20,
        &"gate":     10 + ante * 2,
    }
    var total := 0
    for w in weights.values(): total += w
    var roll := rng.range_int(0, total)
    var acc := 0
    for cat in weights:
        acc += weights[cat]
        if roll < acc: return cat
    return &"trigger"

# 按稀有度权重抽具体物品（×倍率等稀有件深区略升但仍稀缺）
func _roll_item(category: StringName, ante: int, rng: DeterministicRng) -> Resource:
    var pool := _get_pool(category)
    var weights := []
    for item in pool:
        var base_w := 100 - item.rarity * 25          # rarity 0=常见, 1=中等, 2=稀有, 3=传说
        var ante_bonus := item.rarity * ante           # 深区稀有件略升
        weights.append(maxi(5, base_w + ante_bonus))
    var total := 0
    for w in weights: total += w
    var roll := rng.range_int(0, total)
    var acc := 0
    for i in pool.size():
        acc += weights[i]
        if roll < acc: return pool[i]
    return pool[-1]

func _price_of(item: Resource, ante: int) -> int:
    var base := [3, 5, 8, 12][mini(item.rarity, 3)]
    return base + ante / 2   # 深区价格略涨

# 购买：扣钱 → 装备到 Inventory（槽满需先移除）
func buy(slot: int, inventory: Dictionary, money_ref: Array) -> bool:
    var offer: Dictionary = offerings[slot]
    if offer[&"sold"] or money_ref[0] < offer[&"price"]:
        return false
    money_ref[0] -= offer[&"price"]
    offer[&"sold"] = true
    inventory[&"items"].append(offer[&"item"])
    return true

# 移除服务：付费删一件（防哑火/转型关键）
func remove_item(item_idx: int, inventory: Dictionary, money_ref: Array) -> bool:
    const REMOVE_COST := 3
    if money_ref[0] < REMOVE_COST: return false
    money_ref[0] -= REMOVE_COST
    inventory[&"items"].remove_at(item_idx)
    return true
```

### G.2 节点地图（MVP 可极简）

```gdscript
# run/node_map.gd
class_name NodeMap

enum NodeType { SHOP, EVENT, TREASURE, ELITE }

var layers: Array = []   # Array of Array[Dictionary]（每层若干节点）
var cursor: int = 0      # 当前层

# 每区 3 轮之间插入 2 个节点（MVP：固定进商店 + 一个三选一事件）
static func generate_mvp(master_seed: int, ante: int) -> NodeMap:
    var map := NodeMap.new()
    var rng := DeterministicRng.derive(master_seed, ante * 999)
    # MVP 两层：每层只有一个节点（线性，无分支）
    map.layers = [
        [{&"type": NodeType.SHOP}],
        [{&"type": NodeType.EVENT if rng.next_float() > 0.3 else NodeType.TREASURE}],
    ]
    return map

# 完整版（后续解锁）：每层 2–3 个节点供玩家选路，每层保底一个安全节点（SHOP）
static func generate_full(master_seed: int, ante: int) -> NodeMap:
    var map := NodeMap.new()
    var rng := DeterministicRng.derive(master_seed, ante * 999)
    map.layers = []
    for layer in 2:   # 每区 2 个节点层
        var nodes := []
        var has_safe := false
        for _slot in rng.range_int(2, 4):   # 2–3 个节点
            var t := _roll_node_type(rng)
            if t == NodeType.SHOP: has_safe = true
            nodes.append({&"type": t})
        if not has_safe:
            nodes[0][&"type"] = NodeType.SHOP   # 保底一个商店
        map.layers.append(nodes)
    return map

static func _roll_node_type(rng: DeterministicRng) -> int:
    var r := rng.next_float()
    if r < 0.45: return NodeType.SHOP
    if r < 0.70: return NodeType.EVENT
    if r < 0.90: return NodeType.TREASURE
    return NodeType.ELITE

func current_nodes() -> Array:
    if cursor >= layers.size(): return []
    return layers[cursor]

func advance() -> void:
    cursor += 1
```

### G.3 确定性 & 存档要点

- 所有随机 `DeterministicRng.derive(master_seed, 唯一tag)` 派生独立子流，不共用游标。
- `RunManager.state` 完整序列化为 JSON（含 `run_mods`、`inventory`、`input_log`、`node_map.cursor`）。
- 续局：`load_all()` → `RunManager` 从序列化状态恢复，直接 `advance()` 继续。
- 回放测试：固定 `master_seed + input_log` 重跑 `advance()` → 断言最终 `state` 逐字段一致。

```gdscript
# tests/test_run_manager.gd
extends GutTest

func test_replay_same_final_state() -> void:
    var a := _run_headless(12345, _make_inputs())
    var b := _run_headless(12345, _make_inputs())
    assert_eq(a[&"round_score"], b[&"round_score"])
    assert_eq(a[&"money"],       b[&"money"])
    assert_eq(a[&"ante"],        b[&"ante"])

func _run_headless(seed: int, inputs: Array) -> Dictionary:
    var mgr := RunManager.new()
    mgr.state[&"master_seed"] = seed
    mgr.advance()   # RUN_START
    for inp in inputs:
        mgr.advance(inp)
    return mgr.state.duplicate()
```

---

## 附录 H：离线平衡模拟工具

### H.1 用途

批量跑 N 局「中位 build」，导出每区通过率曲线和破表分布，辅助调 quota 系数（对应设计 §4 数值表）。

### H.2 实现（GDScript headless 脚本）

```gdscript
# tools/balance_sim.gd（以 --headless -s 方式运行）
extends SceneTree

const SEEDS := 500
const ANTE_MAX := 8

func _init() -> void:
    var results := []
    for s in SEEDS:
        results.append(_simulate_run(s, _median_build()))
    _export_csv(results)
    quit()

func _simulate_run(seed: int, build: Dictionary) -> Dictionary:
    var mgr := RunManager.new()
    mgr.state[&"master_seed"] = seed
    # 预装中位 build（5 个触发器槽）
    mgr.state[&"inventory"] = {&"items": build[&"triggers"].duplicate()}
    var per_ante := []
    for _ante in ANTE_MAX:
        var passed := _play_ante(mgr)
        per_ante.append(passed)
        if not passed: break
    return {&"seed": seed, &"per_ante": per_ante,
            &"final_ante": mgr.state[&"ante"],
            &"final_score": mgr.state[&"round_score"]}

func _play_ante(mgr: RunManager) -> bool:
    for _round in 3:
        # 模拟一轮：用随机瞄准点跑若干发球
        var score := _simulate_round(mgr.state)
        mgr.state[&"round_score"] = score
        mgr.advance()   # 判定 quota
        if mgr.state[&"phase"] == RunManager.Phase.RUN_LOSE:
            return false
    return true

func _simulate_round(state: Dictionary) -> float:
    # 简化：固定从顶边中点发射，跑 5 发，汇总基础分
    var rect := Rect2(0, 0, 540, 900)
    var pegs := BoardBuilder.new().generate(
        state[&"master_seed"], state[&"ante"], state[&"round_in_ante"],
        GameDB.board_templates[&"honeycomb"], state.get(&"run_mods", {}), {})
    var cfg := {&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
                &"restitution": 0.82, &"tangent_keep": 0.98, &"dt": 1.0 / 120.0}
    var sim := BallSimulation.new(rect, pegs, cfg)
    var scorer := ScoringEngine.new()
    var total := 0.0
    for _i in state.get(&"launches_left", 5):
        var ball := EntryResolver.make_ball(
            EntryResolver.BoardEdge.TOP, 0.5, 0.0, 1500.0, 8.0, rect)
        var events := []
        var ctx := ScoreContext.new()
        while ball.alive:
            sim.step(ball, events)
        for e in events:
            scorer.route_event(e, state.get(&"equipped_triggers", []), ctx)
        var res := scorer.settle(ctx)
        total += res[0]
    return total

func _median_build() -> Dictionary:
    # 中位 build：2 个 +基础分触发器 + 2 个 +倍率触发器 + 1 个 ×倍率触发器
    return {&"triggers": [
        GameDB.triggers[&"add_base_on_hit"],
        GameDB.triggers[&"add_base_on_hit"],
        GameDB.triggers[&"add_mult_on_bounce"],
        GameDB.triggers[&"add_mult_on_bounce"],
        GameDB.triggers[&"mul_mult_on_10_hits"],
    ]}

func _export_csv(results: Array) -> void:
    var file := FileAccess.open("user://balance_sim.csv", FileAccess.WRITE)
    file.store_line("seed,final_ante,final_score," +
                    ",".join(Array(range(ANTE_MAX)).map(func(i): return "ante%d" % (i+1))))
    for r in results:
        var ante_cols := ",".join(r[&"per_ante"].map(func(p): return "1" if p else "0"))
        file.store_line("%d,%d,%.0f,%s" % [r[&"seed"], r[&"final_ante"],
                                            r[&"final_score"], ante_cols])
    print("Balance sim done → user://balance_sim.csv")
```

**运行方式**：

```bash
godot --headless --path /path/to/project -s res://tools/balance_sim.gd
```

输出 CSV 用 Excel / Python / Jupyter 绘制「每区通过率曲线」和「破表分布」，据此调整 `quota_of()` 的底数与增长系数。

---

## 附录 I：Juice 补充细节

### I.1 升调音效（连锁越长越高）

```gdscript
# view/juice_controller.gd（补充升调逻辑）

const BASE_PITCH := 1.0
const PITCH_STEP := 1.06   # 每个结算步升一个半音约的音高

func _start_tally_animation(steps: Array) -> void:
    for i in steps.size():
        var s: Dictionary = steps[i]
        # 每步延迟播放，形成逐项跳动节奏
        await get_tree().create_timer(i * 0.12).timeout
        _play_tally_sfx(i)
        _animate_score_label(s)
        if s[&"kind"] == &"×mult":
            _big_shake()
            _slow_mo(0.15)

func _play_tally_sfx(step_index: int) -> void:
    var player := $TallySfxPlayer as AudioStreamPlayer
    # pitch = basePitch × 1.06^step_index（连锁越长，音越高）
    player.pitch_scale = BASE_PITCH * pow(PITCH_STEP, step_index)
    player.play()
```

### I.2 关键纪律

- 慢动作只缩放 `Engine.time_scale`（视觉/音频时间轴），绝不改 Sim 的 `DT`——确定性保持。
- `_tiny_shake()` 里的 `randf_range` 是**纯视觉噪声**，不影响任何游戏逻辑，允许用全局随机（不需要确定性）。
- Juice 只读 `SimEvent` 和 `settle_steps`，不写任何逻辑状态——关掉所有 juice，分数完全不变。

### I.3 音效节流（防同帧爆音）

```gdscript
# view/juice_controller.gd
var _hit_queue: int = 0     # 本帧累计命中次数
var _hit_timer: float = 0.0

func on_sim_events(events: Array) -> void:
    for e in events:
        match e[&"type"]:
            SimEvent.PEG_HIT:
                _hit_queue += 1
                _spawn_hit_particles(e[&"pos"])
            SimEvent.BOUNCE:
                _tiny_shake()

func _process(delta: float) -> void:
    if _hit_queue > 0:
        _hit_timer += delta
        if _hit_timer >= 0.016:   # 每帧最多触发一次合并音效
            _play_merged_hit_sfx(_hit_queue)
            _hit_queue = 0; _hit_timer = 0.0

func _play_merged_hit_sfx(count: int) -> void:
    var player := $HitSfxPlayer as AudioStreamPlayer
    # 命中越多，音量越大（线性到 dB，封顶防爆音）
    player.volume_db = linear_to_db(clampf(1.0 + count * 0.15, 1.0, 3.0))
    player.play()
```
