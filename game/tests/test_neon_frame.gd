extends GutTest

const NeonFrameScript := preload("res://juice/neon_frame.gd")

func test_heat_color_endpoints() -> void:
	assert_eq(NeonFrameScript.heat_color(0.0), NeonFrameScript.IDLE, "heat 0 = 霓虹青")
	assert_eq(NeonFrameScript.heat_color(1.0), NeonFrameScript.HOT, "heat 1 = 热粉")

func test_heat_color_not_white_at_max() -> void:
	var c := NeonFrameScript.heat_color(1.0)
	assert_lt(c.g, 0.5, "最烫不褪白：绿分量低")
	assert_lt(c.b, 0.9, "最烫不褪白：蓝分量不高")

func test_heat_color_trend() -> void:
	assert_lt(NeonFrameScript.heat_color(0.0).r, NeonFrameScript.heat_color(1.0).r, "R 随热度升")
	assert_gt(NeonFrameScript.heat_color(0.0).b, NeonFrameScript.heat_color(1.0).b, "B 随热度降")

func test_pulse_count_zero_when_calm() -> void:
	assert_eq(NeonFrameScript.pulse_count_for_heat(0.0), 0, "平静无脉冲")
	assert_eq(NeonFrameScript.pulse_count_for_heat(0.04), 0, "低于阈值无脉冲")

func test_pulse_count_monotonic_and_capped() -> void:
	assert_gte(NeonFrameScript.pulse_count_for_heat(0.05), 1, "过阈值至少 1 条")
	for n in range(0, 20):
		var lo := NeonFrameScript.pulse_count_for_heat(float(n) / 20.0)
		var hi := NeonFrameScript.pulse_count_for_heat(float(n + 1) / 20.0)
		assert_true(hi >= lo, "脉冲数单调不降 @%d" % n)
	assert_eq(NeonFrameScript.pulse_count_for_heat(1.0), 4, "封顶 4 条")

func test_speed_monotonic_and_range() -> void:
	assert_almost_eq(NeonFrameScript.speed_for_heat(0.0), 0.10, 1e-4, "平静流速 0.10")
	assert_almost_eq(NeonFrameScript.speed_for_heat(1.0), 0.60, 1e-4, "满热流速 0.60")
	assert_gt(NeonFrameScript.speed_for_heat(1.0), NeonFrameScript.speed_for_heat(0.0), "流速随热度升")

func test_brightness_monotonic_and_range() -> void:
	assert_almost_eq(NeonFrameScript.brightness_for_heat(0.0), 1.2, 1e-4, "平静亮度 1.2")
	assert_almost_eq(NeonFrameScript.brightness_for_heat(1.0), 3.0, 1e-4, "满热亮度 3.0")
	assert_gt(NeonFrameScript.brightness_for_heat(1.0), NeonFrameScript.brightness_for_heat(0.0), "亮度随热度升")

func test_decay_heat() -> void:
	assert_almost_eq(NeonFrameScript.decay_heat(1.0, 2.0), 0.0, 1e-4, "满热 2 秒冷却到 0")
	assert_eq(NeonFrameScript.decay_heat(0.0, 1.0), 0.0, "不为负")
	assert_lt(NeonFrameScript.decay_heat(0.5, 0.1), 0.5, "随时间下降")

func test_point_at_square() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	assert_eq(NeonFrameScript.point_at(sq, 0.0), Vector2(0, 0), "s=0 起点")
	var p25 := NeonFrameScript.point_at(sq, 0.25)
	assert_almost_eq(p25.x, 1.0, 1e-4, "s=0.25 → (1,0).x")
	assert_almost_eq(p25.y, 0.0, 1e-4, "s=0.25 → (1,0).y")
	var p50 := NeonFrameScript.point_at(sq, 0.5)
	assert_almost_eq(p50.x, 1.0, 1e-4, "s=0.5 → (1,1).x")
	assert_almost_eq(p50.y, 1.0, 1e-4, "s=0.5 → (1,1).y")

func test_point_at_wraps() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	assert_eq(NeonFrameScript.point_at(sq, 1.0), NeonFrameScript.point_at(sq, 0.0), "s=1 绕回 s=0")

func test_point_at_degenerate() -> void:
	assert_eq(NeonFrameScript.point_at(PackedVector2Array([]), 0.5), Vector2.ZERO, "空折线 → 零向量")
	var one := PackedVector2Array([Vector2(3, 4)])
	assert_eq(NeonFrameScript.point_at(one, 0.7), Vector2(3, 4), "单点 → 该点")

