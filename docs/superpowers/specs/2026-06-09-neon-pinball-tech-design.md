# 技术设计文档：霓虹弹珠 × Roguelike 构筑（Godot 4 + C#）

- **日期**：2026-06-09
- **配套游戏设计文档**：`2026-06-09-neon-pinball-roguelike-deckbuilder-design.md`
- **技术栈**：Godot 4.x（.NET/Mono 版）+ C#（.NET 8）+ Rider + Git
- **本文目标**：把游戏设计落成可实现的技术架构——确定性物理、数据驱动、事件化计分管线、入口/门系统，以及项目结构与测试策略。

---

## 1. 顶层架构原则

四条贯穿全局的原则：

1. **模拟 / 渲染分离（Sim/View Separation）**：游戏逻辑（弹球物理、计分）跑在**定步长**的纯 C# 模拟层，与 Godot 渲染/节点解耦。渲染层只「读取模拟状态 + 插值 + 播 juice」，**永不反向影响逻辑**。这是确定性、回放、预测线、单元测试的共同地基。
2. **确定性优先（Determinism First）**：相同 `seed + 输入序列` ⇒ 相同结果。不使用 Godot 内置 `RigidBody2D`（跨平台/跨帧不确定），改用自写定步长弹球物理。
3. **数据驱动（Data-Driven）**：钉子/球种/触发器/门/棋盘模板全部是 Godot `Resource(.tres)`，策划在 Inspector 里编辑，加内容/调平衡**不改代码**。
4. **事件化计分（Event-Driven Scoring）**：物理模拟产出**事件流**（命中、弹跳、落袋…），计分与触发器是这条事件流的**订阅者管线**，可组合、可测试。

---

## 2. 为什么 Godot 4 + C#（及注意点）

- ✅ 开源免费、2D 工具链成熟、个人开发轻量、导出 Steam/移动方便。
- ✅ C# 强类型 + Rider 重构/调试体验好，适合写复杂的计分/触发器系统。
- ⚠️ **不用内置物理做核心弹球**：Godot 物理（GodotPhysics/Jolt）非定步长确定性，无法满足回放/每日种子 → 自写简化物理（见 §4）。物理简单（少量球 vs 静态钉），自写完全可控且不难。
- ⚠️ **C# 热路径 GC**：模拟步进每帧多次，避免在步进里 `new`（用 `struct` + 对象池，见 §13）。
- ⚠️ **Godot C# 热重载弱**：逻辑层尽量纯 C#（少依赖 Node），便于在 Rider 里跑 headless 测试、绕开编辑器重启。

---

## 3. 项目结构

```
/project.godot
/NeonPinball.sln                 # Rider 打开这个
/src/
  /Sim/                          # 纯 C# 模拟层（不引用 Godot 渲染节点）
    BallSimulation.cs            # 定步长弹球物理 + 事件产出
    Ball.cs (struct)             # 球状态：pos, vel, flags, bounceCount...
    PegGrid.cs                   # 静态钉碰撞查询（空间网格）
    SimEvent.cs (struct/enum)    # 命中/弹跳/落袋/进门 等事件
    DeterministicRng.cs          # 种子化 PRNG（xorshift/PCG）
  /Scoring/
    ScoringEngine.cs             # base/mult 累加 + 触发器管线
    TriggerRuntime.cs            # 运行时触发器实例（订阅事件）
    ScoreContext.cs              # 一发球的计分上下文
  /Launch/
    LaunchController.cs          # 入口位置(三边滑选) + 瞄准 + 微操(nudge)
    GateRuntime.cs               # 门对进场球的变换 + 串联
    TrajectoryPredictor.cs       # 用 BallSimulation 做无渲染前瞻 → 预测线
  /Run/
    RunManager.cs                # 跑局状态机：区/轮/quota/胜负
    Economy.cs                   # 金钱/利息
    Shop.cs                      # 商店生成/购买/刷新/移除
    BoardBuilder.cs              # 模板 + 程序化填充生成棋盘
  /Meta/
    SaveSystem.cs                # 存档（解锁/设置/统计）
    UnlockManager.cs
    DailySeed.cs
  /Data/                         # 数据定义（Resource 子类）
    PegType.cs  OrbType.cs  TriggerDef.cs  GateDef.cs  BoardTemplate.cs
/data/                           # 实际 .tres 资源（策划编辑）
  /pegs/  /orbs/  /triggers/  /gates/  /boards/
/scenes/                         # Godot 场景（View 层）
  Board.tscn  BallView.tscn  Hud.tscn  Shop.tscn  ...
/view/                           # View 脚本：读取 Sim 状态 + juice
  BoardView.cs  BallView.cs  JuiceController.cs
/tests/                          # headless 单元/回放测试
  SimDeterminismTests.cs  ScoringTests.cs  ReplayTests.cs
/assets/                         # 美术/音频
```

命名空间：`NeonPinball.Sim` / `.Scoring` / `.Launch` / `.Run` / `.Meta` / `.Data` / `.View`。

---

## 4. 确定性弹球物理（核心）

自写**定步长**圆形球 vs 静态碰撞体的模拟。

### 4.1 步进模型
- 固定 `dt`（如 1/120s），逻辑与渲染帧解耦。每个渲染帧把累积时间切成若干固定步。
- 球：圆形，状态 `Ball { Vector2 Pos, Vel; int BounceCount; flags }`。用 `struct`。
- 钉/墙：静态圆 + 线段（边界、通道壁）。
- 碰撞：圆-圆、圆-线段解析解；反射 = `v' = v - 2(v·n)n * restitution`。
- **空间网格**（`PegGrid`）做宽相位，避免 O(n²)。

