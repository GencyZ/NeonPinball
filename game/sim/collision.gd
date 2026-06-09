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
