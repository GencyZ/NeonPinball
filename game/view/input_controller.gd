extends Node

@export var board_path: NodePath

var _board: Node2D
var _edge: int = EntryResolver.BoardEdge.TOP
var _t := 0.5
var _aim := 0.0
const SPEED := 1500.0
const BALL_RADIUS := 8.0

func _ready() -> void:
	_board = get_node(board_path)

func _process(_delta: float) -> void:
	var m := _board.get_local_mouse_position()
	var r: Rect2 = _board.rect
	match _edge:
		EntryResolver.BoardEdge.TOP:
			_t = clampf((m.x - r.position.x) / r.size.x, 0.0, 1.0)
			_aim = clampf((m.x - r.get_center().x) / (r.size.x * 0.5), -1.0, 1.0) * 0.9
		_:
			_t = clampf((m.y - r.position.y) / r.size.y, 0.15, 0.85)
			_aim = clampf((m.y - r.get_center().y) / (r.size.y * 0.5), -1.0, 1.0) * 0.9

	# Tell board current entry info (for gate drawing)
	_board.set_entry(_edge, _t)

	var gate_def: GateDef = _board.active_gate_def
	var start := EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r)
	var axis := _board.gate_axis()
	var threshold := _board.gate_threshold()

	# Pre-gate: single ball path from entry to gate
	var pre := TrajectoryPredictor.predict_to_gate(_board.sim, start, axis, threshold, 30)
	_board.prediction_pts = pre[&"pts"]

	# Post-gate: depends on gate type
	var gate_ball: BallState = pre[&"ball"]
	_board.prediction_fans.clear()

	match gate_def.kind:
		GateDef.Kind.ACCEL:
			var fast := BallState.new(gate_ball.pos, gate_ball.vel * gate_def.speed_mul, gate_ball.radius)
			_board.prediction_fans = [TrajectoryPredictor.predict(_board.sim, fast, 60)]
		GateDef.Kind.SCATTER_ANGLE:
			_board.prediction_fans = TrajectoryPredictor.predict_fan(
				_board.sim, gate_ball, gate_def.scatter_angle, 5, 60)
		GateDef.Kind.SCATTER_SPLIT:
			for k in gate_def.split_count:
				var frac := float(k) / maxf(gate_def.split_count - 1, 1) - 0.5
				var nb := BallState.new(gate_ball.pos,
				                       gate_ball.vel.rotated(frac * gate_def.scatter_angle),
				                       gate_ball.radius)
				_board.prediction_fans.append(TrajectoryPredictor.predict(_board.sim, nb, 60))
		_:  # NORMAL
			_board.prediction_fans = [TrajectoryPredictor.predict(_board.sim, gate_ball.clone(), 60)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_edge = (_edge + 1) % 3
			KEY_1: _board.set_active_gate(&"normal")
			KEY_2: _board.set_active_gate(&"accel")
			KEY_3: _board.set_active_gate(&"scatter_angle")
			KEY_4: _board.set_active_gate(&"scatter_split")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var r: Rect2 = _board.rect
			_board.launch(EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r))
