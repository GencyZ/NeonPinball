# 中空霓虹墙 + 灯泡 + 连击彩虹铺开 设计文档

**日期：** 2026-06-16
**主题：** 把霓虹边框升级为"中空双线墙 + 缝中一圈小灯泡"，平静时几种冷色缓慢交替流动，连击越高色域越宽（青 → 满频谱彩虹流光），高连击叠加现有热脉冲沸腾

---

## 目标

在已完成的"霓虹边框 + 连击追逐光"基础上做视觉升级：边框变成**中空双线光管**，缝里一圈**小灯泡**沿墙缓慢交替流动；平静时灯泡是几种冷色（青/蓝/青紫）流动，**连击越高、同时显示的颜色越多**——色带从青向暖色铺开成一条流动的彩虹渐变，满热整圈满频谱流光，并叠加现有热追逐光脉冲。让墙在静止时就"活着"，连击时层层升级到沸腾。

## 设计原则

- **在现有特性上增量**：复用 `_wall_heat`/`_neon_phase`（充能/冷却/相位已有），扩展 `juice/neon_frame.gd` 与 board_view 的 `_draw_neon_frame`/`_neon_perimeter`，不新增状态变量。
- **颜色=强度计**：连击强度主要靠"同时出现的色相数量（色带宽度）+ 流速 + 亮度"表达，比单一色相升温更炸；但必须是**有序流动的彩虹渐变**，不是随机杂色。
- **对 sim/确定性零侵入**：纯 view 层 + 纯函数；现有 249 测试不受影响。
- **纯函数可测**：色带宽度、灯泡色、内线偏移都是纯函数，TDD 单测；绘制实机确认。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript。基线 **249 测试全绿，37 脚本**。缩进 TAB。
- 已完成的霓虹边框（2026-06-16）：
  - `juice/neon_frame.gd`（NeonFrame）：`heat_color`、`pulse_count_for_heat`、`speed_for_heat`、`brightness_for_heat`、`decay_heat`、`point_at(poly, s)`（闭合折线弧长采样）；consts `IDLE/HOT/HEAT_PER_HIT/DECAY_RATE`。
  - `view/neon_environment.gd`：2D Glow（`glow_hdr_threshold=0.8`，亮色 bloom）。
  - `view/board_view.gd`：`_wall_heat`（PEG_HIT +0.12 封顶 1）、`_neon_phase`（每帧 += speed_for_heat）、`decay_heat` 在不依赖 `_has_ball` 段；`_neon_perimeter()` 返回 6 点桶形折线；`_draw_neon_frame()` 画暗底框 + N 条热追逐光脉冲。`_rect = Rect2(135,225,540,900)`，局部中心 (270,450)。
- 本特性**改写** `_draw_neon_frame`（双线 + 灯泡 + 彩虹色），扩 NeonFrame；保留热脉冲作为高连击叠加层。

---

## 系统组成

### 1. `juice/neon_frame.gd`（扩展，纯逻辑可测）

新增（保留现有函数）：

```gdscript
const COOL_HUE := 0.5          # 青（HSV 色相）
const COOL_SPREAD := 0.1       # 平静色带半宽（青附近几种冷色）
const FULL_SPREAD := 0.5       # 满热色带半宽（±0.5 = 整圈彩虹）

# 色带半宽：热度越高色域越宽（冷色窄带 → 全频谱）
static func hue_spread_for_heat(heat: float) -> float:
	return lerpf(COOL_SPREAD, FULL_SPREAD, clampf(heat, 0.0, 1.0))

# 沿环位置 p∈[0,1) + 流动相位 + 热度 → 灯泡颜色。
# 色相 = 青 ± 色带，绕环铺开；平静窄冷带、满热全彩虹。亮度随热度（>1 触发 bloom）。
static func bulb_color(p: float, phase: float, heat: float) -> Color:
	var local := fposmod(p + phase, 1.0)              # 含流动的环位置
	var spread := hue_spread_for_heat(heat)
	var hue := fposmod(COOL_HUE + (local - 0.5) * 2.0 * spread, 1.0)
	var val := lerpf(0.9, 2.4, clampf(heat, 0.0, 1.0))  # 亮度随热度，>1 溢光
	return Color.from_hsv(hue, 1.0, val)
```

> `point_at`、`speed_for_heat`、`brightness_for_heat`、`pulse_count_for_heat`、`heat_color`、`decay_heat` 不变，热脉冲仍用它们。

### 2. `view/board_view.gd`（改写 `_draw_neon_frame`，加内线/灯泡）

