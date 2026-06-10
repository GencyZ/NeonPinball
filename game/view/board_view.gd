extends Node2D

const DT := 1.0 / 120.0
const GATE_DIST := 80.0
const RunManagerScript := preload("res://run/run_manager.gd")

var _rect: Rect2
var _pegs: Array = []
var _sim: BallSimulation
var _engine: ScoringEngine
var _score_ctx: ScoreContext
var _trigger_runtimes: Array = []
var _gate_chain: GateChain
var _active_gate_def: GateDef
var _active_shop: Shop = null

var _active_balls: Array = []
var _prev_positions: Array = []
var _curr_positions: Array = []
var _has_ball := false
var _acc := 0.0

var _events: Array = []
var _event_cursor := 0
var _flashes: Array = []

var _launch_count := 0

var _entry_edge: int = EntryResolver.BoardEdge.TOP
var _entry_t: float = 0.5
var _gate_applied := false

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
	_sim = _make_sim(_pegs)
	_engine = ScoringEngine.new()
	_score_ctx = ScoreContext.new()

	for tid in [&"peg_bonus", &"bounce_mult", &"big_hit"]:
		_trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))

	set_active_gate(&"normal")

	# Auto-advance RunManager to ROUND on first start
	if RunMan.state[&"phase"] == RunManager.Phase.BOOT:
		RunMan.advance()   # BOOT → RUN_START
		RunMan.advance()   # RUN_START → ROUND
	_apply_boss_mod()
	_refresh_equipped()
	_sync_hud()

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
				var peg_type: PegType = GameDB.peg_types[&"mult"] if (r * 7 + c) % 7 == 3 else GameDB.peg_types[&"normal"]
				list.append({&"id": id, &"pos": Vector2(x, y),
							&"radius": sizes[tier], &"base_score": scores[tier],
							&"type": peg_type})
				id += 1
	return list

func _make_sim(pegs: Array) -> BallSimulation:
	return BallSimulation.new(_rect, pegs, {
		&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
		&"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
	})

func set_active_gate(gate_id: StringName) -> void:
	_active_gate_def = GameDB.gate_defs[gate_id]
	var rng := DeterministicRng.new(_launch_count * 1000 + (gate_id.hash() & 0x7FFFFFFF))
	var gate_rt := GateRuntime.new(_active_gate_def, rng)
	_gate_chain = GateChain.new([gate_rt])
	$Hud.set_gate_label(String(gate_id))

func set_entry(edge: int, t: float) -> void:
	_entry_edge = edge
	_entry_t = t

func gate_axis() -> int:
	match _entry_edge:
		EntryResolver.BoardEdge.TOP:   return 0
		EntryResolver.BoardEdge.LEFT:  return 1
		_:                             return 2

func gate_threshold() -> float:
	match _entry_edge:
		EntryResolver.BoardEdge.TOP:   return _rect.position.y + GATE_DIST
		EntryResolver.BoardEdge.LEFT:  return _rect.position.x + GATE_DIST
		_:                             return _rect.end.x - GATE_DIST

func _apply_boss_mod() -> void:
	var bm: Dictionary = RunMan.state[&"boss_mod"]
	if bm.is_empty():
		return
	match bm[&"type"]:
		&"ban_mult":
			for peg in _pegs:
				if peg[&"type"] != null and peg[&"type"].behavior == PegType.Behavior.MULT:
					peg[&"type"] = GameDB.peg_types[&"normal"]
		&"sparse":
			var rng := DeterministicRng.derive(RunMan.state[&"master_seed"],
											   RunMan.state[&"ante"] * 77 + 3)
			var keep: Array = []
			for peg in _pegs:
				if peg[&"type"].behavior != PegType.Behavior.NORMAL or rng.next_float() >= bm[&"remove_chance"]:
					keep.append(peg)
			_pegs = keep
			for i in _pegs.size():
				_pegs[i][&"id"] = i
			_sim = _make_sim(_pegs)

