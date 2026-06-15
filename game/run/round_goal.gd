class_name RoundGoal extends RefCounted

# 每轮目标钉数量（随区轻微增长，封顶 6）
static func target_count_for(ante: int) -> int:
	return clampi(3 + (ante - 1) / 2, 3, 6)

# 每个目标钉 HP（随区轻微增长，封顶 3；HP=1 即一击清）
static func target_hp_for(ante: int) -> int:
	return clampi(2 + (ante - 1) / 3, 2, 3)
