class_name ComboScore extends RefCounted

const COMBO_RATE := 0.12      # 每命中一钉的 ×倍率增量
const COMBO_CAP := 5.0        # ×倍率封顶
const COMBO_MIN_PEGS := 2     # 低于此命中数不给加成

# 本发命中钉数 → ×倍率（与现有 ×mult 相乘）
static func xmult_for(pegs_hit: int) -> float:
	if pegs_hit < COMBO_MIN_PEGS:
		return 1.0
	return minf(1.0 + float(pegs_hit) * COMBO_RATE, COMBO_CAP)
