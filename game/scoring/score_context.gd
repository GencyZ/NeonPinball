class_name ScoreContext

const KIND_ADD_BASE := 0
const KIND_ADD_MULT := 1
const KIND_MUL_MULT := 2

var ledger: Array = []
var bounce_count: int = 0
var pegs_hit: int = 0
var gate_used_accel: bool = false
var gate_used_scatter: bool = false
var launch_index: int = 0

func add(kind: int, value: float, source: StringName) -> void:
    ledger.append({&"kind": kind, &"value": value, &"source": source})

func clear_for_launch() -> void:
    ledger.clear()
    bounce_count = 0; pegs_hit = 0
    gate_used_accel = false; gate_used_scatter = false
