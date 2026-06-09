class_name TrajectoryPredictor

# 用同一套 BallSimulation 无渲染前瞻，返回每步球心位置。
# 完全确定 → 返回值 == 真实弹道（直到混沌发散）。
# 使用 BallState.clone() 防止污染真实球状态或 sim 内部状态。
static func predict(sim: BallSimulation, start: BallState, steps: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var ball := start.clone()
	var scratch: Array = []   # 丢弃事件，不外泄
	for _i in steps:
		if not ball.alive:
			break
		scratch.clear()
		sim.step(ball, scratch)
		pts.append(ball.pos)
	return pts

# Returns Array of Array[Vector2], one per angular sample.
# Samples span [-scatter_rad, +scatter_rad] left-to-right.
static func predict_fan(sim: BallSimulation, start: BallState,
                        scatter_rad: float, samples: int,
                        steps: int) -> Array:
	var fans := []
	for i in samples:
		var a := lerpf(-scatter_rad, scatter_rad,
		               float(i) / maxf(samples - 1, 1))
		var b := BallState.new(start.pos, start.vel.rotated(a), start.radius)
		fans.append(predict(sim, b, steps))
	return fans
