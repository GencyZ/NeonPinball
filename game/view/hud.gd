extends CanvasLayer

var _total := 0.0
var _label_total: Label
var _label_last: Label
var _label_gate: Label

func _ready() -> void:
	_label_total = Label.new()
	_label_total.position = Vector2(20, 20)
	_label_total.add_theme_font_size_override(&"font_size", 28)
	add_child(_label_total)

	_label_last = Label.new()
	_label_last.position = Vector2(20, 60)
	_label_last.add_theme_font_size_override(&"font_size", 18)
	_label_last.modulate = Color(1, 1, 0.5)
	add_child(_label_last)

	_label_gate = Label.new()
	_label_gate.position = Vector2(20, 90)
	_label_gate.add_theme_font_size_override(&"font_size", 18)
	_label_gate.modulate = Color(0.6, 1.0, 0.8)
	add_child(_label_gate)

	_label_total.text = "Score: 0"
	_label_last.text = ""
	_label_gate.text = "Gate: normal"

func add_score(s: float) -> void:
	_total += s
	_label_total.text = "Score: %d" % int(_total)
	_label_last.text = "+%d" % int(s)

func set_gate_label(gate_name: String) -> void:
	_label_gate.text = "Gate: " + gate_name
