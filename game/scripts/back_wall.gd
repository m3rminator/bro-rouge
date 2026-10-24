class_name BackWall
extends Node2D
## The dark earth behind the terrain: one flat wall tile per block of the level, drawn behind everything.
## It is not solid. Where a block is shot away the wall shows through, so only that layer is gone
## and not the ground behind it (design/entities/block.yaml). One canvas item draws all of them.

const FRAMES := preload("res://assets/sprites/terrain_frames.tres")

var _cells := {}  # position -> [texture, flip_h, flip_v]; drawn only once its block was broken
var _shown := {}


func _init() -> void:
	z_index = -1


func add(pos: Vector2, anim: String, flip_h: bool, flip_v: bool) -> void:
	_cells[pos] = [FRAMES.get_frame_texture(anim, 0), flip_h, flip_v]


## The block at pos was broken: its wall tile now shows (and only then).
func reveal(pos: Vector2) -> void:
	if _cells.has(pos):
		_shown[pos] = true
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var s := float(Block.SIZE)
	for p in _shown:
		var c: Array = _cells[p]
		var rect := Rect2(p.x - s / 2.0, p.y - s / 2.0, s, s)
		if c[1]:
			rect = Rect2(rect.position.x + s, rect.position.y, -s, s)
		if c[2]:
			rect = Rect2(rect.position.x, rect.position.y + s, rect.size.x, -s)
		draw_texture_rect(c[0], rect, false)
