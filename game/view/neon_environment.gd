class_name NeonEnvironment extends RefCounted

# 代码构建开启 2D Glow 的 Environment（枚举常量编译期校验，比手写 .tres 稳）。
# 实际辉光强度需实机调，调整下面数值即可。
static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 1.0
	env.glow_strength = 1.2
	env.glow_bloom = 0.2
	return env
