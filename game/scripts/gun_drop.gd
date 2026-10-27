class_name GunDrop
extends ShellCasing
## One of Blala's SMGs falling out of his hands at the start of a reload (frame 1 of his "reload" animation,
## player.gd). Same flight as a spent shell (scripts/shell_casing.gd): tumbles, bounces, lies there and fades.

const BODY := Color("3a3a46")
const EDGE := Color("1c1a24")
const GRIP := Color("5a3c28")


static func drop(parent: Node, pos: Vector2, facing: int) -> void:
	var g := GunDrop.new()
	g.position = pos
	g.velocity = Vector2(-facing * randf_range(4.0, 20.0), randf_range(-35.0, -10.0))
	g._spin = randf_range(-6.0, 6.0)
	parent.add_child(g)


func _ready() -> void:
	z_index = 3
	rotation = randf_range(-0.4, 0.4)


func _draw() -> void:
	draw_rect(Rect2(-6, -2, 12, 4), EDGE)
	draw_rect(Rect2(-5, -1, 10, 2), BODY)
	draw_rect(Rect2(-2, 1, 2, 3), GRIP)
