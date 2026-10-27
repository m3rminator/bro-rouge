class_name Shockwave
extends Node2D
## A visible ring of force that spreads out from a point and fades: the raygun's impact (blue-white) and the
## disco grenade's burst (rainbow). Pure picture - the raygun does its own damage (raygun.gd).

var _radius := 60.0
var _time := 0.45
var _age := 0.0
var _rainbow := false


static func emit(parent: Node, at: Vector2, radius: float, time: float, rainbow := false) -> void:
	var wave := Shockwave.new()
	wave.position = at
	wave._radius = radius
	wave._time = time
	wave._rainbow = rainbow
	parent.add_child(wave)


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_age += delta
	if _age >= _time:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / _time, 0.0, 1.0)
	var spread := 1.0 - pow(1.0 - t, 3.0)  # fast at first, then slowing
	var fade := 1.0 - t
	for ring in 3:  # three rings, each a little behind the one before
		var rt := clampf(spread - ring * 0.12, 0.0, 1.0)
		if rt <= 0.0:
			continue
		var color := Color.from_hsv(fmod(ring * 0.18 + t * 1.5, 1.0), 0.7, 1.0) if _rainbow else (Color("e8f6ff") if ring == 0 else Color("4aa8ff"))
		color.a = fade * (1.0 - ring * 0.25)
		draw_arc(Vector2.ZERO, _radius * rt, 0.0, TAU, 40, color, maxf(1.0, 4.0 * fade), false)
	draw_circle(Vector2.ZERO, _radius * 0.35 * fade, Color(0.8, 0.93, 1.0, 0.7 * fade) if not _rainbow else Color(1, 1, 1, 0.8 * fade))
