class_name GateDef extends Resource

enum Kind { NORMAL, ACCEL, SCATTER_ANGLE, SCATTER_SPLIT }

@export var id: StringName
@export var kind: Kind = Kind.NORMAL
@export var speed_mul: float = 1.5
@export var scatter_angle: float = 0.3
@export var split_count: int = 3
@export var rarity: int = 0
