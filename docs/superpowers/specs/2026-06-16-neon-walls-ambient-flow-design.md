# 霓虹墙常驻流光 + 连击提速变色 设计文档

**日期：** 2026-06-16
**主题：** 给中空霓虹墙加"常驻明暗行波 + 缓慢循环变色"（不依赖击中也在跑），内外双线 + 灯泡同步；墙更宽、灯更密、对比更强；连击时提速 + 加速变色 + 加宽色域 + 加亮 + 叠热脉冲（绝对速度比现在略慢）

---

## 目标

实机发现：默认状态下灯泡的缓慢流动看不出来、明暗对比太低、跑马灯只在外线、不击中时没有动感。本次升级：
- 内外双线 + 灯泡**始终**跑一条缓慢的**明暗行波**（波峰亮波谷暗、对比拉大、多个波峰），并**缓慢循环变色**——即使没击中也在动、在变色。
- 内外线同步。
- 墙更宽、灯更密。
- 连击（`_wall_heat`）时：**提速 + 加速变色 + 加宽色域（颜色变多）+ 加亮**，并叠加现有热追逐光脉冲；但绝对速度比当前实现**略慢一档**。

## 设计原则

- **在现有中空墙特性上增量**：复用 `_wall_heat`/`_neon_phase`，新增 `_neon_hue_phase`（变色相位）。
- **可见性靠对比+变色，不靠飙速**：行波明暗对比拉大、颜色缓慢循环；速度保持慢，连击才提。
- **零侵入 sim**：纯 view 层 + 纯函数；现有 254 测试除受影响项外保持绿。
- **纯函数可测**：行波亮度、色相、流速曲线都是纯函数，TDD 单测。

---

## 现状（代码库上下文）

- 基线 **254 测试全绿，37 脚本**。缩进 TAB。
- `juice/neon_frame.gd`（NeonFrame）：`heat_color`、`pulse_count_for_heat`（heat<0.05→0，封顶 4）、`speed_for_heat`（**现 0.15→0.8**）、`brightness_for_heat`、`decay_heat`、`point_at`、`hue_spread_for_heat`（0.1→0.5）、`bulb_color(p, phase, heat)`、consts `COOL_HUE 0.5 / COOL_SPREAD 0.1 / FULL_SPREAD 0.5`。
- `view/board_view.gd`：`_wall_heat`（PEG_HIT +0.12 封顶 1）、`_neon_phase`（每帧 += `speed_for_heat`）、`decay_heat`（regardless-of-ball 段）。`_draw_neon_frame`：内外双线（扁平 `heat_color*0.6`）+ 缝中灯泡环（`bulb_color`，奇偶错相）+ 热脉冲（仅外线）。consts `NEON_GAP 12 / BULB_SPACING 40 / BULB_RADIUS 2.5 / HALF_PULSE_LEN 0.04`。`_neon_perimeter`/`_neon_inner_perimeter`。

---

## 系统组成

### 1. `juice/neon_frame.gd`（改 + 增，纯函数可测）

**改：** `speed_for_heat` 调慢——`lerpf(0.10, 0.60, clampf(heat,0,1))`（原 0.15/0.8）。**同步改 `test_speed_monotonic_and_range` 的两个端点断言。**

**增常量：**
```gdscript
const WAVE_COUNT := 5.0       # 行波波峰数（"多几处"）
const HUE_CYCLE := 0.5        # 变色相位相对流动的速率比（缓慢变色）
```

**增纯函数（取代/扩展 `bulb_color`）：**
- `frame_hue(p, flow_phase, hue_phase, heat) -> float`：
  色带中心 = `fposmod(COOL_HUE + hue_phase, 1.0)`（随 hue_phase 缓慢绕色盘 → 变色）；
  `local = fposmod(p + flow_phase, 1.0)`；`spread = hue_spread_for_heat(heat)`；
  `hue = fposmod(center + (local-0.5)*2*spread, 1.0)`。
  平静窄冷带、连击宽彩虹；中心随时间缓慢循环。
- `ambient_value(p, flow_phase, heat) -> float`：行波亮度（明暗对比、多波峰、随相位移动、随热度变亮）：
  `w = 0.5 + 0.5*sin(TAU*(p*WAVE_COUNT - flow_phase))`；
  返回 `lerpf(trough, peak, w)`，其中 `trough = lerpf(0.35, 0.7, heat)`、`peak = lerpf(1.5, 2.6, heat)`（峰值 >1 触发 bloom；对比大）。
- `frame_color(p, flow_phase, hue_phase, heat) -> Color`：`Color.from_hsv(frame_hue(...), 1.0, ambient_value(...))`。供线和灯泡共用。

