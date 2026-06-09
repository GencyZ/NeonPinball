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

func test_swept_walls_right_wall() -> void:
	# 球在 x=4，沿 +x 走 d.x=10，半径 1
	# 右墙有效线 x = rect.end.x - r = 10 - 1 = 9 → t = (9-4)/10 = 0.5
	var rect := Rect2(0, 0, 10, 100)
	var result := Collision.swept_walls(Vector2(4, 50), Vector2(10, 0), 1.0, rect)
	assert_false(result.is_empty(), "should hit right wall")
	assert_almost_eq(result[&"t"], 0.5, 1e-4, "right wall at t=0.5")
	assert_eq(result[&"normal"], Vector2(-1, 0), "normal points left")

func test_swept_walls_top_wall() -> void:
	# 球在 y=5，沿 -y 走 d.y=-10，半径 1
	# 顶墙有效线 y = rect.position.y + r = 0 + 1 = 1 → t = (1-5)/(-10) = 0.4
	var rect := Rect2(0, 0, 100, 100)
	var result := Collision.swept_walls(Vector2(50, 5), Vector2(0, -10), 1.0, rect)
	assert_false(result.is_empty(), "should hit top wall")
	assert_almost_eq(result[&"t"], 0.4, 1e-4, "top wall at t=0.4")
	assert_eq(result[&"normal"], Vector2(0, 1), "normal points down")

func test_swept_walls_no_bottom_wall() -> void:
	# 底部开口，球向下穿出不应命中
	var rect := Rect2(0, 0, 100, 100)
	var result := Collision.swept_walls(Vector2(50, 95), Vector2(0, 10), 1.0, rect)
	assert_true(result.is_empty(), "bottom is open, no hit")

func test_reflect_off_right_wall() -> void:
	# 速度 (3, 2) 撞右墙法线 (-1,0)，完全弹性
	var v := Collision.reflect(Vector2(3, 2), Vector2(-1, 0), 1.0, 1.0)
	assert_almost_eq(v.x, -3.0, 1e-4, "x component flipped")
	assert_almost_eq(v.y, 2.0, 1e-4, "y component unchanged")

func test_reflect_with_restitution() -> void:
	# restitution=0.8，法向分量乘以 0.8
	var v := Collision.reflect(Vector2(0, 4), Vector2(0, -1), 0.8, 1.0)
	assert_almost_eq(v.y, -3.2, 1e-4, "normal component scaled by restitution")
