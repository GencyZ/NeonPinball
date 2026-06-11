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
