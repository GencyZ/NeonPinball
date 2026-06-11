extends CanvasLayer
# Autoload: FadeMan — full-screen black fade for scene transitions.

const FADE_DURATION := 0.3

var _rect: ColorRect

func _ready() -> void:
	layer = 128
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root and node != self:
		fade_in()

func fade_to(action: Callable) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, FADE_DURATION)
	tw.tween_callback(action)

func fade_in() -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0, FADE_DURATION)
