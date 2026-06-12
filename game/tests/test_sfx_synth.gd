extends GutTest

const SfxSynthScript := preload("res://juice/sfx_synth.gd")

func test_first_hit_is_base_pitch() -> void:
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(1), 1.0, 1e-5,
		"第一击为基准音 pitch_scale=1.0")

func test_pitch_monotonic_non_decreasing() -> void:
	for n in range(1, 16):
		assert_true(SfxSynthScript.pitch_scale_for_combo(n + 1)
			>= SfxSynthScript.pitch_scale_for_combo(n),
			"音高随连击单调不降 @%d" % n)

func test_pitch_within_range() -> void:
	for n in range(1, 60):
		var p := SfxSynthScript.pitch_scale_for_combo(n)
		assert_between(p, 1.0, 4.0, "音高落在 [1.0,4.0] @%d" % n)

func test_pitch_second_step_is_pentatonic() -> void:
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(2),
		pow(2.0, 2.0 / 12.0), 1e-5, "第二档为五声第二音")

func test_pitch_caps_at_top() -> void:
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(50),
		SfxSynthScript.pitch_scale_for_combo(11), 1e-5, "超表长封顶")
	assert_almost_eq(SfxSynthScript.pitch_scale_for_combo(50), 4.0, 1e-5,
		"封顶值为 4.0（两个八度）")

func test_make_ping_returns_nonempty_wav() -> void:
	var s := SfxSynthScript.make_ping()
	assert_true(s is AudioStreamWAV, "返回 AudioStreamWAV")
	assert_gt(s.data.size(), 0, "波形数据非空")
	assert_eq(s.mix_rate, 22050, "默认采样率 22050")
