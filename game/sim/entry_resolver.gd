class_name EntryResolver

enum BoardEdge { TOP, LEFT, RIGHT }

# Fixed t values for each launcher gate center
const LAUNCHER_T := {
	BoardEdge.LEFT:  0.150,   # local y=135 / 900
	BoardEdge.RIGHT: 0.150,
	BoardEdge.TOP:   0.500,   # local x=270 / 540 → actual x=405, aligns with LAUNCHER_POS
}

# Launcher canvas positions (fixed; outside _rect) — used by draw layer.
# LEFT/RIGHT launchers sit diagonally (≈45°) up-out from their gate centres
# (gate centre absolute y=360); TOP sits straight above. The channel walls run
# parallel to the launcher→gate direction and the launcher end-cap is built
# perpendicular to them (see _channel_geometry in board_view.gd).
const LAUNCHER_POS := {
	BoardEdge.LEFT:  Vector2(85.0, 310.0),
	BoardEdge.TOP:   Vector2(405.0, 155.0),
	BoardEdge.RIGHT: Vector2(725.0, 310.0),
}

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

# 通道方向：从发射器位置指向门中心，归一化。
static func channel_dir(edge: int, rect: Rect2) -> Vector2:
	var gate_center: Vector2 = resolve(edge, LAUNCHER_T[edge], rect)[&"pos"]
	return (gate_center - LAUNCHER_POS[edge]).normalized()

# 球从发射器位置生成，沿通道方向旋转 aim_offset 弧度，夹紧在 ±20°。
static func make_ball(edge: int, _t: float, aim_offset: float,
					speed: float, radius: float, rect: Rect2) -> BallState:
	var clamped := clampf(aim_offset, -PI / 9.0, PI / 9.0)
	var dir: Vector2 = channel_dir(edge, rect).rotated(clamped)
	return BallState.new(LAUNCHER_POS[edge], dir * speed, radius)
