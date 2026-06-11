extends CanvasLayer

# ---- Run state labels (top-left and top-right) ----
var _label_total: Label
var _label_last: Label
var _label_gate: Label
var _label_ante: Label
var _label_quota: Label
var _label_money: Label
var _label_launches: Label

# ---- Shop panel ----
var _shop_panel: PanelContainer
var _shop_title: Label
var _shop_slots: Array[Button] = []
var _shop_continue_btn: Button
var _shop_visible := false

signal shop_slot_pressed(slot: int)
signal shop_continue_pressed

# ---- End-of-run buttons ----
var _end_panel: Control

# ---- Internal ----
var _total := 0.0

func _ready() -> void:
	# Top-left: score display
	_label_total = _make_label(Vector2(20, 20), 28)
	_label_last  = _make_label(Vector2(20, 56), 18, Color(1, 1, 0.5))
	_label_gate  = _make_label(Vector2(20, 82), 18, Color(0.6, 1.0, 0.8))

	# Top-right: run state
	_label_ante    = _make_label(Vector2(490, 20), 18, Color(1.0, 0.8, 0.4))
	_label_quota   = _make_label(Vector2(490, 44), 18, Color(1.0, 0.5, 0.5))
	_label_money   = _make_label(Vector2(490, 68), 18, Color(0.4, 1.0, 0.6))
	_label_launches = _make_label(Vector2(490, 92), 18, Color(0.8, 0.8, 1.0))

	# Initialize text
	_label_total.text    = "Score: 0"
	_label_last.text     = ""
	_label_gate.text     = "Gate: normal"
	_label_ante.text     = "Ante 1 · Round 1"
	_label_quota.text    = "Score 0 / 50"
	_label_money.text    = "Gold: 0"
	_label_launches.text = "Launches: 5"

	_build_shop_panel()
	_build_end_panel()

func _make_label(pos: Vector2, size: int, color: Color = Color.WHITE) -> Label:
	var lbl := Label.new()
	lbl.position = pos
	lbl.add_theme_font_size_override(&"font_size", size)
	lbl.modulate = color
	add_child(lbl)
	return lbl

func _build_shop_panel() -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.position = Vector2(60, 210)
	_shop_panel.custom_minimum_size = Vector2(420, 300)
	_shop_panel.visible = false
	add_child(_shop_panel)

	var vbox := VBoxContainer.new()
	_shop_panel.add_child(vbox)

	_shop_title = Label.new()
	_shop_title.text = "=== SHOP ==="
	_shop_title.add_theme_font_size_override(&"font_size", 24)
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_shop_title)

	for i in 4:
		var btn := Button.new()
		btn.add_theme_font_size_override(&"font_size", 17)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot_idx := i
		btn.pressed.connect(func(): shop_slot_pressed.emit(slot_idx))
		vbox.add_child(btn)
		_shop_slots.append(btn)

	_shop_continue_btn = Button.new()
	_shop_continue_btn.text = "Continue →  (Space)"
	_shop_continue_btn.add_theme_font_size_override(&"font_size", 16)
	_shop_continue_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_continue_btn.pressed.connect(func(): shop_continue_pressed.emit())
	vbox.add_child(_shop_continue_btn)

# ---- Public API ----

func add_score(s: float) -> void:
	_total += s
	_label_total.text = "Score: %d" % int(_total)
	_label_last.text  = "+%d" % int(s)

func set_gate_label(gate_name: String) -> void:
	_label_gate.text = "Gate: " + gate_name

func update_run_state(ante: int, round_in_ante: int,
					  quota: float, money: int, launches: int,
					  round_score: float) -> void:
	_label_ante.text    = "Ante %d · Round %d" % [ante, round_in_ante + 1]
	_label_quota.text   = "Score %d / %d" % [int(round_score), int(quota)]
	_label_money.text   = "Gold: %d" % money
	_label_launches.text = "Launches: %d" % launches

func show_shop(offerings: Array, money: int) -> void:
	_shop_visible = true
	_shop_panel.visible = true

	for i in 4:
		_shop_slots[i].text = ""
		_shop_slots[i].disabled = false
		_shop_slots[i].modulate = Color.WHITE

	for i in mini(offerings.size(), 4):
		var offer: Dictionary = offerings[i]
		var item: Resource = offer.get(&"item")
		var name_str: String = String(item.id) if item != null and "id" in item else "Unknown"
		var price: int = offer.get(&"price", 0)
		var is_sold: bool = offer.get(&"sold", false)
		if is_sold:
			_shop_slots[i].text = "[%d] SOLD" % (i + 1)
			_shop_slots[i].disabled = true
			_shop_slots[i].modulate = Color(0.4, 0.4, 0.4)
		else:
			var can_afford := money >= price
			_shop_slots[i].text = "[%d] %s  (%d gold)" % [i + 1, name_str, price]
			_shop_slots[i].disabled = not can_afford
			_shop_slots[i].modulate = Color(1, 1, 0.5) if can_afford else Color(0.5, 0.5, 0.5)

func hide_shop() -> void:
	_shop_visible = false
	_shop_panel.visible = false

func is_shop_visible() -> bool:
	return _shop_visible

func _build_end_panel() -> void:
	_end_panel = Control.new()
	_end_panel.visible = false
	add_child(_end_panel)

	var btn_restart := Button.new()
	btn_restart.text = "Restart  (R)"
	btn_restart.position = Vector2(280, 780)
	btn_restart.custom_minimum_size = Vector2(250, 56)
	btn_restart.pressed.connect(SceneMan.start_run)
	_end_panel.add_child(btn_restart)

	var btn_menu := Button.new()
	btn_menu.text = "Main Menu  (Esc)"
	btn_menu.position = Vector2(280, 848)
	btn_menu.custom_minimum_size = Vector2(250, 56)
	btn_menu.pressed.connect(SceneMan.goto_menu)
	_end_panel.add_child(btn_menu)

func show_end_buttons() -> void:
	_end_panel.visible = true

func hide_end_buttons() -> void:
	_end_panel.visible = false
