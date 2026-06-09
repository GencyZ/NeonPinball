class_name SimEvent

const LAUNCH   := &"launch"
const PEG_HIT  := &"peg_hit"
const BOUNCE   := &"bounce"
const WALL_HIT := &"wall_hit"
const SETTLED  := &"ball_settled"

static func peg_hit(id: int, p: Vector2) -> Dictionary:
	return {&"type": PEG_HIT, &"peg_id": id, &"pos": p}

static func bounce(p: Vector2) -> Dictionary:
	return {&"type": BOUNCE, &"peg_id": -1, &"pos": p}

static func wall_hit(p: Vector2) -> Dictionary:
	return {&"type": WALL_HIT, &"peg_id": -1, &"pos": p}

static func settled(p: Vector2) -> Dictionary:
	return {&"type": SETTLED, &"peg_id": -1, &"pos": p}

static func launch(p: Vector2) -> Dictionary:
	return {&"type": LAUNCH, &"peg_id": -1, &"pos": p}
