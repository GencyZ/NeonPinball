class_name PegGrid

var _rect: Rect2
var _cell: float
var _cols: int
var _rows: int
var _cells: Array  # Array of Array[int]（pegId 列表）

func build(pegs: Array, rect: Rect2, cell_size: float) -> void:
	_rect = rect; _cell = cell_size
	_cols = maxi(1, ceili(rect.size.x / cell_size))
	_rows = maxi(1, ceili(rect.size.y / cell_size))
	_cells.resize(_cols * _rows)
	for i in _cells.size():
		_cells[i] = []
	for peg in pegs:
		var cx := clampi(int((peg[&"pos"].x - rect.position.x) / cell_size), 0, _cols - 1)
		var cy := clampi(int((peg[&"pos"].y - rect.position.y) / cell_size), 0, _rows - 1)
		_cells[cy * _cols + cx].append(peg[&"id"])

# 返回 center 附近 radius 范围格子内的 peg_id，按 id 升序（保证确定性遍历）。
func query_near(center: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var min_cx := clampi(int((center.x - radius - _rect.position.x) / _cell), 0, _cols - 1)
	var max_cx := clampi(int((center.x + radius - _rect.position.x) / _cell), 0, _cols - 1)
	var min_cy := clampi(int((center.y - radius - _rect.position.y) / _cell), 0, _rows - 1)
	var max_cy := clampi(int((center.y + radius - _rect.position.y) / _cell), 0, _rows - 1)
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			for id in _cells[cy * _cols + cx]:
				result.append(id)
	result.sort()   # 确定遍历顺序，不依赖 Dictionary 哈希序
	return result
