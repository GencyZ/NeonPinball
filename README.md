# NeonPinball（工作标题：OVERCLOCK / 超频）

一款「再来一把」的**霓虹弹珠 × Roguelike 构筑**独立游戏：每一发弹球引爆一连串霓虹连锁，看着分数指数炸开。
定位独立精品、买断制、无内购；首发 Steam PC（预留竖屏便于移动移植）。

## 文档

- 游戏设计：[docs/superpowers/specs/2026-06-09-neon-pinball-roguelike-deckbuilder-design.md](docs/superpowers/specs/2026-06-09-neon-pinball-roguelike-deckbuilder-design.md)
- 技术设计（含附录 A–H 实现细节）：[docs/superpowers/specs/2026-06-09-neon-pinball-tech-design.md](docs/superpowers/specs/2026-06-09-neon-pinball-tech-design.md)
- 里程碑 1 实现计划（TDD，16 个任务）：[docs/superpowers/plans/2026-06-09-milestone1-pinball-prototype.md](docs/superpowers/plans/2026-06-09-milestone1-pinball-prototype.md)

## 技术栈

Godot 4.x（**.NET / Mono 版**）+ C#（.NET 8）+ Rider + xUnit。
核心模拟层为纯 C#（仅依赖 `System.Numerics`，确定性物理，可 headless 单测），与 Godot 渲染层严格分离。

## 规划中的工程结构

```
sim/    NeonPinball.Sim.csproj   纯 C# 模拟层（物理/计分/入口门/棋盘生成）
tests/  NeonPinball.Tests.csproj xUnit 单元 + 确定性回放测试
game/   Godot .NET 项目          渲染/输入/juice（引用 sim）
docs/   设计 / 技术 / 计划 文档
```

## 从哪开始

里程碑 1 是 **go/no-go**：先验证"发射一颗球弹得爽不爽"。

- **现在就能做**：里程碑 1 计划的 **Task 0–10**（`sim/` + `tests/`）是纯 C#，只需 .NET 8 SDK，不依赖 Godot。
- **需要 Godot 后**：Task 11+（`game/` 渲染/输入/juice）。安装见计划的 **Task -1：环境准备**（务必下 Godot 的 .NET 版）。

执行计划：可交给 Claude Code 用 `executing-plans` / `subagent-driven-development` 逐任务推进，或人工照计划（每个任务含完整代码与命令）实现。
