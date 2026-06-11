# Boundary Walls, Funnel & Launcher System — Design Spec

**Date:** 2026-06-11  
**Status:** Approved

## Goal

给 NeonPinball 添加：
1. 可视边界墙（左/右/上弹性反弹，底部漏斗低弹导向回收）
2. 三个固定发射器（LEFT/TOP/RIGHT），各有短通道和可开关的门
3. 鼠标 + 键盘双控旋转，Space/鼠标左键发射
4. 球落入漏斗后沿坡滑向开口被回收，结算逻辑不变

---

## Section 1: 物理引擎扩展

### 1.1 `sim/collision.gd` — 新增 `swept_segment`

```gdscript
static func swept_segment(p: Vector2, d: Vector2, r: float,
                           seg_a: Vector2, seg_b: Vector2) -> Dictionary
```

算法：
1. 将线段投影为无限直线，求圆心到直线的距离，解 CCD 二次方程得 t_line
2. 再对两端点分别做 swept_circle（端点 cap）
3. 取三者中最小合法 t∈[0,1]，命中返回 `{t, normal}`，未命中返回 `{}`

法线方向：始终指向球所在侧（`(p + d*t - closest_point).normalized()`）。

### 1.2 `sim/ball_simulation.gd` — 额外墙段支持

新增字段：
```gdscript
var _wall_segs: Array = []  # [{a:Vector2, b:Vector2, restitution:float}]
```

`_find_earliest()` 在现有 peg + rect 检查之后，遍历 `_wall_segs` 调用 `swept_segment()`，按 t 最小选取最近碰撞。  
每段有独立 restitution，传给 `Collision.reflect()`（覆盖全局 `_cfg[&"restitution"]`）。

新增公共方法：
```gdscript
func set_wall_segs(segs: Array) -> void:
    _wall_segs = segs
```

矩形左/右/上墙（`swept_walls`）**保持不变**。矩形底部**保持开放**。

---

## Section 2: 场地几何

### 2.1 板面居中

| 参数 | 旧值 | 新值 |
|---|---|---|
| `_rect` | `Rect2(0, 0, 540, 900)` | `Rect2(135, 225, 540, 900)` |
| 画布 | 810×1350 | 810×1350（不变） |

左右各留 135px、顶部留 225px、底部留 225px 供通道/发射器/回收区使用。  
`_build_honeycomb()` 中所有绝对坐标改为 `_rect.position + 局部偏移`。

### 2.2 漏斗（板面内部坐标，相对 `_rect.position`）

| 线段 | 起点（局部） | 终点（局部） | restitution |
|---|---|---|---|
| 左漏斗壁 | (0, 780) | (240, 900) | 0.05 |
| 右漏斗壁 | (540, 780) | (300, 900) | 0.05 |

漏斗开口：x=240..300（局部），宽 60px，位于 y=900 底边。  
球出界条件不变：`ball.pos.y - ball.radius > _rect.end.y` → `alive = false`。

### 2.3 门的位置（板面内部坐标，相对 `_rect.position`）

| 门 | 线段（局部坐标） | 方向 |
|---|---|---|
| LEFT  | x=0，y=115..155  | 竖直（平行左墙） |
| RIGHT | x=540，y=115..155 | 竖直（平行右墙） |
| TOP   | y=0，x=195..255  | 水平（平行上墙） |

### 2.4 发射器位置（画布绝对坐标）

发射器 y 坐标须**高于**对应门的中心 y 坐标，使通道呈斜向下走势（"靠上"设计要求）。

| 发射器 | 画布坐标（参考值） | 对应门中心（画布） | 通道方向 |
|---|---|---|---|
| LEFT  | (55, 255)  | (135, 360) | 斜向右下，约 52° |
| TOP   | (405, 112) | (405, 225) | 竖直向下，90°   |
| RIGHT | (755, 255) | (675, 360) | 斜向左下，约 52° |

> 具体像素坐标在实现阶段可微调，保证通道在视觉上自然即可。

### 2.5 各门对应的固定 t 值（EntryResolver）

| 门 | 边 | 门中心（局部） | t 值（沿边归一化） |
|---|---|---|---|
| LEFT  | 左边（高度=900） | y=135 | 135/900 ≈ 0.150 |
| RIGHT | 右边（高度=900） | y=135 | 135/900 ≈ 0.150 |
| TOP   | 上边（宽度=540） | x=225 | 225/540 ≈ 0.417 |

这些常量定义在 `entry_resolver.gd` 中供 `InputController` 使用。

