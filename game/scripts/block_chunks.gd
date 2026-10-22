class_name BlockChunks
extends Node2D
## Lumps of flesh lying on top of one block (added by Gibs). They belong to the block, so
## they vanish if it is destroyed. Keeps at most GameData.BLOOD.gibs_per_block (oldest go first).

var _lumps: Array[Dictionary] = []


func add(x: float, w: int, h: int, bump: int, color: Color) -> void:
	if _lumps.size() >= GameData.BLOOD.gibs_per_block:
		_lumps.pop_front()
	var half := Block.SIZE / 2.0
	_lumps.append({"x": floorf(clampf(x - w / 2.0, -half, half - w - 1)), "w": w, "h": h, "bump": bump, "color": color})
	queue_redraw()


func _draw() -> void:
	var top := -Block.SIZE / 2.0
	for l in _lumps:
		Gibs.draw_lump(self, Vector2(l.x, top - l.h), l.w, l.h, l.bump, l.color)
