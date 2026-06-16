extends Node2D

const DT := 1.0 / 120.0
const GATE_DIST := 0.0
const PEG_ANIM_DUR := 0.18      # peg hit pop duration (s)
const PEG_ANIM_SCALE := 0.5     # extra radius at pop peak (1.0 -> 1.5x)
const PEG_EXIT_DUR  := 0.4      # peg disappear animation (s)
const PEG_ENTER_DUR := 0.4      # peg appear animation (s)
const HALO_DUR      := 0.45     # expanding ring on peg hit (s)
const HALO_EXPAND   := 38.0     # ring max expand beyond peg radius (px)
const RunManagerScript := preload("res://run/run_manager.gd")
const SaveSystemScript := preload("res://run/save_system.gd")
const JuiceControllerScript := preload("res://juice/juice_controller.gd")
const ComboScoreScript := preload("res://scoring/combo_score.gd")
const ScoreTickerScript := preload("res://juice/score_ticker.gd")
const RoundGoalScript := preload("res://run/round_goal.gd")
const ALL_CLEAR_DUR := 0.5
const SfxControllerScript := preload("res://juice/sfx_controller.gd")
const NeonEnvScript := preload("res://view/neon_environment.gd")
const COMBO_DISPLAY_DUR := 0.6

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

var _is_transitioning := false
var _dying_pegs: Array = []         # [{data, ttl, max_ttl}] — visual shrink
var _peg_enter_ttls: Dictionary = {} # peg_id → remaining ttl — visual grow
var _peg_halos: Array = []           # [{pos, r0, r1, ttl, max_ttl, color}]

var _juice
var _last_settle_pos := Vector2.ZERO
var _combo: int = 0
var _last_hit_pos := Vector2.ZERO
var _combo_display_ttl := 0.0
var _sfx

var _target_pegs: Array = []        # 跨本轮持久的目标钉 dict（含 hp/is_target）
var _target_total_placed: int = 0   # 本轮实际生成的目标钉数（用于 HUD 计数）
var _all_clear_ttl := 0.0           # ALL CLEAR 大字计时（由 _draw() 读取绘制；见目标钉可视化任务）
var _score_ticker
var _live_target := 0.0

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
	_target_pegs = _generate_target_pegs()
	_pegs = _compose_pegs()
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(false)  # active gate open, others closed
	_engine = ScoringEngine.new()
	_score_ctx = ScoreContext.new()
	_juice = JuiceControllerScript.new()
	_score_ticker = ScoreTickerScript.new()
	_sfx = SfxControllerScript.new()
	add_child(_sfx)
	var we := WorldEnvironment.new()
	we.environment = NeonEnvScript.make_environment()
	add_child(we)

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

func _generate_pegs(avoid_pos: Array = []) -> Array:
	var ante: int = RunMan.state[&"ante"]
	var ria: int  = RunMan.state[&"round_in_ante"]
	var depth := (ante - 1) * 3 + ria   # 0 (ante1 r1) … 23 (ante8 boss)
	var rng := DeterministicRng.derive(int(RunMan.state[&"master_seed"]) + _launch_count, 0x9E3779B9)

	var count := rng.range_int(25 + ante * 2, 38 + ante * 3)

	# Placeable area: inside board, above funnel, with margins
	var margin := 44.0
	var area := Rect2(
		_rect.position.x + margin,
		_rect.position.y + margin + 80.0,   # extra top gap for channel walls
		_rect.size.x - margin * 2.0,
		780.0 - margin * 2.0 - 80.0)        # height fits above funnel (local y < 780)

	var special_rate := minf(float(depth) / 23.0 * 0.55, 0.55)
	var type_pool := _build_type_pool(depth)

	var list: Array = []
	var placed_pos: Array = []
	var placed_rad: Array = []
	var id := 0
	var attempts := 0

	while list.size() < count and attempts < count * 30:
		attempts += 1
		var r := rng.range_float(10.0, 20.0)
		var pos := Vector2(
			rng.range_float(area.position.x + r, area.end.x - r),
			rng.range_float(area.position.y + r, area.end.y - r))

		var too_close := false
		for j in placed_pos.size():
			if pos.distance_to(placed_pos[j]) < r + placed_rad[j] + 18.0:
				too_close = true; break
		if not too_close:
			for ap in avoid_pos:
				if pos.distance_to(ap) < r + 24.0 + 18.0:
					too_close = true; break
		if too_close:
			continue

		var peg_type: PegType
		if type_pool.size() > 0 and rng.next_float() < special_rate:
			peg_type = type_pool[rng.range_int(0, type_pool.size())]
		else:
			peg_type = GameDB.peg_types[&"normal"]

		list.append({&"id": id, &"pos": pos, &"radius": r,
					 &"base_score": r * 0.6, &"type": peg_type,
					 &"frozen": false, &"poisoned": false})
		placed_pos.append(pos)
		placed_rad.append(r)
		id += 1
	return list

