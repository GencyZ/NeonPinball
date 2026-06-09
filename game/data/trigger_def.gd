class_name TriggerDef extends Resource

enum Effect { ADD_BASE, ADD_MULT, MUL_MULT }
enum Condition { NONE, BOUNCE_GTE, PEGS_HIT_GTE }

@export var id: StringName
@export_flags("PegHit:1", "Bounce:2", "Settled:4", "Launch:8") var listen_mask: int = 1
@export var effect: Effect = Effect.ADD_BASE
@export var value: float = 1.0
@export var condition: Condition = Condition.NONE
@export var condition_threshold: int = 0
@export var rarity: int = 1
