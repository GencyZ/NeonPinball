extends Node

const RunManagerScript := preload("res://run/run_manager.gd")

@export var board_path: NodePath

var _board: Node2D
var _edge: int = EntryResolver.BoardEdge.TOP
var _aim := 0.0
var _last_mouse := Vector2.INF
const SPEED := 1500.0
const BALL_RADIUS := 8.0

func _ready() -> void:
	_board = get_node(board_path)

func _process(delta: float) -> void:
	if _board._has_ball:
		_board.prediction_pts.clear()
		_board.prediction_fans.clear()
		return

	var r: Rect2 = _board.rect
	var t: float = EntryResolver.LAUNCHER_T[_edge]
	var entry: Dictionary = EntryResolver.resolve(_edge, t, r)
	var gate_pos: Vector2 = entry[&"pos"]
	var inward_n: Vector2 = entry[&"normal"]

	# Mouse sets aim angle when it moves
	var mouse: Vector2 = _board.get_local_mouse_position()
	if mouse.distance_squared_to(_last_mouse) > 1.0:
		_last_mouse = mouse
		var to_mouse := mouse - gate_pos
		if to_mouse.length_squared() > 1.0:
			_aim = inward_n.angle_to(to_mouse.normalized())

	# A/D fine-tunes
	if Input.is_key_pressed(KEY_A):
		_aim -= deg_to_rad(90.0) * delta
	if Input.is_key_pressed(KEY_D):
		_aim += deg_to_rad(90.0) * delta

	_aim = clampf(_aim, -PI / 3.0, PI / 3.0)

	_board.set_entry(_edge, t)

	var start := EntryResolver.make_ball(_edge, t, _aim, SPEED, BALL_RADIUS, r)
	var axis: int = _board.gate_axis()
	var threshold: float = _board.gate_threshold()
	var pre := TrajectoryPredictor.predict_to_gate(_board.sim, start, axis, threshold, 30)
	_board.prediction_pts = pre[&"pts"]

	var gate_ball: BallState = pre[&"ball"]
	_board.prediction_fans.clear()
	var gate_def: GateDef = _board.active_gate_def
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
		_:
			_board.prediction_fans = [TrajectoryPredictor.predict(_board.sim, gate_ball.clone(), 60)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Shop phase: intercept key presses
		var cur_phase: int = RunMan.state[&"phase"]
		if cur_phase == RunManager.Phase.SHOP:
			_handle_shop_key(event.keycode)
			return
		# Win/Lose: R=restart fresh run, Esc=back to main menu
		if cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE:
			if event.keycode == KEY_R:
				SceneMan.start_run()
				return
			if event.keycode == KEY_ESCAPE:
				SceneMan.goto_menu()
				return
		match event.keycode:
			KEY_TAB:
				_edge = (_edge + 1) % 3
			KEY_SPACE:
				if cur_phase == RunManager.Phase.ROUND or cur_phase == RunManager.Phase.BOSS_ROUND:
					var r2: Rect2 = _board.rect
					_board.launch(EntryResolver.make_ball(_edge, EntryResolver.LAUNCHER_T[_edge], _aim, SPEED, BALL_RADIUS, r2))
			KEY_1: _board.set_active_gate(&"normal")
			KEY_2: _board.set_active_gate(&"accel")
			KEY_3: _board.set_active_gate(&"scatter_angle")
			KEY_4: _board.set_active_gate(&"scatter_split")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var r: Rect2 = _board.rect
			_board.launch(EntryResolver.make_ball(_edge, EntryResolver.LAUNCHER_T[_edge], _aim, SPEED, BALL_RADIUS, r))

func _handle_shop_key(keycode: Key) -> void:
	match keycode:
		KEY_1: _board.buy_shop_slot(0)
		KEY_2: _board.buy_shop_slot(1)
		KEY_3: _board.buy_shop_slot(2)
		KEY_4: _board.buy_shop_slot(3)
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_board.leave_shop()
