# 霓虹边框 + 连击追逐光设计文档

**日期：** 2026-06-12
**主题：** 把四周墙做成真辉光霓虹边框，击中/连击充能时一圈跑马灯追逐光循环流动，越连越烫色

---

## 目标

让四周边界变成会发光的霓虹光管，并与击中/连击联动：短时间内连续击中会给边框"充能"，一圈追逐光（跑马灯）沿边框循环流动，热度越高脉冲越多、越快、越亮、色相越烫；停手后约 2 秒冷却回平静的暗青常亮。配合刚做的击中反馈，把 NeonPinball 的"霓虹"质感真正立起来。

## 设计原则

- **对确定性 sim 零侵入**：全部活在 view 层与渲染环境，sim/计分不变，现有 207 测试保持全绿。
- **热度独立于计分 combo**：计分 combo 落地清零；本特性用一个**时间衰减的热度 `_wall_heat ∈ [0,1]`**，跨发射、跨整局累积，符合"短时间内连击就循环播放"。
- **饱和不褪白**：色相报热度、亮度+bloom 报强度，但始终是饱和霓虹色，绝不褪成白（褪白丢霓虹味；bloom 芯部自然过曝的白边可接受）。
- **纯逻辑可测**：所有"热度/相位 → 颜色/条数/速度/坐标"的映射都是纯函数，全部 TDD 单测；渲染本身实机确认。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript，Forward+；项目根 `D:/NeonPinball/game/`。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**207 个测试全部通过，32 个脚本**。
- **全游戏无辉光**：无 WorldEnvironment / glow / bloom（peg 的 `glow` 属性只是颜色字段，非渲染辉光）。背景纯黑（`default_clear_color=Color(0,0,0,1)`）。
- 墙绘制在 `view/board_view.gd` 的 `_draw_walls()`：全部 `draw_line(a, b, color, width)`，扁平青色/橙色/绿色。
- board 场景 `scenes/board.tscn`：`BoardView`(Node2D) + `Hud`(CanvasLayer) + `InputController` + `Camera2D`。无 Environment。
- `_combo`(int) 已存在（击中反馈系统），落地清零——本特性**不复用它做热度**，另起时间衰减热度。
- 边界几何（局部坐标，`_rect = Rect2(135,225,540,900)`，`o = _rect.position`）：
  - 顶墙 y=0、左墙 x=0、右墙 x=540（各被门缺口分两段，门由 `_channel_geometry` 动态算）
  - 漏斗：`o+(0,780)→o+(240,900)` 与 `o+(540,780)→o+(300,900)`，底部缺口在 x∈[240,300]

---

## 系统组成

### 1. WorldEnvironment + `Environment`（渲染环境，board 场景）

**职责：** 开启 2D 辉光，让亮色溢光成霓虹。

- 在 `scenes/board.tscn` 加 `WorldEnvironment` 节点，挂一个 `Environment`（存为 `data/resources/board_env.tres`，沿用本项目 .tres + ext_resource 习惯——但 Environment 是内置类，直接 `type="Environment"` 即可，无需脚本引用）。
- 关键参数：`glow_enabled = true`；`glow_blend_mode = ADDITIVE`；`glow_hdr_threshold ≈ 1.0`（只有亮度 >1 的内容强溢光，普通 HUD 不糊）；`glow_intensity`/`glow_bloom`/`glow_strength` 调到霓虹感。
- 开启 2D HDR：项目设置 `rendering/viewport/hdr_2d = true`，使 canvas 颜色分量可超过 1.0 并强烈 bloom。
- **HUD 注意**：glow 是整视口后处理，HUD 文字也会被波及。靠 `glow_hdr_threshold ≈ 1.0` + HUD 颜色保持 ≤1.0 规避；若实机发现 HUD 发糊，再单独处理（提阈值或 HUD 单独 viewport）——记 Backlog。