> `bulb_color` 被 `frame_color` 取代（其 5 个测试改为 `frame_hue`/`ambient_value`/`frame_color` 的测试）。`hue_spread_for_heat`/`pulse_count_for_heat`/`heat_color`/`point_at`/`decay_heat` 不变。热脉冲仍 heat-gated（idle 0 条），常驻动感由行波提供。

### 2. `view/board_view.gd`（改）

- 常量：`NEON_GAP 12→20`、`BULB_SPACING 40→32`。
- 新状态：`var _neon_hue_phase := 0.0`。
- `_process`（推进相位处，与 `_neon_phase` 同处）：
  `_neon_hue_phase = fmod(_neon_hue_phase + delta * NeonFrameScript.speed_for_heat(_wall_heat) * NeonFrameScript.HUE_CYCLE, 1.0)`
  （按 `speed_for_heat` 推进 → 连击越高变色越快；idle 慢）。
- `_draw_neon_frame` 改：
  - **内外双线**：不再扁平——沿每条线**按弧长采样若干点**（如每 ~10px 一点），每点用 `frame_color(s, _neon_phase, _neon_hue_phase, _wall_heat)` 上色，相邻点连线 → 线上跑明暗行波 + 变色。**内外用同一 `s/_neon_phase` → 同步**。
  - **灯泡**：位置不变（缝中点），颜色用 `frame_color(bp, _neon_phase（偶）/ _neon_phase+0.5（奇）, _neon_hue_phase, _wall_heat)`（奇偶错相保留交替）。间距 32 → 更密。
  - **热脉冲**：保留，且**内外线都画一份（同相位 → 同步）**，连击叠加亮色高光。

---

## 数据流

```
每帧：_neon_phase += speed_for_heat(heat)·delta        # 流动（idle 0.1 → 满热 0.6）
      _neon_hue_phase += speed_for_heat(heat)·HUE_CYCLE·delta  # 变色（随热度加速）
_draw_neon_frame():
   内/外线：沿弧长采样点 → frame_color(s, _neon_phase, _neon_hue_phase, heat) 连线  # 明暗行波+变色，内外同步
   灯泡：缝中点 → frame_color(bp, 偶/奇相位, _neon_hue_phase, heat)              # 交替
   热脉冲：内外两线各画 pulse_count_for_heat 条（heat-gated，同步）              # 连击叠加
```

idle：慢流动 + 慢变色 + 窄冷带 + 明暗对比；连击：提速 + 加速变色 + 宽彩虹 + 加亮 + 热脉冲。

---

## 测试策略

NeonFrame 纯函数（headless 可测）：
- `speed_for_heat`：端点改 0.10 / 0.60，单调。
- `frame_hue`：heat 0 时各 p 落窄冷带（中心 + 时间偏移 ± COOL_SPREAD）；heat 1 时跨多色相；hue_phase 改变 → 中心移动（变色）。
- `ambient_value`：随 `w` 在 [trough, peak] 间；峰值（heat 1）>1（HDR）；trough/peak 随 heat 升；不同 flow_phase → 波峰位置移动。
- `frame_color`：饱和度 1；返回合法 Color。
- 替换原 `bulb_color` 的 5 测试为以上。

board_view 绘制/采样/`_neon_hue_phase`：场景加载检查 + 实机确认（view 层无单测）。

---

## 验收标准

- [ ] 墙更宽（20）、灯更密（间距 32）
- [ ] 不击中时内外双线 + 灯泡都在**缓慢跑明暗行波**（看得出在动，对比明显）且**缓慢循环变色**
- [ ] 跑马灯内外线都有且同步
- [ ] 击中/连击：流动提速 + 变色加速 + 颜色变多（色域铺开）+ 变亮 + 叠热脉冲；绝对速度比改前略慢
- [ ] NeonFrame 新纯函数全单测通过；现有测试除 speed/bulb 受影响项已更新；全绿
- [ ] 无回归：物理/计分/其他视觉正常；确定性不变

---

## 后期备用项（Backlog）

- 墙叠画重影（_draw_walls 与霓虹外线同位置）若实机不好看：把霓虹边框挪到墙之前画 / 去掉功能墙线
- 灯泡命中炸亮（PEG_HIT 联动）
- 漏斗角灯泡密度补偿

---

## 已知局限 / 留待后续

- 线按弧长采样点连线（每 ~10px）增加 draw_line 数量（外线 ~3160px → ~316 段 ×2 线），仍在 2D 可接受范围；若卡顿降采样密度。
- `_neon_hue_phase` 用 `speed_for_heat·HUE_CYCLE` 推进 → 连击变色更快；idle 很慢但持续（缓慢变色）。
- 速度/对比/波峰数/采样密度首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
- 平静色带仍以青为中心，但中心随 `_neon_hue_phase` 缓慢绕盘 → idle 也会缓慢经历多种（含暖）色；这是"缓慢变色"的预期。
