class_name GateRuntime

var _def: GateDef
var _rng: DeterministicRng

func _init(def: GateDef, rng: DeterministicRng) -> void:
    _def = def; _rng = rng

func apply(balls: Array) -> Array:
    var result := []
    for ball in balls:
        match _def.kind:
            GateDef.Kind.NORMAL:
                result.append(ball)
            GateDef.Kind.ACCEL:
                ball.vel = ball.vel * _def.speed_mul
                result.append(ball)
            GateDef.Kind.SCATTER_ANGLE:
                var angle := _rng.range_float(-_def.scatter_angle, _def.scatter_angle)
                ball.vel = ball.vel.rotated(angle)
                result.append(ball)
            GateDef.Kind.SCATTER_SPLIT:
                for k in _def.split_count:
                    var frac := float(k) / maxf(_def.split_count - 1, 1) - 0.5
                    var nb: BallState = ball.clone()
                    nb.vel = ball.vel.rotated(frac * _def.scatter_angle)
                    result.append(nb)
    return result
