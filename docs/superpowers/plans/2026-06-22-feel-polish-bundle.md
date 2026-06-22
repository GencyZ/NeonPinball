# 手感打磨打包（#2）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** 五个 view 层打磨：① 押注 HUD 按钮 ② boss 预告更醒目 ③ ticker 飞行中显示 ×2 待定 ④ 过渡非阻塞（补钉完成即可发射）⑤ 商店空装备槽隐藏。

**Architecture:** 纯 view/HUD，零侵入 sim/计分/确定性。无新单测，靠场景冒烟 + 全套保持 268 绿。

**Tech Stack:** Godot 4.6.3 纯 GDScript，GUT 9.x。

---

## Background（已核对）

- 项目根 `D:/NeonPinball/game/`。Godot `/d/Program/Godot/godot`。缩进 **TAB**。**基线 268 全绿，39 脚本。** 不 push、不新建分支。
- `view/hud.gd`：
  - 成员有 `var _label_gamble: Label`（已存在）；`signal shop_*`。
  - `_ready` 里 `_label_gamble = _make_label(Vector2(490, 140), 16, Color(1.0, 0.55, 0.2))`、末尾 `set_gamble_label(false)`。
  - `_build_shop_panel`：`_shop_boss_label`（行 88-93，font 17、`Color(1.0,0.5,0.3)`）；局部 `var equip_label`（行 111-116，"— 已装备触发器（点击卖出）—"）。
  - `show_shop(offerings, money, reroll_cost=-1, boss_preview="", equipped=[])`（行 186 设 boss label）。
  - `set_gamble_label(armed)`（押注状态 label）。
- `view/board_view.gd`：
  - `_ready` 已有 `$Hud.shop_*` connect 段。
  - `toggle_gamble()`（已存在）、`_gamble_active`（已存在）、`_has_ball`、`_is_transitioning`。
  - `_draw()` ticker 段（992-1000）：`var sv := int(round(_score_ticker.value()))` → `if sv > 0:` 画居中分数 `stxt` 于 `_rect.position + Vector2(270 - tw*0.5, 60)`，font `fsz`。其后 `_draw_walls()`（1001）。
  - `_on_peg_exit_done()`（持久棋盘版）：`_dying_pegs.clear()` → `_topup_pegs` → 重排 id → `_sim=_make_sim` → `_rebuild_wall_segs(false)` → 设 `_peg_enter_ttls` → 计时器 `_on_peg_enter_done`。`_on_peg_enter_done` 清 ttls + `_is_transitioning=false`。

---

## Task 1：HUD —— 押注按钮 + boss 预告醒目 + 空装备隐藏

**Files:** Modify `view/hud.gd`

- [ ] **Step 1: 加信号 + 成员**
找到 `signal shop_sell_trigger_pressed(index: int)`，其**后**加：
```gdscript
signal gamble_toggle_pressed
```
找到 `var _label_gamble: Label`，其**后**加：
```gdscript
var _gamble_btn: Button
var _equip_label: Label
```

- [ ] **Step 2: `_ready` 创建押注按钮** —— 找到 `_label_gamble = _make_label(Vector2(490, 140), 16, Color(1.0, 0.55, 0.2))`，其**后**加：
```gdscript
	_gamble_btn = Button.new()
	_gamble_btn.position = Vector2(490, 162)
	_gamble_btn.add_theme_font_size_override(&"font_size", 14)
	_gamble_btn.pressed.connect(func(): gamble_toggle_pressed.emit())
	add_child(_gamble_btn)
```

- [ ] **Step 3: boss 预告更醒目** —— 在 `_build_shop_panel` 找到：
```gdscript
	_shop_boss_label.add_theme_font_size_override(&"font_size", 17)
	_shop_boss_label.modulate = Color(1.0, 0.5, 0.3)
```
改为：
```gdscript
	_shop_boss_label.add_theme_font_size_override(&"font_size", 22)
	_shop_boss_label.modulate = Color(1.0, 0.65, 0.2)
```

- [ ] **Step 4: equip 标题改成员 + 可隐藏** —— 在 `_build_shop_panel` 找到：
```gdscript
	var equip_label := Label.new()
	equip_label.text = "— 已装备触发器（点击卖出）—"
	equip_label.add_theme_font_size_override(&"font_size", 14)
	equip_label.modulate = Color(0.7, 0.9, 1.0)
	equip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(equip_label)
```
把所有 `equip_label` 改为 `_equip_label`（赋值给成员，去掉 `var`），即：
```gdscript
	_equip_label = Label.new()
	_equip_label.text = "— 已装备触发器（点击卖出）—"
	_equip_label.add_theme_font_size_override(&"font_size", 14)
	_equip_label.modulate = Color(0.7, 0.9, 1.0)
	_equip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_equip_label)
```

- [ ] **Step 5: `show_shop` 隐藏空装备标题** —— 在 `show_shop` 末尾（满槽 hint 设置那段附近）加：
```gdscript
	_equip_label.visible = equipped.size() > 0
```

