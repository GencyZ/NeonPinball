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
