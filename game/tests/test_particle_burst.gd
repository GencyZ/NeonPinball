extends GutTest
const ParticleBurstScript := preload("res://juice/particle_burst.gd")

func test_emit_adds_count() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2(10, 10), Color.RED, 8)
	assert_eq(pb.particles.size(), 8)

func test_emit_zero_adds_none() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2.ZERO, Color.RED, 0)
	assert_eq(pb.particles.size(), 0)

func test_emitted_have_positive_ttl() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2.ZERO, Color.RED, 5)
	for p in pb.particles:
		assert_gt(float(p[&"ttl"]), 0.0)

func test_update_decrements_ttl() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2.ZERO, Color.RED, 1)
	var t0: float = pb.particles[0][&"ttl"]
	pb.update(0.1)
	assert_lt(float(pb.particles[0][&"ttl"]), t0)

func test_update_moves_pos() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2.ZERO, Color.RED, 1)
	var before: Vector2 = pb.particles[0][&"pos"]
	pb.update(0.1)
	assert_ne(pb.particles[0][&"pos"], before)

func test_dead_removed() -> void:
	var pb := ParticleBurstScript.new()
	pb.emit(Vector2.ZERO, Color.RED, 3)
	pb.update(10.0)
	assert_eq(pb.particles.size(), 0)
