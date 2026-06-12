extends GutTest

const SfxControllerScript := preload("res://juice/sfx_controller.gd")
const SfxSynthScript := preload("res://juice/sfx_synth.gd")

func test_pool_created_on_ready() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)   # 触发 _ready
	assert_eq(sfx._players.size(), SfxControllerScript.POOL_SIZE, "池按 POOL_SIZE 创建")

func test_play_hit_sets_pitch_from_combo() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_hit(1)   # 用掉 index 0
	assert_almost_eq(sfx._players[0].pitch_scale,
		SfxSynthScript.pitch_scale_for_combo(1), 1e-4, "play_hit 设置正确音高")

func test_play_hit_higher_combo_higher_pitch() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_hit(1)   # index 0
	sfx.play_hit(6)   # index 1
	assert_gt(sfx._players[1].pitch_scale, sfx._players[0].pitch_scale,
		"连击越高音高越高")

func test_play_settle_low_pitch() -> void:
	var sfx = SfxControllerScript.new()
	add_child_autofree(sfx)
	sfx.play_settle()
	assert_lt(sfx._players[0].pitch_scale, 1.0, "落定为低音")
