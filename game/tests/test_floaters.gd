extends GutTest
const FloatersScript := preload("res://juice/floaters.gd")

func test_add_appends() -> void:
	var f := FloatersScript.new()
	f.add(Vector2(5, 5), "+100", 0.9)
	assert_eq(f.items.size(), 1)
	assert_eq(String(f.items[0][&"text"]), "+100")
	assert_almost_eq(float(f.items[0][&"ttl"]), 0.9, 0.0001)
	assert_almost_eq(float(f.items[0][&"max_ttl"]), 0.9, 0.0001)

func test_update_rises_and_decays() -> void:
	var f := FloatersScript.new()
	f.add(Vector2(0, 100), "+1", 0.9)
	var y0: float = f.items[0][&"pos"].y
	var t0: float = f.items[0][&"ttl"]
	f.update(0.1)
	assert_lt(float(f.items[0][&"pos"].y), y0)
	assert_lt(float(f.items[0][&"ttl"]), t0)

func test_alpha_full_at_spawn() -> void:
	var f := FloatersScript.new()
	f.add(Vector2.ZERO, "+1", 0.9)
	assert_almost_eq(f.alpha_of(f.items[0]), 1.0, 0.0001)

func test_alpha_low_near_death() -> void:
	var f := FloatersScript.new()
	f.add(Vector2.ZERO, "+1", 0.9)
	f.update(0.85)
	assert_lt(f.alpha_of(f.items[0]), 0.1)

func test_expired_removed() -> void:
	var f := FloatersScript.new()
	f.add(Vector2.ZERO, "+1", 0.9)
	f.update(2.0)
	assert_eq(f.items.size(), 0)
