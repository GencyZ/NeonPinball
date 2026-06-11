extends GutTest
const RunManagerScript := preload("res://run/run_manager.gd")

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
