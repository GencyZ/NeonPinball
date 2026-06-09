# 里程碑 1：弹球物理原型（go/no-go）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出一个可玩原型——从三条边任意位置瞄准、看预测线、发射一颗确定性弹球在钉阵中弹跳、累计基础分——用来验证"发射手感"是否成立。

**Architecture:** 纯 C# 确定性模拟层（`NeonPinball.Sim`，只依赖 `System.Numerics`，可 headless 单测）+ Godot 渲染层（`NeonPinball`，读模拟状态做插值与输入）+ 测试项目（`NeonPinball.Tests`，xUnit）。模拟与渲染严格分离：关掉渲染逻辑结果不变。

**Tech Stack:** Godot 4.x (.NET/C#)、.NET 8、System.Numerics、xUnit、Rider。

**配套文档：** 设计 `2026-06-09-neon-pinball-roguelike-deckbuilder-design.md`；技术 `2026-06-09-neon-pinball-tech-design.md`（附录 A 物理 / B 计分）。

**里程碑 1 不含**：门/触发器/球种/商店/区轮/随机（散射门等）。只做：确定性单球物理 + 三边入口 + 瞄准 + 预测线 + 每钉基础分 + 基础 juice。

---

## 文件结构

```
/NeonPinball.sln
/sim/NeonPinball.Sim.csproj          # 纯 C# 类库（net8, 仅 System.Numerics）
  MathHelpers.cs                     # Rotate 等
  Ball.cs                            # 球状态 struct
  Peg.cs                             # 钉 struct
  SimEvent.cs                        # 事件 enum + struct
  Collision.cs                       # 圆-圆扫掠 TOI、轴对齐墙 TOI、反射
  SpatialGrid.cs                     # 宽相位网格
  BoardRect.cs                       # 棋盘矩形 + 边界
  BallSimulation.cs                  # 定步长 CCD 步进 + 事件产出
  EntryResolver.cs                   # (edge,t)+瞄准 → 球初始状态
  TrajectoryPredictor.cs            # 无渲染前瞻 → 预测线
  Scorer.cs                          # 从事件流累计基础分
/tests/NeonPinball.Tests.csproj      # xUnit（引用 Sim）
  MathHelpersTests.cs  CollisionTests.cs  SpatialGridTests.cs
  BallSimulationTests.cs  EntryResolverTests.cs
  TrajectoryPredictorTests.cs  ScorerTests.cs  DeterminismTests.cs
/game/                               # Godot .NET 项目（引用 Sim）
  project.godot
  NeonPinball.csproj
  scenes/Board.tscn
  view/BoardView.cs                  # 主循环(accumulator)+渲染+插值
  view/InputController.cs            # 三边拖动入口+瞄准+发射
  view/Hud.cs                        # 分数/发射数/命中粒子
```

> 约定：`Vector2` 全程指 `System.Numerics.Vector2`（Sim 层），在 View 边界转 `Godot.Vector2`。

---

## Task -1：环境准备（开工前一次性）

> **执行顺序提示**：Task 0–10（`NeonPinball.Sim` + 测试）是**纯 C#，不依赖 Godot**——只要装好 .NET 8 就能立刻开始并跑通全部单测。**Godot 只有 Task 11 起才需要**。所以可以先做完物理/计分核心，再装 Godot 做渲染。

**Files:** 无（安装与目录约定）

- [ ] **Step 1: 确认 .NET 8 SDK**

Run: `dotnet --version`
Expected: `8.0.x`（已确认本机为 8.0.204）。若无 → 安装 .NET 8 SDK（https://dotnet.microsoft.com/download）。

- [ ] **Step 2: 安装 Godot 4.x —— 必须是 “.NET / Mono” 版**

⚠️ Godot 有两个下载：标准版（仅 GDScript）和 **".NET" 版**。**必须下 ".NET" 版**，否则不支持 C#。
- 下载页：https://godotengine.org/download/windows/ → 选 **Godot 4.x .NET**。
- 建议**固定版本**（如 4.4 .NET），全程不随意升级，避免 API/项目格式漂移。
- 解压到固定目录（如 `D:\Tools\Godot_4.4_mono\`），并把可执行文件目录加入 PATH（便于 `godot --headless` 等命令）。

- [ ] **Step 3: 安装/配置 Rider**

- 安装 JetBrains Rider，启用 **Godot 插件**（Settings → Plugins 搜 "Godot"）。
- Rider 里打开 `NeonPinball.sln`；Godot 项目首次需在 Godot 编辑器生成 `.csproj`/`.sln` 后再用 Rider 打开。
- 配置 Godot 运行/调试：Rider 的运行配置选 Godot，可断点调 C#。

- [ ] **Step 4: 约定项目根目录**

- 建议项目根：**`D:\NeonPinball\`**（独立目录，勿用 `D:\` 根，避免与其他文件混）。
- 后续所有相对路径（`sim/`、`tests/`、`game/`）都相对于此根。
- Task 0 的 `dotnet new sln` 等命令在此目录下执行（把计划里的 `cd /d/` 理解为 `cd /d/NeonPinball`）。

- [ ] **Step 5: 验证 Godot .NET 工具链（装好 Godot 后再做）**

Run: `godot --version`
Expected: 输出 `4.x.stable.mono` 字样（含 `mono`/`.NET` 标识即正确版本）。
> 此步可推迟到开始 Task 11 前；Task 0–10 不需要。

---

## Task 0：解决方案与项目骨架

**Files:**
- Create: `sim/NeonPinball.Sim.csproj`
- Create: `tests/NeonPinball.Tests.csproj`
- Create: `NeonPinball.sln`
- Create: `sim/SmokeMarker.cs`、`tests/SmokeTests.cs`

- [ ] **Step 1: 创建 Sim 类库工程文件**

`sim/NeonPinball.Sim.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <LangVersion>latest</LangVersion>
    <RootNamespace>NeonPinball.Sim</RootNamespace>
  </PropertyGroup>
</Project>
```

- [ ] **Step 2: 创建测试工程文件**

`tests/NeonPinball.Tests.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../sim/NeonPinball.Sim.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: 创建解决方案并加入两个工程**

Run:
```bash
cd /d/  # 进入 D 盘工作目录（按实际项目根调整）
dotnet new sln -n NeonPinball -o .
dotnet sln NeonPinball.sln add sim/NeonPinball.Sim.csproj tests/NeonPinball.Tests.csproj
```
Expected: `Project ... added to the solution.` ×2

- [ ] **Step 4: 写冒烟标记 + 冒烟测试**

`sim/SmokeMarker.cs`:
```csharp
namespace NeonPinball.Sim;
public static class SmokeMarker { public const string Ok = "ok"; }
```

`tests/SmokeTests.cs`:
```csharp
using NeonPinball.Sim;
using Xunit;
public class SmokeTests {
    [Fact] public void Sim_Is_Referenced() => Assert.Equal("ok", SmokeMarker.Ok);
}
```

- [ ] **Step 5: 跑测试验证工具链通**

Run: `dotnet test NeonPinball.sln`
Expected: `Passed!  - Failed: 0, Passed: 1`

- [ ] **Step 6: Commit**

```bash
git init
git add -A
git commit -m "chore: scaffold Sim + Tests solution"
```

---

## Task 1：数学辅助（向量旋转）

**Files:**
- Create: `sim/MathHelpers.cs`
- Test: `tests/MathHelpersTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/MathHelpersTests.cs`:
```csharp
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class MathHelpersTests {
    [Fact] public void Rotate_90deg_TurnsRightIntoUp() {
        var v = new Vector2(1, 0);
        var r = MathHelpers.Rotate(v, MathF.PI / 2);
        Assert.True(MathF.Abs(r.X - 0) < 1e-4);
        Assert.True(MathF.Abs(r.Y - 1) < 1e-4);
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter MathHelpersTests`
Expected: FAIL（`MathHelpers` 不存在 / 编译错误）

- [ ] **Step 3: 实现**

`sim/MathHelpers.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public static class MathHelpers {
    public static Vector2 Rotate(Vector2 v, float rad) {
        float c = MathF.Cos(rad), s = MathF.Sin(rad);
        return new Vector2(v.X * c - v.Y * s, v.X * s + v.Y * c);
    }
    public static Vector2 ClampLength(Vector2 v, float max) {
        float len = v.Length();
        return len > max && len > 1e-6f ? v * (max / len) : v;
    }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter MathHelpersTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add sim/MathHelpers.cs tests/MathHelpersTests.cs
git commit -m "feat(sim): vector rotate + clamp-length helpers"
```

---

## Task 2：数据结构（Ball / Peg / BoardRect / SimEvent）

**Files:**
- Create: `sim/Ball.cs`、`sim/Peg.cs`、`sim/BoardRect.cs`、`sim/SimEvent.cs`

- [ ] **Step 1: 写 Ball**

`sim/Ball.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public struct Ball {
    public Vector2 Pos;
    public Vector2 Vel;
    public float Radius;
    public int BounceCount;
    public bool Alive;
    public Ball(Vector2 pos, Vector2 vel, float radius) {
        Pos = pos; Vel = vel; Radius = radius; BounceCount = 0; Alive = true;
    }
}
```

- [ ] **Step 2: 写 Peg**

`sim/Peg.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public readonly struct Peg {
    public readonly int Id;
    public readonly Vector2 Pos;
    public readonly float Radius;
    public readonly float BaseScore;
    public Peg(int id, Vector2 pos, float radius, float baseScore) {
        Id = id; Pos = pos; Radius = radius; BaseScore = baseScore;
    }
}
```

- [ ] **Step 3: 写 BoardRect**

`sim/BoardRect.cs`:
```csharp
namespace NeonPinball.Sim;
public readonly struct BoardRect {
    public readonly float Left, Right, Top, Bottom;   // 屏幕坐标：Top<Bottom，y 向下
    public BoardRect(float left, float top, float right, float bottom) {
        Left = left; Top = top; Right = right; Bottom = bottom;
    }
    public float Width => Right - Left;
    public float Height => Bottom - Top;
}
```

- [ ] **Step 4: 写 SimEvent**

`sim/SimEvent.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public enum SimEventType { Launch, PegHit, Bounce, WallHit, BallSettled }
public readonly struct SimEvent {
    public readonly SimEventType Type;
    public readonly int PegId;     // 非钉事件为 -1
    public readonly Vector2 Pos;
    public SimEvent(SimEventType type, int pegId, Vector2 pos) { Type = type; PegId = pegId; Pos = pos; }
    public static SimEvent PegHit(int id, Vector2 p) => new(SimEventType.PegHit, id, p);
    public static SimEvent Bounce(Vector2 p)         => new(SimEventType.Bounce, -1, p);
    public static SimEvent WallHit(Vector2 p)        => new(SimEventType.WallHit, -1, p);
    public static SimEvent Settled(Vector2 p)        => new(SimEventType.BallSettled, -1, p);
    public static SimEvent Launch(Vector2 p)         => new(SimEventType.Launch, -1, p);
}
```

- [ ] **Step 5: 编译确认**

Run: `dotnet build NeonPinball.sln`
Expected: `Build succeeded`

- [ ] **Step 6: Commit**

```bash
git add sim/Ball.cs sim/Peg.cs sim/BoardRect.cs sim/SimEvent.cs
git commit -m "feat(sim): core data structs (Ball/Peg/BoardRect/SimEvent)"
```

---

## Task 3：圆-圆扫掠碰撞（CCD / TOI）

**Files:**
- Create: `sim/Collision.cs`
- Test: `tests/CollisionTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/CollisionTests.cs`:
```csharp
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class CollisionTests {
    [Fact] public void SweptCircle_HeadOn_HitsAtHalf() {
        // 点从 (0,0) 沿 +x 走 10，目标圆心 (10,0)，合半径 R=5 → 在距离5处命中 → t=0.5
        bool hit = Collision.SweptCircle(new Vector2(0,0), new Vector2(10,0),
                                         new Vector2(10,0), 5f, out float t);
        Assert.True(hit);
        Assert.True(MathF.Abs(t - 0.5f) < 1e-4);
    }
    [Fact] public void SweptCircle_Misses_WhenOffside() {
        bool hit = Collision.SweptCircle(new Vector2(0,0), new Vector2(10,0),
                                         new Vector2(5,100), 5f, out _);
        Assert.False(hit);
    }
    [Fact] public void SweptCircle_NoHit_WhenTooShort() {
        bool hit = Collision.SweptCircle(new Vector2(0,0), new Vector2(1,0),
                                         new Vector2(10,0), 5f, out _);
        Assert.False(hit); // 位移不足以到达
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter CollisionTests`
Expected: FAIL（`Collision` 不存在）

- [ ] **Step 3: 实现 SweptCircle**

`sim/Collision.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public static class Collision {
    // 点 p 沿位移 d 移动，与以 c 为心、合半径 R 的圆求最早相交。命中返回 t∈[0,1]。
    public static bool SweptCircle(Vector2 p, Vector2 d, Vector2 c, float R, out float t) {
        t = 0f;
        Vector2 m = p - c;
        float a = Vector2.Dot(d, d);
        if (a < 1e-12f) return false;                 // 几乎不动
        float b = 2f * Vector2.Dot(m, d);
        float cc = Vector2.Dot(m, m) - R * R;
        float disc = b * b - 4f * a * cc;
        if (disc < 0f) return false;                  // 无交点
        float root = (-b - MathF.Sqrt(disc)) / (2f * a);
        if (root < 0f || root > 1f) return false;     // 不在本段位移内
        t = root;
        return true;
    }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter CollisionTests`
Expected: PASS（3 个）

- [ ] **Step 5: Commit**

```bash
git add sim/Collision.cs tests/CollisionTests.cs
git commit -m "feat(sim): swept circle-circle TOI"
```

---

## Task 4：轴对齐墙 TOI + 反射

**Files:**
- Modify: `sim/Collision.cs`
- Test: `tests/CollisionTests.cs`（追加）

- [ ] **Step 1: 追加失败测试**

在 `tests/CollisionTests.cs` 追加：
```csharp
    [Fact] public void WallToi_RightWall_HitsAtHalf() {
        var rect = new BoardRect(0, 0, 10, 100);
        // 球半径1，从 x=4 沿 +x 走 10；右墙有效线 x=Right-r=9 → 距离5 → t=0.5
        bool hit = Collision.SweptWalls(new Vector2(4,50), new Vector2(10,0), 1f, rect,
                                        out float t, out Vector2 n);
        Assert.True(hit);
        Assert.True(MathF.Abs(t - 0.5f) < 1e-4);
        Assert.Equal(new Vector2(-1, 0), n);  // 右墙法线朝左
    }
    [Fact] public void Reflect_OffVerticalWall_FlipsX() {
        var v = Collision.Reflect(new Vector2(3, 2), new Vector2(-1, 0), restitution: 1f, tangentKeep: 1f);
        Assert.True(MathF.Abs(v.X - (-3)) < 1e-4);
        Assert.True(MathF.Abs(v.Y - 2) < 1e-4);
    }
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter CollisionTests`
Expected: FAIL（`SweptWalls`/`Reflect` 不存在）

- [ ] **Step 3: 实现 SweptWalls + Reflect**

在 `sim/Collision.cs` 的类中追加：
```csharp
    // 左/右/顶三面轴对齐墙（底部开口落球）。返回最早命中的 t 与法线。
    public static bool SweptWalls(Vector2 p, Vector2 d, float r, in BoardRect rect,
                                  out float t, out Vector2 n) {
        t = float.MaxValue; n = Vector2.Zero; bool found = false;
        void Consider(float cand, Vector2 normal) {
            if (cand >= 0f && cand <= 1f && cand < t) { t = cand; n = normal; found = true; }
        }
        if (d.X < 0f) Consider(((rect.Left + r) - p.X) / d.X,  new Vector2(1, 0));   // 左墙
        if (d.X > 0f) Consider(((rect.Right - r) - p.X) / d.X, new Vector2(-1, 0));  // 右墙
        if (d.Y < 0f) Consider(((rect.Top + r) - p.Y) / d.Y,   new Vector2(0, 1));   // 顶墙
        if (!found) t = 0f;
        return found;
    }

    public static Vector2 Reflect(Vector2 v, Vector2 n, float restitution, float tangentKeep) {
        float vn = Vector2.Dot(v, n);
        Vector2 vNormal = vn * n;
        Vector2 vTangent = v - vNormal;
        return vTangent * tangentKeep - vNormal * restitution;
    }
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter CollisionTests`
Expected: PASS（全部）

- [ ] **Step 5: Commit**

```bash
git add sim/Collision.cs tests/CollisionTests.cs
git commit -m "feat(sim): axis-aligned wall TOI + reflection"
```

---

## Task 5：宽相位空间网格

**Files:**
- Create: `sim/SpatialGrid.cs`
- Test: `tests/SpatialGridTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/SpatialGridTests.cs`:
```csharp
using System.Numerics;
using System.Linq;
using NeonPinball.Sim;
using Xunit;
public class SpatialGridTests {
    [Fact] public void Query_ReturnsNearbyPeg_NotFarPeg() {
        var pegs = new[] {
            new Peg(0, new Vector2(10,10), 5, 1),
            new Peg(1, new Vector2(500,500), 5, 1),
        };
        var grid = new SpatialGrid(new BoardRect(0,0,600,600), cellSize: 50);
        grid.Build(pegs);
        var near = grid.QueryNear(new Vector2(12,12), radius: 20).ToList();
        Assert.Contains(0, near);
        Assert.DoesNotContain(1, near);
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter SpatialGridTests`
Expected: FAIL

- [ ] **Step 3: 实现**

`sim/SpatialGrid.cs`:
```csharp
using System;
using System.Collections.Generic;
using System.Numerics;
namespace NeonPinball.Sim;
public sealed class SpatialGrid {
    private readonly BoardRect _rect;
    private readonly float _cell;
    private readonly int _cols, _rows;
    private readonly List<int>[] _cells;
    private Peg[] _pegs = Array.Empty<Peg>();

    public SpatialGrid(BoardRect rect, float cellSize) {
        _rect = rect; _cell = cellSize;
        _cols = Math.Max(1, (int)MathF.Ceiling(rect.Width / cellSize));
        _rows = Math.Max(1, (int)MathF.Ceiling(rect.Height / cellSize));
        _cells = new List<int>[_cols * _rows];
        for (int i = 0; i < _cells.Length; i++) _cells[i] = new List<int>();
    }

    private int Index(int cx, int cy) => cy * _cols + cx;
    private (int cx, int cy) CellOf(Vector2 p) {
        int cx = Math.Clamp((int)((p.X - _rect.Left) / _cell), 0, _cols - 1);
        int cy = Math.Clamp((int)((p.Y - _rect.Top) / _cell), 0, _rows - 1);
        return (cx, cy);
    }

    public void Build(Peg[] pegs) {
        _pegs = pegs;
        foreach (var c in _cells) c.Clear();
        foreach (var peg in pegs) {
            var (cx, cy) = CellOf(peg.Pos);
            _cells[Index(cx, cy)].Add(peg.Id);
        }
    }

    // 返回中心点附近 radius 范围内格子的钉 Id（按 pegId 升序，确定遍历）。
    public IEnumerable<int> QueryNear(Vector2 center, float radius) {
        var (minx, miny) = CellOf(center - new Vector2(radius, radius));
        var (maxx, maxy) = CellOf(center + new Vector2(radius, radius));
        var result = new SortedSet<int>();
        for (int cy = miny; cy <= maxy; cy++)
            for (int cx = minx; cx <= maxx; cx++)
                foreach (var id in _cells[Index(cx, cy)]) result.Add(id);
        return result;
    }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter SpatialGridTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add sim/SpatialGrid.cs tests/SpatialGridTests.cs
git commit -m "feat(sim): broadphase spatial grid"
```

---

## Task 6：弹球模拟步进（定步长 + CCD + 事件）

**Files:**
- Create: `sim/BallSimulation.cs`
- Test: `tests/BallSimulationTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/BallSimulationTests.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
using System.Linq;
using NeonPinball.Sim;
using Xunit;
public class BallSimulationTests {
    private static BallSimulation MakeSim(Peg[] pegs) {
        var rect = new BoardRect(0, 0, 200, 400);
        var sim = new BallSimulation(rect, pegs, new SimConfig {
            Gravity = new Vector2(0, 500), MaxSpeed = 2000,
            Restitution = 0.8f, TangentKeep = 1f, Dt = 1f/120f
        });
        return sim;
    }

    [Fact] public void Ball_FallsAndSettles_AtBottom() {
        var sim = MakeSim(System.Array.Empty<Peg>());
        var ball = new Ball(new Vector2(100, 10), Vector2.Zero, 5);
        var events = new List<SimEvent>();
        for (int i = 0; i < 600 && ball.Alive; i++) sim.Step(ref ball, events);
        Assert.False(ball.Alive);
        Assert.Contains(events, e => e.Type == SimEventType.BallSettled);
    }

    [Fact] public void Ball_HitsPeg_EmitsPegHit() {
        var pegs = new[] { new Peg(0, new Vector2(100, 100), 8, 5) };
        var sim = MakeSim(pegs);
        var ball = new Ball(new Vector2(100, 10), Vector2.Zero, 5); // 正上方自由落体砸中
        var events = new List<SimEvent>();
        for (int i = 0; i < 600 && ball.Alive; i++) sim.Step(ref ball, events);
        Assert.Contains(events, e => e.Type == SimEventType.PegHit && e.PegId == 0);
    }

    [Fact] public void Ball_NoTunneling_AtHighSpeed() {
        var pegs = new[] { new Peg(0, new Vector2(100, 200), 8, 5) };
        var sim = MakeSim(pegs);
        // 高速向下，单步位移远大于钉直径，仍须命中（CCD 生效）
        var ball = new Ball(new Vector2(100, 10), new Vector2(0, 3000), 5);
        var events = new List<SimEvent>();
        for (int i = 0; i < 600 && ball.Alive; i++) sim.Step(ref ball, events);
        Assert.Contains(events, e => e.Type == SimEventType.PegHit && e.PegId == 0);
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter BallSimulationTests`
Expected: FAIL（`BallSimulation`/`SimConfig` 不存在）

- [ ] **Step 3: 实现 SimConfig + BallSimulation**

`sim/BallSimulation.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
namespace NeonPinball.Sim;

public struct SimConfig {
    public Vector2 Gravity;
    public float MaxSpeed;
    public float Restitution;
    public float TangentKeep;
    public float Dt;
}

public sealed class BallSimulation {
    private const float Epsilon = 1e-5f;
    private const int MaxBouncesPerStep = 8;

    private readonly BoardRect _rect;
    private readonly Peg[] _pegs;
    private readonly SpatialGrid _grid;
    private readonly SimConfig _cfg;

    public BallSimulation(BoardRect rect, Peg[] pegs, SimConfig cfg) {
        _rect = rect; _pegs = pegs; _cfg = cfg;
        _grid = new SpatialGrid(rect, cellSize: 50f);
        _grid.Build(pegs);
    }

    public float Dt => _cfg.Dt;

    // 推进一个固定步；产出事件追加到 outEvents。
    public void Step(ref Ball b, List<SimEvent> outEvents) {
        if (!b.Alive) return;
        b.Vel += _cfg.Gravity * _cfg.Dt;
        b.Vel = MathHelpers.ClampLength(b.Vel, _cfg.MaxSpeed);

        float rt = _cfg.Dt;
        int guard = 0;
        while (rt > Epsilon && guard++ < MaxBouncesPerStep) {
            Vector2 d = b.Vel * rt;
            if (!FindEarliest(b.Pos, d, b.Radius, out float t, out Vector2 n, out int pegId)) {
                b.Pos += d; break;
            }
            b.Pos += d * t;
            if (pegId >= 0) outEvents.Add(SimEvent.PegHit(pegId, b.Pos));
            else            outEvents.Add(SimEvent.WallHit(b.Pos));
            outEvents.Add(SimEvent.Bounce(b.Pos));
            b.Vel = Collision.Reflect(b.Vel, n, _cfg.Restitution, _cfg.TangentKeep);
            b.BounceCount++;
            rt *= (1f - t);
        }

        if (b.Pos.Y - b.Radius > _rect.Bottom) {
            b.Alive = false;
            outEvents.Add(SimEvent.Settled(b.Pos));
        }
    }

    // 求本段位移内最早碰撞（钉优先按 TOI，再按 pegId 决胜；与墙比较取更早）。
    private bool FindEarliest(Vector2 p, Vector2 d, float r,
                             out float t, out Vector2 n, out int pegId) {
        t = float.MaxValue; n = Vector2.Zero; pegId = -1; bool found = false;

        float searchR = d.Length() + r + 32f;
        foreach (int id in _grid.QueryNear(p, searchR)) {
            ref readonly Peg peg = ref _pegs[id];
            if (Collision.SweptCircle(p, d, peg.Pos, r + peg.Radius, out float pt)) {
                if (pt < t) {
                    t = pt; pegId = id; found = true;
                    Vector2 contact = p + d * pt;
                    n = Vector2.Normalize(contact - peg.Pos);
                }
            }
        }
        if (Collision.SweptWalls(p, d, r, _rect, out float wt, out Vector2 wn)) {
            if (wt < t) { t = wt; n = wn; pegId = -1; found = true; }
        }
        if (!found) t = 0f;
        return found;
    }
}
```
> 注：`_pegs` 以 `Id` 作为数组下标，因此 Task 7 之后生成棋盘时必须保证 `peg.Id == 数组索引`。

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter BallSimulationTests`
Expected: PASS（3 个，含高速无隧穿）

- [ ] **Step 5: Commit**

```bash
git add sim/BallSimulation.cs tests/BallSimulationTests.cs
git commit -m "feat(sim): fixed-step CCD ball simulation with events"
```

---

## Task 7：入口解析（三边滑选 + 瞄准 → 初始球）

**Files:**
- Create: `sim/EntryResolver.cs`
- Test: `tests/EntryResolverTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/EntryResolverTests.cs`:
```csharp
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class EntryResolverTests {
    private static readonly BoardRect Rect = new(0, 0, 200, 400);

    [Fact] public void TopEdge_Mid_PosCenteredTop_NormalDown() {
        var (pos, n) = EntryResolver.Resolve(BoardEdge.Top, 0.5f, Rect);
        Assert.Equal(new Vector2(100, 0), pos);
        Assert.Equal(new Vector2(0, 1), n);
    }
    [Fact] public void RightEdge_Quarter_PosOnRight_NormalLeft() {
        var (pos, n) = EntryResolver.Resolve(BoardEdge.Right, 0.25f, Rect);
        Assert.Equal(new Vector2(200, 100), pos);
        Assert.Equal(new Vector2(-1, 0), n);
    }
    [Fact] public void MakeBall_AimsAlongNormal_WhenOffsetZero() {
        var ball = EntryResolver.MakeBall(BoardEdge.Top, 0.5f, aimOffset: 0f,
                                          speed: 100f, radius: 5f, Rect);
        Assert.True(ball.Vel.Y > 0);                       // 朝棋盘内（向下）
        Assert.True(MathF.Abs(ball.Vel.X) < 1e-3);
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter EntryResolverTests`
Expected: FAIL

- [ ] **Step 3: 实现**

`sim/EntryResolver.cs`:
```csharp
using System.Numerics;
namespace NeonPinball.Sim;
public enum BoardEdge { Top, Left, Right }
public static class EntryResolver {
    // (edge,t) → 世界坐标 + 朝棋盘内法线。t∈[0,1] 沿边。
    public static (Vector2 pos, Vector2 inwardNormal) Resolve(BoardEdge edge, float t, in BoardRect r) {
        t = System.Math.Clamp(t, 0f, 1f);
        return edge switch {
            BoardEdge.Top   => (new Vector2(Lerp(r.Left, r.Right, t), r.Top),  new Vector2(0, 1)),
            BoardEdge.Left  => (new Vector2(r.Left,  Lerp(r.Top, r.Bottom, t)), new Vector2(1, 0)),
            _               => (new Vector2(r.Right, Lerp(r.Top, r.Bottom, t)), new Vector2(-1, 0)),
        };
    }

    // 瞄准：法线绕轴旋转 aimOffset（弧度），夹紧在朝内 ±80° 锥角内。
    public static Ball MakeBall(BoardEdge edge, float t, float aimOffset,
                               float speed, float radius, in BoardRect r) {
        var (pos, n) = Resolve(edge, t, r);
        float clamped = System.Math.Clamp(aimOffset, -1.396f, 1.396f); // ±80°
        Vector2 dir = MathHelpers.Rotate(n, clamped);
        return new Ball(pos, dir * speed, radius);
    }

    private static float Lerp(float a, float b, float t) => a + (b - a) * t;
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter EntryResolverTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add sim/EntryResolver.cs tests/EntryResolverTests.cs
git commit -m "feat(sim): three-edge entry resolver + aim"
```

---

## Task 8：轨迹预测（预测线 = 同一套 Sim 前瞻）

**Files:**
- Create: `sim/TrajectoryPredictor.cs`
- Test: `tests/TrajectoryPredictorTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/TrajectoryPredictorTests.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class TrajectoryPredictorTests {
    [Fact] public void Prediction_MatchesActualPath() {
        var rect = new BoardRect(0, 0, 200, 400);
        var pegs = new[] { new Peg(0, new Vector2(100, 150), 8, 5) };
        var cfg = new SimConfig { Gravity = new Vector2(0,500), MaxSpeed = 2000,
                                  Restitution = 0.8f, TangentKeep = 1f, Dt = 1f/120f };
        var sim = new BallSimulation(rect, pegs, cfg);
        var start = EntryResolver.MakeBall(BoardEdge.Top, 0.5f, 0.2f, 300f, 5f, rect);

        var predicted = TrajectoryPredictor.Predict(sim, start, steps: 40);

        // 实际跑同样起点 40 步，逐点比对
        var actual = new List<Vector2>();
        var ball = start; var ev = new List<SimEvent>();
        for (int i = 0; i < 40 && ball.Alive; i++) { sim.Step(ref ball, ev); actual.Add(ball.Pos); }

        Assert.Equal(actual.Count, predicted.Count);
        for (int i = 0; i < actual.Count; i++) {
            Assert.True(Vector2.Distance(actual[i], predicted[i]) < 1e-4);
        }
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter TrajectoryPredictorTests`
Expected: FAIL

- [ ] **Step 3: 实现**

`sim/TrajectoryPredictor.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
namespace NeonPinball.Sim;
public static class TrajectoryPredictor {
    // 用同一套 BallSimulation 无渲染前瞻，返回每步球心位置。完全确定 → 等于真实弹道。
    public static List<Vector2> Predict(BallSimulation sim, Ball start, int steps) {
        var pts = new List<Vector2>(steps);
        var ball = start;
        var scratch = new List<SimEvent>();   // 丢弃，不外泄
        for (int i = 0; i < steps && ball.Alive; i++) {
            scratch.Clear();
            sim.Step(ref ball, scratch);
            pts.Add(ball.Pos);
        }
        return pts;
    }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter TrajectoryPredictorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add sim/TrajectoryPredictor.cs tests/TrajectoryPredictorTests.cs
git commit -m "feat(sim): trajectory predictor (matches actual path)"
```

---

## Task 9：基础计分（从事件流累计 base）

**Files:**
- Create: `sim/Scorer.cs`
- Test: `tests/ScorerTests.cs`

- [ ] **Step 1: 写失败测试**

`tests/ScorerTests.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class ScorerTests {
    [Fact] public void Sum_BaseScore_PerPegHit() {
        var pegs = new[] {
            new Peg(0, new Vector2(0,0), 5, 3),
            new Peg(1, new Vector2(0,0), 5, 7),
        };
        var scorer = new Scorer(pegs);
        var events = new List<SimEvent> {
            SimEvent.PegHit(0, Vector2.Zero),
            SimEvent.PegHit(1, Vector2.Zero),
            SimEvent.PegHit(0, Vector2.Zero),
            SimEvent.Bounce(Vector2.Zero),     // 非计分事件，忽略
        };
        double score = scorer.ScoreLaunch(events);
        Assert.Equal(3 + 7 + 3, score);
    }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `dotnet test --filter ScorerTests`
Expected: FAIL

- [ ] **Step 3: 实现**

`sim/Scorer.cs`:
```csharp
using System.Collections.Generic;
namespace NeonPinball.Sim;
// 里程碑 1 仅基础分：每个 PegHit 加该钉 BaseScore。触发器/倍率在里程碑 2 接入（见技术文档附录 B）。
public sealed class Scorer {
    private readonly Peg[] _pegs;
    public Scorer(Peg[] pegs) { _pegs = pegs; }
    public double ScoreLaunch(IReadOnlyList<SimEvent> events) {
        double baseScore = 0;
        for (int i = 0; i < events.Count; i++) {
            var e = events[i];
            if (e.Type == SimEventType.PegHit && e.PegId >= 0 && e.PegId < _pegs.Length)
                baseScore += _pegs[e.PegId].BaseScore;
        }
        return baseScore;
    }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `dotnet test --filter ScorerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add sim/Scorer.cs tests/ScorerTests.cs
git commit -m "feat(sim): base scorer from event stream"
```

---

## Task 10：确定性回放守卫测试

**Files:**
- Test: `tests/DeterminismTests.cs`

- [ ] **Step 1: 写测试（守卫：同输入→逐位一致）**

`tests/DeterminismTests.cs`:
```csharp
using System.Collections.Generic;
using System.Numerics;
using NeonPinball.Sim;
using Xunit;
public class DeterminismTests {
    private static (List<Vector2> path, double score) Run() {
        var rect = new BoardRect(0, 0, 200, 400);
        var pegs = new[] {
            new Peg(0, new Vector2(60, 120), 8, 5),
            new Peg(1, new Vector2(140, 160), 8, 5),
            new Peg(2, new Vector2(100, 220), 8, 5),
        };
        var cfg = new SimConfig { Gravity = new Vector2(0,500), MaxSpeed = 2000,
                                  Restitution = 0.85f, TangentKeep = 1f, Dt = 1f/120f };
        var sim = new BallSimulation(rect, pegs, cfg);
        var scorer = new Scorer(pegs);
        var ball = EntryResolver.MakeBall(BoardEdge.Top, 0.42f, 0.15f, 280f, 5f, rect);
        var path = new List<Vector2>(); var ev = new List<SimEvent>();
        for (int i = 0; i < 1000 && ball.Alive; i++) { sim.Step(ref ball, ev); path.Add(ball.Pos); }
        return (path, scorer.ScoreLaunch(ev));
    }

    [Fact] public void SameInputs_ProduceIdenticalResult() {
        var a = Run(); var b = Run();
        Assert.Equal(a.score, b.score);
        Assert.Equal(a.path.Count, b.path.Count);
        for (int i = 0; i < a.path.Count; i++) Assert.Equal(a.path[i], b.path[i]); // 逐位一致
    }
}
```

- [ ] **Step 2: 跑测试验证通过（无需新代码）**

Run: `dotnet test --filter DeterminismTests`
Expected: PASS（若失败说明引入了非确定性，须排查）

- [ ] **Step 3: 跑全量测试**

Run: `dotnet test NeonPinball.sln`
Expected: 全部 PASS

- [ ] **Step 4: Commit**

```bash
git add tests/DeterminismTests.cs
git commit -m "test(sim): determinism replay guard"
```

---

## Task 11：Godot 游戏工程接入 Sim

> ⚠️ **Godot .NET 常见坑（动手前先读）**
> - **必须用 Godot ".NET" 版**（Task -1 Step 2），标准版无法编译 C#。
> - **改了 C# 必须先 `dotnet build`（或 Godot 内 Build 按钮）再 F5**——Godot 跑的是已编译的程序集，不会自动热编译。
> - 首次新建 C# 项目后，Godot 会生成 `.csproj`/`.sln`；**手动加 `<ProjectReference>` 引用 Sim 后**要重新 build 一次。
> - 节点脚本类名/文件名建议一致；挂脚本的节点类型要和脚本基类匹配（如 `BoardView : Node2D` 必须挂在 `Node2D` 上）。
> - Rider 调试需选 **Godot 运行配置**；断点不命中通常是没 build 或附加到了错误进程。
> - `[Export]` 字段改动后，已存在场景里的旧值不会自动更新，必要时在 Inspector 重设。

**Files:**
- Create: `game/project.godot`、`game/NeonPinball.csproj`
- Modify: `NeonPinball.sln`

- [ ] **Step 1: 用 Godot 创建 .NET 项目**

在 Godot 编辑器：新建项目到 `game/`，语言选 C#（生成 `project.godot` 与 `.csproj`）。然后编辑 `game/NeonPinball.csproj` 加入对 Sim 的引用：
```xml
  <ItemGroup>
    <ProjectReference Include="../sim/NeonPinball.Sim.csproj" />
  </ItemGroup>
```

- [ ] **Step 2: 把游戏工程加入解决方案**

Run: `dotnet sln NeonPinball.sln add game/NeonPinball.csproj`
Expected: `Project ... added`

- [ ] **Step 3: 构建确认 Godot 工程能引用 Sim**

Run: `dotnet build game/NeonPinball.csproj`
Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add game/ NeonPinball.sln
git commit -m "chore(game): Godot .NET project referencing Sim"
```

---

## Task 12：棋盘渲染 + 主循环（accumulator + 插值）

**Files:**
- Create: `game/scenes/Board.tscn`、`game/view/BoardView.cs`

- [ ] **Step 1: 实现 BoardView（生成测试钉阵 + 定步长循环 + 插值渲染）**

`game/view/BoardView.cs`:
```csharp
using System.Collections.Generic;
using Godot;
using Sim = NeonPinball.Sim;
using SVec = System.Numerics.Vector2;

public partial class BoardView : Node2D {
    private Sim.BoardRect _rect;
    private Sim.Peg[] _pegs = System.Array.Empty<Sim.Peg>();
    private Sim.BallSimulation _sim = null!;
    private Sim.Scorer _scorer = null!;

    private Sim.Ball _ball; private bool _hasBall;
    private SVec _prevPos, _currPos;
    private readonly List<Sim.SimEvent> _events = new();
    private double _acc;
    private const double Dt = 1.0 / 120.0;

    public override void _Ready() {
        _rect = new Sim.BoardRect(0, 0, 540, 900);
        _pegs = BuildHoneycomb();
        var cfg = new Sim.SimConfig {
            Gravity = new SVec(0, 1400), MaxSpeed = 4000,
            Restitution = 0.82f, TangentKeep = 0.98f, Dt = (float)Dt
        };
        _sim = new Sim.BallSimulation(_rect, _pegs, cfg);
        _scorer = new Sim.Scorer(_pegs);
    }

    private Sim.Peg[] BuildHoneycomb() {
        var list = new List<Sim.Peg>();
        int id = 0; int rows = 8, cols = 7; float spacing = 64, margin = 60;
        for (int r = 0; r < rows; r++) {
            float y = margin + 140 + r * spacing;
            float xOff = (r % 2) * spacing * 0.5f;
            for (int c = 0; c < cols; c++) {
                float x = margin + xOff + c * spacing;
                if (x > _rect.Right - margin) continue;
                list.Add(new Sim.Peg(id++, new SVec(x, y), 10f, 5f)); // id==索引
            }
        }
        return list.ToArray();
    }

    // 由 InputController 调用：发射一颗球
    public void Launch(Sim.Ball ball) {
        _ball = ball; _hasBall = true;
        _prevPos = _currPos = ball.Pos; _events.Clear();
    }

    public Sim.BoardRect Rect => _rect;
    public Sim.BallSimulation Sim => _sim;

    public override void _Process(double delta) {
        if (_hasBall) {
            _acc += delta;
            while (_acc >= Dt) {
                _prevPos = _ball.Pos;
                _sim.Step(ref _ball, _events);
                _currPos = _ball.Pos;
                _acc -= Dt;
                if (!_ball.Alive) {
                    double s = _scorer.ScoreLaunch(_events);
                    GetNode<Hud>("Hud").AddScore(s);
                    _hasBall = false; _acc = 0; break;
                }
            }
        }
        QueueRedraw();
    }

    public override void _Draw() {
        // 钉
        foreach (var peg in _pegs)
            DrawCircle(new Vector2(peg.Pos.X, peg.Pos.Y), peg.Radius, new Color(0.2f,0.9f,1f));
        // 球（插值）
        if (_hasBall) {
            float a = (float)(_acc / Dt);
            var p = _prevPos + (_currPos - _prevPos) * a;
            DrawCircle(new Vector2(p.X, p.Y), _ball.Radius, new Color(1f,0.3f,0.8f));
        }
    }
}
```

- [ ] **Step 2: 建场景 Board.tscn**

在 Godot：新建场景，根节点 `Node2D` 挂 `BoardView.cs`；添加子节点 `Hud`（Task 14 实现脚本，先建空 `CanvasLayer` 命名 `Hud`）与 `InputController`（Task 13）。设为主场景。

- [ ] **Step 3: 手动验证（落球 + 弹跳 + 插值流畅）**

Run: 在 Godot 里 F5 运行；临时在 `_Ready` 末尾加 `Launch(EntryResolver.MakeBall(BoardEdge.Top,0.5f,0f,300,8,_rect));` 看球是否从顶部落下、撞钉弹跳、最终从底部消失、移动顺滑无抖动。验证后移除该临时行。
Expected: 球确定性下落弹跳、视觉顺滑。

- [ ] **Step 4: Commit**

```bash
git add game/scenes/Board.tscn game/view/BoardView.cs
git commit -m "feat(game): board rendering + fixed-step loop with interpolation"
```

---

## Task 13：输入——三边拖动入口 + 瞄准 + 预测线 + 发射

**Files:**
- Create: `game/view/InputController.cs`
- Modify: `game/view/BoardView.cs`（暴露预测线绘制）

- [ ] **Step 1: BoardView 增加预测线状态与绘制**

在 `game/view/BoardView.cs` 增加字段与绘制（在 `_Draw` 末尾追加预测线）：
```csharp
    public List<Vector2> PredictionPts = new();
    // 在 _Draw 末尾追加：
    // for (int i = 1; i < PredictionPts.Count; i++)
    //     DrawLine(PredictionPts[i-1], PredictionPts[i], new Color(1,1,1,0.4f), 2);
```
将上面注释的两行实际加入 `_Draw` 方法末尾（去掉注释符）。

- [ ] **Step 2: 实现 InputController**

`game/view/InputController.cs`:
```csharp
using System.Collections.Generic;
using Godot;
using Sim = NeonPinball.Sim;
using SVec = System.Numerics.Vector2;

public partial class InputController : Node {
    [Export] public NodePath BoardPath = null!;
    private BoardView _board = null!;
    private Sim.BoardEdge _edge = Sim.BoardEdge.Top;
    private float _t = 0.5f, _aim = 0f, _speed = 1500f;

    public override void _Ready() => _board = GetNode<BoardView>(BoardPath);

    public override void _Process(double delta) {
        var m = _board.GetLocalMousePosition();
        // 鼠标横向 → 顶边入口位置 t；纵向相对中心 → 瞄准偏移（原型够用）
        var r = _board.Rect;
        _t = Mathf.Clamp((m.X - r.Left) / r.Width, 0f, 1f);
        _aim = Mathf.Clamp((m.X - (r.Left + r.Width*0.5f)) / (r.Width*0.5f), -1f, 1f) * 1.2f;

        var start = Sim.EntryResolver.MakeBall(_edge, _t, _aim, _speed, 8f, r);
        var pts = Sim.TrajectoryPredictor.Predict(_board.Sim, start, 60);
        _board.PredictionPts = ToGodot(pts);
    }

    public override void _UnhandledInput(InputEvent e) {
        if (e is InputEventKey { Pressed: true, Keycode: Key.Tab })
            _edge = (Sim.BoardEdge)(((int)_edge + 1) % 3);     // 切换三边
        if (e is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left }) {
            var r = _board.Rect;
            _board.Launch(Sim.EntryResolver.MakeBall(_edge, _t, _aim, _speed, 8f, r));
        }
    }

    private static List<Vector2> ToGodot(List<SVec> pts) {
        var o = new List<Vector2>(pts.Count);
        foreach (var p in pts) o.Add(new Vector2(p.X, p.Y));
        return o;
    }
}
```
> 原型期入口/瞄准用鼠标横向映射；后续再做沿三边真正拖动的精细 UI（设计 §6.5）。

- [ ] **Step 3: 接线**

在 `Board.tscn` 选中 `InputController` 节点，把 `BoardPath` 指向 `BoardView` 根节点。

- [ ] **Step 4: 手动验证（预测线随鼠标动 + 点击发射命中预测）**

Run: F5；移动鼠标看白色预测线实时更新；按 Tab 切换入口边；左键发射，球应**沿预测线轨迹**飞行（确定性 → 实际=预测）。
Expected: 预测线与实际弹道一致；三边可切换。

- [ ] **Step 5: Commit**

```bash
git add game/view/InputController.cs game/view/BoardView.cs game/scenes/Board.tscn
git commit -m "feat(game): edge entry + aim + live prediction line + launch"
```

---

## Task 14：HUD + 基础 juice（分数 / 命中粒子）

**Files:**
- Create: `game/view/Hud.cs`
- Modify: `game/view/BoardView.cs`（命中时触发粒子）

- [ ] **Step 1: 实现 Hud**

`game/view/Hud.cs`:
```csharp
using Godot;
public partial class Hud : CanvasLayer {
    private double _score;
    private Label _label = null!;
    public override void _Ready() {
        _label = new Label { Position = new Vector2(20, 20) };
        _label.AddThemeFontSizeOverride("font_size", 28);
        AddChild(_label);
        Update();
    }
    public void AddScore(double s) { _score += s; Update(); }
    private void Update() => _label.Text = $"SCORE  {_score:0}";
}
```

- [ ] **Step 2: 命中粒子（事件驱动，纯视觉）**

在 `game/view/BoardView.cs` 的 `_Process` 内步进循环里，处理新产生的事件触发粒子（在 `_sim.Step` 之后读取 `_events` 新增项）。最简实现：每次 `PegHit` 在该位置画一个短暂闪光。新增字段与逻辑：
```csharp
    private readonly List<(Vector2 pos, float ttl)> _flashes = new();
    private int _eventCursor;
    // 在 while 循环内 _sim.Step 之后追加：
    //   for (; _eventCursor < _events.Count; _eventCursor++)
    //       if (_events[_eventCursor].Type == NeonPinball.Sim.SimEventType.PegHit) {
    //           var ep = _events[_eventCursor].Pos; _flashes.Add((new Vector2(ep.X, ep.Y), 0.15f)); }
    // 发射新球时（Launch 内）重置 _eventCursor = 0; _flashes.Clear();
    // _Process 末尾衰减：for (int i=_flashes.Count-1;i>=0;i--){ var f=_flashes[i]; f.ttl-=(float)delta;
    //     if (f.ttl<=0) _flashes.RemoveAt(i); else _flashes[i]=f; }
    // _Draw 末尾：foreach (var f in _flashes)
    //     DrawCircle(f.pos, 16, new Color(1,1,0.6f, f.ttl/0.15f*0.8f));
```
将以上注释逻辑实际写入对应位置（`Launch` 重置、`_Process` 步进后采集与末尾衰减、`_Draw` 末尾绘制）。

- [ ] **Step 3: 手动验证（命中有反馈 + 分数累加）**

Run: F5；发射后命中钉子有黄色闪光、底部消失后 `SCORE` 增加对应基础分。
Expected: 有打击反馈、分数正确累加。

- [ ] **Step 4: Commit**

```bash
git add game/view/Hud.cs game/view/BoardView.cs
git commit -m "feat(game): HUD score + hit-flash juice"
```

---

## Task 15：里程碑 1 验收（go/no-go 手感评估）

**Files:** 无（评估 + 记录）

- [ ] **Step 1: 跑全量自动化测试**

Run: `dotnet test NeonPinball.sln`
Expected: 全部 PASS（含确定性守卫）。

- [ ] **Step 2: 手感评估清单（手动）**

逐项主观打分（1–5），目标是回答"发射一颗球弹得爽不爽"：
- 弹跳轨迹是否可读、可预判（预测线是否真帮到瞄准）？
- 三边入口是否带来不同且有意思的弹道？
- 命中反馈（闪光/即时性）是否"脆"？
- 是否产生"想再来一发"的冲动？

- [ ] **Step 3: 记录结论**

在仓库根新建 `MILESTONE1_VERDICT.md`，写下评分、问题清单、go/no-go 结论与下一步（手感不达标→优先调 `SimConfig` 参数与预测线长度；达标→进入里程碑 2：三类积木 + 门 + round loop）。

- [ ] **Step 4: Commit**

```bash
git add MILESTONE1_VERDICT.md
git commit -m "docs: milestone 1 go/no-go verdict"
```

---

## 附录：手感调参起步表（Task 15 go/no-go 用）

`SimConfig` 初始建议值（棋盘约 540×900，钉半径 10，球半径 8；最终以手感为准）：

| 参数 | 起始值 | 含义 | 偏大/偏小的体感 |
|---|---|---|---|
| `Gravity.Y` | 1400 | 下落加速度 | 太大→球砸太快难读；太小→飘、节奏拖 |
| `MaxSpeed` | 4000 | 限速上限 | 太大→易隧穿感/失控；太小→加速门后期无力 |
| `Restitution` | 0.82 | 弹性（法向保留） | →1 越弹越久越乱；过低→一两下就沉底没戏 |
| `TangentKeep` | 0.98 | 擦边切向保留 | 低→黏滞拖沓；高→顺滑但更难控 |
| `Dt` | 1/120 | 逻辑步长 | 不要动（动了影响一切确定性基线） |
| 发射初速 `speed` | 1500 | 入场速度 | 太大→直接砸穿少弹跳；太小→软绵 |
| 预测线步数 | 60 | 预测前瞻长度 | 太长→后段因混沌失真误导；太短→瞄不准 |

**"手感不对就调哪个" 速查：**
- 球**太飘/弹太久不落** → ↓`Restitution`、↑`Gravity.Y`。
- 球**太沉/一两下就死** → ↑`Restitution`、↓`Gravity.Y`、↓发射 `speed`。
- **瞄不准/预测线没用** → 预测线本就只前段准（混沌）；缩短预测步数到弹道开始发散前，或降低初速让前段更可控。
- **像抽奖、没掌控感** → 检查确定性是否真生效（重开同输入轨迹应一致）；加大棋盘"漏斗/通道"引导（设计 §6）；考虑加飞行微操（里程碑 2，本里程碑可不做）。
- **打击不脆** → 加强命中闪光/缩短延迟（Task 14），后续里程碑再加屏震/升调音效。

> 调参流程：先**关闭命中粒子**只看裸弹道找基础手感，确定 `Gravity/Restitution/speed` 三者后再开 juice 评估"脆度"。

---

## 自检备注（计划作者）

- **Spec 覆盖**：里程碑 1 范围（确定性物理 / 三边入口 / 预测线 / 基础计分 / 基础 juice）均有任务覆盖；门/触发器/商店/区轮明确排除，留里程碑 2+。
- **类型一致性**：`Ball`、`Peg(Id==数组索引)`、`SimEvent`、`SimConfig`、`BoardEdge`、`BallSimulation.Step(ref Ball,List<SimEvent>)`、`EntryResolver.MakeBall(...)`、`TrajectoryPredictor.Predict(sim,start,steps)`、`Scorer.ScoreLaunch(events)` 在各任务签名一致。
- **确定性**：Sim 仅依赖 `System.Numerics`，无系统时间/全局随机；Task 10 守卫。
- **手感优先**：Task 12–15 把"可玩 + 可评估"作为终点，符合 go/no-go 目的。
