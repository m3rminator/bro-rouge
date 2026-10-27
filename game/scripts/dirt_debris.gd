class_name DirtDebris
extends Node2D
## The crumbs of a broken block. Every crumb flies and falls on its own and collides with the blocks
## still standing (Block.cells): it lands on top of the earth below, bounces a little, slides to a stop,
## lies there for a moment, then fades. Hits on a wall bounce it back.

const GRAVITY := 500.0
const BOUNCE := 0.3

var _crumbs: Array[Dictionary] = []  # {p, v, s, c, rest (time lying), life (time left once resting)}


## Bursts `amount` crumbs of `color` from `at` (in `parent`'s space).
static func burst(parent: Node, at: Vector2, color: Color, amount: int) -> void:
	var d := DirtDebris.new()
	d.position = at
	d.z_index = 2
	for i in amount:
		var a := randf_range(-1.0, 1.0) * deg_to_rad(85.0) - PI / 2.0
		var tone := randf_range(0.8, 1.15)
		d._crumbs.append({
			"p": Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)),
			"v": Vector2.from_angle(a) * randf_range(70.0, 220.0),
			"s": float(randi_range(2, 4)),
			"c": Color(color.r * tone, color.g * tone, color.b * tone),
			"resting": false,
			"life": randf_range(1.5, 3.5),
		})
	parent.add_child(d)


func _physics_process(delta: float) -> void:
	var alive := false
	for c in _crumbs:
		if c.resting:
			c.life -= delta
			if not _solid(c.p + Vector2(0.0, 1.0)):  # the block under it was broken: it falls again from where it lies
				c.resting = false
		else:
			_step(c, delta)
		if c.life > 0.0:
			alive = true
	if not alive:
		queue_free()
		return
	queue_redraw()


func _step(c: Dictionary, delta: float) -> void:
	var v: Vector2 = c.v
	v.y += GRAVITY * delta
	var p: Vector2 = c.p
	var next_x := p + Vector2(v.x * delta, 0.0)
	if _solid(next_x):  # a wall: bounce back
		v.x = -v.x * BOUNCE
	else:
		p = next_x
	var next_y := p + Vector2(0.0, v.y * delta)
	if _solid(next_y):
		if v.y > 0.0:  # landed on top of a block
			var top := floorf((position.y + next_y.y) / Block.SIZE) * Block.SIZE - position.y
			p.y = top - 0.01
			if v.y > 60.0:
				v.y = -v.y * BOUNCE
				v.x *= 0.6
			else:
				v = Vector2.ZERO
				c.resting = true
		else:  # hit a ceiling
			v.y = 0.0
	else:
		p = next_y
	c.p = p
	c.v = v


func _solid(local: Vector2) -> bool:
	var world := local + position
	return Block.cells.has(Vector2i(floori(world.x / Block.SIZE), floori(world.y / Block.SIZE)))


func _draw() -> void:
	for c in _crumbs:
		if c.life <= 0.0:
			continue
		var col: Color = c.c
		if c.resting and c.life < 0.5:
			col.a = c.life / 0.5
		var s: float = c.s
		draw_rect(Rect2(roundf(c.p.x - s / 2.0), roundf(c.p.y) - s, s, s), col)
