extends GutTest

func _make_pegs() -> Array:
	return [
		{&"id": 0, &"pos": Vector2(10, 10), &"radius": 5.0, &"base_score": 1.0},
		{&"id": 1, &"pos": Vector2(500, 500), &"radius": 5.0, &"base_score": 1.0},
	]

func test_query_returns_near_not_far() -> void:
	var grid := PegGrid.new()
	grid.build(_make_pegs(), Rect2(0, 0, 600, 600), 50.0)
	var near := grid.query_near(Vector2(12, 12), 20.0)
	assert_true(0 in near, "peg 0 should be near (12,12)")
	assert_false(1 in near, "peg 1 at (500,500) should be far")

func test_query_sorted_ascending() -> void:
	var pegs := [
		{&"id": 0, &"pos": Vector2(25, 25), &"radius": 5.0, &"base_score": 1.0},
		{&"id": 1, &"pos": Vector2(30, 25), &"radius": 5.0, &"base_score": 1.0},
		{&"id": 2, &"pos": Vector2(35, 25), &"radius": 5.0, &"base_score": 1.0},
	]
	var grid := PegGrid.new()
	grid.build(pegs, Rect2(0, 0, 200, 200), 50.0)
	var near := grid.query_near(Vector2(30, 25), 30.0)
	assert_eq(near.size(), 3, "all three pegs in range")
	assert_eq(near[0], 0, "sorted: id 0 first")
	assert_eq(near[1], 1, "sorted: id 1 second")
	assert_eq(near[2], 2, "sorted: id 2 third")

func test_query_empty_when_no_pegs_nearby() -> void:
	var grid := PegGrid.new()
	grid.build(_make_pegs(), Rect2(0, 0, 600, 600), 50.0)
	var near := grid.query_near(Vector2(300, 300), 10.0)
	assert_eq(near.size(), 0, "no pegs near center")
