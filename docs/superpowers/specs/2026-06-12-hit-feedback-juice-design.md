# 局内击中反馈爽感（Hit-Feedback Juice）设计文档

**日期：** 2026-06-12
**主题：** 让"每一下撞钉"都爽——以 Peggle 式音高爬升为核心的击中反馈系统

---

## 目标

补上 NeonPinball 局内最大的爽感空缺：**击中反馈**。当前游戏完全没有音效，分数只在落定那一刻静默弹一个 "+N"，撞击过程缺少节节攀升、逐击变脆的快感。本期通过 **程序化合成撞钉音 + 音高随连击爬升 + 逐击微顿帧 + 连击 escalation** 把"每一下都脆、一长串越撞越上头"做出来。

## 设计原则

- **对确定性物理 sim 零侵入**：爽感系统全部活在 view 层，只对 sim 产生的事件做"播放表现"。sim 照常算，188 个现有 GUT 测试保持全绿。
- **零音频素材**：撞钉音用 Godot 程序化合成（`AudioStreamWAV` + `pitch_scale`），不依赖任何 `.ogg/.wav` 文件，契合"霓虹合成器"美术调性，也不阻塞美术资源进度。
- **本期纯表现**：combo 只驱动手感（音/震/光/顿帧/屏上数字），**不进计分管线**。让 combo 影响分数属于后期"连锁/结算爽"，记入 Backlog。
- **映射逻辑可测**：音频实际播放 headless 测不了，但所有"connect值→参数"的映射都是纯函数，全部 TDD 单测。

---

## 现状（代码库上下文）

- 引擎 Godot 4.6.3 纯 GDScript；项目根 `D:/NeonPinball/game/`。
- 测试命令：
  ```
  D:/Program/Godot/godot.exe --headless --path D:/NeonPinball/game -s addons/gut/gut_cmdln.gd -gdir=res://tests/ -gprefix=test_ -gexit
  ```
- 当前基线：**188 个测试全部通过，30 个脚本**。
- **全局无音频**：除 GUT 插件外，无任何 `AudioStreamPlayer` / 音频文件 / 音频代码。

### 现有 juice 系统（`juice/`）

- `juice_controller.gd`：聚合 `screen_shake / particle_burst / floaters / slow_mo`
  - `on_peg_hit(pos, color, big)` → 屏震（0.12/0.3）+ 粒子（6/14）
  - `on_settle(pos, score, is_final_launch)` → 飘字 "+N" + 屏震 0.2 + 仅最后一球慢动作
  - `update(delta)` → 输出 `camera_offset()` 与 `time_scale()`
- `slow_mo.gd`：`request(scale, duration)`，`update(delta) -> time_scale`。当前只在最后一球用。
- 已有测试 `tests/test_juice_controller.gd` 可作模板。

### 击中事件接线点（`view/board_view.gd`）

- 在事件处理循环里处理 `SimEvent.PEG_HIT`（约 380–410 行附近），当前调用 `_juice.on_peg_hit(...)` 并生成彩虹光环 + 命中闪光。
- `launch()` 开新球；`_on_all_settled()` 落定结算。
- `_juice.update(delta)` 每帧更新；`Engine.time_scale = _juice.time_scale()` 已是现有机制。

---

## 系统组成

### 1. `juice/sfx_synth.gd`（新建，纯逻辑 + 波形生成）

**职责：** 程序化生成一个短"叮"声波形，并提供 connect→音高的纯函数映射。

- `static func make_ping(sample_rate := 22050) -> AudioStreamWAV`
  生成一个短促 blip：三角/正弦载波 + 快速指数衰减包络（约 120–160ms，霓虹合成器味）。返回 16-bit PCM 的 `AudioStreamWAV`。
- `static func pitch_scale_for_combo(n: int) -> float`
  **核心爬升映射。** 音高档位走五声音阶（pentatonic），半音 degrees 取 `[0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]`，`pitch_scale = 2^(semitone/12)`。
  - `n` = 本次发射内的连击序号（从 0 起）。
  - `n` 超过表长后**封顶**在最高档（最高约 2 个八度，pitch_scale ≈ 4.0），避免尖到刺耳。
  - 保证单调不降、落在 `[1.0, 4.0]` 区间。
- 纯函数，可完整单测；波形生成产出非空 buffer 也可断言。

### 2. `juice/sfx_controller.gd`（新建，`extends Node`）

**职责：** 持有 `AudioStreamPlayer` 池，按档位播放合成音。必须在场景树内（`AudioStreamPlayer` 要求入树），由 `board_view` 作为子节点创建。

- `_ready()`：用 `SfxSynth.make_ping()` 生成一次波形；创建 N 个（如 8 个）`AudioStreamPlayer` 子节点轮询使用（避免同帧多击互相打断）。
- `func play_hit(combo: int) -> void`：取下一个空闲 player，设 `pitch_scale = SfxSynth.pitch_scale_for_combo(combo)`，`play()`。
- `func play_settle() -> void`：播一个低音"咚"（同波形、低 `pitch_scale`，或更长包络）。
- `func play_special(peg_kind: StringName) -> void`：**本期留接口/最小实现**（普通钉走 `play_hit`，落定走 `play_settle`）；炸弹轰、jackpot 叮咚等专属音入 Backlog。

### 3. `juice/slow_mo.gd` / `juice_controller.gd`（改动，加逐击微顿帧）

**职责：** 加入区别于"最后一球慢动作"的**逐击 hit-stop**。