- [ ] **Step 6: `set_gamble_label` 同步按钮** —— 把整个 `set_gamble_label` 替换为：
```gdscript
func set_gamble_label(armed: bool) -> void:
	if armed:
		_label_gamble.text = "🎲 押注:开 ×2/0  [G]"
		_label_gamble.modulate = Color(1.0, 0.85, 0.2)
	else:
		_label_gamble.text = "🎲 押注:关  [G]"
		_label_gamble.modulate = Color(0.55, 0.55, 0.55)
	if _gamble_btn != null:
		_gamble_btn.text = "🎲 押注 ON" if armed else "🎲 押注 OFF"
		_gamble_btn.modulate = Color(1.0, 0.85, 0.2) if armed else Color(0.8, 0.8, 0.8)
```
> `set_gamble_label(false)` 在 `_ready` 末尾调用（已存在），那时 `_gamble_btn` 已在 Step 2 创建（Step 2 在 `_ready` 中、早于末尾的 `set_gamble_label(false)`）；`!= null` 守卫再加一层保险。

- [ ] **Step 7: 场景冒烟 + 全套**
`/tmp/fp.gd`（load+instantiate board.tscn，print BOARD_OK/FAIL）→ `/d/Program/Godot/godot --headless --path . -s /tmp/fp.gd 2>&1 | grep -iE "BOARD_OK|BOARD_FAIL|Parse Error|SCRIPT ERROR"` 期望 BOARD_OK，`rm -f /tmp/fp.gd`。全套仍 **268**。

- [ ] **Step 8: 提交**
```bash
git -C D:/NeonPinball/game add view/hud.gd
git -C D:/NeonPinball/game commit -m "polish: gamble HUD button, prominent boss telegraph, hide empty equip label"
```

---

## Task 2：board_view —— 连接押注按钮 + ticker ×2 待定 + 过渡非阻塞

**Files:** Modify `view/board_view.gd`

- [ ] **Step 1: 连接押注按钮信号** —— 在 `_ready` 找到 `$Hud.shop_sell_trigger_pressed.connect(sell_equipped_trigger)`（或任一 `$Hud.shop_*` connect 行），其**后**加：
```gdscript
	$Hud.gamble_toggle_pressed.connect(toggle_gamble)
```

- [ ] **Step 2: ticker ×2 待定指示** —— 在 `_draw()` 的 ticker 段，找到画分数的 `draw_string(tf, _rect.position + Vector2(270.0 - tw * 0.5, 60.0), stxt, ...)`（在 `if sv > 0:` 块内），在该 `if sv > 0:` 块**之后**（与 `var sv := ...` 同缩进）插入：
```gdscript
		if _gamble_active and _has_ball:
			var gf := ThemeDB.fallback_font
			var gtxt := "GAMBLE x2?"
			var gw := gf.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(gf, _rect.position + Vector2(270.0 - gw * 0.5, 96.0),
				gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.2))
```
> 用 ASCII "GAMBLE x2?"（board draw_string 用 fallback_font，避免 CJK/emoji 不渲染）。位置在分数(y=60)下方 y=96。

- [ ] **Step 3: 过渡非阻塞（补钉完成即解禁）** —— 在 `_on_peg_exit_done()` 找到 `_rebuild_wall_segs(false)`，在其**后**加：
```gdscript
	_is_transitioning = false   # 棋盘已就绪（存活+补钉），立即可发射；新钉的放大动画非阻塞继续
```
> 退场期(0.4s 缩小被撞钉)仍阻塞；补钉/重建 sim 完成后立即解禁，新钉的 enter 动画纯视觉非阻塞。`_on_peg_enter_done` 不变（再 set false 无害）。

- [ ] **Step 4: 验证场景加载 + 全套**
(a) 场景冒烟（同 T1 的 `/tmp/fp.gd`）→ BOARD_OK，无新增 Parse/SCRIPT error，`rm -f /tmp/fp.gd`。
(b) 全套 → **268** 全绿。若失败/解析错修到绿。

> 实机验收：① HUD 有"🎲 押注"按钮、点击与 G 等效、状态同步 label ② boss 预告更大更醒目 ③ 押注球飞行中分数下方显示 "GAMBLE x2?" ④ 持久棋盘落定后约 0.4s（补钉完成）即可瞄下一发、新钉边长边能发 ⑤ 商店 0 装备时不显"已装备"标题。

- [ ] **Step 5: 提交**
```bash
git -C D:/NeonPinball/game add view/board_view.gd
git -C D:/NeonPinball/game commit -m "polish: wire gamble button, ticker x2-pending indicator, non-blocking peg transition"
```

---

## 自检清单
- [ ] **覆盖**：押注按钮(T1 Step1-2/6 + T2 Step1) ✓；boss 醒目(T1 Step3) ✓；ticker ×2(T2 Step2) ✓；过渡非阻塞(T2 Step3) ✓；空装备隐藏(T1 Step4-5) ✓
- [ ] **占位符**：每步完整代码 ✓
- [ ] **一致性**：信号 `gamble_toggle_pressed` 声明(T1)/emit(T1 按钮)/connect(T2) 一致；`_gamble_btn`/`_equip_label` 声明+用一致；`set_gamble_label` 按钮 `!=null` 守卫；`_is_transitioning` 解禁时机正确（exit_done 后板已就绪）✓
- [ ] **范围**：仅 5 项打磨；漏斗物理改动**不在本计划**（单独处理）；无 sim/计分改动 ✓

## 备注
- 过渡非阻塞反转持久棋盘当时的"保留阻塞"决策（本次打磨意图，用户 2026-06-22 认可方向）。
- 押注按钮位置 (490,162) 首版，实机若与瞄准/发射点击冲突再调位。
- ticker 指示用 ASCII 防字体缺字；后续可换更显眼样式（Backlog）。
