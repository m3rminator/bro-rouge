class_name PunchAura
extends Node2D
## The hit-aura of a punch or kick: a ring of force that blooms in front of the fist or foot and fades. Drawn in code
## (gold, or red in fury). The bullets it destroys are found by player.gd (_fist_deflect), this is only the picture.

const LIFE := 0.16

var _t := 0.0
var _size := 10.0
var _color := Color("fff3b0")
var _side := 1


static func spawn(parent: Node, at: Vector2, side: int, size: float, color: Color) -> void:
	var aura := PunchAura.new()
	aura.position = at
	aura._side = side
	aura._size = size
	aura._color = color
	aura.z_index = 4
	parent.add_child(aura)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFE
	var r := _size * (0.55 + 0.7 * ease(k, 0.4))  # the ring grows fast, then slows
	var fade := 1.0 - k
	var mid := 0.0 if _side > 0 else PI
	draw_arc(Vector2.ZERO, r, mid - 1.1, mid + 1.1, 12, Color(_color, fade), 2.0, false)
	draw_arc(Vector2.ZERO, r * 0.62, mid - 0.9, mid + 0.9, 10, Color(1, 1, 1, fade), 1.0, false)
	for i in 5:  # short rays out of the ring
		var a := mid + (i - 2) * 0.45
		draw_line(Vector2.from_angle(a) * (r + 1.0), Vector2.from_angle(a) * (r + 3.0 + 0.5 * k * _size * 0.3), Color(_color, fade), 1.0)
