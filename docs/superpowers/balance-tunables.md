# 平衡可调参数（Balance Tunables）

**用途：** 集中记录需要实机试玩微调的数值/机制开关，含当前值、位置、改法。每项调整后**同步更新对应单测断言**。

状态：✅已上线 · 📝spec待定（值在实现时落到代码）

---

## 连击计分 Combo→×倍率 ✅（首版，待试玩调）

| 参数 | 当前值 | 位置 | 说明 / 改法 |
|---|---|---|---|
| `COMBO_RATE` | 0.12 | `scoring/combo_score.gd` | 每命中一钉的 ×倍率增量 |
| `COMBO_CAP` | 5.0 | `scoring/combo_score.gd` | combo ×倍率封顶（34 钉触顶）|
| `COMBO_MIN_PEGS` | 2 | `scoring/combo_score.gd` | 低于此命中数不给加成 |
| 配额基数 | 90.0 | `run/run_manager.gd` `quota_of`（原 50）| 改后同步 `tests/test_run_manager.gd` 两个配额断言 |
| 落定揭示震斜率/封顶 | 0.12 / 0.6 | `juice/juice_controller.gd` `on_settle_combo` | 越爆震越强的强度 |

> 最终审查提示：配额×1.8 vs combo 均值≈×2.2，可能偏松，后续或调到 ~110~120。实机后定。

---

## 目标钉 / 每轮目标感 📝（spec 已写，值在实现时落地；机制开关待你最终确认）

**数值（首版）**
| 参数 | 首版值 | 说明 |
|---|---|---|
| 目标钉数量 | `clamp(3+(区-1)/2, 3, 6)` | 1区3 / 3区4 / 5区5 / 7区6 |
| 目标钉 HP | `clamp(2+(区-1)/3, 2, 3)` | 1~3区 HP2，4~8区 HP3；**HP=1 即一击清** |
| 清光奖励金钱 | +5 | 清光所有目标钉的额外金钱 |

**机制开关**
| 开关 | 决定 | 备注 |
|---|---|---|
| 目标钉持久 | ✅ 跨本轮 5 发持久（填充钉照常重生）| 不持久则"清光"无意义 |
| 清光时机 | ✅ **只给奖励 + 高潮，不提前过关** | 清光设 `targets_done=true` + ALL CLEAR 高潮 + 奖励；**回合仍发完 5 球**，结束时按 `targets_done 或 够配额` 判定（用户 2026-06-15 定）|
| 与配额关系 | ✅ 双路：清光 或 够配额 | targets_done 在发完时也算赢 |

实现落地位置（计划时定）：`run/round_goal.gd`（`target_count_for`/`target_hp_for`）、`run/run_manager.gd`（`targets_done` 赢条件 + 奖励）、`view/board_view.gd`（目标钉生成/HP/全清）。

---

## 其他计划中特性的可调点（实现时落地）📝

| 特性 | 主要可调点 | 文档 |
|---|---|---|
| 霓虹边框追逐光 | 热度充能 `HEAT_PER_HIT`、冷却 `DECAY_RATE`、脉冲数/流速/亮度曲线、heat_color 端点 | `specs/2026-06-12-neon-walls-chase-light-design.md` |
| 蓄力发射（想法）| 初速度区间 min/max | 路线图 |
| 推板 Nudge（想法）| 每轮次数、推力大小 | 路线图 |

---

## 调参纪律

- 纯函数里的值改完，对应单测断言一起改（如配额、combo 曲线）。
- 机制开关改动会动 RunManager 赢条件 / board_view 钉生成，属代码改动，走正常流程。
- 实机试玩后把"定稿值"回填到这里，并标注 ✅。
