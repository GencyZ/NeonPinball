# 更多钉子类型 Implementation Plan

**Goal:** 实现 8 种钉子类型：CHAIN、BOMB（原计划）+ FREEZE、JACKPOT、LIFE、POISON、PORTAL、MAGNET（新增）。

**架构总览：**
- `peg_type.gd` 扩展枚举
- `game_database.gd` 注册全部 8 种类型
- `board_view.gd` 三处修改：`_build_honeycomb()` 布局分配、`_draw()` 颜色、命中处理管线
- 部分类型需要 peg dict 里的可变状态字段（`frozen`、`poisoned`）
- PORTAL 通过命中时修改 `_active_balls[i].pos/vel` + 截断 `_events` 实现球传送

**测试命令：**
```
D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
```
**当前基线：156 个测试全部通过。不要 push。**

---

## 类型一览

| 类型 | 颜色 | one_shot | 效果 | 占比 |
|------|------|----------|------|------|
| CHAIN | 蓝紫 | ✗ | 命中→周围 60px 内普通钉同时计分 | ~5% |
| BOMB | 红色 | ✓ | 命中→周围 80px 内所有钉计分并消失 | ~3% |
| FREEZE | 浅蓝 | ✗ | 命中→周围 60px 钉冻结；冻结钉被打到得分×3 | ~4% |
| JACKPOT | 金色 | ✓ | 命中→随机加 1~10 倍数到本轮得分 | ~2% |
| LIFE | 绿色 | ✓ | 命中→发球次数+1 | ~2% |
| POISON | 紫绿 | ✓ | 命中→周围 60px 普通钉变毒（被打到扣分） | ~3% |
| PORTAL | 青白 | ✗ | 两个一对，球打到其中一个→瞬移到另一个 | ~2% |
| MAGNET | 蓝白 | ✗ | 命中→周围 50px 所有未打到的钉直接计分（不消失） | ~4% |

---

## Task 1：扩展枚举 + 注册 GameDB

- [ ] **修改** `data/peg_type.gd`，扩展枚举：

  ```gdscript
  enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB, FREEZE, JACKPOT, LIFE, POISON, PORTAL, MAGNET }
  ```

- [ ] **修改** `data/game_database.gd` 的 `_register_defaults()`，在 mult peg 之后追加：

  ```gdscript
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
  ```

- [ ] **新建** `tests/test_peg_types.gd`：

  ```gdscript
  extends GutTest

  func test_all_new_types_registered() -> void:
      for id in [&"chain", &"bomb", &"freeze", &"jackpot", &"life", &"poison", &"portal", &"magnet"]:
          assert_true(GameDB.peg_types.has(id), "%s 已注册" % id)

  func test_bomb_is_one_shot() -> void:
      assert_true((GameDB.peg_types[&"bomb"] as PegType).one_shot)

  func test_jackpot_is_one_shot() -> void:
      assert_true((GameDB.peg_types[&"jackpot"] as PegType).one_shot)

  func test_life_is_one_shot() -> void:
      assert_true((GameDB.peg_types[&"life"] as PegType).one_shot)

  func test_chain_not_one_shot() -> void:
      assert_false((GameDB.peg_types[&"chain"] as PegType).one_shot)

  func test_portal_not_one_shot() -> void:
      assert_false((GameDB.peg_types[&"portal"] as PegType).one_shot)
  ```

- [x] **运行测试**，预期 156 → 162（+6）
- [x] **提交：**
  ```
  git -C D:/NeonPinball/game add data/peg_type.gd data/game_database.gd tests/test_peg_types.gd
  git -C D:/NeonPinball/game commit -m "feat: register 8 new peg types in GameDB"
  ```

---

## Task 2：棋盘布局 + 颜色统一

