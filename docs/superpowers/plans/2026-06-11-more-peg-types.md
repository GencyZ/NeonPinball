# 更多钉子类型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增两种钉子类型：**CHAIN**（链式触发周围钉）和 **BOMB**（范围爆炸得分），让棋盘产生更多变化和策略性。

**Architecture:**
- `PegType.Behavior` 已有 CHAIN、BOMB 枚举值，只需实现行为逻辑
- **CHAIN**：球命中 CHAIN 钉后，自动触发其 R 范围内所有未命中普通钉的计分（视觉上这些钉也闪光），递归深度限 1
- **BOMB**：球命中 BOMB 钉后，R 范围内所有钉都计分并清除出棋盘（one_shot），伴随大爆炸粒子特效
- 行为逻辑写在 `view/board_view.gd` 的命中处理管线里，`GameDB` 注册两种新 PegType
- 棋盘布局：蜂巢网格中按固定规律插入 CHAIN（蓝紫色）和 BOMB（红色）钉，比例约 5% / 3%

**Tech Stack:** Godot 4.6.3 GDScript, GUT。

---

## Background（代码库上下文）

- 项目根目录：`D:/NeonPinball/game/`，Godot 4.6.3 纯 GDScript。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**150 个测试**全部通过。
- 每个任务只提交它自己改动的文件。**不要 push。**

### PegType 已定义枚举

```gdscript
# data/peg_type.gd
enum Behavior { NORMAL, MULT, CHAIN, SPAWN, BOMB }
@export var one_shot: bool = false   # ← BOMB 钉用到
```

### 棋盘生成（board_view.gd）

```gdscript
# _build_honeycomb() 生成钉子列表，每个钉为 Dictionary：
# { id, pos, radius, type: PegType }
# MULT 钉判断：(r*7+c) % 7 == 3  → ~14% 为 mult

# _on_peg_hit(peg_id) 命中处理：
# - 更新 ScoringEngine（计分）
# - 记录 _flashes（闪光特效）
# - 触发 JuiceController
```

### 命中处理关键路径

```gdscript
func _on_peg_hit(peg_id: StringName) -> void:
    var peg := _peg_by_id(peg_id)
    # ... ScoringEngine 计分、flash 特效 ...
    if peg[&"type"] != null and peg[&"type"].one_shot:
        _pegs.erase(...)   # 移除 one_shot 钉
```

（以上为伪代码，实际实现时需读当前代码确认字段名和逻辑。）

---

## Task 1：注册 CHAIN 和 BOMB PegType 到 GameDB

- [ ] **修改** `data/game_database.gd` 的 `_register_defaults()`，在 mult peg 之后追加：

  ```gdscript
  var pc := PegType.new()
  pc.id = &"chain"; pc.behavior = PegType.Behavior.CHAIN
  pc.base_score = 6.0; pc.glow = Color(0.5, 0.3, 1.0, 1.0)   # 蓝紫色
  peg_types[pc.id] = pc

  var pb := PegType.new()
  pb.id = &"bomb"; pb.behavior = PegType.Behavior.BOMB
  pb.base_score = 20.0; pb.one_shot = true; pb.glow = Color(1.0, 0.2, 0.1, 1.0)  # 红色
  peg_types[pb.id] = pb
  ```

- [ ] **新建测试** `tests/test_peg_types.gd`（TAB 缩进）：

  ```gdscript
  extends GutTest

  func test_chain_peg_registered() -> void:
      assert_true(GameDB.peg_types.has(&"chain"), "chain 钉已注册")
      var pt: PegType = GameDB.peg_types[&"chain"]
      assert_eq(pt.behavior, PegType.Behavior.CHAIN)
      assert_false(pt.one_shot, "chain 钉不是 one_shot")

  func test_bomb_peg_registered() -> void:
      assert_true(GameDB.peg_types.has(&"bomb"), "bomb 钉已注册")
      var pt: PegType = GameDB.peg_types[&"bomb"]
      assert_eq(pt.behavior, PegType.Behavior.BOMB)
      assert_true(pt.one_shot, "bomb 钉是 one_shot")

  func test_bomb_base_score_higher_than_normal() -> void:
      var bomb_score: float = (GameDB.peg_types[&"bomb"] as PegType).base_score
      var normal_score: float = (GameDB.peg_types[&"normal"] as PegType).base_score
      assert_gt(bomb_score, normal_score, "bomb 基础分高于 normal")
  ```

- [ ] **运行测试**，预期 150 → 153（+3 个）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add data/game_database.gd tests/test_peg_types.gd
  git -C D:/NeonPinball/game commit -m "feat: register CHAIN and BOMB peg types in GameDB"
  ```

---

## Task 2：棋盘布局插入新钉子

- [ ] **修改** `view/board_view.gd` 的 `_build_honeycomb()`：在 MULT 判断之后追加 CHAIN 和 BOMB 的分配规则。

  **现有 MULT 分配（约 14%）：**
  ```gdscript
  if (r * 7 + c) % 7 == 3:
      peg_type = GameDB.peg_types.get(&"mult")
  ```

  **追加（在 MULT 判断之后）：**
  ```gdscript
  elif (r * 11 + c) % 19 == 7:
      peg_type = GameDB.peg_types.get(&"chain")   # ~5%
  elif (r * 13 + c) % 31 == 5:
      peg_type = GameDB.peg_types.get(&"bomb")    # ~3%
  ```

  > `elif` 确保一个钉只属于一种类型，优先级 MULT > CHAIN > BOMB。
  > 若 GameDB 中该类型未注册（被 UnlockManager 过滤），`get()` 返回 null，钉子退化为普通 NORMAL 钉（board_view 的 null 判断已有处理）。

- [ ] **修改 `_draw()` 的颜色逻辑**，按 behavior 选色：

  **改前：**
  ```gdscript
  var col := Color(0.2, 0.9, 1.0)   # 默认青色
  if pt != null and pt.behavior == PegType.Behavior.MULT:
      col = Color(1.0, 0.55, 0.0)
  ```

  **改后：**
  ```gdscript
  var col := Color(0.2, 0.9, 1.0)
  if pt != null:
      col = pt.glow   # 直接用 PegType 的 glow 颜色，统一管理
  ```

  > 这样 NORMAL=青色、MULT=橙色、CHAIN=蓝紫、BOMB=红色，后续新增类型只改 GameDB，不改 draw。

- [ ] **运行测试**，预期 153 个测试全部通过（棋盘布局改动无新纯逻辑测试，既有物理测试覆盖回归）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: add CHAIN and BOMB pegs to honeycomb layout; use glow color"
  ```

