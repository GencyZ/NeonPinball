extends GutTest

const SMALL_RECT := Rect2(0, 0, 200, 400)   # synthetic rect for resolve() tests
const GAME_RECT  := Rect2(135, 225, 540, 900) # real rect for make_ball / channel_dir tests

# ── resolve() ──────────────────────────────────────────────────────────────────

func test_top_edge_mid_pos_and_normal() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.TOP, 0.5, SMALL_RECT)
	assert_eq(r[&"pos"], Vector2(100, 0), "top edge mid → pos at (100,0)")
	assert_eq(r[&"normal"], Vector2.DOWN, "top normal points down")

func test_right_edge_quarter() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.RIGHT, 0.25, SMALL_RECT)
	assert_eq(r[&"pos"], Vector2(200, 100), "right edge t=0.25 → (200,100)")
	assert_eq(r[&"normal"], Vector2.LEFT, "right normal points left")

func test_left_edge_three_quarter() -> void:
	var r := EntryResolver.resolve(EntryResolver.BoardEdge.LEFT, 0.75, SMALL_RECT)
	assert_eq(r[&"pos"], Vector2(0, 300), "left edge t=0.75 → (0,300)")
	assert_eq(r[&"normal"], Vector2.RIGHT, "left normal points right")

# ── channel_dir() ──────────────────────────────────────────────────────────────

func test_channel_dir_points_toward_gate() -> void:
	for edge in [EntryResolver.BoardEdge.TOP, EntryResolver.BoardEdge.LEFT,
				 EntryResolver.BoardEdge.RIGHT]:
		var cd := EntryResolver.channel_dir(edge, GAME_RECT)
		var gate_pos := EntryResolver.resolve(edge, EntryResolver.LAUNCHER_T[edge], GAME_RECT)[&"pos"]
		var expected := (gate_pos - EntryResolver.LAUNCHER_POS[edge]).normalized()
		assert_almost_eq(cd.x, expected.x, 1e-4, "channel_dir.x edge %d" % edge)
		assert_almost_eq(cd.y, expected.y, 1e-4, "channel_dir.y edge %d" % edge)
		assert_almost_eq(cd.length(), 1.0, 1e-4, "channel_dir normalized edge %d" % edge)

# ── make_ball() ────────────────────────────────────────────────────────────────

func test_make_ball_starts_at_launcher_pos() -> void:
	for edge in [EntryResolver.BoardEdge.TOP, EntryResolver.BoardEdge.LEFT,
				 EntryResolver.BoardEdge.RIGHT]:
		var ball := EntryResolver.make_ball(edge, 0.5, 0.0, 100.0, 5.0, GAME_RECT)
		assert_eq(ball.pos, EntryResolver.LAUNCHER_POS[edge],
				  "ball spawns at launcher pos for edge %d" % edge)

func test_make_ball_zero_aim_aligns_with_channel() -> void:
	var edge := EntryResolver.BoardEdge.TOP
	var ball := EntryResolver.make_ball(edge, 0.5, 0.0, 100.0, 5.0, GAME_RECT)
	var cd := EntryResolver.channel_dir(edge, GAME_RECT)
	assert_almost_eq(ball.vel.normalized().x, cd.x, 1e-3, "vel direction x matches channel")
	assert_almost_eq(ball.vel.normalized().y, cd.y, 1e-3, "vel direction y matches channel")
	assert_almost_eq(ball.vel.length(), 100.0, 1e-3, "speed preserved")

func test_make_ball_clamps_extreme_aim() -> void:
	var edge := EntryResolver.BoardEdge.TOP
	var cd := EntryResolver.channel_dir(edge, GAME_RECT)
	# 999 rad clamped to ±20°; ball should still have positive dot with channel_dir
	var ball := EntryResolver.make_ball(edge, 0.5, 999.0, 100.0, 5.0, GAME_RECT)
	assert_gt(ball.vel.dot(cd), 0.0, "clamped aim still travels toward board")
	assert_almost_eq(ball.vel.length(), 100.0, 1e-3, "speed preserved after clamp")