- [ ] **修改** `view/board_view.gd` 的 `_build_honeycomb()`：

  将现有：
  ```gdscript
  var peg_type: PegType = GameDB.peg_types[&"mult"] if (r * 7 + c) % 7 == 3 else GameDB.peg_types[&"normal"]
  list.append({&"id": id, &"pos": Vector2(x, y),
              &"radius": sizes[tier], &"base_score": scores[tier],
              &"type": peg_type})
  ```

  替换为：
  ```gdscript
  var peg_type: PegType
  if   (r * 7  + c) % 7  == 3: peg_type = GameDB.peg_types[&"mult"]
  elif (r * 11 + c) % 19 == 7: peg_type = GameDB.peg_types[&"chain"]
  elif (r * 13 + c) % 31 == 5: peg_type = GameDB.peg_types[&"bomb"]
  elif (r * 9  + c) % 23 == 4: peg_type = GameDB.peg_types[&"freeze"]
  elif (r * 17 + c) % 47 == 9: peg_type = GameDB.peg_types[&"jackpot"]
  elif (r * 19 + c) % 53 == 11: peg_type = GameDB.peg_types[&"life"]
  elif (r * 23 + c) % 37 == 6: peg_type = GameDB.peg_types[&"poison"]
  elif (r * 29 + c) % 41 == 3: peg_type = GameDB.peg_types[&"magnet"]
  else: peg_type = GameDB.peg_types[&"normal"]
  list.append({&"id": id, &"pos": Vector2(x, y),
              &"radius": sizes[tier], &"base_score": scores[tier],
              &"type": peg_type, &"frozen": false, &"poisoned": false})
  ```

  > PORTAL 单独处理：生成完列表后，遍历找出所有 portal peg，两两配对记录 `portal_pair_id`（见下）：
  ```gdscript
  # 在 return list 之前追加 portal 分配逻辑
  var portal_indices: Array = []
  for i in list.size():
      if list[i][&"type"] != null and list[i][&"type"].behavior == PegType.Behavior.PORTAL:
          portal_indices.append(i)
  # 两两配对（奇数个时最后一个退化为 normal）
  var pi := 0
  while pi + 1 < portal_indices.size():
      list[portal_indices[pi]][&"portal_pair"] = portal_indices[pi + 1]
      list[portal_indices[pi + 1]][&"portal_pair"] = portal_indices[pi]
      pi += 2
  if pi < portal_indices.size():
      list[portal_indices[pi]][&"type"] = GameDB.peg_types[&"normal"]
  ```

  但目前布局用质数取模，portal 数量可能为 0。改用固定索引插入：在列表生成完成后，手动将第 5 和第 45 号钉设为 portal 并配对（若 list.size() > 45）：
  ```gdscript
  if list.size() > 45:
      list[5][&"type"] = GameDB.peg_types[&"portal"]
      list[5][&"portal_pair"] = 45
      list[45][&"type"] = GameDB.peg_types[&"portal"]
      list[45][&"portal_pair"] = 5
  ```

- [ ] **修改 `_draw()` 颜色逻辑**，统一用 `pt.glow`，并对 frozen/poisoned 叠加色：

  找到：
  ```gdscript
  if pt != null and pt.behavior == PegType.Behavior.MULT:
      col = Color(1.0, 0.55, 0.0)
  ```
  替换为：
  ```gdscript
  if pt != null:
      col = pt.glow
  # 冻结叠加浅蓝色
  if peg.get(&"frozen", false):
      col = col.lerp(Color(0.6, 0.9, 1.0), 0.6)
  # 中毒叠加紫绿色
  if peg.get(&"poisoned", false):
      col = col.lerp(Color(0.3, 0.8, 0.2), 0.5)
  ```

