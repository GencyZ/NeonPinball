extends Node

var triggers: Dictionary = {}
var gate_defs: Dictionary = {}
var peg_types: Dictionary = {}

func _ready() -> void:
    _register_defaults()

func _register_defaults() -> void:
    # --- Peg types ---
    var pn := PegType.new()
    pn.id = &"normal"; pn.behavior = PegType.Behavior.NORMAL
    pn.base_score = 5.0; pn.glow = Color(0.2, 0.9, 1.0, 1.0)
    peg_types[pn.id] = pn

    var pm := PegType.new()
    pm.id = &"mult"; pm.behavior = PegType.Behavior.MULT
    pm.base_score = 8.0; pm.mult_add = 0.5; pm.glow = Color(1.0, 0.5, 0.1, 1.0)
    peg_types[pm.id] = pm

    # --- Triggers ---
    var peg_bonus := TriggerDef.new()
    peg_bonus.id = &"peg_bonus"
    peg_bonus.listen_mask = 1
    peg_bonus.effect = TriggerDef.Effect.ADD_BASE
    peg_bonus.value = 3.0
    triggers[peg_bonus.id] = peg_bonus

    var bmult := TriggerDef.new()
    bmult.id = &"bounce_mult"
    bmult.listen_mask = 2
    bmult.effect = TriggerDef.Effect.ADD_MULT
    bmult.value = 0.2
    triggers[bmult.id] = bmult

    var big_hit := TriggerDef.new()
    big_hit.id = &"big_hit"
    big_hit.listen_mask = 4
    big_hit.effect = TriggerDef.Effect.MUL_MULT
    big_hit.value = 1.5
    big_hit.condition = TriggerDef.Condition.PEGS_HIT_GTE
    big_hit.condition_threshold = 5
    triggers[big_hit.id] = big_hit

    # --- Gates ---
    var gn := GateDef.new()
    gn.id = &"normal"; gn.kind = GateDef.Kind.NORMAL
    gate_defs[gn.id] = gn

    var ga := GateDef.new()
    ga.id = &"accel"; ga.kind = GateDef.Kind.ACCEL; ga.speed_mul = 1.5
    gate_defs[ga.id] = ga

    var gsa := GateDef.new()
    gsa.id = &"scatter_angle"; gsa.kind = GateDef.Kind.SCATTER_ANGLE; gsa.scatter_angle = 0.3
    gate_defs[gsa.id] = gsa

    var gss := GateDef.new()
    gss.id = &"scatter_split"; gss.kind = GateDef.Kind.SCATTER_SPLIT
    gss.split_count = 3; gss.scatter_angle = 0.4
    gate_defs[gss.id] = gss
