extends GutTest

func test_swept_circle_head_on() -> void:
	# p=(0,0) 沿 d=(10,0) 运动，目标圆心 c=(10,0)，合半径 R=5
	# → m=(-10,0), a=100, b=-200, cc=75, disc=10000, root=0.5
	var t := Collision.swept_circle(Vector2.ZERO, Vector2(10, 0), Vector2(10, 0), 5.0)
	assert_almost_eq(t, 0.5, 1e-4, "head-on hit at t=0.5")

func test_swept_circle_miss_offside() -> void:
	var t := Collision.swept_circle(Vector2.ZERO, Vector2(10, 0), Vector2(5, 100), 5.0)
	assert_eq(t, -1.0, "should miss when target is far off-axis")

func test_swept_circle_too_short() -> void:
	# 位移长度 1，但目标在距离 5 处 → root=5 > 1 → miss
	var t := Collision.swept_circle(Vector2.ZERO, Vector2(1, 0), Vector2(10, 0), 5.0)
	assert_eq(t, -1.0, "should miss when displacement too short")

func test_swept_circle_already_overlapping() -> void:
	# 已重叠（球心距 < R），root 为负 → miss（避免重复碰撞）
	var t := Collision.swept_circle(Vector2(9, 0), Vector2(1, 0), Vector2(10, 0), 5.0)
	assert_eq(t, -1.0, "already overlapping, root negative → miss")