### 2. `juice/neon_frame.gd`（新建，纯逻辑 + 几何）

**职责：** 热度/相位 → 颜色/脉冲参数/边框坐标的纯函数，可完整单测。

- `const IDLE := Color(0.0, 0.9, 1.0)`、`const HOT := Color(1.0, 0.15, 0.55)`（饱和热粉，不到白）
- `static func heat_color(heat: float) -> Color`
  线性插值 `IDLE.lerp(HOT, clampf(heat,0,1))`。heat 0→青，heat 1→热粉。始终饱和。
- `static func pulse_count_for_heat(heat: float) -> int`
  `0` 当 heat < 0.05（完全平静无脉冲）；否则 `1 + floori(heat * 3.0)`（1→4 条）。单调不降、有界。
- `static func speed_for_heat(heat: float) -> float`
  `lerpf(0.15, 0.8, clampf(heat,0,1))`（每秒绕框圈数）。单调。
- `static func brightness_for_heat(heat: float) -> float`
  脉冲峰值亮度倍率 `lerpf(1.2, 3.0, clampf(heat,0,1))`（>1 触发强 bloom）。单调。
- `static func decay_heat(heat: float, delta: float) -> float`
  `maxf(heat - DECAY_RATE * delta, 0.0)`，`const DECAY_RATE := 0.5`（满热约 2s 冷却到 0）。单调趋零、不为负。
- `static func point_at(poly: PackedVector2Array, s: float) -> Vector2`
  把 `s ∈ [0,1)` 按**弧长**映射到闭合折线 `poly`（首尾相连）上的坐标。s=0→poly[0]，s 绕一圈回到起点。线性插值各段。

> 充能常数 `HEAT_PER_HIT := 0.12` 也放此文件作 `const`，board_view 引用。

### 3. `view/board_view.gd`（改动，状态 + 绘制接线）

- 新增状态：`var _wall_heat := 0.0`、`var _neon_phase := 0.0`、`const HALF_PULSE_LEN := 0.04`（脉冲沿边框的归一化半宽）。
- 预载 `const NeonFrameScript := preload("res://juice/neon_frame.gd")`。
- **边框折线** `_neon_perimeter() -> PackedVector2Array`：按桶形边界闭合走一圈，顺序
  `顶左角 → 顶右角 → 右墙底 → 右漏斗内点(300,900) → 左漏斗内点(240,900) → 左墙底 → 回顶左角`
  （用 `o + 局部点`；忽略门缺口，做成连续装饰光框）。
- PEG_HIT 处（已有 `_combo += 1` 那块）：`_wall_heat = minf(_wall_heat + NeonFrameScript.HEAT_PER_HIT, 1.0)`。
- `_process(delta)`（在不依赖 `_has_ball` 的那段，与 combo 显示计时同处）：
  `_wall_heat = NeonFrameScript.decay_heat(_wall_heat, delta)`；
  `_neon_phase = fmod(_neon_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat), 1.0)`。
- `_draw()`（在 `_draw_walls()` 之后叠加）：调用新 `_draw_neon_frame()`：
  1. 底框：沿 `_neon_perimeter()` 画 `heat_color(_wall_heat)` 的暗光描边（亮度 ~0.6），各段 `draw_line` 宽 ~2.5。
  2. 追逐光：`var n := pulse_count_for_heat(_wall_heat)`；对 `i in n`，`s = fmod(_neon_phase + float(i)/n, 1.0)`；在 `point_at(poly, s)` 附近沿边框画一小段高斯衰减高亮（采样 `s ± 0..HALF_PULSE_LEN` 若干点连线），颜色 `heat_color(_wall_heat)` 乘 `brightness_for_heat(_wall_heat)`（分量可 >1，触发 bloom）。

> 现有 `_draw_walls()` 的功能性墙/门/漏斗/通道线**保留**（它们现在也会被 bloom 轻微照亮）；霓虹边框是叠加在边界上的装饰追逐层。

