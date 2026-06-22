class_name Gamble extends RefCounted
# 赌球：双倍或清零。成功 = 本球命中钉数达阈值。纯逻辑，无状态。

const GAMBLE_MULT := 2.0       # 成功倍率
const GAMBLE_MIN_PEGS := 6     # 成功所需最少命中钉数（头号旋钮，实机调）

static func is_success(pegs_hit: int) -> bool:
	return pegs_hit >= GAMBLE_MIN_PEGS

# 押注的球落定得分结算：成功 ×GAMBLE_MULT，失败清零。
static func resolve(base_score: float, pegs_hit: int) -> float:
	return base_score * GAMBLE_MULT if is_success(pegs_hit) else 0.0
