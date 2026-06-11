extends Node2D

const DT := 1.0 / 120.0
const GATE_DIST := 0.0
const PEG_ANIM_DUR := 0.18      # peg hit pop duration (s)
const PEG_ANIM_SCALE := 0.5     # extra radius at pop peak (1.0 -> 1.5x)
const RunManagerScript := preload("res://run/run_manager.gd")
const SaveSystemScript := preload("res://run/save_system.gd")
const JuiceControllerScript := preload("res://juice/juice_controller.gd")

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
var _peg_anims: Dictionary = {}   # peg_id -> remaining pop-anim ttl

var _launch_count := 0

var _juice
var _last_settle_pos := Vector2.ZERO

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
	_rect = Rect2(135, 225, 540, 900)
	_pegs = _build_honeycomb()
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(false)  # active gate open, others closed
	_engine = ScoringEngine.new()
	_score_ctx = ScoreContext.new()
	_juice = JuiceControllerScript.new()

	for tid in [&"peg_bonus", &"bounce_mult", &"big_hit"]:
		_trigger_runtimes.append(TriggerRuntime.new(GameDB.triggers[tid]))

	set_active_gate(&"normal")

	if int(RunMan.state[&"master_seed"]) == 0:
		RunMan.state[&"master_seed"] = SaveSystemScript.daily_seed()

	# Auto-advance RunManager to ROUND on first start
	if RunMan.state[&"phase"] == RunManager.Phase.BOOT:
		RunMan.advance()   # BOOT → RUN_START
		RunMan.advance()   # RUN_START → ROUND
	_apply_boss_mod()
	_refresh_equipped()
	_sync_hud()

	var saved := SaveSystemScript.load_data()
	var daily_done: bool = bool(saved[&"daily_completed"]) and String(saved[&"last_date"]) == SaveSystemScript.today_string()
	if daily_done:
		$Hud.set_gate_label("Daily DONE  Best: %d" % int(saved[&"best_score"]))
	else:
		$Hud.set_gate_label("Daily #%d" % int(RunMan.state[&"master_seed"]))

	$Hud.shop_slot_pressed.connect(buy_shop_slot)
	$Hud.shop_continue_pressed.connect(leave_shop)

func _build_honeycomb() -> Array:
	var list := []
	var id := 0
	var rows := 8; var cols := 7
	var spacing := 64.0; var margin := 60.0
	var sizes := [7.0, 10.0, 13.0]
	var scores := [3.0, 5.0, 8.0]
	for r in rows:
		var y := _rect.position.y + margin + 140.0 + r * spacing
		var x_off := (r % 2) * spacing * 0.5
		for c in cols:
			var x := _rect.position.x + margin + x_off + c * spacing
			if x < _rect.end.x - margin:
				var tier := (r + c * 2) % 3
				var peg_type: PegType
				if   (r * 7  + c) % 7  == 3:  peg_type = GameDB.peg_types[&"mult"]
				elif (r * 11 + c) % 19 == 7:  peg_type = GameDB.peg_types[&"chain"]
				elif (r * 13 + c) % 31 == 5:  peg_type = GameDB.peg_types[&"bomb"]
				elif (r * 9  + c) % 23 == 4:  peg_type = GameDB.peg_types[&"freeze"]
				elif (r * 17 + c) % 47 == 9:  peg_type = GameDB.peg_types[&"jackpot"]
				elif (r * 19 + c) % 53 == 11: peg_type = GameDB.peg_types[&"life"]
				elif (r * 23 + c) % 37 == 6:  peg_type = GameDB.peg_types[&"poison"]
				elif (r * 29 + c) % 41 == 3:  peg_type = GameDB.peg_types[&"magnet"]
				else:                          peg_type = GameDB.peg_types[&"normal"]
				list.append({&"id": id, &"pos": Vector2(x, y),
							&"radius": sizes[tier], &"base_score": scores[tier],
							&"type": peg_type, &"frozen": false, &"poisoned": false})
				id += 1
	# Portal: 固定将第 5、45 号钉配对
	if list.size() > 45:
		list[5][&"type"]         = GameDB.peg_types[&"portal"]
		list[5][&"portal_pair"]  = 45
		list[45][&"type"]        = GameDB.peg_types[&"portal"]
		list[45][&"portal_pair"] = 5
	return list

