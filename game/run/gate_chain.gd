class_name GateChain

var _gates: Array[GateRuntime] = []

func _init(gates: Array = []) -> void:
    for g in gates:
        _gates.append(g as GateRuntime)

func process(entry_ball: BallState) -> Array:
    var balls: Array = [entry_ball]
    for gate in _gates:
        balls = gate.apply(balls)
    return balls
