extends GutTest

const NeonEnvScript := preload("res://view/neon_environment.gd")

func test_make_environment_enables_glow() -> void:
	var env := NeonEnvScript.make_environment()
	assert_true(env is Environment, "返回 Environment")
	assert_true(env.glow_enabled, "Glow 已开启")

func test_make_environment_additive_threshold() -> void:
	var env := NeonEnvScript.make_environment()
	assert_eq(env.glow_blend_mode, Environment.GLOW_BLEND_MODE_ADDITIVE, "加色混合")
	assert_almost_eq(env.glow_hdr_threshold, 1.0, 1e-4, "阈值 1.0（普通内容不糊）")

func test_make_environment_canvas_background() -> void:
	var env := NeonEnvScript.make_environment()
	assert_eq(env.background_mode, Environment.BG_CANVAS, "2D 用 Canvas 背景模式")
