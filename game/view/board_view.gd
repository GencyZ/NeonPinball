extends Node2D

const DT := 1.0 / 120.0

var _rect: Rect2
var _pegs: Array = []
var _sim: BallSimulation
var _engine: ScoringEngine
var _score_ctx: ScoreContext
var _trigger_runtimes: Array = []
var _gate_chain: GateChain
var _active_gate_def: GateDef

var _active_balls: Array = []
var _prev_positions: Array = []
var _curr_positions: Array = []
var _has_ball := false
var _acc := 0.0

var _events: Array = []
var _event_cursor := 0
var _flashes: Array = []

var _launch_count := 0

var prediction_pts: Array[Vector2] = []
var prediction_fans: Array = []

var rect: Rect2:
	get: return _rect
var sim: BallSimulation:
	get: return _sim
var active_gate_def: GateDef:
	get: return _active_gate_def

func _ready() -> void:
	_rect = Rect2(0, 0, 540, 900)
	_pegs = _build_honeycomb()
	var cfg := {
		&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
		&"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
	}
	_sim = BallSimulation.new(_rect, _pegs, cfg)
	_engine = ScoringEngine.new()
	_score_ctx = ScoreContext.new()

	for tid in [&"peg_bonus", &"bounce_mult", &"big_hit"]:
		_trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))

	set_active_gate(&"normal")

func _build_honeycomb() -> Array:
	var list := []
	var id := 0
	var rows := 8; var cols := 7
	var spacing := 64.0; var margin := 60.0
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

func set_active_gate(gate_id: StringName) -> void:
	_active_gate_def = GameDB.gate_defs[gate_id]
	var rng := DeterministicRng.new(_launch_count * 1000 + (gate_id.hash() & 0x7FFFFFFF))
	var gate_rt := GateRuntime.new(_active_gate_def, rng)
	_gate_chain = GateChain.new([gate_rt])
	$Hud.set_gate_label(String(gate_id))

func launch(ball: BallState) -> void:
	if _has_ball:
		return
	_score_ctx.clear_for_launch()
	_active_balls = _gate_chain.process(ball)
	_has_ball = _active_balls.size() > 0
	_prev_positions.resize(_active_balls.size())
	_curr_positions.resize(_active_balls.size())
	for i in _active_balls.size():
		_prev_positions[i] = _active_balls[i].pos
		_curr_positions[i] = _active_balls[i].pos
	_events.clear(); _event_cursor = 0; _flashes.clear()
	_launch_count += 1
	set_active_gate(_active_gate_def.id)

func _process(delta: float) -> void:
	if _has_ball:
		_acc += delta
		while _acc >= DT:
			for i in _active_balls.size():
				if _active_balls[i].alive:
					_prev_positions[i] = _active_balls[i].pos
					_sim.step(_active_balls[i], _events)
					_curr_positions[i] = _active_balls[i].pos

			while _event_cursor < _events.size():
				var e: Dictionary = _events[_event_cursor]
				if e[&"type"] == SimEvent.PEG_HIT:
					_score_ctx.pegs_hit += 1
					_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15})
				elif e[&"type"] == SimEvent.BOUNCE:
					_score_ctx.bounce_count += 1
				for rt in _trigger_runtimes:
					rt.on_event(e, _score_ctx)
				_event_cursor += 1

			_acc -= DT

			var all_dead := true
			for b in _active_balls:
				if b.alive:
					all_dead = false; break
			if all_dead:
				_on_all_settled()
				break

		for i in range(_flashes.size() - 1, -1, -1):
			_flashes[i][&"ttl"] -= delta
			if _flashes[i][&"ttl"] <= 0.0:
				_flashes.remove_at(i)
	queue_redraw()

func _on_all_settled() -> void:
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
	$Hud.add_score(score)
	_has_ball = false; _acc = 0.0
	_active_balls.clear()
	_prev_positions.clear(); _curr_positions.clear()

func _draw() -> void:
	for peg in _pegs:
		draw_circle(peg[&"pos"], peg[&"radius"], Color(0.2, 0.9, 1.0))
	for i in range(1, prediction_pts.size()):
		draw_line(prediction_pts[i - 1], prediction_pts[i], Color(1, 1, 1, 0.4), 2.0)
	for fan in prediction_fans:
		for i in range(1, fan.size()):
			draw_line(fan[i - 1], fan[i], Color(1.0, 1.0, 0.4, 0.25), 1.5)
	if _has_ball:
		var alpha := _acc / DT
		for i in _active_balls.size():
			if _active_balls[i].alive:
				var dp := (_prev_positions[i] as Vector2).lerp(_curr_positions[i], alpha)
				draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))
	for f in _flashes:
		var a: float = f[&"ttl"] / 0.15
		draw_circle(f[&"pos"], 16.0, Color(1.0, 1.0, 0.6, a * 0.8))
