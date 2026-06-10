# run/shop.gd
class_name Shop
extends Object

const SLOT_COUNT := 4
const BASE_REROLL_COST := 1
const REROLL_STEP := 1

var offerings: Array = []   # Array of {&"item": Resource, &"price": int, &"sold": bool}

func roll(master_seed: int, ante: int, node_cursor: int, reroll_count: int) -> void:
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
    if use_gate:
        return _roll_from_pool(GameDB.gate_defs.values(), ante, rng)
    return _roll_from_pool(GameDB.triggers.values(), ante, rng)

func _roll_from_pool(pool: Array, ante: int, rng: DeterministicRng) -> Resource:
    if pool.is_empty():
        return GameDB.triggers.values()[0]
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

func _price_of(item: Resource, ante: int) -> int:
    var r: int = 0
    if "rarity" in item:
        r = item.rarity
    var base: int = ([3, 5, 8, 12] as Array[int])[clampi(r, 0, 3)]
    return base + ante / 2
