class_name SlowMo extends RefCounted

var _timer := 0.0
var _target := 1.0

func request(scale: float, duration: float) -> void:
	# 更强(更慢=更低 scale)者胜；计时取更长者，逐击顿帧与最后一球慢动作不打架。
	if _timer <= 0.0 or scale < _target:
		_target = scale
	_timer = maxf(_timer, duration)

func update(delta: float) -> float:
	if _timer > 0.0:
		_timer -= delta
		return _target
	return 1.0

func is_active() -> bool:
	return _timer > 0.0