func _refresh_equipped() -> void:
	_trigger_runtimes.clear()
	for tid in RunMan.state[&"equipped_triggers"]:
		if GameDB.triggers.has(tid):
			_trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))
	var gate_id: StringName = RunMan.state[&"equipped_gate"]
	if GameDB.gate_defs.has(gate_id):
		set_active_gate(gate_id)

func _sync_hud() -> void:
	$Hud.update_run_state(
		RunMan.state[&"ante"],
		RunMan.state[&"round_in_ante"],
		RunMan.state[&"quota"],
		RunMan.state[&"money"],
		RunMan.state[&"launches_left"],
		RunMan.state[&"round_score"],
	)

func launch(ball: BallState) -> void:
	if _has_ball:
		return
	# Block launch if SHOP or WIN or LOSE phase
	var phase: int = RunMan.state[&"phase"]
	if phase != RunManager.Phase.ROUND and phase != RunManager.Phase.BOSS_ROUND:
		return
	# Block if no launches left
	if RunMan.launches_exhausted():
		return
	RunMan.spend_launch()
	_sync_hud()
	_score_ctx.clear_for_launch()
	_active_balls = [ball]
	_gate_applied = false
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

			# Gate crossing check (only for first ball, before gate applied)
			if not _gate_applied and _active_balls.size() == 1:
				var b: BallState = _active_balls[0]
				var axis := gate_axis()
				var threshold := gate_threshold()
				var crossed := false
				match axis:
					0: crossed = b.pos.y >= threshold
					1: crossed = b.pos.x >= threshold
					2: crossed = b.pos.x <= threshold
				if crossed:
					_active_balls = _gate_chain.process(b)
					_gate_applied = true
					# Resize position arrays for new ball count
					_prev_positions.resize(_active_balls.size())
					_curr_positions.resize(_active_balls.size())
					for i in _active_balls.size():
						_prev_positions[i] = _active_balls[i].pos
						_curr_positions[i] = _active_balls[i].pos
					# Flash at gate line position
					_flashes.append({&"pos": b.pos, &"ttl": 0.2, &"max_ttl": 0.2})

			while _event_cursor < _events.size():
				var e: Dictionary = _events[_event_cursor]
				if e[&"type"] == SimEvent.PEG_HIT:
					_score_ctx.pegs_hit += 1
					var hit_peg_id: int = e[&"peg_id"]
					if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
						var hit_type: PegType = _pegs[hit_peg_id].get(&"type")
						if hit_type != null and hit_type.behavior == PegType.Behavior.MULT:
							_score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
					_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15})
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
	RunMan.add_launch_score(score)
	# Clean up ball state first, before any phase transition
	_has_ball = false; _acc = 0.0
	_active_balls.clear()
	_prev_positions.clear(); _curr_positions.clear()
	_sync_hud()
	# Auto-advance when launches exhausted
	if RunMan.launches_exhausted():
		RunMan.advance()   # ROUND/BOSS_ROUND → ANTE_CLEAR or RUN_LOSE
		_handle_phase_transition()

func _handle_phase_transition() -> void:
	var phase: int = RunMan.state[&"phase"]
	match phase:
		RunManager.Phase.ANTE_CLEAR:
			RunMan.advance()   # ANTE_CLEAR → SHOP (triggers payout)
			_show_shop_ui()
		RunManager.Phase.RUN_LOSE:
			$Hud.set_gate_label("GAME OVER  (R to restart)")
		RunManager.Phase.RUN_WIN:
			$Hud.set_gate_label("YOU WIN!  (R to restart)")

func _show_shop_ui() -> void:
	_active_shop = Shop.new()
	_active_shop.roll(
		RunMan.state[&"master_seed"],
		RunMan.state[&"ante"],
		RunMan.state[&"round_in_ante"],
		0,
	)
	$Hud.show_shop(_active_shop.offerings, RunMan.state[&"money"])
	_sync_hud()

func leave_shop() -> void:
	if _active_shop == null:
		return
	_active_shop = null
	$Hud.hide_shop()
	RunMan.advance()   # SHOP → ROUND (calls _start_round inside)
	# Rebuild board for the new round
	_pegs = _build_honeycomb()
	_sim = _make_sim(_pegs)
	_apply_boss_mod()
	_refresh_equipped()
	_sync_hud()