### 4.2 确定性要点
- 全程用 `float`（单平台一致即可，PC 优先）；如需跨平台严格一致，可上**定点数/`fixed`**，但 MVP 用 `float` + 单平台。
- **禁用** `Time`、`GetProcessDeltaTime`、`Math.random` 进入逻辑；所有随机走 `DeterministicRng`。
- 碰撞处理顺序固定（按网格遍历 + 稳定排序），不依赖哈希/引用地址。

### 4.3 事件产出
模拟步进**只产出事件**，不直接计分：
```csharp
public enum SimEventType { Launch, EnterGate, EnterField, PegHit, Bounce, PegDestroyed, ChainTrigger, BallSettled }
public struct SimEvent { public SimEventType Type; public int PegId; public Vector2 Pos; public int BallId; /*…*/ }
```
`BallSimulation.Step()` 把事件追加到 `List<SimEvent>`（预分配，避免每步 new），上层消费。

---

## 5. 随机与种子策略

- **每局一个 master seed**（手动局可用时间派生；每日局用 `DailySeed`）。
- 由 master seed **派生独立子流**：棋盘生成流 / 商店流 / 散射门流 / 事件流……（用 `Splitmix64` 派生，避免相关性）。
- `DeterministicRng`：自写 xorshift128+/PCG，**不要用** Godot `RandomNumberGenerator` 的全局态。
- 散射门、随机事件、商店掉落都从各自子流取数 → **回放/每日种子可复现**。

---

## 6. 数据驱动定义（Godot Resource）

每类内容一个 `Resource` 子类，策划在 Inspector 编辑、存为 `.tres`：

```csharp
[GlobalClass] public partial class PegType : Resource {
    [Export] public string Id;
    [Export] public PegBehavior Behavior;   // Normal/Mult/Chain/Spawn/Bomb...
    [Export] public float BaseScore;
    [Export] public float MultAdd;
    [Export] public bool OneShot;            // 一次性高价值钉
    [Export] public Color Glow;
}
[GlobalClass] public partial class OrbType : Resource { /* split count, bounciness, pierce, homing… */ }
[GlobalClass] public partial class GateDef  : Resource { /* GateKind, speedMul, scatterAngle, splitCount… */ }
[GlobalClass] public partial class TriggerDef : Resource {
    [Export] public string Id;
    [Export] public TriggerEventMask Listen;  // 监听哪些事件
    [Export] public TriggerEffect Effect;      // +base/+mult/×mult/spawn…
    [Export] public float Value;
    [Export] public TriggerCondition Condition; // 条件（如 bounce>=10）
    [Export] public int Rarity;
}
[GlobalClass] public partial class BoardTemplate : Resource { /* 布局原型 + 钉位锚点 + 难度填充规则 */ }
```

数值/行为复杂的触发器用「数据 + 少量预置行为枚举」覆盖 80%，长尾特例再用代码策略类（避免做成全脚本系统）。

---

## 7. 计分与触发器管线（系统的心脏）

### 7.1 数据流
```
BallSimulation → SimEvent 流 → ScoringEngine → 遍历已装备 TriggerRuntime（按固定顺序）
   → 每个触发器对匹配事件改写 ScoreContext(base/mult) → 一发球结束汇总 → RunManager 计入 quota
```

### 7.2 ScoreContext（一发球的累加器）
```csharp
public sealed class ScoreContext {
    public double BaseScore;   // Σ基础分
    public double Mult;        // 总倍率（初始 1）
    public double LaunchScore => BaseScore * Mult;
    // 供触发器读取的只读快照：bounceCount, pegsHitThisLaunch, gateUsed…
}
```

### 7.3 触发器求值顺序（决定结果，必须确定）
- 固定顺序：**先所有 `+base` → 再所有 `+mult` → 最后所有 `×mult`**（与 §设计 三层结构一致），同层内按装备槽位序。
- 这保证「加法先铺、乘法后乘、×倍率最后翻」的可预期结算，也利于 ka-ching 逐项动画。

### 7.4 与 juice 的关系
计分管线产出**结算步骤列表**（每步：来源、+base/×mult、当前值），View 层据此播放「逐项跳动 + 升调音效 + 屏震」。**juice 读结算列表，不参与计算**。

---

## 8. 入口通道与门系统（技术实现）

对应设计 §6.5。

### 8.1 入口位置（三边任意滑动）
- 棋盘三条边（顶/左/右）参数化为一条**边界路径**，入口点用 `0..1` 归一化参数 `t` 表示（`(edge, t)`）。
- `LaunchController` 持有当前 `(edge, t)` + 瞄准方向；玩家拖动滑选，免费、每发可换。
- 入场初速方向 = 该边法向 ± 瞄准偏转。

### 8.2 门对进场球的变换
门是「对球初始状态的变换函数」，装在入口通道末端：
```csharp
public interface IGateEffect { void Apply(ref Ball ball, GateContext ctx, DeterministicRng rng); }
// 普通：no-op；加速：ball.Vel *= speedMul；
// 变角散射：ball.Vel 旋转 rng.Range(-a,a)（种子化）；
// 分裂散射：spawn N 颗扇形球（ctx.SpawnBall）。
```
- `GateRuntime` 包装 `GateDef` → `IGateEffect`，在 `EnterGate` 事件时作用。

