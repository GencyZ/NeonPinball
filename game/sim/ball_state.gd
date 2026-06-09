class_name BallState

var pos: Vector2
var vel: Vector2
var radius: float
var bounce_count: int
var alive: bool

func _init(p: Vector2, v: Vector2, r: float) -> void:
	pos = p; vel = v; radius = r
	bounce_count = 0; alive = true

func clone() -> BallState:
	var b := BallState.new(pos, vel, radius)
	b.bounce_count = bounce_count
	b.alive = alive
	return b
