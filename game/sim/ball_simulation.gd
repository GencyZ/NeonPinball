class_name BallSimulation

const MAX_BOUNCES_PER_STEP := 8
const EPSILON := 1e-5

var _rect: Rect2
var _pegs: Array
var _grid: PegGrid
var _cfg: Dictionary

func _init(rect: Rect2, pegs: Array, cfg: Dictionary) -> void:
	_rect = rect; _pegs = pegs; _cfg = cfg
	_grid = PegGrid.new()
	_grid.build(pegs, rect, 50.0)

# 推进一个固定步；产出事件追加到 out_events。
func step(ball: BallState, out_events: Array) -> void:
	if not ball.alive:
		return
	# 半隐式欧拉积分 + 限速
	ball.vel += _cfg[&"gravity"] * _cfg[&"dt"]
	var speed := ball.vel.length()
	if speed > _cfg[&"max_speed"]:
		ball.vel = ball.vel * (_cfg[&"max_speed"] / speed)
	# CCD 步进
	_integrate_ccd(ball, out_events, _cfg[&"dt"])
	# 底部开口：球心超出底边 → 落袋
	if ball.pos.y - ball.radius > _rect.end.y:
		ball.alive = false
		out_events.append(SimEvent.settled(ball.pos))

func _integrate_ccd(ball: BallState, out_events: Array, dt: float) -> void:
	var remaining := dt
	var guard := 0
	while remaining > EPSILON and guard < MAX_BOUNCES_PER_STEP:
		guard += 1
		var d := ball.vel * remaining
		var hit := _find_earliest(ball.pos, d, ball.radius)
		if hit.is_empty():
			ball.pos += d
			break
		ball.pos += d * hit[&"t"]
		if hit[&"peg_id"] >= 0:
			out_events.append(SimEvent.peg_hit(hit[&"peg_id"], ball.pos))
		else:
			out_events.append(SimEvent.wall_hit(ball.pos))
		out_events.append(SimEvent.bounce(ball.pos))
		ball.vel = Collision.reflect(
			ball.vel, hit[&"normal"], _cfg[&"restitution"], _cfg[&"tangent_keep"])
		ball.bounce_count += 1
		remaining *= (1.0 - hit[&"t"])

# 求本段位移内最早碰撞（TOI 最小；同 TOI 按 peg_id 升序决胜）。
func _find_earliest(p: Vector2, d: Vector2, r: float) -> Dictionary:
	var best := {}
	var best_t := INF
	var search_r := d.length() + r + 32.0
	for peg_id in _grid.query_near(p, search_r):
		var peg: Dictionary = _pegs[peg_id]
		var t := Collision.swept_circle(p, d, peg[&"pos"], r + peg[&"radius"])
		if t >= 0.0:
			if t < best_t or (is_equal_approx(t, best_t) and peg_id < best.get(&"peg_id", INF)):
				best_t = t
				var contact := p + d * t
				best = {&"t": t, &"peg_id": peg_id,
						&"normal": (contact - peg[&"pos"]).normalized()}
	var wall := Collision.swept_walls(p, d, r, _rect)
	if not wall.is_empty() and wall[&"t"] < best_t:
		best = {&"t": wall[&"t"], &"peg_id": -1, &"normal": wall[&"normal"]}
	return best
