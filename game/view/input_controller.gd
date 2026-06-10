extends Node

const RunManagerScript := preload("res://run/run_manager.gd")

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
	var axis: int = _board.gate_axis()
	var threshold: float = _board.gate_threshold()

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
		# Shop phase: intercept key presses
		var cur_phase: int = RunMan.state[&"phase"]
		if cur_phase == RunManager.Phase.SHOP:
			_handle_shop_key(event.keycode)
			return
		# Win/Lose: R to restart
		if event.keycode == KEY_R and (cur_phase == RunManager.Phase.RUN_WIN or cur_phase == RunManager.Phase.RUN_LOSE):
			RunMan.advance()   # WIN/LOSE → _reset() → BOOT
			_board.get_tree().reload_current_scene()
			return
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

func _handle_shop_key(keycode: Key) -> void:
	var shop: Shop = _board._active_shop
	if shop == null:
		return
	var slot := -1
	match keycode:
		KEY_1: slot = 0
		KEY_2: slot = 1
		KEY_3: slot = 2
		KEY_4: slot = 3
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			_board.leave_shop()
			return
	if slot < 0:
		return
	var money_ref := [RunMan.state[&"money"]]
	var inv := {&"items": []}
	var ok := shop.buy(slot, inv, money_ref)
	if ok:
		RunMan.state[&"money"] = money_ref[0]
		for item in inv[&"items"]:
			if item is TriggerDef:
				var equipped: Array = RunMan.state[&"equipped_triggers"]
				if equipped.size() < 5:
					equipped.append(item.id)
			elif item is GateDef:
				RunMan.state[&"equipped_gate"] = item.id
		_board.get_node("Hud").show_shop(shop.offerings, RunMan.state[&"money"])
		_board._sync_hud()
