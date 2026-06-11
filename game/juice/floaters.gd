class_name Floaters extends RefCounted

var items: Array = []
const RISE := 40.0

func add(pos: Vector2, text: String, ttl: float = 0.9) -> void:
	items.append({&"pos": pos, &"text": text, &"ttl": ttl, &"max_ttl": ttl})

func update(delta: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it[&"pos"] = (it[&"pos"] as Vector2) - Vector2(0.0, RISE * delta)
		it[&"ttl"] -= delta
		if it[&"ttl"] <= 0.0:
			items.remove_at(i)

func alpha_of(item: Dictionary) -> float:
	return clampf(item[&"ttl"] / item[&"max_ttl"], 0.0, 1.0)
