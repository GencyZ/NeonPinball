extends GutTest

const BoardRefillScript := preload("res://run/board_refill.gd")

func _peg(id: int, is_target := false) -> Dictionary:
	return {&"id": id, &"is_target": is_target}

func test_keeps_unhit_removes_hit() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1), _peg(2)], {1: true})
	var ids: Array = []
	for p in kept:
		ids.append(int(p[&"id"]))
	assert_eq(kept.size(), 2, "撞中的 id1 被清，剩 2")
	assert_does_not_have(ids, 1, "id1 已清")
	assert_has(ids, 0, "id0 留")
	assert_has(ids, 2, "id2 留")

func test_targets_always_kept_even_if_hit() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0, true), _peg(1)], {0: true, 1: true})
	var ids: Array = []
	for p in kept:
		ids.append(int(p[&"id"]))
	assert_has(ids, 0, "目标钉无条件保留（存亡由 HP 管）")
	assert_does_not_have(ids, 1, "非目标撞中清除")

func test_empty_hit_keeps_all() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1, true), _peg(2)], {})
	assert_eq(kept.size(), 3, "没撞任何钉 → 全留")

func test_empty_pegs_returns_empty() -> void:
	assert_eq(BoardRefillScript.survivors([], {3: true}).size(), 0, "空盘 → 空")

func test_all_hit_nontargets_cleared_target_stays() -> void:
	var kept: Array = BoardRefillScript.survivors([_peg(0), _peg(1), _peg(2, true)], {0: true, 1: true, 2: true})
	assert_eq(kept.size(), 1, "两普通清除，目标留")
	assert_true(kept[0].get(&"is_target", false), "留下的是目标钉")
