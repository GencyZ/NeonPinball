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

func on_peg_hit(pos: Vector2, color: Color, big: bool) -> void:
	shake.add(0.3 if big else 0.12)
	particles.emit(pos, color, 14 if big else 6)

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
