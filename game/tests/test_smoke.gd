extends GutTest

func test_gut_works() -> void:
    assert_eq(1 + 1, 2, "GUT is working")

func test_vector2_built_in() -> void:
    var v := Vector2(1, 0).rotated(PI / 2)
    assert_almost_eq(v.x, 0.0, 1e-4, "rotated x")
    assert_almost_eq(v.y, 1.0, 1e-4, "rotated y")
