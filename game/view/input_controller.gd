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
		_:  # LEFT / RIGHT：用鼠标 Y，范围限制在 [0.15, 0.85]
			_t = clampf((m.y - r.position.y) / r.size.y, 0.15, 0.85)
			_aim = clampf((m.y - r.get_center().y) / (r.size.y * 0.5), -1.0, 1.0) * 0.9
	var start := EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r)
	_board.prediction_pts = TrajectoryPredictor.predict(_board.sim, start, 60)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_edge = (_edge + 1) % 3
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var r: Rect2 = _board.rect
			_board.launch(
				EntryResolver.make_ball(_edge, _t, _aim, SPEED, BALL_RADIUS, r))