### 8.3 门串联（后期解锁）
- 通道是一个**有序门列表** `List<GateRuntime>`；球依次经过每扇门 `Apply`（普通→加速→散射 链式）。
- MVP 列表长度=1（单门槽）；解锁后允许多槽 → 直接扩列表，逻辑零改动。

### 8.4 预测线兼容
`TrajectoryPredictor` 复用 `BallSimulation` 做**无渲染前瞻**：以当前 `(edge,t)+门+瞄准` 跑 N 步，画轨迹。散射门因含随机 → **画扇形包络**（取角度区间两端 + 采样若干条），而非单线。

---

## 9. 跑局状态机（RunManager）

```
Boot → MainMenu → RunStart
  → [Ante 循环]:
      Round(小关) → Round(小关) → BossRound(词条)
      每 Round: 发射循环（launch×N）→ 判定 quota → 过/败
      Round 之间: Shop / Event / Treasure 节点
  → Ante++ (quota 指数增长) → … → RunWin / RunLose → MetaUpdate → MainMenu
```
- 用显式状态枚举 + 转移函数，避免散落的布尔标志。
- 全程可序列化（支持中途存档/退出续局，且利于回放）。

---

## 10. 渲染与 Juice 解耦（View 层）

- `BoardView`/`BallView` 每渲染帧**读取 Sim 当前状态**并在上一/当前模拟步间**插值**显示（消除定步长视觉卡顿）。
- `JuiceController` 订阅 `SimEvent` + 结算列表 → 触发：粒子、屏震、慢动作（仅视觉时间缩放，不改 sim dt）、连锁**升调**音效（pitch 随连锁长度递增）、ka-ching 逐项结算动画。
- 原则：**关掉所有 juice，游戏逻辑结果完全不变。**

---

## 11. 存档与序列化

- 存档内容：解锁项、设置、统计、（可选）当前局快照。
- 用 C# 结构 + JSON（`System.Text.Json`），存到 `user://`。
- **局快照**仅需 `master seed + 玩家输入序列 + 当前节点状态` → 可重建（也即天然回放）。

---

## 12. 测试策略（确定性带来的红利）

- **模拟单元测试**（headless，纯 C#，Rider 里跑）：圆-线/圆-圆碰撞、反射、空间网格正确性。
- **确定性回放测试**：固定 `seed + 输入` → 断言最终分数/事件序列逐位一致（防回归、防不小心引入非确定性）。
- **计分测试**：构造事件流 → 断言 base/mult/×mult 顺序与结果；覆盖各触发器与门。
- **平衡模拟**（离线工具）：批量跑 N 局中位 build，导出 quota 通过率曲线，辅助调数值（对应设计 §4 数值表）。

---

## 13. 性能与 C# 注意

- 模拟步进**零分配**：`Ball` 用 `struct`；事件 `List` 预分配并复用；避免 LINQ/闭包进热路径。
- 球/粒子用**对象池**。
- `[GlobalClass]` Resource 加载缓存复用。
- 大量发光/粒子走 shader 与 GPU 粒子（`GpuParticles2D`），别用 CPU 粒子堆。

---

## 14. Rider / Godot 工作流

- 用 Godot「.NET」版；首次在编辑器生成 `.sln`，Rider 打开 `.sln`。
- 调试：Rider 配 Godot 运行/调试配置，断点调 C#。
- 约定逻辑层不依赖 `Node`，可直接在 Rider 里跑 `/tests`（无需开编辑器）。
- 提交前跑回放测试，确保确定性未被破坏。

---

## 15. 技术里程碑（映射设计 §15）

| 设计里程碑 | 技术交付 |
|---|---|
| 1. 物理原型验手感(go/no-go) | `BallSimulation` + `BoardView` 插值 + 三边入口 + 瞄准/预测线 + 基础计分 |
| 2. 积木系统 + round loop | Resource 数据层 + 触发器管线 + 球种 + 钉子改造 + 门(单槽) + 一轮完整循环 |
| 3. run loop | `RunManager` 状态机 + `Shop`/`Economy` + Boss 词条 + 3 区 |
| 4. meta | `SaveSystem`/`UnlockManager` + 程序化棋盘扩充 + `DailySeed` |
| 5. 打磨/平衡 | `JuiceController` 全量 + 离线平衡模拟工具 + Steam Demo 构建 |
| 6. 上线 | EA→1.0；移动输入层（触控瞄准/微操）适配 |

---

## 16. 技术风险与缓解

| 风险 | 缓解 |
|---|---|
| 自写物理手感不达标 | 里程碑 1 即 go/no-go；优先打磨碰撞/弹性参数与预测线 |
| 非确定性悄悄混入 | 回放测试入 CI；逻辑层禁用引擎时间/全局随机 |
| C# 热路径 GC 卡顿 | struct + 对象池 + 零分配步进；Profiler 盯帧 |
| 触发器系统过度工程 | 数据+枚举覆盖 80%，长尾才写策略类，别一上来做全脚本 |
| Godot C# 移动导出坑 | PC 先行；移动移植作为独立阶段，预留竖屏 UI |

---

## 17. 待定（不阻塞里程碑 1）

- `float` vs 定点数：PC 单平台先用 `float`；若未来要跨平台严格一致回放再评估定点。
- 触发器特例是否需要轻量脚本（如 Expression/小 DSL）：内容铺开后再判断。
- 移动端输入手感方案：PC 1.0 后单独设计。

---

## 附录 A：确定性弹球物理实现细节

### A.1 定步长主循环（accumulator + 渲染插值）
逻辑恒定 120Hz 步进，与显示 fps 无关；渲染用余量插值。

