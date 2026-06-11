extends GutTest

func test_all_new_types_registered() -> void:
	for id in [&"chain", &"bomb", &"freeze", &"jackpot", &"life", &"poison", &"portal", &"magnet"]:
		assert_true(GameDB.peg_types.has(id), "%s 已注册" % id)

func test_bomb_is_one_shot() -> void:
	assert_true((GameDB.peg_types[&"bomb"] as PegType).one_shot)

func test_jackpot_is_one_shot() -> void:
	assert_true((GameDB.peg_types[&"jackpot"] as PegType).one_shot)

func test_life_is_one_shot() -> void:
	assert_true((GameDB.peg_types[&"life"] as PegType).one_shot)

func test_chain_not_one_shot() -> void:
	assert_false((GameDB.peg_types[&"chain"] as PegType).one_shot)

func test_portal_not_one_shot() -> void:
	assert_false((GameDB.peg_types[&"portal"] as PegType).one_shot)
