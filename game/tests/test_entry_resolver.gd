extends GutTest

const RECT := Rect2(0, 0, 200, 400)

func test_top_edge_mid_pos_and_normal() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.TOP, 0.5, RECT)
	assert_eq(r[&"pos"], Vector2(100, 0), "top edge mid → pos at (100,0)")
	assert_eq(r[&"normal"], Vector2.DOWN, "top normal points down")

func test_right_edge_quarter() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.RIGHT, 0.25, RECT)
	assert_eq(r[&"pos"], Vector2(200, 100), "right edge t=0.25 → (200,100)")
	assert_eq(r[&"normal"], Vector2.LEFT, "right normal points left")

func test_left_edge_three_quarter() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.LEFT, 0.75, RECT)
	assert_eq(r[&"pos"], Vector2(0, 300), "left edge t=0.75 → (0,300)")
	assert_eq(r[&"normal"], Vector2.RIGHT, "left normal points right")

func test_make_ball_zero_aim_points_inward() -> void:
	var ball := EntryResolver.make_ball(
		EntryResolver.BoardEdge.TOP, 0.5, 0.0, 100.0, 5.0, RECT)
	assert_almost_eq(ball.vel.x, 0.0, 1e-3, "zero aim → no lateral drift")
	assert_gt(ball.vel.y, 0.0, "velocity points into board (down)")
	assert_almost_eq(ball.vel.length(), 100.0, 1e-3, "speed == 100")

func test_make_ball_clamps_extreme_aim() -> void:
	# aim_offset = 999 应被夹紧到 ±80°（±1.396 rad）
	var ball := EntryResolver.make_ball(
		EntryResolver.BoardEdge.TOP, 0.5, 999.0, 100.0, 5.0, RECT)
	# 夹紧后方向仍朝棋盘内（y > 0）
	assert_gt(ball.vel.y, 0.0, "even extreme aim stays inward")