```csharp
const double DT = 1.0 / 120.0;
double _acc; SimState _prev, _curr;

public override void _Process(double delta) {
    _acc += delta;
    while (_acc >= DT) { _prev = _curr; _curr = Sim.Step(_curr, DT); _acc -= DT; }
    View.Render(_prev, _curr, (float)(_acc / DT)); // 视觉插值
}
```

### A.2 积分（半隐式欧拉 + 限速）
```csharp
v += gravity * dt;            // 先更新速度
v = ClampSpeed(v, maxSpeed);  // 限速，防加速门数值爆炸/隧穿
// 位移按 TOI 推进（见 A.3），不是 pos += v*dt
```

### A.3 ⚠️ 隧穿与扫掠连续碰撞（CCD/TOI）——加速门头号坑
快球一步可能穿过钉子不触发。用**扫掠 TOI**：把每步运动看成线段，求与所有钉/墙的最早碰撞时间，推进→反射→用剩余时间继续，循环到 dt 用完。

```csharp
SimState Step(SimState s, double dt) {
    foreach (ref Ball b in s.Balls) {
        double remaining = dt; int guard = 0;
        while (remaining > EPS && guard++ < MAX_BOUNCES_PER_STEP) {
            var hit = SweepClosest(b, remaining);          // 宽相位+窄相位，最早 TOI
            if (!hit.Found) { b.Pos += b.Vel * (float)remaining; break; }
            b.Pos += b.Vel * (float)hit.Toi;
            Reflect(ref b, hit.Normal);
            Emit(SimEventType.Bounce, b, hit);
            if (hit.IsPeg) Emit(SimEventType.PegHit, b, hit);
            remaining -= hit.Toi;
        }
    }
    return s;
}
```
`MAX_BOUNCES_PER_STEP`（如 8）为夹缝无限反射的安全阀。

### A.4 碰撞数学
**圆 vs 圆（钉，扫掠 TOI）**：合半径 `R=ballR+pegR`，解一元二次取较早根。
```csharp
Vector2 m = p - c; float a = d.Dot(d), b = 2*m.Dot(d), cc = m.Dot(m) - R*R;
float disc = b*b - 4*a*cc; if (disc < 0) return NoHit;
float t = (-b - Mathf.Sqrt(disc)) / (2*a); if (t < 0 || t > remaining) return NoHit;
```
**圆 vs 线段（墙/通道壁）**：球心轨迹到线段最近距离何时 = ballR；端点用圆 vs 圆兜底。
**反射（弹性 + 切向）**：
```csharp
void Reflect(ref Ball b, Vector2 n) {
    float vn = b.Vel.Dot(n); Vector2 vN = vn*n, vT = b.Vel - vN;
    b.Vel = vT*tangentKeep - vN*restitution; b.BounceCount++;
}
```

### A.5 宽相位：空间网格
静态钉烘焙到均匀网格；扫掠只查球线段经过的格子。遍历顺序固定（格 index 升序、格内 pegId 升序）→ 多候选确定地取最小 TOI（TOI 相等按 pegId 决胜）。

### A.6 确定性检查清单
- 全程 float 单精度、单平台；逻辑不混 double 再截断。
- 随机只走 `DeterministicRng`（禁 `GD.Randf`/`Random`）。
- 逻辑禁用 `delta`/系统时间，只用固定 `DT`。
- 多碰撞求值顺序固定（TOI→pegId），不依赖 Dictionary/引用地址/哈希遍历序。
- 不用 `RigidBody2D`/`PhysicsServer`。
- 浮点比较带 `EPS`，避免边界抖动分叉。

### A.7 手感旋钮（里程碑 1 主调）
| 参数 | 作用 |
|---|---|
| `gravity` | 下落节奏 |
| `restitution` | 弹性（弹床钉可 >1 配限速） |
| `tangentKeep` | 擦边顺滑/黏滞感 |
| `maxSpeed` | 限速，防爆炸/隧穿 |
| `ball/peg radius` | 命中宽容度 |
| `MAX_BOUNCES_PER_STEP` | 夹缝安全阀 |

调参流程：关 juice + 开调试可视化（TOI 命中点/法线/网格），反复手射找手感。**不达标不往下做。**

### A.8 预测线 = 同一套 Sim 跑前瞻
```csharp
List<Vector2> Predict(SimState s, LaunchParams lp, int steps) {
    var clone = s.CloneForPredict();           // 不产 juice、不改真实态
    ApplyEntryAndGate(ref clone, lp, _predRng);// 入口+门一并算入
    var pts = new List<Vector2>();
    for (int i=0;i<steps;i++){ clone=Sim.Step(clone,DT); pts.Add(clone.MainBall.Pos);} 
    return pts;
}
```
- 完全确定 → 预测线 100% 等于真实弹道。
- 散射门含随机 → 画**扇形包络**（区间两端 + 采样几条）。
- 弹球对初角极敏感（混沌）→ 预测**只在前若干跳准**；预测线有限长度既是设计选择也是物理现实。

### A.9 连锁钉递归也要确定
连锁引爆相邻用**显式队列 BFS**（按 pegId 升序入队），禁递归 + 无序集合，否则得分顺序在不同运行下可能分叉。

---

## 附录 B：计分 / 触发器管线实现细节

### B.0 核心：「何时触发」与「数值怎么合」分离
飞行中按事件实时**记账**，落袋时按固定顺序**结算**。触发条件在事件当下判定（实时快照），数值延迟到落袋按 +base→+mult→×mult 统一结算 → 顺序确定、可预期、可做逐项动画。

