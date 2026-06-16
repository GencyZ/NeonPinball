class_name ScoreTicker extends RefCounted

const APPROACH := 12.0       # display 朝 target 每秒逼近比例
const JUMP_FRAC := 0.15      # target 相对当前跳升超过此比例…
const JUMP_MIN := 20.0       # …且绝对增量超过此值 → 触发 punch（两者都满足）
const PUNCH_DUR := 0.18      # punch 持续（秒）
const PUNCH_SCALE := 0.4     # punch 峰值额外缩放（1.0 → 1.4）

var _display := 0.0
var _target := 0.0
var _punch_ttl := 0.0

# 每帧调用：设目标、检测跳升、逼近、衰减 punch。
func update(target: float, delta: float) -> void:
	var jump := target - _target
	if jump > JUMP_MIN and jump > _target * JUMP_FRAC:
		_punch_ttl = PUNCH_DUR
	_target = target
	_display += (_target - _display) * minf(1.0, APPROACH * delta)
	if absf(_target - _display) < 0.5:
		_display = _target
	if _punch_ttl > 0.0:
		_punch_ttl = maxf(0.0, _punch_ttl - delta)

func value() -> float:
	return _display

# punch 缩放：基准 1.0，跳升后鼓包再回落。
func punch_scale() -> float:
	return 1.0 + PUNCH_SCALE * sin(_punch_ttl / PUNCH_DUR * PI)

func reset() -> void:
	_display = 0.0
	_target = 0.0
	_punch_ttl = 0.0