---

## Task 3：实现 CHAIN 和 BOMB 命中行为

- [ ] **修改** `view/board_view.gd` 的命中处理逻辑（`_on_peg_hit` 或等效位置）。实现时先阅读当前代码确认实际函数名和字段。

  **CHAIN 行为：** 命中 CHAIN 钉后，找到其 `CHAIN_RADIUS`（建议 60px）内所有未命中普通钉，对每个触发一次得分（不递归）：

  ```gdscript
  const CHAIN_RADIUS := 60.0

  func _trigger_chain(chain_peg: Dictionary) -> void:
      for peg in _pegs:
          if peg[&"id"] == chain_peg[&"id"]:
              continue
          if peg.get(&"hit", false):
              continue
          var dist: float = (peg[&"pos"] as Vector2).distance_to(chain_peg[&"pos"])
          if dist <= CHAIN_RADIUS:
              _score_peg(peg)               # 计分（不触发物理命中）
              _flashes.append({ &"pos": peg[&"pos"], &"ttl": 0.25, &"max_ttl": 0.25,
                                 &"color": Color(0.5, 0.3, 1.0) })  # 蓝紫闪光
  ```

  **BOMB 行为：** 命中 BOMB 钉后，`BOMB_RADIUS`（建议 80px）内所有钉计分并标记为 one_shot 移除：

  ```gdscript
  const BOMB_RADIUS := 80.0

  func _trigger_bomb(bomb_peg: Dictionary) -> void:
      var to_remove: Array = []
      for peg in _pegs:
          var dist: float = (peg[&"pos"] as Vector2).distance_to(bomb_peg[&"pos"])
          if dist <= BOMB_RADIUS:
              _score_peg(peg)
              to_remove.append(peg)
              _flashes.append({ &"pos": peg[&"pos"], &"ttl": 0.4, &"max_ttl": 0.4,
                                 &"color": Color(1.0, 0.4, 0.1) })  # 橙红闪光
      for peg in to_remove:
          _pegs.erase(peg)
      _sim = _make_sim(_pegs)   # 重建物理模拟（钉已减少）
      _juice.on_peg_hit(true)   # big hit juice
  ```

  在 `_on_peg_hit` 里，按 behavior 分派：

  ```gdscript
  # 在正常计分之后追加：
  if pt != null:
      if pt.behavior == PegType.Behavior.CHAIN:
          _trigger_chain(peg)
      elif pt.behavior == PegType.Behavior.BOMB:
          _trigger_bomb(peg)
  ```

  > `_score_peg(peg)` 是需要提取的辅助方法，包含 ScoringEngine 更新 + flash 记录。实施时若无此方法，先将现有计分逻辑重构为该方法再调用。

- [ ] **运行测试**，预期 153 个测试全部通过（行为逻辑由手动游戏验证，headless 物理测试覆盖回归）：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```

- [ ] **手动验证：**
  - CHAIN 钉（蓝紫）被击中时，周围钉同时闪蓝紫光并计分
  - BOMB 钉（红色）被击中时，周围区域大爆炸，钉子消失
  - CHAIN/BOMB 的 glow 颜色正确显示

- [ ] **提交：**
  ```
  git -C D:/NeonPinball/game add view/board_view.gd
  git -C D:/NeonPinball/game commit -m "feat: CHAIN peg chain-triggers neighbors; BOMB peg clears area"
  ```

---

## 文件结构

**新建：**
- `tests/test_peg_types.gd` — 3 个 GameDB 注册测试

**修改：**
- `data/game_database.gd` — 注册 chain、bomb PegType
- `view/board_view.gd` — 布局插入新钉；颜色用 glow 统一；实现 CHAIN/BOMB 行为

---

## 自检清单

- [ ] 153 个测试全部通过（150 基线 + 3 新增）
- [ ] 棋盘出现蓝紫色 CHAIN 钉和红色 BOMB 钉
- [ ] CHAIN 钉命中时周围钉蓝紫闪光并计分
- [ ] BOMB 钉命中时周围红色爆炸，钉消失，物理模拟正确更新
- [ ] MULT 钉（橙色）行为不变
- [ ] 无物理/计分回归

---

## 已知局限 / 留待后续

- CHAIN 不递归（链式 CHAIN 不触发第二层 CHAIN），避免无限循环；后续可加递归深度参数
- BOMB 重建 `_sim` 开销较大；若频繁爆炸可优化为增量更新
- SPAWN 枚举值（生成新球）留待后续实现
- 钉子比例（CHAIN ~5%，BOMB ~3%）为初始值，建议游戏测试后调整