### B.1 数据流
```
BallSimulation → SimEvent 流 → ScoringEngine 按槽位序路由给 TriggerRuntime
  → 命中监听位+条件则向 ScoreContext.Ledger 追加贡献条目
  → BallSettled：按固定顺序结算 Ledger → LaunchScore → 汇入 RunManager + 交 juice
```

### B.2 账本条目与上下文
```csharp
public enum ContribKind { AddBase, AddMult, MulMult }
public readonly struct Contribution {
    public readonly ContribKind Kind; public readonly double Value; public readonly string SourceId;
}
public sealed class ScoreContext {
    public readonly List<Contribution> Ledger = new(64);       // 一发球，预分配
    public int BounceCount, PegsHitThisLaunch;                 // 实时快照（判条件）
    public bool GateUsedAccel, GateUsedScatter;
    public int LaunchIndexInRound; public RunScopeState Run;   // 跨作用域
    public void Add(ContribKind k, double v, string src) => Ledger.Add(new(k, v, src));
}
```

### B.3 触发器运行时（数据 → 实例）
```csharp
public sealed class TriggerRuntime {
    readonly TriggerDef _def; int _stateCounter;
    public void OnEvent(in SimEvent e, ScoreContext ctx) {
        if ((_def.Listen & e.Type.ToMask()) == 0) return;
        if (!ConditionMet(_def.Condition, e, ctx)) return;
        switch (_def.Effect) {
            case TriggerEffect.AddBase: ctx.Add(ContribKind.AddBase, _def.Value, _def.Id); break;
            case TriggerEffect.AddMult: ctx.Add(ContribKind.AddMult, _def.Value, _def.Id); break;
            case TriggerEffect.MulMult: ctx.Add(ContribKind.MulMult, _def.Value, _def.Id); break;
            case TriggerEffect.Custom:  _def.Strategy.Apply(e, ctx, ref _stateCounter); break;
        }
    }
}
```
80% 触发器用「数据+枚举效果」零代码；长尾特例（如"下一次命中翻倍"这类改未来事件的 buff）走 `Custom` 策略类，在 ctx 上挂待生效修正。

### B.4 结算（固定顺序）
```csharp
public double Settle(ScoreContext ctx, List<SettleStep> outSteps) {
    double baseScore = 0, multAdd = 0, mult;
    foreach (var c in ctx.Ledger) if (c.Kind == ContribKind.AddBase) {
        baseScore += c.Value; outSteps.Add(new(c.SourceId, "+base", c.Value, baseScore)); }
    foreach (var c in ctx.Ledger) if (c.Kind == ContribKind.AddMult) {
        multAdd += c.Value; outSteps.Add(new(c.SourceId, "+mult", c.Value, 1 + multAdd)); }
    mult = 1 + multAdd;
    foreach (var c in ctx.Ledger) if (c.Kind == ContribKind.MulMult) {
        mult *= c.Value; outSteps.Add(new(c.SourceId, "×mult", c.Value, mult)); }
    return baseScore * mult;   // score = base × (1+Σ加倍率) × Π(乘倍率)
}
```
同层内按账本插入序（事件时间序）→ sim 确定 ⇒ 结算确定。

### B.5 作用域
- **Launch**：每发清空（账本、bounceCount）。
- **Round**：每轮累计（轮总分 vs quota）。
- **Run**：整局（利息、用门次数、"每第N发"计数）→ `RunScopeState`，触发器经 `ctx.Run` 读写。

### B.6 与 juice 解耦
`Settle` 产出 `List<SettleStep>`（来源/类型/增量/当前值）；`JuiceController` 照单播放逐项跳动 + 升调音效（pitch 随 step index 递增）+ ×mult 项强屏震/慢动作。juice 只读列表，不参与计算 → 关 juice 分数不变。

### B.7 确定性要点（管线侧）
- 触发器遍历按装备槽位 index，不用无序集合。
- 结算分三遍、层内按插入序，不排序、不依赖引用。
- `Custom` 策略禁系统时间/全局随机；随机走 `DeterministicRng`。
- 连锁钉引发的 PegHit 也进同一事件流（A.9 BFS 序）→ 自然纳入账本。

### B.8 完整例子
分裂球 + "每弹跳+0.2倍率(AddMult)" + 连锁钉 + 加速门：① 加速门提速→弹跳更多；② 飞行中每 Bounce 记一条 AddMult，每 PegHit 钉记 AddBase，连锁钉 BFS 引爆再生 PegHit；③ 落袋结算 base 累加、倍率=1+(0.2×弹跳数)、再过 ×mult → 满屏逐项瀑布。

---

## 附录 C：入口通道与门系统实现细节

### C.1 入口位置参数化（三边任意滑选）
```csharp
public enum BoardEdge { Top, Left, Right }
public readonly struct EntryPoint { public readonly BoardEdge Edge; public readonly float T; } // t∈[0,1]
public (Vector2 pos, Vector2 inwardNormal) Resolve(EntryPoint e, in BoardRect r) => e.Edge switch {
    BoardEdge.Top   => (new Vector2(Mathf.Lerp(r.Left, r.Right, e.T), r.Top),  Vector2.Down),
    BoardEdge.Left  => (new Vector2(r.Left,  Mathf.Lerp(r.Top, r.Bottom, e.T)), Vector2.Right),
    BoardEdge.Right => (new Vector2(r.Right, Mathf.Lerp(r.Top, r.Bottom, e.T)), Vector2.Left),
};
```
免费、每发可换（手感层）；拖到角落可跨边。

