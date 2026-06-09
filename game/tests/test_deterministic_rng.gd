extends GutTest

func test_next_float_in_range() -> void:
    var rng := DeterministicRng.new(1)
    for _i in 100:
        var f := rng.next_float()
        assert_true(f >= 0.0 and f < 1.0, "float in [0,1)")

func test_same_seed_same_sequence() -> void:
    var a := DeterministicRng.new(42)
    var b := DeterministicRng.new(42)
    for _i in 20:
        assert_eq(a.next_int(), b.next_int(), "same seed → same sequence")

func test_different_seeds_different_sequences() -> void:
    var a := DeterministicRng.new(1)
    var b := DeterministicRng.new(2)
    var same := true
    for _i in 10:
        if a.next_int() != b.next_int():
            same = false; break
    assert_false(same, "different seeds must diverge")

func test_range_int_bounds() -> void:
    var rng := DeterministicRng.new(7)
    for _i in 200:
        var v := rng.range_int(3, 8)
        assert_true(v >= 3 and v < 8, "range_int in [3,8)")

func test_range_float_bounds() -> void:
    var rng := DeterministicRng.new(13)
    for _i in 100:
        var v := rng.range_float(-1.0, 1.0)
        assert_true(v >= -1.0 and v < 1.0, "range_float in [-1,1)")

func test_derive_gives_independent_stream() -> void:
    var a := DeterministicRng.derive(100, 0)
    var b := DeterministicRng.derive(100, 1)
    var same := true
    for _i in 10:
        if a.next_int() != b.next_int():
            same = false; break
    assert_false(same, "different tags must diverge")

func test_range_int_different_range() -> void:
    var rng := DeterministicRng.new(99)
    for _i in 100:
        var v := rng.range_int(10, 20)
        assert_true(v >= 10 and v < 20, "range_int(10,20) in bounds")
