class_name BoardRefill extends RefCounted
# 棋盘持久/补钉的纯决策逻辑（可单测）。view 层调用，不持有状态。

# 落定后保留哪些钉：目标钉无条件保留（存亡由 HP 管）；
# 非目标钉若本发被直接命中（其 id 在 hit_ids）则清除，否则保留。
# pegs: Array[Dictionary]（每个含 &"id"，可选 &"is_target"）；hit_ids: Dictionary（peg id -> true）。
static func survivors(pegs: Array, hit_ids: Dictionary) -> Array:
	var kept: Array = []
	for peg in pegs:
		if peg.get(&"is_target", false):
			kept.append(peg)
		elif not hit_ids.has(int(peg[&"id"])):
			kept.append(peg)
	return kept
