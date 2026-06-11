extends GutTest
const RunManagerScript := preload("res://run/run_manager.gd")
const SceneManagerScript := preload("res://run/scene_manager.gd")
const MainMenuScript := preload("res://view/main_menu.gd")

func test_reset_run_restores_boot() -> void:
	var mgr := RunManagerScript.new()
	mgr.state[&"phase"] = RunManagerScript.Phase.RUN_WIN
	mgr.state[&"ante"] = 3
	mgr.state[&"money"] = 99
	mgr.reset_run()
	assert_eq(mgr.state[&"phase"], RunManagerScript.Phase.BOOT)
	assert_eq(int(mgr.state[&"ante"]), 1)
	assert_eq(int(mgr.state[&"money"]), 0)
	assert_eq(int(mgr.state[&"master_seed"]), 0)
	mgr.free()

func test_reset_run_matches_default() -> void:
	var mgr := RunManagerScript.new()
	mgr.state[&"money"] = 500
	mgr.reset_run()
	assert_eq(mgr.state.hash(), RunManagerScript._make_default_state().hash())
	mgr.free()

func test_game_scene_path_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/board.tscn"))

func test_scene_manager_script_loads() -> void:
	assert_not_null(load("res://run/scene_manager.gd"))

func test_best_text_format() -> void:
	var mm := MainMenuScript.new()
	assert_eq(mm.best_text({&"best_score": 4200}), "Best: 4200", "有 best_score 时格式正确")
	assert_eq(mm.best_text({}), "Best: 0", "无 best_score 时默认 0")
	mm.free()

func test_menu_scene_loads_without_error() -> void:
	var packed = load("res://scenes/main_menu.tscn")
	assert_not_null(packed, "main_menu.tscn 可加载")
	var inst = packed.instantiate()
	add_child_autofree(inst)
	assert_not_null(inst, "实例化成功，_ready 构建 UI 无报错")

func test_menu_scene_path_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/main_menu.tscn"), "main_menu.tscn 存在")

func test_board_scene_still_loads() -> void:
	assert_true(ResourceLoader.exists("res://scenes/board.tscn"), "board.tscn 仍存在")
	assert_not_null(load("res://view/input_controller.gd"), "input_controller.gd 编辑后仍能解析")

func test_fade_manager_script_loads() -> void:
	assert_not_null(load("res://run/fade_manager.gd"), "FadeManager 脚本可加载/解析")