### C.2 发射参数与瞄准
```csharp
public struct LaunchParams { public EntryPoint Entry; public float AimOffset; public float NudgeBudget; }
```
入场方向 = `inwardNormal` 旋转 `AimOffset`，夹紧在朝内合法锥角内（防朝外/平行发射）。

### C.3 门 = 对"球集合"的变换
```csharp
public interface IGateEffect { void Apply(List<Ball> balls, in GateContext ctx, DeterministicRng rng); }
// NormalGate: no-op
// AccelGate:  for each b: b.Vel *= mul; b.Flags |= GateAccel;  （配 maxSpeed 限速）
// ScatterAngleGate: for each b: b.Vel = b.Vel.Rotated(rng.Range(-maxRad, maxRad));   // 变角=变数
// ScatterSplitGate: 每球裂成 N 球，角度对称分布于 arc（frac = k/(N-1)-0.5）；偏覆盖
```
作用在球集合上，因为分裂门会把 1 球变多球。

### C.4 门链管线（单门起步 → 后期串联）
```csharp
public sealed class GateRuntime {
    readonly List<IGateEffect> _chain;   // MVP 长度=1
    public List<Ball> Process(Ball entry, in GateContext ctx, DeterministicRng rng){
        var balls = new List<Ball>{ entry };
        foreach (var gate in _chain){ gate.Apply(balls, ctx, rng); Emit(SimEventType.EnterGate, ctx); }
        return balls;
    }
}
```
串联语义：后装门作用于前一门的产物（加速→散射 = 先提速再裂开）。解锁多门直接扩 `_chain`，零逻辑改动。

### C.5 散射确定性 + 扇形预测
- 散射门只从 `gateRng`（master seed 派生子流）取数 → 每日种子/回放可复现；玩家感知为变数。
- 预测线对散射门画**扇形包络**（采样代表角度各跑前瞻），不画单线：
```csharp
IEnumerable<List<Vector2>> PredictFan(SimState s, LaunchParams lp, int steps){
    foreach (float a in SampleArc(lp, 5)) yield return Predict(s, lp.WithAim(a), steps);
}
```
设计含义：散射门 = 用「可预测范围」换「覆盖面」，与变角门「纯变数」形成取舍。

### C.6 通道与时序
通道为入场前带壁走廊（也参与物理，可扩加速带）。门效果在 `EnterGate` 时刻作用，之后球集合释放进主钉阵开始 CCD 弹跳。事件次序：`Launch → (每门)EnterGate → EnterField → PegHit/Bounce… → BallSettled`，全进同一事件流喂计分（用 `GateUsedAccel/Scatter` 快照判条件）。

### C.7 确定性清单（门侧）
- 散射/随机门只用 `gateRng`（禁全局随机）。
- 门链按装备序遍历；分裂球按生成序（k 升序）加入 → 后续模拟/计分顺序确定。
- 预测采样为纯展示，不消耗真实 `gateRng`（真实发射才推进子流）。

---

## 附录 D：程序化棋盘生成实现细节

### D.0 两层模型
结构手工（有趣）+ 细节随机（多变）：
```
布局模板(手工原型) → 程序化填充(按区难度预算) → 叠加玩家本局钉子改造(常驻累积)
   → Boss 词条后处理(每轮) → 可玩性校验 → 最终棋盘
```

### D.1 布局模板（Resource）
```csharp
[GlobalClass] public partial class BoardTemplate : Resource {
    [Export] public string Id;
    [Export] public BoardPrototype Prototype;                  // Honeycomb/Funnel/TwinTower/Spiral
    [Export] public Godot.Collections.Array<Vector2> Anchors;  // 显式锚点（可空，用生成器代替）
    [Export] public GeneratorParams GenParams;
    [Export] public Godot.Collections.Array<Rect2> FunnelZones;
    [Export] public float BaseDensity;
}
```
锚点来源：显式手摆 或 参数化生成器（可混）。

### D.2 参数化生成器（纯函数）
```csharp
static List<Vector2> Honeycomb(GeneratorParams p, BoardRect r){
    var pts = new List<Vector2>();
    for (int row=0; row<p.Rows; row++){
        float y = Mathf.Lerp(r.Top+p.Margin, r.Bottom-p.Margin, row/(float)(p.Rows-1));
        float xOff = (row%2)*p.Spacing*0.5f;
        for (int col=0; col<p.Cols; col++)
            pts.Add(new Vector2(r.Left+p.Margin+xOff+col*p.Spacing, y));
    }
    return pts;   // Funnel/Spiral/TwinTower 同理
}
```

### D.3 填充（按区难度预算，种子化）
```csharp
PegInstance[] Fill(List<Vector2> anchors, int ante, DeterministicRng rng, PegPool pool){
    int n = anchors.Count, specialBudget = SpecialBudget(ante, n);
    var idx = ShuffleIndices(n, rng);
    var pegs = new PegInstance[n];
    for (int i=0;i<n;i++) pegs[i] = new(anchors[i], pool.Normal);
    for (int k=0;k<specialBudget;k++){
        var type = pool.RollSpecial(ante, rng);
        pegs[idx[k]] = new(anchors[idx[k]], type);
    }
    return pegs;
}
int SpecialBudget(int ante, int n) => Mathf.RoundToInt(n * Mathf.Lerp(0.08f, 0.30f, ante/8f));
```
难度旋钮：特殊钉比例/密度/非对称度随 ante 提升。

