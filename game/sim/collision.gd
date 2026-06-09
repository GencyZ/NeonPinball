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
