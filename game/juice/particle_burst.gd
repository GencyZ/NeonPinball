class_name ParticleBurst extends RefCounted

var particles: Array = []

func emit(pos: Vector2, color: Color, count: int = 8) -> void:
	for i in count:
		var angle := randf_range(0.0, TAU)
		var speed := randf_range(80.0, 220.0)
		particles.append({
			&"pos": pos,
			&"vel": Vector2(cos(angle), sin(angle)) * speed,
			&"ttl": 0.35,
			&"max_ttl": 0.35,
			&"color": color,
		})

func update(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p[&"pos"] = (p[&"pos"] as Vector2) + (p[&"vel"] as Vector2) * delta
		p[&"vel"] = (p[&"vel"] as Vector2) + Vector2(0.0, 600.0) * delta
		p[&"ttl"] -= delta
		if p[&"ttl"] <= 0.0:
			particles.remove_at(i)
