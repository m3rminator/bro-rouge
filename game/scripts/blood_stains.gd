class_name BloodStains
extends Node2D
## Blood stains on one block, drawn in front of its tile. Added by landing droplets
## (BloodDrops); they go away with the block. Keeps at most GameData.BLOOD.stains_per_block.

var _rects: Array[Rect2] = []
var _colors: Array[Color] = []


func add(at: Vector2, size: Vector2, color: Color) -> void:
	if _rects.size() >= GameData.BLOOD.stains_per_block:
		_rects.pop_front()
		_colors.pop_front()
	_rects.append(Rect2(at, size))
	_colors.append(color)
	queue_redraw()


func _draw() -> void:
	for i in _rects.size():
		draw_rect(_rects[i], _colors[i])
