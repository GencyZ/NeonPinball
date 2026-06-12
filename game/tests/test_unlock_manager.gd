extends GutTest

const UnlockManagerScript := preload("res://run/unlock_manager.gd")

class FakeDB:
	var triggers: Dictionary = {}
	var gate_defs: Dictionary = {}
	var peg_types: Dictionary = {}

func test_zero_runs_no_extra_unlocks() -> void:
	var ids: Array[StringName] = UnlockManagerScript.unlocked_ids(0)
	assert_false(ids.has(&"chain_bonus"),   "0 runs: chain_bonus locked")
	assert_false(ids.has(&"scatter_angle"), "0 runs: scatter_angle locked")
	assert_false(ids.has(&"double_mult"),   "0 runs: double_mult locked")
	assert_false(ids.has(&"scatter_split"), "0 runs: scatter_split locked")

func test_three_runs_unlocks_chain_bonus() -> void:
	var ids: Array[StringName] = UnlockManagerScript.unlocked_ids(3)
	assert_true(ids.has(&"chain_bonus"),     "3 runs: chain_bonus unlocked")
	assert_false(ids.has(&"scatter_angle"),  "3 runs: scatter_angle still locked")

func test_five_runs_unlocks_scatter_angle() -> void:
	var ids: Array[StringName] = UnlockManagerScript.unlocked_ids(5)
	assert_true(ids.has(&"chain_bonus"))
	assert_true(ids.has(&"scatter_angle"),  "5 runs: scatter_angle unlocked")
	assert_false(ids.has(&"double_mult"),   "5 runs: double_mult still locked")

func test_twelve_runs_all_unlocked() -> void:
	var ids: Array[StringName] = UnlockManagerScript.unlocked_ids(12)
	assert_true(ids.has(&"chain_bonus"))
	assert_true(ids.has(&"scatter_angle"))
	assert_true(ids.has(&"double_mult"))
	assert_true(ids.has(&"scatter_split"), "12 runs: everything unlocked")

func test_next_unlock_at_zero() -> void:
	var nxt: Dictionary = UnlockManagerScript.next_unlock(0)
	assert_false(nxt.is_empty(), "0 runs: next unlock exists")
	assert_eq(int(nxt["required_runs"]), 3)

func test_next_unlock_at_three() -> void:
	var nxt: Dictionary = UnlockManagerScript.next_unlock(3)
	assert_eq(int(nxt["required_runs"]), 5)

func test_next_unlock_fully_unlocked() -> void:
	var nxt: Dictionary = UnlockManagerScript.next_unlock(99)
	assert_true(nxt.is_empty(), "99 runs: all unlocked, next is empty")

func test_apply_unlocks_removes_locked_triggers() -> void:
	var fake := FakeDB.new()
	fake.triggers = {&"chain_bonus": true, &"double_mult": true}
	fake.gate_defs = {}
	fake.peg_types = {}
	UnlockManagerScript.apply_unlocks(fake, 0)
	assert_false(fake.triggers.has(&"chain_bonus"),  "chain_bonus removed at 0 runs")
	assert_false(fake.triggers.has(&"double_mult"),  "double_mult removed at 0 runs")

func test_apply_unlocks_keeps_earned_items() -> void:
	var fake := FakeDB.new()
	fake.triggers  = {&"chain_bonus": true, &"double_mult": true}
	fake.gate_defs = {&"scatter_angle": true}
	fake.peg_types = {}
	UnlockManagerScript.apply_unlocks(fake, 5)
	assert_true(fake.triggers.has(&"chain_bonus"),   "chain_bonus kept at 5 runs")
	assert_true(fake.gate_defs.has(&"scatter_angle"),"scatter_angle kept at 5 runs")
	assert_false(fake.triggers.has(&"double_mult"),  "double_mult removed at 5 runs")
