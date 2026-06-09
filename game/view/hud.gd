extends CanvasLayer

var _total_score := 0.0
var _last_score := 0.0
var _label_total: Label
var _label_last: Label

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

	_update()

func add_score(s: float) -> void:
	_last_score = s
	_total_score += s
	_update()

func _update() -> void:
	_label_total.text = "SCORE  %d" % int(_total_score)
	_label_last.text = "+%d" % int(_last_score) if _last_score > 0 else ""