func _draw_gate() -> void:
	var axis := gate_axis()
	var threshold := gate_threshold()
	var half_w := 25.0  # half-width of gate channel

	# Gate color by type
	var gate_color := Color(0.8, 0.8, 0.8, 0.7)
	match _active_gate_def.kind:
		GateDef.Kind.ACCEL:
			gate_color = Color(1.0, 0.8, 0.0, 0.85)
		GateDef.Kind.SCATTER_ANGLE:
			gate_color = Color(0.0, 0.8, 1.0, 0.85)
		GateDef.Kind.SCATTER_SPLIT:
			gate_color = Color(0.8, 0.2, 1.0, 0.85)

	var p1: Vector2; var p2: Vector2
	var entry_pos: Vector2 = EntryResolver.resolve(_entry_edge, _entry_t, _rect)[&"pos"]

	match axis:
		0:  # TOP: horizontal gate line
			p1 = Vector2(entry_pos.x - half_w, threshold)
			p2 = Vector2(entry_pos.x + half_w, threshold)
		1:  # LEFT: vertical gate line
			p1 = Vector2(threshold, entry_pos.y - half_w)
			p2 = Vector2(threshold, entry_pos.y + half_w)
		_:  # RIGHT: vertical gate line
			p1 = Vector2(threshold, entry_pos.y - half_w)
			p2 = Vector2(threshold, entry_pos.y + half_w)

	# Glow (wide, semi-transparent)
	draw_line(p1, p2, Color(gate_color.r, gate_color.g, gate_color.b, 0.3), 8.0)
	# Core (bright, thin)
	draw_line(p1, p2, gate_color, 2.5)

	# Channel walls (thin lines from edge to gate)
	var edge_p1: Vector2; var edge_p2: Vector2
	match axis:
		0:
			edge_p1 = Vector2(entry_pos.x - half_w, _rect.position.y)
			edge_p2 = Vector2(entry_pos.x + half_w, _rect.position.y)
		1:
			edge_p1 = Vector2(_rect.position.x, entry_pos.y - half_w)
			edge_p2 = Vector2(_rect.position.x, entry_pos.y + half_w)
		_:
			edge_p1 = Vector2(_rect.end.x, entry_pos.y - half_w)
			edge_p2 = Vector2(_rect.end.x, entry_pos.y + half_w)

	draw_line(edge_p1, p1, Color(gate_color.r, gate_color.g, gate_color.b, 0.25), 1.0)
	draw_line(edge_p2, p2, Color(gate_color.r, gate_color.g, gate_color.b, 0.25), 1.0)

func _draw() -> void:
	for peg in _pegs:
		var pt: PegType = peg.get(&"type")
		var col := Color(0.2, 0.9, 1.0)
		if pt != null and pt.behavior == PegType.Behavior.MULT:
			col = Color(1.0, 0.55, 0.0)
		draw_circle(peg[&"pos"], peg[&"radius"], col)
	if not _has_ball:
		_draw_gate()
	for i in range(1, prediction_pts.size()):
		draw_line(prediction_pts[i - 1], prediction_pts[i], Color(1, 1, 1, 0.4), 2.0)
	for fan in prediction_fans:
		for i in range(1, fan.size()):
			draw_line(fan[i - 1], fan[i], Color(1.0, 1.0, 0.4, 0.3), 1.5)
	if _has_ball:
		var alpha := _acc / DT
		for i in _active_balls.size():
			if _active_balls[i].alive:
				var dp := (_prev_positions[i] as Vector2).lerp(_curr_positions[i], alpha)
				draw_circle(dp, _active_balls[i].radius, Color(1.0, 0.3, 0.8))
	for f in _flashes:
		var a: float = f[&"ttl"] / f[&"max_ttl"]
		draw_circle(f[&"pos"], 16.0, Color(1.0, 1.0, 0.6, a * 0.8))