### D.4 完整生成管线（确定、分层）
```csharp
Board GenerateBoard(ulong masterSeed, int ante, int round,
                    BoardTemplate tpl, RunPegMods runMods, BossModifier boss){
    var rng = DeterministicRng.Derive(masterSeed, ante, round);
    var anchors = tpl.Anchors.Count>0 ? tpl.Anchors.ToList()
                                      : Generate(tpl.Prototype, tpl.GenParams, _rect);
    var pegs = Fill(anchors, ante, rng, _pool);
    runMods.ApplyPersistent(pegs);          // ① 玩家本局钉子改造（常驻累积）
    boss?.PostProcess(pegs, _rect, rng);    // ② Boss 词条（每轮，临时）
    if (!Validate(pegs)) return Reroll(...); // ③ 可玩性校验
    return new Board(pegs, tpl.FunnelZones);
}
```
叠加顺序固定 → 确定。

### D.5 Boss 词条改棋盘（零美术）
- 禁倍率钉（Mult→Normal）、移动钉（打 Moving 标记，模拟层确定轨迹移动）、遮挡视野（Fogged，仅 View 遮）、钉变稀（种子化移除）。
- 多数 Boss 只改钉类型/标记，无新资源。⚠️ 移动钉需模拟层支持动态碰撞体（CCD 用相对速度求 TOI），MVP 可后置。

### D.6 可玩性校验（防退化）
```csharp
bool Validate(PegInstance[] pegs)
    => ReachableRatio(pegs) >= 0.6f && SpecialSpread(pegs) >= MinSpread;
```
失败→派生下一种子重生成（有上限，超了用兜底安全模板）；重roll 要 `log`，避免静默退化。

### D.7 确定性清单（棋盘侧）
- `boardRng = Derive(masterSeed, ante, round)` → 每棋盘独立可复现。
- 生成器纯函数；洗牌/抽类型只用 `boardRng`；叠加顺序固定；重roll 走派生子种子。

### D.8 与"棋盘即引擎"的关系
玩家钉子改造存 `RunPegMods`，整局常驻、逐区累积，每区生成后 `ApplyPersistent` 重新套用 → 即便每区结构不同，攒的引擎持续生长。

---

## 附录 E：跨局状态机 + 商店实现细节

### E.1 显式状态机
```csharp
public enum RunPhase {
    Boot, MainMenu, RunStart, NodeMap, Round, BossRound,
    Shop, Event, Treasure, AnteClear, RunWin, RunLose, MetaUpdate
}
```
转移由纯函数 `Next(state,input)` 决定 → 易测、可序列化、可回放。

### E.2 跑局状态（可序列化 = 存档 + 回放）
```csharp
public sealed class RunState {
    public ulong MasterSeed; public RunPhase Phase;
    public int Ante = 1, RoundInAnte = 0;       // 每区 3 轮：0,1=小关 2=Boss
    public double RoundScore, Quota; public int LaunchesLeft;
    public Economy Economy; public Inventory Inv;
    public NodeMap Map; public int NodeCursor; public List<InputRecord> InputLog;
}
```
存档只存 `RunState`；MasterSeed+状态决定一切 → 重开=续局=回放。

### E.3 区/轮/quota 主循环
```csharp
RunState Advance(RunState s){
    switch (s.Phase){
        case RunPhase.RunStart:
            s.Map = NodeMap.Generate(Derive(s.MasterSeed,0)); s.Phase = RunPhase.NodeMap; break;
        case RunPhase.NodeMap:
            s.Phase = MapNodeToPhase(s.Map.Current(s.NodeCursor)); break;
        case RunPhase.Round: case RunPhase.BossRound:
            s.Quota = QuotaOf(s.Ante, s.RoundInAnte);
            s.Phase = (s.RoundScore >= s.Quota) ? RunPhase.AnteClear : RunPhase.RunLose; break;
        case RunPhase.AnteClear:
            Payout(s);
            if (++s.RoundInAnte > 2){ s.RoundInAnte=0; if (++s.Ante>8){ s.Phase=RunPhase.RunWin; break; } }
            s.Phase = RunPhase.Shop; break;
        case RunPhase.Shop: case RunPhase.Event: case RunPhase.Treasure:
            s.NodeCursor++; s.Phase = RunPhase.NodeMap; break;
        case RunPhase.RunWin: case RunPhase.RunLose:
            s.Phase = RunPhase.MetaUpdate; break;
    }
    return s;
}
```

### E.4 quota 曲线（指数）
```csharp
double QuotaOf(int ante, int round){
    double anteBase = 50 * Math.Pow(1.6, ante-1);
    double roundMul = round switch { 0=>1.0, 1=>1.3, _=>1.8 };
    return Math.Round(anteBase * roundMul);
}
```
系数靠离线平衡模拟调。

### E.5 经济：发钱 + 利息（Balatro 式）
```csharp
void Payout(RunState s){
    int reward = BaseReward(s.Ante) + s.LaunchesLeft * PerLaunchBonus + Interest(s.Economy.Money);
    s.Economy.Money += reward;
}
int Interest(int money) => Math.Min(money / 5, InterestCap);  // 每5块+1，封顶 → 鼓励攒钱
```
"剩余发射换钱" + "存款利息" = 打得好/攒得住 双收益张力。