# 每轮生成一次的持久目标钉（金色、带 HP）。确定性 RNG。
func _generate_target_pegs() -> Array:
	var ante: int = RunMan.state[&"ante"]
	var k := RoundGoalScript.target_count_for(ante)
	var hp := RoundGoalScript.target_hp_for(ante)
	# tag 按 (ante, round_in_ante) 唯一区分，且与填充钉的 seed(master+launch_count) 不同源，互不相关
	var rng := DeterministicRng.derive(int(RunMan.state[&"master_seed"]),
		ante * 131 + int(RunMan.state[&"round_in_ante"]) * 17 + 1009)
	var margin := 44.0
	var area := Rect2(
		_rect.position.x + margin,
		_rect.position.y + margin + 80.0,
		_rect.size.x - margin * 2.0,
		780.0 - margin * 2.0 - 80.0)
	var list: Array = []
	var placed: Array = []
	var attempts := 0
	while list.size() < k and attempts < k * 40:
		attempts += 1
		var r := 16.0
		var pos := Vector2(
			rng.range_float(area.position.x + r, area.end.x - r),
			rng.range_float(area.position.y + r, area.end.y - r))
		var too_close := false
		for p in placed:
			if pos.distance_to(p) < 90.0:
				too_close = true; break
		if too_close:
			continue
		list.append({&"pos": pos, &"radius": r, &"base_score": 10.0,
					 &"type": GameDB.peg_types[&"normal"], &"frozen": false, &"poisoned": false,
					 &"is_target": true, &"hp": hp, &"hp_max": hp})
		placed.append(pos)
	_target_total_placed = list.size()
	return list

# 合成本发棋盘：填充钉（避开目标位）+ 存活目标钉，按下标重排 id。
func _compose_pegs() -> Array:
	var avoid: Array = []
	for t in _target_pegs:
		avoid.append(t[&"pos"])
	var combined: Array = _generate_pegs(avoid)
	combined.append_array(_target_pegs)
	for i in combined.size():
		combined[i][&"id"] = i
	return combined

func _build_type_pool(depth: int) -> Array:
	var pool: Array = []
	if depth >= 3:  pool.append(GameDB.peg_types[&"mult"])
	if depth >= 7:  pool.append(GameDB.peg_types[&"chain"])
	if depth >= 11:
		pool.append(GameDB.peg_types[&"bomb"])
		pool.append(GameDB.peg_types[&"freeze"])
	if depth >= 15:
		pool.append(GameDB.peg_types[&"jackpot"])
		pool.append(GameDB.peg_types[&"poison"])
	if depth >= 19:
		pool.append(GameDB.peg_types[&"life"])
		pool.append(GameDB.peg_types[&"magnet"])
	return pool

func _make_sim(pegs: Array) -> BallSimulation:
	return BallSimulation.new(_rect, pegs, {
		&"gravity": Vector2(0, 1400), &"max_speed": 4000.0,
		&"restitution": 0.82, &"tangent_keep": 0.98, &"dt": DT,
	})

const WALL_REST := 0.82
const FUNNEL_REST := 0.05
const CHANNEL_REST := 0.65

# 通道半宽（垂直于通道方向）：两条侧墙间距 = 2 * CHANNEL_HW，三个通道一致。
const CHANNEL_HW := 30.0

