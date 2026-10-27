class_name MagDrop
extends ShellCasing
## The empty magazine that falls out of the gun at the start of a reload (frame 3 of Bro's "reload"
## animation, player.gd). Same flight as a spent shell (scripts/shell_casing.gd): a small spin, a bounce or
## two, settles on the ground and fades. No sprite - a few pixels drawn in code.

const BODY := Color("3a3a46")
const EDGE := Color("1c1a24")
const BRASS_TOP := Color("a88a40")


## Drops a magazine from `pos`; it tips a little away from the way the gun faces.
static func drop(parent: Node, pos: Vector2, facing: int) -> void:
	var m := MagDrop.new()
	m.position = pos
	m.velocity = Vector2(-facing * randf_range(6.0, 22.0), randf_range(-30.0, -10.0))
	m._spin = randf_range(-7.0, 7.0)
	parent.add_child(m)


func _ready() -> void:
	z_index = 3
	rotation = randf_range(-0.3, 0.3)


func _draw() -> void:
	draw_rect(Rect2(-2, -3, 4, 6), EDGE)
	draw_rect(Rect2(-1, -3, 2, 5), BODY)
	draw_rect(Rect2(-1, -4, 2, 1), BRASS_TOP)