---

## 数据流

```
PEG_HIT（确定性事件，不变）
   └─→ board_view: _wall_heat += HEAT_PER_HIT（封顶 1）
每帧 _process:
   _wall_heat = decay_heat(_wall_heat, delta)         # 时间冷却
   _neon_phase += delta * speed_for_heat(_wall_heat)  # 相位推进（取模 1）
_draw():
   底框 = heat_color(_wall_heat) 暗描边
   for i in pulse_count_for_heat(_wall_heat):
       s = frac(_neon_phase + i/n)
       在 point_at(perimeter, s) 画 heat_color×brightness 高亮脉冲
   → WorldEnvironment Glow 后处理 → 霓虹溢光
```

热度只读 PEG_HIT 事件，不回写 sim/计分。

---

## 测试策略

新增约 9 个测试（纯函数 + 几何），对 sim 零侵入，207 基线保持全绿。

`tests/test_neon_frame.gd`：
- `heat_color(0)` == IDLE 青；`heat_color(1)` == HOT 热粉；`heat_color(1)` **不是白**（断言 `g < 0.5` 或 `b < 0.9` 等，确保未褪白）
- `heat_color` 在 0→1 间 R 分量单调不降、B 分量单调不增（青→粉的趋势）
- `pulse_count_for_heat(0)` == 0；heat≥0.05 时 ≥1；单调不降；封顶 ≤4
- `speed_for_heat` / `brightness_for_heat`：单调不降、落在各自区间
- `decay_heat`：结果不为负；`decay_heat(1.0, 2.0) == 0`（2s 冷却到 0）；不超过原值
- `point_at`：用单位正方形折线 `[(0,0),(1,0),(1,1),(0,1)]`，`point_at(0)`==(0,0)；`point_at(0.25)`≈(1,0)（周长 4，1/4 处到第二顶点）；`point_at(0.5)`≈(1,1)

渲染/场景（WorldEnvironment、`_draw_neon_frame`、hdr_2d）：场景加载检查 + 实机确认，不单测（与现有渲染代码一致）。

---

## 验收标准

- [ ] board 场景有真 bloom：亮色溢光，整体霓虹质感
- [ ] 四周边框是会发光的霓虹光管（平静时暗青常亮）
- [ ] 击中充能：短时间连击 → 边框追逐光出现并加速变多变亮
- [ ] 热度越高色相越烫（青→紫→热粉），**始终饱和、不褪白**
- [ ] 停手约 2 秒冷却回平静暗青，脉冲消失
- [ ] 纯函数映射全部单测通过；216+ 全绿
- [ ] HUD 文字未被 glow 糊（或已记 Backlog 待处理）
- [ ] 无回归：物理、计分、商店、关卡流程、击中反馈正常

---

## 后期备用项（Backlog）

- 主菜单 / 其他场景也上 WorldEnvironment 辉光，全局统一霓虹
- 钉子/球专属霓虹调色与发光强度微调（现在它们已被动 bloom）
- 追逐光经过门缺口时的处理精修（当前做成连续装饰框，忽略缺口）
- 若 HUD 被 glow 糊：HUD 单独 viewport 或提 glow 阈值
- 热度也驱动其他元素（背景脉动、钉子微亮）联动
- 上一特性遗留：逐击 hit-stop 平滑恢复版 / 只在关键时刻顿

---

## 已知局限 / 留待后续

- 2D glow 是整视口后处理，HUD/全部 CanvasItem 都受影响；靠阈值+颜色控制规避，必要时再隔离。
- `hdr_2d` 为项目级渲染设置，影响所有 2D 场景的颜色处理；本期只在 board 验证视觉，其他场景若异常再评估。
- 霓虹边框做成连续装饰框（忽略门开关缺口），与功能性墙段分离绘制；视觉优先。
- `_wall_heat` 仅 view 层状态，不持久化、不影响存档与确定性回放。
