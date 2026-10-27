class_name ChargeRing
extends Node2D
## The charge circle - the one look for everything that charges (refrences/ui, the 8-step circle sheet). Today that is
## Sharif's revolver (design/entities/revolver.yaml). A see-through dark disc with a black outline and a grey track;
## the coloured stroke fills clockwise from the top and turns white, cream, yellow, orange, yellow-green, green as
## it goes. Full: the whole circle goes green, a flash blooms and a few sparks fly off.

const STATS := GameData.REVOLVER
const OUTLINE := Color("14101e")
const TRACK := Color("4a4858")
const INSIDE := Color(0.08, 0.12, 0.16, 0.55)  # the dark see-through middle
const FULL := Color("2ee84a")
const STEPS := [  # [ratio, colour] along the fill
	[0.0, Color("f4f2e8")],
	[0.3, Color("fff0b0")],
	[0.5, Color("ffc61a")],
	[0.75, Color("ff9d1a")],
	[0.92, Color("c4d820")],
	[1.0, Color("2ee84a")],
]

var _ratio := 0.0
var _flash := 0.0  # 1 -> 0 after it fills
var _time := 0.0
var _sparks := PackedVector2Array()  # directions of the sparks of the flash


func _ready() -> void:
	z_index = 20
	visible = false


## ratio 0..1 of the charge; < 0 hides the ring.
func show_charge(ratio: float) -> void:
	if ratio < 0.0:
		visible = false
		_ratio = 0.0
		_flash = 0.0
		return
	visible = true
	if ratio >= 1.0 and _ratio < 1.0:
		_flash = 1.0  # it just filled up
		_sparks.clear()
		for i in 7:
			_sparks.append(Vector2.from_angle(randf() * TAU))
	_ratio = ratio
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_flash = maxf(0.0, _flash - delta / STATS.flash_time)
	queue_redraw()


func _stroke_color(ratio: float) -> Color:
	for i in range(1, STEPS.size()):
		if ratio <= STEPS[i][0]:
			var a: Array = STEPS[i - 1]
			var b: Array = STEPS[i]
			return a[1].lerp(b[1], (ratio - a[0]) / (b[0] - a[0]))
	return FULL


func _draw() -> void:
	var r: float = STATS.ring_radius
	var thick := maxf(1.5, r * 0.28)
	var mid := r - thick / 2.0  # the stroke's centre line
	var full := _ratio >= 1.0
	var color := FULL if full else _stroke_color(_ratio)
	draw_circle(Vector2.ZERO, r + 1.0, OUTLINE)
	draw_circle(Vector2.ZERO, r - thick, FULL if full else INSIDE)
	if full:
		draw_arc(Vector2.ZERO, mid, 0.0, TAU, 28, color, thick, false)
		draw_arc(Vector2.ZERO, r - thick, 0.0, TAU, 28, OUTLINE, 1.0, false)  # the thin dark ring inside it
	else:
		draw_arc(Vector2.ZERO, mid, 0.0, TAU, 28, TRACK, thick, false)
		if _ratio > 0.0:
			draw_arc(Vector2.ZERO, mid, -PI / 2.0, -PI / 2.0 + TAU * _ratio, 28, color, thick, false)
		draw_arc(Vector2.ZERO, r - thick, 0.0, TAU, 28, OUTLINE, 1.0, false)
	if _flash > 0.0:  # a green bloom that grows and fades, and sparks flying off
		var grow: float = r * (1.0 + (1.0 - _flash) * 1.6)
		draw_circle(Vector2.ZERO, grow, Color(FULL, 0.45 * _flash))
		draw_arc(Vector2.ZERO, grow + 1.0, 0.0, TAU, 28, Color(1, 1, 1, _flash), 1.0, false)
		for dir in _sparks:
			draw_rect(Rect2((dir * (r + (1.0 - _flash) * r * 1.8)).round(), Vector2(1, 1)), Color(0.8, 1.0, 0.8, _flash))