func _funnel_segs() -> Array:
	var o := _rect.position
	return [
		{&"a": o + Vector2(0, 780),   &"b": o + Vector2(240, 900), &"restitution": FUNNEL_REST},
		{&"a": o + Vector2(540, 780), &"b": o + Vector2(300, 900), &"restitution": FUNNEL_REST},
	]

# 通道几何：两条侧墙平行于 launcher→gate 方向，端盖垂直于侧墙。
# 返回 launcher 两端点(lp_a/lp_b)与它们沿通道方向打到板壁的交点(g1/g2，即门口两端)。
func _channel_geometry(edge: int) -> Dictionary:
	var lp: Vector2 = EntryResolver.LAUNCHER_POS[edge]
	var dir: Vector2 = EntryResolver.channel_dir(edge, _rect)
	var perp := Vector2(-dir.y, dir.x)            # 垂直于通道方向
	var lp_a := lp + perp * CHANNEL_HW
	var lp_b := lp - perp * CHANNEL_HW
	return {
		&"lp_a": lp_a, &"lp_b": lp_b,
		&"g1": _ray_hit_wall(edge, lp_a, dir),
		&"g2": _ray_hit_wall(edge, lp_b, dir),
	}

# 从 from 沿 dir 射线打到该边对应的板壁直线上的交点。
func _ray_hit_wall(edge: int, from: Vector2, dir: Vector2) -> Vector2:
	var t := 0.0
	match edge:
		EntryResolver.BoardEdge.LEFT:  t = (_rect.position.x - from.x) / dir.x
		EntryResolver.BoardEdge.RIGHT: t = (_rect.end.x - from.x) / dir.x
		_:                             t = (_rect.position.y - from.y) / dir.y   # TOP
	return from + dir * t

func _wall_segs_for_edge(edge: int) -> Array:
	var geo := _channel_geometry(edge)
	var g1: Vector2 = geo[&"g1"]
	var g2: Vector2 = geo[&"g2"]
	match edge:
		EntryResolver.BoardEdge.LEFT:
			var lo := minf(g1.y, g2.y)
			var hi := maxf(g1.y, g2.y)
			return [
				{&"a": Vector2(_rect.position.x, _rect.position.y), &"b": Vector2(_rect.position.x, lo), &"restitution": WALL_REST},
				{&"a": Vector2(_rect.position.x, hi), &"b": Vector2(_rect.position.x, _rect.position.y + 780.0), &"restitution": WALL_REST},
			]
		EntryResolver.BoardEdge.RIGHT:
			var lo := minf(g1.y, g2.y)
			var hi := maxf(g1.y, g2.y)
			return [
				{&"a": Vector2(_rect.end.x, _rect.position.y), &"b": Vector2(_rect.end.x, lo), &"restitution": WALL_REST},
				{&"a": Vector2(_rect.end.x, hi), &"b": Vector2(_rect.end.x, _rect.position.y + 780.0), &"restitution": WALL_REST},
			]
		_:  # TOP
			var lo := minf(g1.x, g2.x)
			var hi := maxf(g1.x, g2.x)
			return [
				{&"a": Vector2(_rect.position.x, _rect.position.y), &"b": Vector2(lo, _rect.position.y), &"restitution": WALL_REST},
				{&"a": Vector2(hi, _rect.position.y), &"b": Vector2(_rect.end.x, _rect.position.y), &"restitution": WALL_REST},
			]

func _gate_seg(edge: int) -> Dictionary:
	var geo := _channel_geometry(edge)
	return {&"a": geo[&"g1"], &"b": geo[&"g2"], &"restitution": WALL_REST}

