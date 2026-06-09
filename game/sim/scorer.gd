class_name Scorer

var _pegs: Array

func _init(pegs: Array) -> void:
	_pegs = pegs

# 里程碑 1 仅基础分：每个 PEG_HIT 加该钉的 base_score。
# 触发器/倍率在里程碑 2 接入（见技术文档 §8）。
func score_launch(events: Array) -> float:
	var total := 0.0
	for e in events:
		if e[&"type"] == SimEvent.PEG_HIT:
			var id: int = e[&"peg_id"]
			if id >= 0 and id < _pegs.size():
				total += _pegs[id][&"base_score"]
	return total