### 2.6 通道壁（画布绝对坐标，纯视觉，不加入物理）

每个通道由两条短线段定义，在 `_draw()` 中绘制，颜色与围墙一致（cyan）。

| 通道 | 壁线 1 | 壁线 2 |
|---|---|---|
| LEFT  | 门上端 → 发射器左上 | 门下端 → 发射器右下 |
| TOP   | 门左端 → 发射器左侧 | 门右端 → 发射器右侧 |
| RIGHT | 门上端 → 发射器右上 | 门下端 → 发射器左下 |

> **Future / Phase 2：** 若视觉效果不佳，可升级为 Option 2——球从发射器位置生成，通道壁加入物理（需处理 _rect 外侧的单向墙问题）。

---

## Section 3: 发射器控制

### 3.1 旋转

```gdscript
var _aim_angle: float = 0.0   # 相对于各发射器入射方向的旋转偏移（弧度）
```

| 输入 | 行为 |
|---|---|
| 鼠标移动 | 计算鼠标相对当前发射器画布坐标的角度，写入 `_aim_angle` |
| A 键按住 | `_aim_angle -= deg_to_rad(1.5) * delta * 60` |
| D 键按住 | `_aim_angle += deg_to_rad(1.5) * delta * 60` |

角度夹紧：±60°（`clampf(_aim_angle, -PI/3, PI/3)`），确保球始终穿过门进入场地。  
两种输入共用同一 `_aim_angle`，互不冲突（鼠标移动直接覆盖，键盘增量叠加）。

### 3.2 发射

- 触发：鼠标左键 OR Space 键
- 球从**门的中心点**生成（画布坐标），方向由 `_aim_angle` + 各门入射方向合成
- 生成逻辑复用 `EntryResolver.make_ball()`，传入固定 `_t`（各门中心对应的 t 值）

### 3.3 预测线

不变，从门位置出发，使用当前 `_aim_angle`。

---

## Section 4: 门的开关

```gdscript
var _gate_seg_active: bool = false   # 当前激活门的物理线段是否在 _wall_segs 中
```

| 时机 | 操作 |
|---|---|
| 初始化 / 新球准备 | 移除当前激活门线段；其余两门线段**始终留在** `_wall_segs` |
| `_gate_applied` 触发（球穿越门阈值） | 将当前激活门线段加入 `_wall_segs`；`_sim.set_wall_segs(...)` |
| `launch()` 被调用 | 重新移除当前门线段（门打开）；`_sim.set_wall_segs(...)` |

"始终关闭的两个门"防止球从未使用的通道逃出。  
门线段的 restitution 与侧墙一致（0.82）。

---

## Section 5: 球回收

逻辑**不变**：`ball.alive = false` → `_on_all_settled()` 正常结算。  
漏斗壁（低弹性）将球导向开口；球从开口落出时 `pos.y > _rect.end.y`，触发现有回收流程。  
`launches_left` 不额外扣减——漏斗只是视觉通道，一次 launch 计数以 `_on_all_settled` 为准。

---

## Section 6: 测试

| 文件 | 新增测试（约） |
|---|---|
| `test_collision.gd` | swept_segment：平行不碰、垂直命中、端点命中、背面不碰（3-4个） |
| `test_ball_simulation.gd` | 球碰漏斗壁低弹、球从开口出界、非开口处不出界（3个） |
| `tests/test_gate_physics.gd`（新） | 门关闭球被挡、门开放球穿过、Tab 切换后正确门关闭（4-5个） |

预计新增 ~12 个测试，162 → ~174。

---

## 涉及文件

| 文件 | 改动性质 |
|---|---|
| `sim/collision.gd` | 新增 `swept_segment`（~35行） |
| `sim/ball_simulation.gd` | 新增 `_wall_segs` + `set_wall_segs` + `_find_earliest` 扩展（~25行） |
| `view/board_view.gd` | `_rect` 居中、漏斗线段、门线段、gate open/close 逻辑、`_draw` 更新（中型） |
| `view/input_controller.gd` | 固定发射器位置、A/D 键旋转、Space 发射（中型） |
| `sim/entry_resolver.gd` | 新增各门固定 t 值常量（小） |
| `tests/test_collision.gd` | swept_segment 测试（小） |
| `tests/test_ball_simulation.gd` | 漏斗测试（小） |
| `tests/test_gate_physics.gd` | 新建，门物理测试（小） |
| `game/project.godot` 或场景文件 | board_view 节点位置居中（视实现方式） |