# 通道两侧平行墙段：launcher 端点 → 板壁交点，完全平行于通道方向。
func _channel_segs(edge: int) -> Array:
	var geo := _channel_geometry(edge)
	return [
		{&"a": geo[&"lp_a"], &"b": geo[&"g1"], &"restitution": CHANNEL_REST},
		{&"a": geo[&"lp_b"], &"b": geo[&"g2"], &"restitution": CHANNEL_REST},
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
	if edge != _entry_edge:
		_entry_edge = edge
		if not _has_ball:
			_rebuild_wall_segs(false)   # open new gate, close old one
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
	$Hud.set_target_count(_target_total_placed - _target_pegs.size(), _target_total_placed)


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
	_combo = 0
	_score_ticker.reset()
	_live_target = 0.0
	_combo_display_ttl = 0.0
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
					_combo += 1
					_last_hit_pos = e[&"pos"]
					_sfx.play_hit(_combo)
					_combo_display_ttl = COMBO_DISPLAY_DUR
					var hit_peg_id: int = e[&"peg_id"]
					if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
						_peg_anims[hit_peg_id] = PEG_ANIM_DUR
						var hit_peg: Dictionary = _pegs[hit_peg_id]
						var hit_type: PegType = hit_peg.get(&"type")
						var behavior := hit_type.behavior if hit_type != null else PegType.Behavior.NORMAL
						if hit_peg.get(&"is_target", false):
							_hit_target_peg(hit_peg)
						else:
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
						var halo_col := Color.from_hsv(randf(), 1.0, 1.0)
						_peg_halos.append({&"pos": hit_peg[&"pos"],
							&"r0": hit_peg[&"radius"], &"r1": hit_peg[&"radius"] + HALO_EXPAND * (1.0 + minf(float(_combo) * 0.1, 1.0)),
							&"ttl": HALO_DUR, &"max_ttl": HALO_DUR, &"color": halo_col})
						_juice.on_peg_hit_combo(e[&"pos"], flash_color, _combo)
					else:
						_score_ctx.pegs_hit += 1
						var flash_color := Color.from_hsv(randf(), 0.85, 1.0)
						_juice.on_peg_hit_combo(e[&"pos"], flash_color, _combo)
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
	# Transition + halo animations run regardless of ball state
	for i in range(_dying_pegs.size() - 1, -1, -1):
		_dying_pegs[i][&"ttl"] -= delta
	for pid in _peg_enter_ttls.keys():
		_peg_enter_ttls[pid] -= delta
		if _peg_enter_ttls[pid] <= 0.0:
			_peg_enter_ttls.erase(pid)
	for i in range(_peg_halos.size() - 1, -1, -1):
		_peg_halos[i][&"ttl"] -= delta
		if _peg_halos[i][&"ttl"] <= 0.0:
			_peg_halos.remove_at(i)
	if _combo_display_ttl > 0.0:
		_combo_display_ttl -= delta
	if _all_clear_ttl > 0.0:
		_all_clear_ttl -= delta
	if _has_ball:
		# 飞行中实时值不含 combo（combo 仅在 _on_all_settled 注入，落定时再滚到含 combo 的终值）
		_live_target = _engine.settle(_score_ctx)[0]
	_score_ticker.update(_live_target, delta)
	_juice.update(delta)
	$Camera2D.offset = _juice.camera_offset()
	Engine.time_scale = _juice.time_scale()
	queue_redraw()

func _on_all_settled() -> void:
	var combo_x: float = ComboScoreScript.xmult_for(_score_ctx.pegs_hit)
	if combo_x > 1.0:
		_score_ctx.add(ScoreContext.KIND_MUL_MULT, combo_x, &"combo")
	var result := _engine.settle(_score_ctx)
	var score: float = result[0]
	_live_target = score
	_juice.on_settle_combo(_last_settle_pos, score, combo_x, RunMan.launches_exhausted())
	_sfx.play_settle()
	_combo = 0
	$Hud.add_score(score)
	RunMan.add_launch_score(score)
	_has_ball = false; _acc = 0.0
	_active_balls.clear()
	_prev_positions.clear(); _curr_positions.clear()
	_gate_applied = false
	_rebuild_wall_segs(false)
	_sync_hud()
	if RunMan.launches_exhausted():
		RunMan.advance()
		_handle_phase_transition()
	else:
		_start_peg_transition()

func _start_peg_transition() -> void:
	_is_transitioning = true
	_dying_pegs.clear()
	var survivors: Array = []
	for peg in _pegs:
		if peg.get(&"is_target", false):
			survivors.append(peg)   # 目标钉持久，不消失
		else:
			_dying_pegs.append({&"data": peg.duplicate(), &"ttl": PEG_EXIT_DUR, &"max_ttl": PEG_EXIT_DUR})
	_pegs = survivors
	for i in _pegs.size():
		_pegs[i][&"id"] = i
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(false)
	get_tree().create_timer(PEG_EXIT_DUR).timeout.connect(_on_peg_exit_done)

func _on_peg_exit_done() -> void:
	_dying_pegs.clear()
	_pegs = _compose_pegs()
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(false)
	_peg_enter_ttls.clear()
	for peg in _pegs:
		if peg.get(&"is_target", false):
			continue   # 目标钉一直在场，不播放出现动画
		_peg_enter_ttls[peg[&"id"]] = PEG_ENTER_DUR
	get_tree().create_timer(PEG_ENTER_DUR).timeout.connect(_on_peg_enter_done)

func _on_peg_enter_done() -> void:
	_peg_enter_ttls.clear()
	_is_transitioning = false

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
			_live_target = 0.0
			_score_ticker.reset()
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
			_live_target = 0.0
			_score_ticker.reset()
			var saved := SaveSystemScript.load_data()
			saved[&"runs_completed"] = int(saved[&"runs_completed"]) + 1
			SaveSystemScript.save(saved)
			$Hud.set_gate_label("GAME OVER")
			$Hud.show_end_buttons()

func _show_shop_ui() -> void:
	_live_target = 0.0
	_score_ticker.reset()
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
	_target_pegs = _generate_target_pegs()
	_pegs = _compose_pegs()
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
	# Dying pegs: shrink + fade out
	for dp in _dying_pegs:
		var frac := maxf(dp[&"ttl"] / dp[&"max_ttl"], 0.0)
		var r: float = dp[&"data"][&"radius"] * frac
		if r < 0.3:
			continue
		var pt: PegType = dp[&"data"].get(&"type")
		var col := pt.glow if pt != null else Color(0.2, 0.9, 1.0)
		draw_circle(dp[&"data"][&"pos"], r, Color(col.r, col.g, col.b, frac))

	# Active pegs: enter-grow + hit-pop
	for peg in _pegs:
		var pt: PegType = peg.get(&"type")
		var col := Color(0.2, 0.9, 1.0)
		if pt != null: col = pt.glow
		if peg.get(&"frozen", false):   col = col.lerp(Color(0.6, 0.9, 1.0), 0.6)
		if peg.get(&"poisoned", false): col = col.lerp(Color(0.3, 0.8, 0.2), 0.5)
		var radius: float = peg[&"radius"]
		var enter_ttl: float = _peg_enter_ttls.get(peg[&"id"], 0.0)
		if enter_ttl > 0.0:
			radius *= 1.0 - enter_ttl / PEG_ENTER_DUR   # 0 → full
		var anim_ttl: float = _peg_anims.get(peg[&"id"], 0.0)
		if anim_ttl > 0.0:
			var prog := 1.0 - anim_ttl / PEG_ANIM_DUR
			radius *= 1.0 + PEG_ANIM_SCALE * sin(prog * PI)
		if radius < 0.3:
			continue
		draw_circle(peg[&"pos"], radius, col)
		if peg.get(&"is_target", false):
			draw_arc(peg[&"pos"], radius + 3.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.2), 2.0)
			var f := ThemeDB.fallback_font
			draw_string(f, peg[&"pos"] + Vector2(-5, 5), str(int(peg[&"hp"])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))   # 偏移按目标钉 radius=16 调

	# Halos: expanding ring on peg hit
	for h in _peg_halos:
		var t: float = 1.0 - float(h[&"ttl"]) / float(h[&"max_ttl"])
		var hr: float = lerpf(float(h[&"r0"]), float(h[&"r1"]), t)
		var alpha: float = float(h[&"ttl"]) / float(h[&"max_ttl"]) * 0.8
		var c: Color = h[&"color"]
		draw_arc(h[&"pos"], hr, 0.0, TAU, 32, Color(c.r, c.g, c.b, alpha), 2.5)

	if _combo >= 2 and _combo_display_ttl > 0.0:
		var f := ThemeDB.fallback_font
		var frac := _combo_display_ttl / COMBO_DISPLAY_DUR
		var fsize := 28 + mini(_combo, 20) * 2   # 基准 28px，随 combo 增大，封顶 68px
		var col := Color(1.0, 1.0, 1.0, frac)
		draw_string(f, _last_hit_pos + Vector2(-14, -22), "x%d" % _combo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)   # 偏移：命中点左上方
	if _all_clear_ttl > 0.0:
		var f2 := ThemeDB.fallback_font
		var a := _all_clear_ttl / ALL_CLEAR_DUR
		draw_string(f2, _rect.position + Vector2(90, 430), "ALL CLEAR!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.9, 0.3, a))
	var sv := int(round(_score_ticker.value()))
	if sv > 0:
		var tf := ThemeDB.fallback_font
		var psc: float = _score_ticker.punch_scale()
		var fsz := int(40.0 * psc)
		var stxt := str(sv)
		var tw := tf.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		draw_string(tf, _rect.position + Vector2(270.0 - tw * 0.5, 60.0),
			stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(1, 1, 1))
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
		draw_circle(f[&"pos"], 7.0, Color(base_col.r, base_col.g, base_col.b, a * 0.8))
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

# 给目标钉扣 1 HP + 计分；hp≤0 时从 _target_pegs 移除并检测全清。
# 返回是否被摧毁（调用方负责从 _pegs 移除 + 重建 sim）。不触碰 _pegs/sim。
func _damage_target(peg: Dictionary) -> bool:
	peg[&"hp"] = int(peg[&"hp"]) - 1
	_score_peg(peg)
	var destroyed := int(peg[&"hp"]) <= 0
	if destroyed:
		_target_pegs.erase(peg)
		if _target_pegs.is_empty():
			RunMan.state[&"targets_done"] = true
			_play_all_clear()
	_sync_hud()
	return destroyed

# 直接球命中目标钉。
func _hit_target_peg(peg: Dictionary) -> void:
	if _damage_target(peg):
		_pegs.erase(peg)
		_sim = _make_sim(_pegs)
		_rebuild_wall_segs(_gate_applied)
		_events.resize(_event_cursor + 1)

func _play_all_clear() -> void:
	_all_clear_ttl = ALL_CLEAR_DUR
	_juice.slowmo.request(0.3, 0.4)
	_juice.floaters.add(_last_hit_pos + Vector2(0, -40), "ALL CLEAR!")
	_juice.shake.add(0.5)

func _trigger_chain(chain_peg: Dictionary) -> void:
	var chain_removed: Array = []
	for peg in _pegs:
		if peg[&"id"] == chain_peg[&"id"] or peg.get(&"hit", false):
			continue
		if (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"]) <= CHAIN_RADIUS:
			if peg.get(&"is_target", false):
				if _damage_target(peg):
					chain_removed.append(peg)
			else:
				_score_peg(peg)
	for peg in chain_removed:
		_pegs.erase(peg)
	if not chain_removed.is_empty():
		_sim = _make_sim(_pegs)
		_rebuild_wall_segs(_gate_applied)
		_events.resize(_event_cursor + 1)

func _trigger_bomb(bomb_peg: Dictionary) -> void:
	var to_remove: Array = []
	for peg in _pegs:
		if (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"]) <= BOMB_RADIUS:
			if peg.get(&"is_target", false):
				if _damage_target(peg):
					to_remove.append(peg)
			else:
				_score_peg(peg)
				to_remove.append(peg)
	for peg in to_remove:
		_pegs.erase(peg)
	_sim = _make_sim(_pegs)
	_rebuild_wall_segs(_gate_applied)
	# 清除旧 sim 预计算的事件（下标已失效），让下一帧用新 sim 重新生成
	_events.resize(_event_cursor + 1)
	# 炸弹爆炸迸射；冲击的屏震/顿帧已由 PEG_HIT 处的 on_peg_hit_combo 统一处理，避免双重叠加
	_juice.particles.emit(bomb_peg[&"pos"], Color(1.0, 0.4, 0.1), 18)

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
