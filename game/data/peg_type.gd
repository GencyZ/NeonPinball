class_name PegType extends Resource

enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB, FREEZE, JACKPOT, LIFE, POISON, PORTAL, MAGNET }

@export var id: StringName
@export var behavior: Behavior = Behavior.NORMAL
@export var base_score: float = 5.0
@export var mult_add: float = 0.0
@export var one_shot: bool = false
@export var glow: Color = Color(0.2, 0.9, 1.0, 1.0)