- [x] **运行测试**，预期 162 个全通过
- [x] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: layout 8 peg types in honeycomb; glow-color unified"
  ```

---

## Task 3：实现命中行为

在 `view/board_view.gd` 的命中处理段（`if e[&"type"] == SimEvent.PEG_HIT:` 块内），在计算 flash_color 之后，**先提取** `_score_peg` 辅助方法，然后按 behavior 分派。

### 3.1 提取 `_score_peg` 辅助方法

```gdscript
func _score_peg(peg: Dictionary) -> void:
    var pt: PegType = peg.get(&"type")
    var multiplier := 3.0 if peg.get(&"frozen", false) else 1.0
    var neg := -1.0 if peg.get(&"poisoned", false) else 1.0
    var base: float = peg.get(&"base_score", 5.0) * multiplier * neg
    _score_ctx.pegs_hit += 1
    _score_ctx.add(ScoreContext.KIND_ADD_BASE, base, &"peg")
    peg[&"frozen"] = false
    peg[&"poisoned"] = false
    _flashes.append({&"pos": peg[&"pos"], &"ttl": 0.15, &"max_ttl": 0.15,
                     &"color": pt.glow if pt != null else Color.WHITE})
```

### 3.2 修改命中处理块

在 `if e[&"type"] == SimEvent.PEG_HIT:` 内，将现有 MULT 处理替换/扩展为按 behavior 分派：

```gdscript
if hit_peg_id >= 0 and hit_peg_id < _pegs.size():
    _peg_anims[hit_peg_id] = PEG_ANIM_DUR
    var hit_peg: Dictionary = _pegs[hit_peg_id]
    var hit_type: PegType = hit_peg.get(&"type")
    var behavior := hit_type.behavior if hit_type != null else PegType.Behavior.NORMAL

    match behavior:
        PegType.Behavior.NORMAL:
            _score_peg(hit_peg)

        PegType.Behavior.MULT:
            _score_ctx.pegs_hit += 1
            _score_ctx.add(ScoreContext.KIND_ADD_MULT, hit_type.mult_add, &"mult_peg")

        PegType.Behavior.CHAIN:
            _score_peg(hit_peg)
            _trigger_chain(hit_peg)

        PegType.Behavior.BOMB:
            _trigger_bomb(hit_peg, hit_peg_id)

        PegType.Behavior.FREEZE:
            _score_peg(hit_peg)
            _trigger_freeze(hit_peg)

        PegType.Behavior.JACKPOT:
            _score_peg(hit_peg)
            var jackpot_mult := randf_range(1.0, 10.0)
            _score_ctx.add(ScoreContext.KIND_ADD_MULT, jackpot_mult, &"jackpot")
            _flashes.append({&"pos": hit_peg[&"pos"], &"ttl": 0.4, &"max_ttl": 0.4,
                             &"color": Color(1.0, 0.9, 0.0)})

        PegType.Behavior.LIFE:
            RunMan.state[&"launches_left"] += 1
            _sync_hud()
            _score_peg(hit_peg)
            if hit_type.one_shot:
                _pegs.erase(hit_peg)
                _sim = _make_sim(_pegs)

        PegType.Behavior.POISON:
            _score_peg(hit_peg)
            _trigger_poison(hit_peg)
            if hit_type.one_shot:
                _pegs.erase(hit_peg)
                _sim = _make_sim(_pegs)

        PegType.Behavior.PORTAL:
            _trigger_portal(hit_peg, hit_peg_id, i)   # i = ball index in _active_balls

        PegType.Behavior.MAGNET:
            _score_peg(hit_peg)
            _trigger_magnet(hit_peg)

    # one_shot 通用处理（LIFE/POISON/BOMB/JACKPOT 内部已单独处理）
    if hit_type != null and hit_type.one_shot \
       and behavior not in [PegType.Behavior.LIFE, PegType.Behavior.POISON, PegType.Behavior.BOMB]:
        _pegs.erase(hit_peg)
        _sim = _make_sim(_pegs)
```

### 3.3 各辅助方法

```gdscript
const CHAIN_RADIUS  := 60.0
const BOMB_RADIUS   := 80.0
const FREEZE_RADIUS := 60.0
const POISON_RADIUS := 60.0
const MAGNET_RADIUS := 50.0

