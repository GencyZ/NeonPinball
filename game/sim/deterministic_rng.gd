class_name DeterministicRng

var _s0: int
var _s1: int

func _init(seed_val: int) -> void:
    _s0 = _splitmix64(seed_val)
    _s1 = _splitmix64(_s0)

func next_int() -> int:
    var s0 := _s0; var s1 := _s1
    var result := (s0 + s1) & 0x7FFFFFFFFFFFFFFF
    s1 ^= s0
    _s0 = (_rotl(s0, 24) ^ s1 ^ (s1 << 16)) & 0x7FFFFFFFFFFFFFFF
    _s1 = _rotl(s1, 37) & 0x7FFFFFFFFFFFFFFF
    return result

func next_float() -> float:
    return float(next_int() & 0xFFFFFF) / float(0x1000000)

func range_float(lo: float, hi: float) -> float:
    return lo + next_float() * (hi - lo)

func range_int(lo: int, hi: int) -> int:
    assert(hi > lo, "range_int: hi must be greater than lo")
    return lo + (next_int() % (hi - lo))

static func derive(master: int, tag: int) -> DeterministicRng:
    return DeterministicRng.new(master ^ _splitmix64(tag))

static func _splitmix64(x: int) -> int:
    # Split 64-bit constants into two 32-bit halves to avoid GDScript signed-int64 literal overflow.
    # (0xBF58476D << 32) | 0x1CE4E5B9 == 0xBF58476D1CE4E5B9
    # (0x94D049BB << 32) | 0x133111EB == 0x94D049BB133111EB
    var k1: int = (0xBF58476D << 32) | 0x1CE4E5B9
    var k2: int = (0x94D049BB << 32) | 0x133111EB
    x = ((x ^ (x >> 30)) * k1) & 0x7FFFFFFFFFFFFFFF
    x = ((x ^ (x >> 27)) * k2) & 0x7FFFFFFFFFFFFFFF
    return x ^ (x >> 31)

static func _rotl(x: int, k: int) -> int:
    return ((x << k) | (x >> (64 - k))) & 0x7FFFFFFFFFFFFFFF
