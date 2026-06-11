class_name ScreenShake extends RefCounted

var trauma := 0.0
const MAX_OFFSET := 16.0
const DECAY := 1.5

func add(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func update(delta: float) -> Vector2:
	if trauma <= 0.0:
		return Vector2.ZERO
	trauma = maxf(0.0, trauma - DECAY * delta)
	var shake := trauma * trauma
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * MAX_OFFSET

func is_active() -> bool:
	return trauma > 0.0
