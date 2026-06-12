extends Node

var triggers: Dictionary = {}
var gate_defs: Dictionary = {}
var peg_types: Dictionary = {}

const SaveSystemScript    := preload("res://run/save_system.gd")
const UnlockManagerScript := preload("res://run/unlock_manager.gd")

# Content definitions live as .tres resources so designers can edit values in
# the Godot Inspector without touching code. Adding a new def = create the
# .tres and add one preload line below.
const PEG_RES: Array[PegType] = [
    preload("res://data/resources/pegs/peg_normal.tres"),
    preload("res://data/resources/pegs/peg_mult.tres"),
    preload("res://data/resources/pegs/peg_chain.tres"),
    preload("res://data/resources/pegs/peg_bomb.tres"),
    preload("res://data/resources/pegs/peg_freeze.tres"),
    preload("res://data/resources/pegs/peg_jackpot.tres"),
    preload("res://data/resources/pegs/peg_life.tres"),
    preload("res://data/resources/pegs/peg_poison.tres"),
    preload("res://data/resources/pegs/peg_portal.tres"),
    preload("res://data/resources/pegs/peg_magnet.tres"),
]
const TRIGGER_RES: Array[TriggerDef] = [
    preload("res://data/resources/triggers/trigger_peg_bonus.tres"),
    preload("res://data/resources/triggers/trigger_bounce_mult.tres"),
    preload("res://data/resources/triggers/trigger_big_hit.tres"),
    preload("res://data/resources/triggers/trigger_chain_bonus.tres"),
    preload("res://data/resources/triggers/trigger_double_mult.tres"),
]
const GATE_RES: Array[GateDef] = [
    preload("res://data/resources/gates/gate_normal.tres"),
    preload("res://data/resources/gates/gate_accel.tres"),
    preload("res://data/resources/gates/gate_scatter_angle.tres"),
    preload("res://data/resources/gates/gate_scatter_split.tres"),
]

func _ready() -> void:
    _register_defaults()
    _apply_unlocks()

func _apply_unlocks() -> void:
    var saved := SaveSystemScript.load_data()
    UnlockManagerScript.apply_unlocks(self, int(saved.get(&"runs_completed", 0)))

func _register_defaults() -> void:
    for p in PEG_RES:
        peg_types[p.id] = p
    for t in TRIGGER_RES:
        triggers[t.id] = t
    for g in GATE_RES:
        gate_defs[g.id] = g
