class_name SlowMo extends RefCounted

var _timer := 0.0
var _target := 1.0

func request(scale: float, duration: float) -> void:
	_target = scale
	_timer = duration

func update(delta: float) -> float:
	if _timer > 0.0:
		_timer -= delta
		return _target
	return 1.0

func is_active() -> bool:
	return _timer > 0.0
