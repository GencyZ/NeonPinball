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

    var pc := PegType.new()
    pc.id = &"chain"; pc.behavior = PegType.Behavior.CHAIN
    pc.base_score = 6.0; pc.glow = Color(0.5, 0.3, 1.0, 1.0)
    peg_types[pc.id] = pc

    var pb := PegType.new()
    pb.id = &"bomb"; pb.behavior = PegType.Behavior.BOMB
    pb.base_score = 20.0; pb.one_shot = true; pb.glow = Color(1.0, 0.2, 0.1, 1.0)
    peg_types[pb.id] = pb

    var pf := PegType.new()
    pf.id = &"freeze"; pf.behavior = PegType.Behavior.FREEZE
    pf.base_score = 5.0; pf.glow = Color(0.5, 0.85, 1.0, 1.0)
    peg_types[pf.id] = pf

    var pj := PegType.new()
    pj.id = &"jackpot"; pj.behavior = PegType.Behavior.JACKPOT
    pj.base_score = 10.0; pj.one_shot = true; pj.glow = Color(1.0, 0.85, 0.0, 1.0)
    peg_types[pj.id] = pj

    var pl := PegType.new()
    pl.id = &"life"; pl.behavior = PegType.Behavior.LIFE
    pl.base_score = 0.0; pl.one_shot = true; pl.glow = Color(0.2, 1.0, 0.3, 1.0)
    peg_types[pl.id] = pl

    var pp := PegType.new()
    pp.id = &"poison"; pp.behavior = PegType.Behavior.POISON
    pp.base_score = 5.0; pp.one_shot = true; pp.glow = Color(0.4, 0.9, 0.3, 1.0)
    peg_types[pp.id] = pp

    var po := PegType.new()
    po.id = &"portal"; po.behavior = PegType.Behavior.PORTAL
    po.base_score = 0.0; po.glow = Color(0.7, 1.0, 1.0, 1.0)
    peg_types[po.id] = po

    var pmg := PegType.new()
    pmg.id = &"magnet"; pmg.behavior = PegType.Behavior.MAGNET
    pmg.base_score = 5.0; pmg.glow = Color(0.5, 0.7, 1.0, 1.0)
    peg_types[pmg.id] = pmg

    # --- Triggers ---
    var peg_bonus := TriggerDef.new()
    peg_bonus.id = &"peg_bonus"
    peg_bonus.listen_mask = 1
    peg_bonus.effect = TriggerDef.Effect.ADD_BASE
    peg_bonus.value = 3.0
    peg_bonus.rarity = 0    # common
    triggers[peg_bonus.id] = peg_bonus

    var bmult := TriggerDef.new()
    bmult.id = &"bounce_mult"
    bmult.listen_mask = 2
    bmult.effect = TriggerDef.Effect.ADD_MULT
    bmult.value = 0.2
    bmult.rarity = 0        # common
    triggers[bmult.id] = bmult

    var big_hit := TriggerDef.new()
    big_hit.id = &"big_hit"
    big_hit.listen_mask = 4
    big_hit.effect = TriggerDef.Effect.MUL_MULT
    big_hit.value = 1.5
    big_hit.condition = TriggerDef.Condition.PEGS_HIT_GTE
    big_hit.condition_threshold = 5
    big_hit.rarity = 1      # uncommon
    triggers[big_hit.id] = big_hit

    # Extra triggers for shop pool
    var chain_bonus := TriggerDef.new()
    chain_bonus.id = &"chain_bonus"
    chain_bonus.listen_mask = 4         # SETTLED
    chain_bonus.effect = TriggerDef.Effect.ADD_BASE
    chain_bonus.value = 10.0
    chain_bonus.condition = TriggerDef.Condition.PEGS_HIT_GTE
    chain_bonus.condition_threshold = 3
    chain_bonus.rarity = 1
    triggers[chain_bonus.id] = chain_bonus

    var double_mult := TriggerDef.new()
    double_mult.id = &"double_mult"
    double_mult.listen_mask = 4         # SETTLED
    double_mult.effect = TriggerDef.Effect.MUL_MULT
    double_mult.value = 2.0
    double_mult.condition = TriggerDef.Condition.BOUNCE_GTE
    double_mult.condition_threshold = 10
    double_mult.rarity = 2
    triggers[double_mult.id] = double_mult

    # --- Gates ---
    var gn := GateDef.new()
    gn.id = &"normal"; gn.kind = GateDef.Kind.NORMAL
    gn.rarity = 0
    gate_defs[gn.id] = gn

    var ga := GateDef.new()
    ga.id = &"accel"; ga.kind = GateDef.Kind.ACCEL; ga.speed_mul = 1.5
    ga.rarity = 0
    gate_defs[ga.id] = ga

    var gsa := GateDef.new()
    gsa.id = &"scatter_angle"; gsa.kind = GateDef.Kind.SCATTER_ANGLE; gsa.scatter_angle = 0.3
    gsa.rarity = 1
    gate_defs[gsa.id] = gsa

    var gss := GateDef.new()
    gss.id = &"scatter_split"; gss.kind = GateDef.Kind.SCATTER_SPLIT
    gss.split_count = 3; gss.scatter_angle = 0.4
    gss.rarity = 1
    gate_defs[gss.id] = gss
