class_name TriggerRuntime

var _def: TriggerDef

func _init(def: TriggerDef) -> void:
    _def = def

func on_event(event: Dictionary, ctx: ScoreContext) -> void:
    if not _listens_to(event[&"type"]):
        return
    if not _condition_met(ctx):
        return
    match _def.effect:
        TriggerDef.Effect.ADD_BASE:
            ctx.add(ScoreContext.KIND_ADD_BASE, _def.value, _def.id)
        TriggerDef.Effect.ADD_MULT:
            ctx.add(ScoreContext.KIND_ADD_MULT, _def.value, _def.id)
        TriggerDef.Effect.MUL_MULT:
            ctx.add(ScoreContext.KIND_MUL_MULT, _def.value, _def.id)

func _listens_to(event_type: StringName) -> bool:
    var flag: int = 0
    if   event_type == SimEvent.PEG_HIT: flag = 1
    elif event_type == SimEvent.BOUNCE:  flag = 2
    elif event_type == SimEvent.SETTLED: flag = 4
    elif event_type == SimEvent.LAUNCH:  flag = 8
    return (_def.listen_mask & flag) != 0

func _condition_met(ctx: ScoreContext) -> bool:
    match _def.condition:
        TriggerDef.Condition.NONE:         return true
        TriggerDef.Condition.BOUNCE_GTE:   return ctx.bounce_count >= _def.condition_threshold
        TriggerDef.Condition.PEGS_HIT_GTE: return ctx.pegs_hit >= _def.condition_threshold
        _:                                 return true
