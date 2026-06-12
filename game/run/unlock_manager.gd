class_name UnlockManager extends RefCounted

# Unlock table: content gated behind runs_completed count.
# Items not listed here are available from the start.
const UNLOCK_TABLE: Array = [
	{"id": &"chain_bonus",   "type": "trigger", "required_runs": 3 },
	{"id": &"scatter_angle", "type": "gate",    "required_runs": 5 },
	{"id": &"double_mult",   "type": "trigger", "required_runs": 8 },
	{"id": &"scatter_split", "type": "gate",    "required_runs": 12},
]

# Returns ids of all items unlocked so far.
static func unlocked_ids(runs_completed: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry in UNLOCK_TABLE:
		if runs_completed >= int(entry["required_runs"]):
			result.append(entry["id"] as StringName)
	return result

# Returns the next locked entry, or {} if everything is unlocked.
static func next_unlock(runs_completed: int) -> Dictionary:
	for entry in UNLOCK_TABLE:
		if runs_completed < int(entry["required_runs"]):
			return entry
	return {}

# Removes locked items from GameDB in-place.
static func apply_unlocks(db: Object, runs_completed: int) -> void:
	for entry in UNLOCK_TABLE:
		if runs_completed < int(entry["required_runs"]):
			var id := entry["id"] as StringName
			match entry["type"]:
				"trigger": db.triggers.erase(id)
				"gate":    db.gate_defs.erase(id)
				"peg":     db.peg_types.erase(id)
