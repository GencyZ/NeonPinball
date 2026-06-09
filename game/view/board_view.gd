extends Node2D

const DT := 1.0 / 120.0

var _rect: Rect2
var _pegs: Array = []
var _sim: BallSimulation
var _scorer: Scorer

var _ball: BallState
var _has_ball := false
var _prev_pos := Vector2.ZERO
var _curr_pos := Vector2.ZERO
var _events: Array = []
var _acc := 0.0

var _flashes: Array = []
var _event_cursor := 0

var prediction_pts: Array[Vector2] = []

var rect: Rect2:
	get: return _rect
var sim: BallSimulation:
	get: return _sim

func _ready() -> void:
	_rect = Rect2(0, 0, 540, 900)
	_pegs = _build_honeycomb()
	var cfg := {
		&"gravity": Vector2(0, 1400),
		&"max_speed": 4000.0,
		&"restitution": 0.82,
		&"tangent_keep": 0.98,
		&"dt": DT,
	}
	_sim = BallSimulation.new(_rect, _pegs, cfg)
	_scorer = Scorer.new(_pegs)

func _build_honeycomb() -> Array:
	var list := []
	var id := 0
	var rows := 8; var cols := 7
	var spacing := 64.0; var margin := 60.0
	# 三档大小：按行列位置循环分配，制造有规律的混合感
	var sizes := [7.0, 10.0, 13.0]
	var scores := [3.0, 5.0, 8.0]
	for r in rows:
		var y := margin + 140.0 + r * spacing
		var x_off := (r % 2) * spacing * 0.5
		for c in cols:
			var x := margin + x_off + c * spacing
			if x < _rect.end.x - margin:
				var tier := (r + c * 2) % 3
				list.append({&"id": id, &"pos": Vector2(x, y),
							&"radius": sizes[tier], &"base_score": scores[tier]})
				id += 1
	return list

func launch(ball: BallState) -> void:
	_ball = ball; _has_ball = true
	_prev_pos = ball.pos; _curr_pos = ball.pos
	_events.clear(); _event_cursor = 0; _flashes.clear()

func _process(delta: float) -> void:
	if _has_ball:
		_acc += delta
		while _acc >= DT:
			_prev_pos = _ball.pos
			_sim.step(_ball, _events)
			_curr_pos = _ball.pos
			_acc -= DT
			while _event_cursor < _events.size():
				var e: Dictionary = _events[_event_cursor]
				if e[&"type"] == SimEvent.PEG_HIT:
					_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15})
				_event_cursor += 1
			if not _ball.alive:
				var score := _scorer.score_launch(_events)
				$Hud.add_score(score)
				_has_ball = false; _acc = 0.0; break
		for i in range(_flashes.size() - 1, -1, -1):
			_flashes[i][&"ttl"] -= delta
			if _flashes[i][&"ttl"] <= 0.0:
				_flashes.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for peg in _pegs:
		draw_circle(peg[&"pos"], peg[&"radius"], Color(0.2, 0.9, 1.0))
	for i in range(1, prediction_pts.size()):
		draw_line(prediction_pts[i - 1], prediction_pts[i], Color(1, 1, 1, 0.4), 2.0)
	if _has_ball:
		var alpha := _acc / DT
		var draw_pos := _prev_pos.lerp(_curr_pos, alpha)
		draw_circle(draw_pos, _ball.radius, Color(1.0, 0.3, 0.8))
	for f in _flashes:
		var a: float = f[&"ttl"] / 0.15
		draw_circle(f[&"pos"], 16.0, Color(1.0, 1.0, 0.6, a * 0.8))
