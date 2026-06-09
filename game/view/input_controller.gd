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

	var gate_def: GateDef = _board.active_gate_def
	var start := EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r)

	match gate_def.kind:
		GateDef.Kind.ACCEL:
			_board.prediction_fans.clear()
			var fast := BallState.new(start.pos, start.vel * gate_def.speed_mul, start.radius)
			_board.prediction_pts = TrajectoryPredictor.predict(_board.sim, fast, 60)
		GateDef.Kind.SCATTER_ANGLE, GateDef.Kind.SCATTER_SPLIT:
			_board.prediction_pts.clear()
			_board.prediction_fans = TrajectoryPredictor.predict_fan(
				_board.sim, start, gate_def.scatter_angle, 5, 60)
		_:
			_board.prediction_fans.clear()
			_board.prediction_pts = TrajectoryPredictor.predict(_board.sim, start, 60)

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