- 常量：`const NEON_GAP := 12.0`（内外线间距）、`const BULB_SPACING := 40.0`（灯泡间距 px）、`const BULB_RADIUS := 2.5`。
- 几何助手：
  - `_neon_perimeter()`（现有，作**外线**）。
  - `_neon_inner_perimeter()`：外线各点朝板心 `_rect.get_center()` 偏 `NEON_GAP`：`p + (center - p).normalized() * NEON_GAP`。
  - 灯泡数 `n_bulbs := int(周长 / BULB_SPACING)`（周长由外线弧长算）。
- `_draw_neon_frame()` 改为按层画：
  1. **内/外双线**：沿外线、内线各画一圈，色用 `heat_color(_wall_heat)` 暗光（~0.6），bloom 让它发光成"光管"。
  2. **小灯泡（缝中一圈）**：对 `i in n_bulbs`，`p := float(i)/n_bulbs`；位置 = 外线 `point_at(outer, p)` 与内线 `point_at(inner, p)` 的中点；颜色 `NeonFrameScript.bulb_color(p, _neon_phase, _wall_heat)`；**交替**：偶数灯泡用 `_neon_phase`、奇数用 `_neon_phase + 0.5`（错相，一明一暗交替流动）；`draw_circle(mid, BULB_RADIUS, col)`。
  3. **热追逐光脉冲（高连击叠加）**：保留现有脉冲逻辑（`pulse_count_for_heat`/`brightness_for_heat`/`point_at` 沿外线），作为高连击时的亮色高光。
- `_wall_heat`/`_neon_phase` 充能/冷却/推进逻辑不变。

---

## 数据流

```
PEG_HIT → _wall_heat += 0.12（封顶 1）          # 已有
每帧 → _wall_heat 冷却、_neon_phase += speed     # 已有
_draw_neon_frame():
   内线 + 外线（heat_color 暗光，bloom 成光管）
   for i in n_bulbs:
       p = i/n_bulbs；位置 = 内外线中点
       相位 = _neon_phase（偶）/ _neon_phase+0.5（奇，交替）
       色 = bulb_color(p, 相位, _wall_heat)   # 平静窄冷带 → 满热全彩虹
       draw_circle(...)
   热脉冲（pulse_count_for_heat 条，高连击亮色高光）   # 已有逻辑
```

色域宽度/流速/亮度全由 `_wall_heat` 驱动；位置由 `_neon_phase` 流动。

---

## 测试策略

新增约 5 个测试（纯 NeonFrame 新函数），headless 可测；绘制/几何实机确认。

`tests/test_neon_frame.gd`（追加）：
- `hue_spread_for_heat(0)` ≈ COOL_SPREAD(0.1)；`(1)` ≈ FULL_SPREAD(0.5)；单调不降；范围 [0.1,0.5]
- `bulb_color` 平静窄冷带：heat 0 时，多个 p（0/0.25/0.5/0.75）的色相都落在冷色带内（`COOL_HUE ± COOL_SPREAD` 即 [0.4,0.6]）
- `bulb_color` 满热宽带：heat 1 时，p=0 与 p=0.5 的色相差很大（跨多色相，验证"颜色变多"）
- `bulb_color` 亮度随热度：heat 1 的 value > heat 0 的 value（且满热 >1 触发 bloom）
- `bulb_color` 返回合法 Color（饱和度 1）

board_view 双线/灯泡/交替/脉冲叠加：场景加载检查 + 实机确认（view 层无单测，与现有一致）。

---

## 验收标准

- [ ] 边框是中空双线光管，缝里一圈小灯泡
- [ ] 平静时灯泡几种冷色（青/蓝/青紫）缓慢交替流动
- [ ] 连击越高同时显示的颜色越多（色带从青向暖色铺开成流动彩虹渐变），流速/亮度升
- [ ] 满热整圈满频谱流光 + 现有热脉冲叠加沸腾
- [ ] 必须是有序流动渐变、不是随机杂色
- [ ] NeonFrame 新纯函数全单测通过；254 左右全绿
- [ ] 无回归：现有霓虹/物理/计分等正常；确定性不变

---

## 后期备用项（Backlog）

- 灯泡命中时局部炸亮（与 PEG_HIT 联动）
- 内/外线本身也做反向慢流动色（当前为暗光常亮）
- 灯泡密度/大小随热度变化
- 漏斗段灯泡的特殊处理（死亡区警示色）

---

## 已知局限 / 留待后续

- 内线 = 外线朝板心偏移；桶形非凸处偏移非完全均匀，~12px 视觉可接受（实机微调 `NEON_GAP`）。
- 灯泡数按周长/间距估算，每帧重算位置（n≤~70，`draw_circle` 开销可忽略）。
- 平静态色带中心固定为青（COOL_HUE 0.5）；热度只展宽色带、不平移中心——保证"从冷色铺开"而非整体偏色。
- 所有数值（GAP/间距/色带/亮度）首版，记入 `docs/superpowers/balance-tunables.md`，实机调。
