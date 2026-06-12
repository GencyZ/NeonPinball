extends GutTest
const JuiceControllerScript := preload("res://juice/juice_controller.gd")

func test_peg_hit_big_more_trauma_than_small() -> void:
	var a := JuiceControllerScript.new()
	var b := JuiceControllerScript.new()
	a.on_peg_hit(Vector2.ZERO, Color.RED, false)
	b.on_peg_hit(Vector2.ZERO, Color.RED, true)
	assert_gt(b.shake.trauma, a.shake.trauma)

func test_peg_hit_emits_particles() -> void:
	var jc := JuiceControllerScript.new()
	assert_eq(jc.particles.particles.size(), 0)
	jc.on_peg_hit(Vector2.ZERO, Color.RED, false)
	assert_gt(jc.particles.particles.size(), 0)

func test_big_emits_more_particles() -> void:
	var small := JuiceControllerScript.new()
	var big := JuiceControllerScript.new()
	small.on_peg_hit(Vector2.ZERO, Color.RED, false)
	big.on_peg_hit(Vector2.ZERO, Color.RED, true)
	assert_gt(big.particles.particles.size(), small.particles.particles.size())

func test_settle_adds_floater() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle(Vector2(1, 2), 250.0, false)
	assert_eq(jc.floaters.items.size(), 1)
	assert_eq(String(jc.floaters.items[0][&"text"]), "+250")

func test_final_launch_with_score_triggers_slowmo() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle(Vector2.ZERO, 100.0, true)
	jc.update(0.016)
	assert_lt(jc.time_scale(), 1.0)

func test_nonfinal_settle_no_slowmo() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle(Vector2.ZERO, 100.0, false)
	jc.update(0.016)
	assert_almost_eq(jc.time_scale(), 1.0, 0.0001)

func test_zero_score_final_no_slowmo() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_settle(Vector2.ZERO, 0.0, true)
	jc.update(0.016)
	assert_almost_eq(jc.time_scale(), 1.0, 0.0001)

func test_update_advances_systems() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_peg_hit(Vector2.ZERO, Color.RED, false)
	jc.on_settle(Vector2(0, 100), 10.0, false)
	var px0: float = jc.particles.particles[0][&"pos"].x
	var fy0: float = jc.floaters.items[0][&"pos"].y
	jc.update(0.1)
	var moved: bool = (jc.particles.particles[0][&"pos"].x != px0) or (jc.floaters.items[0][&"pos"].y != fy0)
	assert_true(moved)

func test_camera_offset_zero_when_idle() -> void:
	var jc := JuiceControllerScript.new()
	assert_eq(jc.camera_offset(), Vector2.ZERO)

func test_shake_mag_monotonic_and_capped() -> void:
	assert_almost_eq(JuiceControllerScript.shake_mag_for_combo(1), 0.12, 1e-4,
		"combo 1 屏震=0.12（与原小击一致）")
	for n in range(1, 30):
		assert_true(JuiceControllerScript.shake_mag_for_combo(n + 1)
			>= JuiceControllerScript.shake_mag_for_combo(n), "屏震单调不降 @%d" % n)
	assert_almost_eq(JuiceControllerScript.shake_mag_for_combo(99), 0.4, 1e-4,
		"屏震封顶 0.4")

func test_hitstop_monotonic_and_within_range() -> void:
	for n in range(1, 30):
		var d := JuiceControllerScript.hitstop_duration_for_combo(n)
		assert_between(d, 0.025, 0.090, "顿帧时长落在 [0.025,0.090] @%d" % n)
		assert_true(JuiceControllerScript.hitstop_duration_for_combo(n + 1)
			>= JuiceControllerScript.hitstop_duration_for_combo(n), "顿帧单调不降 @%d" % n)
	assert_almost_eq(JuiceControllerScript.hitstop_duration_for_combo(99), 0.090, 1e-4,
		"顿帧封顶 0.090")

func test_combo_hit_higher_combo_more_trauma() -> void:
	var a := JuiceControllerScript.new()
	var b := JuiceControllerScript.new()
	a.on_peg_hit_combo(Vector2.ZERO, Color.RED, 1)
	b.on_peg_hit_combo(Vector2.ZERO, Color.RED, 8)
	assert_gt(b.shake.trauma, a.shake.trauma, "连击越高屏震越强")

func test_combo_hit_no_hitstop() -> void:
	# 逐击顿帧已禁用（实机太突兀）；普通击中不应改变时间缩放。
	var jc := JuiceControllerScript.new()
	jc.on_peg_hit_combo(Vector2.ZERO, Color.RED, 3)
	jc.update(0.016)
	assert_almost_eq(jc.time_scale(), 1.0, 1e-4, "逐击不再产生顿帧")

func test_combo_hit_emits_particles() -> void:
	var jc := JuiceControllerScript.new()
	jc.on_peg_hit_combo(Vector2.ZERO, Color.RED, 5)
	assert_gt(jc.particles.particles.size(), 0, "逐击迸射粒子")
