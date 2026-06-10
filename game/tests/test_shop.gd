# tests/test_shop.gd
extends GutTest

const ShopScript := preload("res://run/shop.gd")
var _shop: Object

func before_each() -> void:
    _shop = ShopScript.new()

func after_each() -> void:
    _shop.free()

func test_roll_fills_4_slots() -> void:
    _shop.roll(12345, 1, 0, 0)
    assert_eq(_shop.offerings.size(), 4)

func test_offerings_have_required_keys() -> void:
    _shop.roll(12345, 1, 0, 0)
    for offer in _shop.offerings:
        assert_true(offer.has(&"item"),  "missing item key")
        assert_true(offer.has(&"price"), "missing price key")
        assert_true(offer.has(&"sold"),  "missing sold key")
        assert_false(offer[&"sold"],     "should start unsold")

func test_buy_deducts_money() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    var price: int = _shop.offerings[0][&"price"]
    var ok: bool = _shop.buy(0, inv, money)
    assert_true(ok, "buy should succeed with enough money")
    assert_eq(money[0], 100 - price)

func test_buy_marks_sold() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    _shop.buy(0, inv, money)
    assert_true(_shop.offerings[0][&"sold"], "slot should be marked sold")

func test_buy_insufficient_money_fails() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [0]
    var inv := {&"items": []}
    var ok: bool = _shop.buy(0, inv, money)
    assert_false(ok, "buy should fail with no money")

func test_buy_cannot_repurchase() -> void:
    _shop.roll(12345, 1, 0, 0)
    var money := [100]
    var inv := {&"items": []}
    _shop.buy(0, inv, money)
    var money2 := [100]
    var inv2 := {&"items": []}
    var ok: bool = _shop.buy(0, inv2, money2)
    assert_false(ok, "sold slot cannot be bought again")

func test_reroll_refreshes_offerings() -> void:
    _shop.roll(12345, 1, 0, 0)
    var first_items := []
    for o in _shop.offerings: first_items.append(o[&"item"])
    _shop.roll(12345, 1, 0, 1)   # reroll_count = 1
    var any_different := false
    for i in 4:
        if _shop.offerings[i][&"item"] != first_items[i]:
            any_different = true
            break
    assert_true(any_different, "reroll should generate at least one different item")

func test_reroll_cost_increases() -> void:
    assert_eq(ShopScript.reroll_cost(0), 1)
    assert_eq(ShopScript.reroll_cost(1), 2)
    assert_eq(ShopScript.reroll_cost(2), 3)

func test_deterministic_same_seed() -> void:
    var shop_a: Object = ShopScript.new()
    var shop_b: Object = ShopScript.new()
    shop_a.roll(99, 2, 0, 0)
    shop_b.roll(99, 2, 0, 0)
    for i in 4:
        assert_eq(shop_a.offerings[i][&"price"], shop_b.offerings[i][&"price"])
        assert_eq(shop_a.offerings[i][&"item"],  shop_b.offerings[i][&"item"])
    shop_a.free(); shop_b.free()
