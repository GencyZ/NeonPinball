class_name NeonFrame extends RefCounted

# 约定：所有曲线函数的 heat 入参为有限的 [0,1] 值（board_view 的 _wall_heat 已 clamp）。

# 热度色斜坡：青 → 饱和热粉，始终饱和不褪白。
const IDLE := Color(0.0, 0.9, 1.0)
const HOT  := Color(1.0, 0.15, 0.55)

const HEAT_PER_HIT := 0.12   # 每次击中充能
const DECAY_RATE   := 0.5    # 每秒冷却（满热约 2s 归零）

# 热度 → 颜色（线性插值，始终饱和）
static func heat_color(heat: float) -> Color:
	var t := clampf(heat, 0.0, 1.0)
	if t <= 0.0:
		return IDLE
	if t >= 1.0:
		return HOT
	return IDLE.lerp(HOT, t)

# 热度 → 追逐光脉冲条数（平静 0 条，过阈值 1 条起，封顶 4）
static func pulse_count_for_heat(heat: float) -> int:
	var h := clampf(heat, 0.0, 1.0)
	if h < 0.05:           # 平静阈值
		return 0
	return 1 + floori(h * 3.0)   # 1~4 条，封顶 4

# 热度 → 流速（每秒绕框圈数）
static func speed_for_heat(heat: float) -> float:
	return lerpf(0.15, 0.8, clampf(heat, 0.0, 1.0))   # 平静 0.15 圈/s → 满热 0.8

# 热度 → 脉冲峰值亮度倍率（>1 触发 bloom）
static func brightness_for_heat(heat: float) -> float:
	return lerpf(1.2, 3.0, clampf(heat, 0.0, 1.0))   # 平静 1.2 → 满热 3.0（>1 触发 bloom）

# 热度随时间冷却（不为负）
static func decay_heat(heat: float, delta: float) -> float:
	return maxf(heat - DECAY_RATE * delta, 0.0)

# 闭合折线按弧长采样：s∈[0,1) 绕一圈，首尾相连。
static func point_at(poly: PackedVector2Array, s: float) -> Vector2:
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return poly[0]
	var total := 0.0
	for i in n:
		total += poly[i].distance_to(poly[(i + 1) % n])
	if total <= 0.0:
		return poly[0]
	var target := fposmod(s, 1.0) * total
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var l := a.distance_to(b)
		if target <= l or i == n - 1:
			var t := (target / l) if l > 0.0 else 0.0
			return a.lerp(b, clampf(t, 0.0, 1.0))
		target -= l
	return poly[0]   # unreachable（循环必在内部返回；GDScript 需所有路径有返回）