func test_point_at_negative_s_wraps() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var a := NeonFrameScript.point_at(sq, -0.25)
	var b := NeonFrameScript.point_at(sq, 0.75)
	assert_almost_eq(a.x, b.x, 1e-4, "负 s 环绕 x")
	assert_almost_eq(a.y, b.y, 1e-4, "负 s 环绕 y")

func test_hue_spread_curve() -> void:
	assert_almost_eq(NeonFrameScript.hue_spread_for_heat(0.0), 0.1, 1e-4, "平静色带 0.1")
	assert_almost_eq(NeonFrameScript.hue_spread_for_heat(1.0), 0.5, 1e-4, "满热色带 0.5")
	assert_gt(NeonFrameScript.hue_spread_for_heat(1.0), NeonFrameScript.hue_spread_for_heat(0.0), "色带随热度变宽")

func test_bulb_color_cool_band_when_idle() -> void:
	for p in [0.0, 0.25, 0.5, 0.75]:
		var h: float = NeonFrameScript.bulb_color(p, 0.0, 0.0).h
		assert_between(h, 0.39, 0.61, "平静色相落冷带 @%.2f" % p)

func test_bulb_color_widens_with_heat() -> void:
	# 满热 spread=0.5：对蹄点 p=0/0.5 的色相分别为 0.0/0.5，相距 0.5 >> 0.3
	var h0: float = NeonFrameScript.bulb_color(0.0, 0.0, 1.0).h
	var h5: float = NeonFrameScript.bulb_color(0.5, 0.0, 1.0).h
	assert_gt(absf(h0 - h5), 0.3, "满热跨多色相")

func test_bulb_color_brightness_rises_and_hdr() -> void:
	var lo := NeonFrameScript.bulb_color(0.0, 0.0, 0.0)
	var hi := NeonFrameScript.bulb_color(0.0, 0.0, 1.0)
	var lo_max := maxf(maxf(lo.r, lo.g), lo.b)
	var hi_max := maxf(maxf(hi.r, hi.g), hi.b)
	assert_gt(hi_max, lo_max, "亮度随热度升")
	assert_gt(hi_max, 1.0, "满热 HDR (>1 触发 bloom)")

func test_bulb_color_saturated() -> void:
	assert_almost_eq(NeonFrameScript.bulb_color(0.3, 0.2, 0.5).s, 1.0, 1e-3, "饱和度 1")

func test_frame_hue_cool_band_idle() -> void:
	for p in [0.0, 0.25, 0.5, 0.75]:
		var h: float = NeonFrameScript.frame_hue(p, 0.0, 0.0, 0.0)
		assert_between(h, 0.39, 0.61, "平静窄冷带 @%.2f" % p)

func test_frame_hue_widens_with_heat() -> void:
	var h0: float = NeonFrameScript.frame_hue(0.0, 0.0, 0.0, 1.0)
	var h5: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.0, 1.0)
	assert_gt(absf(h0 - h5), 0.3, "满热跨多色相")

func test_frame_hue_cycles_with_hue_phase() -> void:
	var a: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.0, 0.0)
	var b: float = NeonFrameScript.frame_hue(0.5, 0.0, 0.25, 0.0)
	assert_gt(absf(a - b), 0.2, "hue_phase 推进 → 色带中心移动（变色）")

func test_frame_hue_flow_phase_shifts_position() -> void:
	# flow_phase 推进 → 同一 p 在冷带内的位置移动（local = fposmod(p+flow_phase)）
	var a: float = NeonFrameScript.frame_hue(0.0, 0.0, 0.0, 0.0)
	var b: float = NeonFrameScript.frame_hue(0.0, 0.5, 0.0, 0.0)
	assert_gt(absf(a - b), 0.05, "flow_phase 推进 → 冷带内位置移动")

func test_ambient_value_range_and_hdr() -> void:
	var seen_hi := 0.0
	for i in 40:
		var p := float(i) / 40.0
		var v0 := NeonFrameScript.ambient_value(p, 0.0, 0.0)
		assert_between(v0, 0.34, 1.51, "idle 值域 @%.2f" % p)
		seen_hi = maxf(seen_hi, NeonFrameScript.ambient_value(p, 0.0, 1.0))
	assert_gt(seen_hi, 1.0, "满热峰值 HDR >1")

func test_ambient_value_wave_moves() -> void:
	var a := NeonFrameScript.ambient_value(0.0, 0.0, 1.0)
	var b := NeonFrameScript.ambient_value(0.0, 0.25, 1.0)
	assert_gt(absf(a - b), 0.01, "波随相位移动")

func test_frame_color_saturated() -> void:
	assert_almost_eq(NeonFrameScript.frame_color(0.3, 0.1, 0.2, 0.5).s, 1.0, 1e-3, "饱和度 1")
