class_name JuiceController extends RefCounted

const ScreenShakeScript := preload("res://juice/screen_shake.gd")
const ParticleBurstScript := preload("res://juice/particle_burst.gd")
const FloatersScript := preload("res://juice/floaters.gd")
const SlowMoScript := preload("res://juice/slow_mo.gd")

var shake
var particles
var floaters
var slowmo
var _cam_offset := Vector2.ZERO
var _time_scale := 1.0

func _init() -> void:
	shake = ScreenShakeScript.new()
	particles = ParticleBurstScript.new()
	floaters = FloatersScript.new()
	slowmo = SlowMoScript.new()

# 旧逐击反馈：board_view 已改用 on_peg_hit_combo（保留兼容，暂不删）。
func on_peg_hit(pos: Vector2, color: Color, big: bool) -> void:
	shake.add(0.3 if big else 0.12)
	particles.emit(pos, color, 14 if big else 6)

# 连击 → 屏震幅度：combo 1=0.12（与原小击一致），每级 +0.02，combo 15 封顶 0.4
static func shake_mag_for_combo(n: int) -> float:
	return minf(0.12 + 0.02 * float(n - 1), 0.4)

# 连击 → 逐击顿帧时长（秒）：combo 1=0.025，每级 +0.006，combo 12 封顶 0.090
static func hitstop_duration_for_combo(n: int) -> float:
	return minf(0.025 + 0.006 * float(n - 1), 0.090)

# 连击感知的击中反馈：屏震/顿帧/粒子随 combo 放大。
func on_peg_hit_combo(pos: Vector2, color: Color, combo: int) -> void:
	shake.add(shake_mag_for_combo(combo))
	particles.emit(pos, color, 6 + mini(combo, 12))   # 6→18 粒子随 combo
	slowmo.request(0.05, hitstop_duration_for_combo(combo))

func on_settle(pos: Vector2, score: float, is_final_launch: bool) -> void:
	floaters.add(pos, "+%d" % int(score))
	shake.add(0.2)
	if is_final_launch and score > 0.0:
		slowmo.request(0.35, 0.25)

func update(delta: float) -> void:
	_cam_offset = shake.update(delta)
	_time_scale = slowmo.update(delta)
	particles.update(delta)
	floaters.update(delta)

func camera_offset() -> Vector2:
	return _cam_offset

func time_scale() -> float:
	return _time_scale