- 在 `JuiceController` 加 `on_peg_hit_combo(pos, color, combo, big)`（或扩展现有 `on_peg_hit`）：
  - 请求一个**短促强冻结**：`Engine.time_scale` 压到 ~0.05，持续 `hitstop_duration_for_combo(combo)`（普通 ~25ms，随 combo/特殊钉升到封顶 ~90ms）后恢复。
  - 复用 `slow_mo` 机制，新增"punch"式短请求；与最后一球的长慢动作叠加时取**更强（更慢）**者，互不打架。
- `static func hitstop_duration_for_combo(n: int) -> float`：纯函数，单调不降，`[0.025, 0.090]` 秒。
- `static func shake_mag_for_combo(n: int) -> float`：纯函数，连击越高屏震越强，封顶防止过度。

### 4. `view/board_view.gd`（改动，接线）

- 新增 view 层状态 `_combo: int`（**纯表现，不入 `ScoreContext`**）。
- 创建 `SfxController` 子节点（在 `_ready`）。
- `launch()`：`_combo = 0`。
- PEG_HIT 处理处：
  1. `_combo += 1`
  2. `_sfx.play_hit(_combo)`
  3. `_juice.on_peg_hit_combo(pos, color, _combo, big)`（按 combo 放大屏震/顿帧）
  4. 光环 `r1` / 亮度按 `_combo` 放大
  5. 刷新屏上 combo 数字（"x{_combo}"，跳动放大）
- `_on_all_settled()`：`_sfx.play_settle()`，`_combo = 0`，combo 数字淡出。
- combo 数字绘制：复用现有 `_draw()`（如 `draw_string` 或 floater 风格），位置可在落点附近或固定 HUD 角。

---

## 数据流

```
sim 产生 PEG_HIT 事件（确定性，不变）
        │
        ▼
board_view 事件处理：_combo += 1
        │
        ├─→ SfxController.play_hit(_combo)  ──→ pitch_scale_for_combo(_combo) ──→ AudioStreamPlayer
        ├─→ JuiceController：屏震/顿帧 = f(_combo)  ──→ Engine.time_scale / camera_offset
        ├─→ 光环/闪光大小亮度 = f(_combo)
        └─→ 屏上 combo 数字刷新
        │
        ▼
落定 _on_all_settled：play_settle()，_combo = 0
```

音频与顿帧**只读**事件，不回写 sim，不影响计分。

---

## 测试策略

新增约 8–10 个测试（纯函数 + 波形），对 sim 零侵入，188 基线保持全绿。

`tests/test_sfx_synth.gd`：
- `pitch_scale_for_combo(0) == 1.0`（基准音不变调）
- 单调不降：`pitch_scale_for_combo(n+1) >= pitch_scale_for_combo(n)`
- 范围：所有档位落在 `[1.0, 4.0]`
- 五声比例：低档位值匹配 `2^(degree/12)`（如 degree=2 → ≈1.1225）
- 封顶：大 `n`（如 50）等于最高档，不越界
- `make_ping()` 返回非空 `AudioStreamWAV`，`data` 长度 > 0 且符合采样率×时长预期

`tests/test_hit_feedback_curves.gd`（或并入 `test_juice_controller.gd`）：
- `hitstop_duration_for_combo`：单调不降、落在 `[0.025, 0.090]`
- `shake_mag_for_combo`：单调不降、封顶不超上限
- combo 重置语义：发射/落定后 combo 归零（若放进可测的小状态对象）

---

## 验收标准

- [ ] 撞钉有声，且音高随本次发射连击逐级上行（"叮↗叮↗叮↗"），下次发射重置
- [ ] 音阶走五声、任意长度连击都不刺耳；爬到顶封顶不尖叫
- [ ] 每次撞击有微顿帧，连击越高/特殊钉越久，密集撞击不至于一直卡顿
- [ ] 连击时屏震、光环、音高、顿帧、屏上数字同步放大
- [ ] 落定有低音"咚"，combo 归零
- [ ] 零音频素材文件；纯函数映射全部单测通过；188+ 全绿
- [ ] 无回归：物理、计分、商店、关卡流程正常

---

## 后期备用项（Backlog）

本期**不做**，按用户意愿记录，后期可能加：

**B 视觉/触觉补充**
- peg pop（命中时缩放挤压回弹）
- 球拖尾（速度越快拖尾越长）

**结算累积的爽（Balatro 式 tally）**
- 落定时 base→+mult→×mult 逐段动画：base 数字滚动累加 → +mult 飞入 → ×mult 重锤砸下
- 数字 count-up + 音高/屏震随累加 crescendo，最后一记大乘法落地"thunk"

**连锁爆屏的爽**
- 一击引发连锁反应（炸弹/chain 钉串烧），钉子接连炸开、整屏沸腾

**构筑 combo 的爽**
- 攒一套触发器/钉子组合，某一发突然打出离谱天文数字的 payoff 顿悟感

**机制联动**
- combo 影响分数（连接"连锁/结算爽"）
- 特殊钉专属音效：炸弹轰、jackpot 叮咚、freeze 冰裂、life 升调等

---

## 已知局限 / 留待后续

- 程序化合成的"叮"声音色有限，后期若要更精致音色可换采样素材（接口不变，替换 `make_ping` 即可）。
- 逐击 hit-stop 通过 `Engine.time_scale` 实现，密集撞击的体感需实机调参（duration/阈值在纯函数里集中、易调）。
- combo 仅 view 层状态，不持久化、不影响存档与确定性回放。