func _trigger_chain(chain_peg: Dictionary) -> void:
    for peg in _pegs:
        if peg[&"id"] == chain_peg[&"id"] or peg.get(&"hit", false):
            continue
        if (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"]) <= CHAIN_RADIUS:
            _score_peg(peg)

func _trigger_bomb(bomb_peg: Dictionary, bomb_id: int) -> void:
    var to_remove: Array = []
    for peg in _pegs:
        if (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"]) <= BOMB_RADIUS:
            _score_peg(peg)
            to_remove.append(peg)
    for peg in to_remove:
        _pegs.erase(peg)
    _sim = _make_sim(_pegs)
    _juice.on_peg_hit(bomb_peg[&"pos"], Color(1.0, 0.4, 0.1), true)

func _trigger_freeze(freeze_peg: Dictionary) -> void:
    for peg in _pegs:
        if peg[&"id"] == freeze_peg[&"id"]:
            continue
        if (peg[&"pos"] as Vector2).distance_to(freeze_peg[&"pos"]) <= FREEZE_RADIUS:
            peg[&"frozen"] = true

func _trigger_poison(poison_peg: Dictionary) -> void:
    for peg in _pegs:
        if peg[&"id"] == poison_peg[&"id"]:
            continue
        var pt: PegType = peg.get(&"type")
        if pt != null and pt.behavior != PegType.Behavior.NORMAL:
            continue
        if (peg[&"pos"] as Vector2).distance_to(poison_peg[&"pos"]) <= POISON_RADIUS:
            peg[&"poisoned"] = true

func _trigger_magnet(magnet_peg: Dictionary) -> void:
    for peg in _pegs:
        if peg[&"id"] == magnet_peg[&"id"] or peg.get(&"hit", false):
            continue
        if (peg[&"pos"] as Vector2).distance_to(magnet_peg[&"pos"]) <= MAGNET_RADIUS:
            _score_peg(peg)

func _trigger_portal(portal_peg: Dictionary, _portal_id: int, ball_idx: int) -> void:
    var pair_idx: int = portal_peg.get(&"portal_pair", -1)
    if pair_idx < 0 or pair_idx >= _pegs.size():
        _score_peg(portal_peg)   # 无配对，退化为普通计分
        return
    var partner: Dictionary = _pegs[pair_idx]
    # 瞬移当前发射球到 partner 位置，保留速度方向
    if ball_idx >= 0 and ball_idx < _active_balls.size():
        _active_balls[ball_idx].pos = partner[&"pos"] + Vector2(0, -20)
        # 截断后续已计算的事件（它们基于旧位置），避免幽灵命中
        _events.resize(_event_cursor + 1)
    _flashes.append({&"pos": portal_peg[&"pos"], &"ttl": 0.3, &"max_ttl": 0.3,
                     &"color": Color(0.7, 1.0, 1.0)})
    _flashes.append({&"pos": partner[&"pos"], &"ttl": 0.3, &"max_ttl": 0.3,
                     &"color": Color(0.7, 1.0, 1.0)})
```

- [x] **注意**：Portal 用 hit_pos 找最近活球，避免依赖 ball index。
- [x] **运行测试**，预期 162 个全通过
- [x] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: implement CHAIN/BOMB/FREEZE/JACKPOT/LIFE/POISON/PORTAL/MAGNET behaviors"
  ```

---

## 自检清单

- [x] 162 个测试全部通过（156 基线 +6 新增）
- [x] 棋盘出现 8 种颜色的钉子
- [x] CHAIN（蓝紫）：命中时周围钉同时闪光计分
- [x] BOMB（红）：命中时周围爆炸，钉消失
- [x] FREEZE（浅蓝）：命中后周围钉变浅蓝，下次被打得分×3
- [x] JACKPOT（金）：命中时随机大倍数，one-shot
- [x] LIFE（绿）：命中后发球数+1，one-shot
- [x] POISON（紫绿）：命中后周围普通钉变毒色，被打扣分
- [x] PORTAL（青白）：球命中后瞬移到配对 portal 位置
- [x] MAGNET（蓝白）：命中后周围未打钉直接计分（不消失）
- [x] MULT（橙）行为不变
- [x] 无物理/计分回归
