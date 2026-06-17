# run/shop.gd
class_name Shop
extends Object

const SLOT_COUNT := 4
const BASE_REROLL_COST := 1
const REROLL_STEP := 1

var offerings: Array = []   # Array of {&"item": Resource, &"price": int, &"sold": bool}

func roll(master_seed: int, ante: int, node_cursor: int, reroll_count: int) -> void:
	assert(node_cursor < 100, "Shop.roll: node_cursor must be < 100 to avoid tag collision")
	assert(reroll_count < 100, "Shop.roll: reroll_count must be < 100 to avoid tag collision")
	var tag := ante * 10000 + node_cursor * 100 + reroll_count
	var rng := DeterministicRng.derive(master_seed, tag)
	offerings.clear()
	for _i in SLOT_COUNT:
		var item: Resource = _roll_item(ante, rng)
		offerings.append({
			&"item":  item,
			&"price": _price_of(item, ante),
			&"sold":  false,
		})

static func reroll_cost(reroll_count: int) -> int:
	return BASE_REROLL_COST + reroll_count * REROLL_STEP

func buy(slot: int, inventory: Dictionary, money_ref: Array) -> bool:
	if slot < 0 or slot >= offerings.size():
		return false
	var offer: Dictionary = offerings[slot]
	if offer[&"sold"]:
		return false
	if money_ref[0] < offer[&"price"]:
		return false
	money_ref[0] -= offer[&"price"]
	offer[&"sold"] = true
	inventory[&"items"].append(offer[&"item"])
	return true

func _roll_item(ante: int, rng: DeterministicRng) -> Resource:
	var use_gate := rng.next_float() < 0.35
	var item: Resource
	if use_gate:
		item = _roll_from_pool(GameDB.gate_defs.values(), ante, rng)
	else:
		item = _roll_from_pool(GameDB.triggers.values(), ante, rng)
	if item == null:
		item = GameDB.triggers.values()[0]   # absolute fallback
	return item

func _roll_from_pool(pool: Array, ante: int, rng: DeterministicRng) -> Resource:
	if pool.is_empty():
		push_error("Shop._roll_from_pool: empty pool")
		return null
	var weights: Array[int] = []
	for item in pool:
		var r: int = 0
		if "rarity" in item:
			r = item.rarity
		var base_w := 100 - r * 25
		var ante_bonus := r * ante
		weights.append(maxi(5, base_w + ante_bonus))
	var total := 0
	for w in weights: total += w
	var roll := rng.range_int(0, total)
	var acc := 0
	for i in pool.size():
		acc += weights[i]
		if roll < acc:
			return pool[i]
	return pool[-1]

# 价格纯函数（供 sell_value 与实例 _price_of 共用）
static func price_for(item: Resource, ante: int) -> int:
	var r: int = item.rarity if ("rarity" in item) else 0
	var base: int = ([3, 5, 8, 12] as Array[int])[clampi(r, 0, 3)]
	return base + ante / 2

# 卖出回收价 = 当前 ante 价的一半（下取整，至少 1）
static func sell_value(item: Resource, ante: int) -> int:
	return maxi(1, price_for(item, ante) / 2)

func _price_of(item: Resource, ante: int) -> int:
	return price_for(item, ante)