### E.6 商店（生成/刷新/移除，种子化）
```csharp
sealed class Shop {
    public List<ShopItem> Offerings;
    public void Roll(RunState s, int rerollCount){
        var rng = Derive(s.MasterSeed, "shop", s.Ante, s.NodeCursor, rerollCount); // 刷新次数进种子
        Offerings = new();
        for (int i=0;i<SlotCount;i++){
            var category = RollCategory(rng);              // 触发器/球种/钉改造/门
            var item = _pools[category].Roll(s.Ante, rng); // 按区稀有度权重
            Offerings.Add(new ShopItem(item, Price(item, s.Ante)));
        }
    }
    public int RerollCost(int n) => BaseReroll + n*RerollStep;
    // 购买：扣钱→装备到 Inventory（槽满需替换）；移除服务：付费删一件（砍废卡/转型）
}
```
稀有度按区缩放（×倍率等稀有件深区略升但仍稀缺）；刷新次数进种子保证可复现；移除服务是防哑火/转型关键。

### E.7 节点地图（可简化）
```csharp
sealed class NodeMap {
    public NodeType[][] Layers;   // 每层若干节点，玩家选路；每层保底一个"安全"节点
    public static NodeMap Generate(DeterministicRng rng){ /* Shop/Event/Treasure/Elite */ }
}
```
MVP 可极简：每过关固定进商店 + 区间一个三选一事件；分支地图作后续增强。

### E.8 确定性 & 存档要点
- 所有随机 `Derive(masterSeed, 标签, 索引…)`，不共用游标。
- `RunState` 用 `System.Text.Json` 存 `user://`；退出存快照，回来 `Advance` 续。
- 回放测试：固定 `MasterSeed + InputLog` 重跑 `Advance` → 断言最终 `RunState` 逐字段一致。

---

## 附录 F：数据驱动 / Resource 实现细节

### F.1 注册表启动加载
```csharp
public sealed class GameDatabase {
    public Dictionary<string, TriggerDef> Triggers = new();
    public Dictionary<string, PegType>    Pegs = new();   // …Orbs/Gates/BoardTemplates…
    public void LoadAll(){
        foreach (var path in DirWalk("res://data/triggers")) { var d = GD.Load<TriggerDef>(path); Triggers[d.Id]=d; }
        Validate();
    }
}
```

### F.2 枚举行为 vs 代码策略类的边界
| 用数据(.tres+枚举) | 用代码策略类(`Custom`) |
|---|---|
| 参数化：数值/条件枚举/监听位/稀有度 | 命令式逻辑：改未来事件的 buff |
| 覆盖 ~80% 内容、策划改表不重编译 | 多步状态、跨作用域副作用、长尾特例 |

### F.3 启动期数据校验（linter）
Id 唯一、引用可解析、数值在区间、监听位非空 → 开机即报错，不等运行时崩。

### F.4 热迭代
`.tres` 编辑器改后可重载；加 debug "重载数据库"命令快速调参。C# 代码热重载弱 → 逻辑层尽量纯 C#，靠数据调参而非改码。

---

## 附录 G：存档 / 回放 / 测试实现细节

### G.1 存档
`RunState`(局内) + `MetaState`(解锁/设置/统计) → `System.Text.Json` 存 `user://`。

### G.2 回放 = 存档副产物
`MasterSeed + InputLog` 无渲染重跑 → 必得同样结果（确定性红利）。

### G.3 测试金字塔（headless，Rider 直接跑）
```csharp
[Test] void Replay_SameSeedAndInputs_SameFinalScore(){
    var a = RunHeadless(12345, inputs); var b = RunHeadless(12345, inputs);
    Assert.AreEqual(a.FinalScoreExact, b.FinalScoreExact);
    CollectionAssert.AreEqual(a.EventLog, b.EventLog);
}
```
- 物理确定性测试（事件/分数逐位一致，入 CI）；计分单元测试；碰撞数学测试。

### G.4 离线平衡模拟工具
```csharp
foreach (var seed in seeds) results.Add(SimulateRun(seed, medianBuild));
ExportCsv(results);   // 每区通过率曲线 / 破表分布 → 调 quota 系数
```

### G.5 CI
`godot --headless` 跑回放回归 + 纯 C# 单测。

---

## 附录 H：Juice / 渲染解耦实现细节

### H.1 Sim/View 分离 + 插值
View 每帧读 `_prev/_curr` 按 alpha 插值（附录 A.1），逻辑帧率恒定。

### H.2 JuiceController 订阅事件 + 结算列表（不参与计算）
```csharp
void OnSimEvents(IReadOnlyList<SimEvent> evs){
    foreach (var e in evs) switch (e.Type){
        case PegHit: SpawnHitParticles(e.Pos); PlayHitSfx(e); break;
        case Bounce: TinyShake(); break;
        case ChainTrigger: BigShake(); break;
    }
}
void OnSettle(IReadOnlyList<SettleStep> steps){
    StartCoroutineTally(steps);                          // 逐项跳动 + 升调音效
    if (steps.Any(s=>s.Kind=="×mult")) SlowMo(0.15f);    // 仅视觉时间缩放
}
```

### H.3 关键纪律
- 慢动作只缩放**视觉**时间，绝不改 sim 的 `DT` → 不破坏确定性。
- 升调音效：`pitch = basePitch * pow(1.06, chainIndex)`，连锁越长越高。
- 关掉所有 juice，分数完全不变（juice 只读不写逻辑）。

### H.4 性能
- 粒子用 `GpuParticles2D`；球/特效对象池；事件回调避免每次 `new`。
- 音效合并节流（一帧大量命中合成一声渐强，防爆音+省开销）。
- 霓虹辉光走 `CanvasItem` shader + 后处理 bloom。