func _make_sim(pegs: Array) -> BallSimulation:
	return BallSimulation.new(_rect, pegs, {
		&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
		&"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
	})

const WALL_REST := 0.82
const FUNNEL_REST := 0.05
const CHANNEL_REST := 0.65

const _GATE_LOCAL := {
	EntryResolver.BoardEdge.LEFT:  [Vector2(0, 105),   Vector2(0, 165)],    # 60px wide, center y=135
	EntryResolver.BoardEdge.RIGHT: [Vector2(540, 105),  Vector2(540, 165)],  # 60px wide, center y=135
	EntryResolver.BoardEdge.TOP:   [Vector2(240, 0),    Vector2(300, 0)],    # 60px wide, center x=270→actual 405
}

func _funnel_segs() -> Array:
	var o := _rect.position
	return [
		{&"a": o + Vector2(0, 780),   &"b": o + Vector2(240, 900), &"restitution": FUNNEL_REST},
		{&"a": o + Vector2(540, 780), &"b": o + Vector2(300, 900), &"restitution": FUNNEL_REST},
	]

func _wall_segs_for_edge(edge: int) -> Array:
	var o := _rect.position
	var g: Array = _GATE_LOCAL[edge]
	match edge:
		EntryResolver.BoardEdge.LEFT:
			return [
				{&"a": o + Vector2(0, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(0, 780), &"restitution": WALL_REST},
			]
		EntryResolver.BoardEdge.RIGHT:
			return [
				{&"a": o + Vector2(540, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(540, 780), &"restitution": WALL_REST},
			]
		_:  # TOP
			return [
				{&"a": o + Vector2(0, 0),   &"b": o + g[0], &"restitution": WALL_REST},
				{&"a": o + g[1], &"b": o + Vector2(540, 0), &"restitution": WALL_REST},
			]

func _gate_seg(edge: int) -> Dictionary:
	var o := _rect.position
	var g: Array = _GATE_LOCAL[edge]
	return {&"a": o + g[0], &"b": o + g[1], &"restitution": WALL_REST}

# 通道两侧平行墙段：从发射器两端连到门两端，完全平行于通道中心线。
func _channel_segs(edge: int) -> Array:
	var lp: Vector2 = EntryResolver.LAUNCHER_POS[edge]
	var glocal: Array = _GATE_LOCAL[edge]
	var gate_a: Vector2 = _rect.position + glocal[0]
	var gate_b: Vector2 = _rect.position + glocal[1]
	# 门边缘方向及半宽（即通道半宽）
	var gate_vec: Vector2 = glocal[1] - glocal[0]
	var gate_dir: Vector2 = gate_vec.normalized()
	var hw: float = gate_vec.length() * 0.5
	# 发射器两端点（沿门边缘方向偏移，使两侧墙平行）
	var lp_a: Vector2 = lp + gate_dir * hw   # +side → gate_b
	var lp_b: Vector2 = lp - gate_dir * hw   # -side → gate_a
	return [
		{&"a": lp_a, &"b": gate_b, &"restitution": CHANNEL_REST},
		{&"a": lp_b, &"b": gate_a, &"restitution": CHANNEL_REST},
	]

func _rebuild_wall_segs(close_active_gate: bool) -> void:
	var segs: Array = _funnel_segs()
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		segs.append_array(_wall_segs_for_edge(edge))
		if close_active_gate or edge != _entry_edge:
			segs.append(_gate_seg(edge))
		segs.append_array(_channel_segs(edge))
	_sim.set_wall_segs(segs)

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
			_rebuild_wall_segs(_gate_applied)

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
	_rebuild_wall_segs(false)  # open active gate for new ball
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
					_rebuild_wall_segs(true)  # seal gate
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
					var hit_peg_id: int = e[&"peg_id"]
					if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
						_peg_anims[hit_peg_id] = PEG_ANIM_DUR
						var hit_peg: Dictionary = _pegs[hit_peg_id]
						var hit_type: PegType = hit_peg.get(&"type")
						var behavior := hit_type.behavior if hit_type != null else PegType.Behavior.NORMAL
						match behavior:
							PegType.Behavior.NORMAL:
								_score_peg(hit_peg)
							PegType.Behavior.MULT:
								_score_ctx.pegs_hit += 1
								_score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")
							PegType.Behavior.CHAIN:
								_score_peg(hit_peg)
								_trigger_chain(hit_peg)
							PegType.Behavior.BOMB:
								_trigger_bomb(hit_peg)
							PegType.Behavior.FREEZE:
								_score_peg(hit_peg)
								_trigger_freeze(hit_peg)
							PegType.Behavior.JACKPOT:
								_score_peg(hit_peg)
								var jackpot_mult := randf_range(1.0, 10.0)
								_score_ctx.add(ScoreContext.KIND_ADD_MULT, jackpot_mult, &"jackpot")
								_flashes.append({&"pos": hit_peg[&"pos"], &"ttl": 0.4, &"max_ttl": 0.4, &"color": Color(1.0, 0.9, 0.0)})
								if hit_type.one_shot:
									_pegs.erase(hit_peg); _sim = _make_sim(_pegs)
									_rebuild_wall_segs(_gate_applied)
									_events.resize(_event_cursor + 1)
							PegType.Behavior.LIFE:
								RunMan.state[&"launches_left"] += 1
								_sync_hud()
								_score_peg(hit_peg)
								if hit_type.one_shot:
									_pegs.erase(hit_peg); _sim = _make_sim(_pegs)
									_rebuild_wall_segs(_gate_applied)
									_events.resize(_event_cursor + 1)
							PegType.Behavior.POISON:
								_score_peg(hit_peg)
								_trigger_poison(hit_peg)
								if hit_type.one_shot:
									_pegs.erase(hit_peg); _sim = _make_sim(_pegs)
									_rebuild_wall_segs(_gate_applied)
									_events.resize(_event_cursor + 1)
							PegType.Behavior.PORTAL:
								_trigger_portal(hit_peg, e[&"pos"])
							PegType.Behavior.MAGNET:
								_score_peg(hit_peg)
								_trigger_magnet(hit_peg)
						var flash_color: Color = hit_type.glow if hit_type != null else Color.from_hsv(randf(), 0.85, 1.0)
						_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)
					else:
						_score_ctx.pegs_hit += 1
						var flash_color := Color.from_hsv(randf(), 0.85, 1.0)
						_juice.on_peg_hit(e[&"pos"], flash_color, _score_ctx.pegs_hit >= 5)
						_flashes.append({&"pos": e[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15, &"color": flash_color})
				elif e[&"type"] == SimEvent.SETTLED:
					_last_settle_pos = e[&"pos"]
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
		for pid in _peg_anims.keys():
			_peg_anims[pid] -= delta
			if _peg_anims[pid] <= 0.0:
				_peg_anims.erase(pid)
	_juice.update(delta)
	$Camera2D.offset = _juice.camera_offset()
	Engine.time_scale = _juice.time_scale()
	queue_redraw()

func _on_all_settled() -> void:
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
	_juice.on_settle(_last_settle_pos, score, RunMan.launches_exhausted())
	$Hud.add_score(score)
	RunMan.add_launch_score(score)
	# Clean up ball state first, before any phase transition
	_has_ball = false; _acc = 0.0
	_active_balls.clear()
	_prev_positions.clear(); _curr_positions.clear()
	# Reopen the active gate so it shows green and is passable for the next launch
	_gate_applied = false
	_rebuild_wall_segs(false)
	_sync_hud()
	# Auto-advance when launches exhausted
	if RunMan.launches_exhausted():
		RunMan.advance()   # ROUND/BOSS_ROUND → ANTE_CLEAR or RUN_LOSE
		_handle_phase_transition()

func _handle_phase_transition() -> void:
	var phase: int = RunMan.state[&"phase"]
	match phase:
		RunManager.Phase.ANTE_CLEAR:
			RunMan.advance()   # ANTE_CLEAR → SHOP, or RUN_WIN on final ante (triggers payout)
			if RunMan.state[&"phase"] == RunManager.Phase.SHOP:
				_show_shop_ui()
			else:
				_handle_phase_transition()   # RUN_WIN: record the win, etc.
		RunManager.Phase.RUN_WIN:
			var saved := SaveSystemScript.load_data()
			var total: int = int(RunMan.state[&"money"])
			if total > int(saved[&"best_score"]):
				saved[&"best_score"] = total
			saved[&"runs_completed"] = int(saved[&"runs_completed"]) + 1
			saved[&"last_date"] = SaveSystemScript.today_string()
			saved[&"daily_completed"] = true
			SaveSystemScript.save(saved)
			$Hud.set_gate_label("YOU WIN!  Best: %d" % int(saved[&"best_score"]))
			$Hud.show_end_buttons()
		RunManager.Phase.RUN_LOSE:
			var saved := SaveSystemScript.load_data()
			saved[&"runs_completed"] = int(saved[&"runs_completed"]) + 1
			SaveSystemScript.save(saved)
			$Hud.set_gate_label("GAME OVER")
			$Hud.show_end_buttons()

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

func buy_shop_slot(slot: int) -> void:
	if _active_shop == null:
		return
	var money_ref := [RunMan.state[&"money"]]
	var inv := {&"items": []}
	var ok := _active_shop.buy(slot, inv, money_ref)
	if not ok:
		return
	RunMan.state[&"money"] = money_ref[0]
	for item in inv[&"items"]:
		if item is TriggerDef:
			var equipped: Array = RunMan.state[&"equipped_triggers"]
			if equipped.size() < 5:
				equipped.append(item.id)
		elif item is GateDef:
			RunMan.state[&"equipped_gate"] = item.id
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
	_rebuild_wall_segs(_gate_applied)
	_apply_boss_mod()
	_refresh_equipped()
	_sync_hud()

func _draw_walls() -> void:
	var cyan   := Color(0.0, 0.9, 1.0, 0.9)
	var g_open := Color(0.0, 1.0, 0.5, 0.9)
	var orange := Color(1.0, 0.55, 0.0, 0.9)
	var o := _rect.position

	# Draw each edge wall (two segments around its gate)
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		var segs: Array = _wall_segs_for_edge(edge)
		for seg in segs:
			draw_line(seg[&"a"], seg[&"b"], cyan, 2.5)

	# Draw funnel walls
	draw_line(o + Vector2(0, 780),   o + Vector2(240, 900), orange, 2.5)
	draw_line(o + Vector2(540, 780), o + Vector2(300, 900), orange, 2.5)

	# Draw gates (green=open, cyan=closed)
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		var is_open: bool = (edge == _entry_edge and not _gate_applied)
		var col := g_open if is_open else cyan
		var seg := _gate_seg(edge)
		draw_line(seg[&"a"], seg[&"b"], col, 3.0)

	# Draw channel walls for all launchers (active = full, inactive = dimmed)
	for edge in [EntryResolver.BoardEdge.LEFT, EntryResolver.BoardEdge.TOP,
				 EntryResolver.BoardEdge.RIGHT]:
		var chan_segs: Array = _channel_segs(edge)
		var col := cyan if edge == _entry_edge else Color(0.0, 0.9, 1.0, 0.3)
		for seg in chan_segs:
			draw_line(seg[&"a"], seg[&"b"], col, 2.5)
		# Launcher end cap (closing bar across the launcher opening)
		draw_line(chan_segs[0][&"a"], chan_segs[1][&"a"], col, 2.5)
	# Active launcher center dot
	draw_circle(EntryResolver.LAUNCHER_POS[_entry_edge], 4.0, Color(1.0, 0.3, 1.0, 0.9))

func _draw() -> void:
	for peg in _pegs:
		var pt: PegType = peg.get(&"type")
		var col := Color(0.2, 0.9, 1.0)
		if pt != null:
			col = pt.glow
		if peg.get(&"frozen", false):
			col = col.lerp(Color(0.6, 0.9, 1.0), 0.6)
		if peg.get(&"poisoned", false):
			col = col.lerp(Color(0.3, 0.8, 0.2), 0.5)
		var radius: float = peg[&"radius"]
		var anim_ttl: float = _peg_anims.get(peg[&"id"], 0.0)
		if anim_ttl > 0.0:
			var prog := 1.0 - anim_ttl / PEG_ANIM_DUR
			radius *= 1.0 + PEG_ANIM_SCALE * sin(prog * PI)
		draw_circle(peg[&"pos"], radius, col)
	_draw_walls()
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
		var base_col: Color = f.get(&"color", Color(1.0, 1.0, 0.6))
		draw_circle(f[&"pos"], 16.0, Color(base_col.r, base_col.g, base_col.b, a * 0.8))
	for p in _juice.particles.particles:
		var pa: float = p[&"ttl"] / p[&"max_ttl"]
		var pc: Color = p[&"color"]
		draw_circle(p[&"pos"], 3.0 * pa + 1.0, Color(pc.r, pc.g, pc.b, pa))
	var font := ThemeDB.fallback_font
	for item in _juice.floaters.items:
		var fa: float = _juice.floaters.alpha_of(item)
		draw_string(font, item[&"pos"], item[&"text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(1.0, 1.0, 1.0, fa))

# ── Peg behavior helpers ──────────────────────────────────────────────────────

const CHAIN_RADIUS  := 60.0
const BOMB_RADIUS   := 80.0
const FREEZE_RADIUS := 60.0
const POISON_RADIUS := 60.0
const MAGNET_RADIUS := 50.0

func _score_peg(peg: Dictionary) -> void:
	var pt: PegType = peg.get(&"type")
	var multiplier := 3.0 if peg.get(&"frozen", false) else 1.0
	var sign := -1.0 if peg.get(&"poisoned", false) else 1.0
	var base: float = peg.get(&"base_score", 5.0) * multiplier * sign
	_score_ctx.pegs_hit += 1
	_score_ctx.add(ScoreContext.KIND_ADD_BASE, base, &"peg")
	peg[&"frozen"] = false
	peg[&"poisoned"] = false
	var col: Color = pt.glow if pt != null else Color.WHITE
	_flashes.append({&"pos": peg[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15, &"color": col})

func _trigger_chain(chain_peg: Dictionary) -> void:
	for peg in _pegs:
		if peg[&"id"] == chain_peg[&"id"] or peg.get(&"hit", false):
			continue
		if (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"]) <= CHAIN_RADIUS:
			_score_peg(peg)

func _trigger_bomb(bomb_peg: Dictionary) -> void:
	var to_remove: Array = []
	for peg in _pegs:
		if (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"]) <= BOMB_RADIUS:
			_score_peg(peg)
			to_remove.append(peg)
	for peg in to_remove:
		_pegs.erase(peg)
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(_gate_applied)
	# 清除旧 sim 预计算的事件（下标已失效），让下一帧用新 sim 重新生成
	_events.resize(_event_cursor + 1)
	_juice.on_peg_hit(bomb_peg[&"pos"], Color(1.0, 0.4, 0.1), true)

func _trigger_freeze(freeze_peg: Dictionary) -> void:
	for peg in _pegs:
		if peg[&"id"] == freeze_peg[&"id"]:
			continue
		if (peg[&"pos"] as Vector2).distance_to(freeze_peg[&"pos"]) <= FREEZE_RADIUS:
			peg[&"frozen"] = true

func _trigger_poison(poison_peg: Dictionary) -> void:
	for peg in _pegs:
		if peg[&"id"] == poison_peg[&"id"]:
			continue
		var pt: PegType = peg.get(&"type")
		if pt != null and pt.behavior != PegType.Behavior.NORMAL:
			continue
		if (peg[&"pos"] as Vector2).distance_to(poison_peg[&"pos"]) <= POISON_RADIUS:
			peg[&"poisoned"] = true

func _trigger_magnet(magnet_peg: Dictionary) -> void:
	for peg in _pegs:
		if peg[&"id"] == magnet_peg[&"id"] or peg.get(&"hit", false):
			continue
		if (peg[&"pos"] as Vector2).distance_to(magnet_peg[&"pos"]) <= MAGNET_RADIUS:
			_score_peg(peg)

func _trigger_portal(portal_peg: Dictionary, hit_pos: Vector2) -> void:
	var pair_idx: int = portal_peg.get(&"portal_pair", -1)
	if pair_idx < 0 or pair_idx >= _pegs.size():
		_score_peg(portal_peg)
		return
	var partner: Dictionary = _pegs[pair_idx]
	# 找最近的活球传送
	var closest_ball: BallState = null
	var closest_dist := INF
	for ball in _active_balls:
		if ball.alive:
			var d: float = ball.pos.distance_to(hit_pos)
			if d < closest_dist:
				closest_dist = d
				closest_ball = ball
	if closest_ball != null:
		closest_ball.pos = partner[&"pos"] + Vector2(0.0, -24.0)
		# 截断后续已基于旧位置计算的事件
		_events.resize(_event_cursor + 1)
	_flashes.append({&"pos": portal_peg[&"pos"], &"ttl": 0.3, &"max_ttl": 0.3, &"color": Color(0.7, 1.0, 1.0)})
	_flashes.append({&"pos": partner[&"pos"],     &"ttl": 0.3, &"max_ttl": 0.3, &"color": Color(0.7, 1.0, 1.0)})
