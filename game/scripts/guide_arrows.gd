class_name GuideArrows
extends Node2D
## Pixel arrows on the screen (drawn in code, in a canvas layer over the game): a flashing arrow to the right when a
## level begins ("go that way"), and, once the kill quota is met, an arrow on the edge of the screen pointing at the
## truck for as long as the truck is out of sight.

const START_SECONDS := 7.0
const FILL := Color("ffd23e")
const EDGE := Color("1f1b2c")

var target: Node2D  # the exit truck
var show_start := true
var show_truck := false  # the quota is met
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view := Screen.view()
	if show_start and _t < START_SECONDS and fmod(_t, 0.8) < 0.5:
		var nudge := roundf(sin(_t * 9.0) * 3.0)
		_arrow(Vector2(view.x - 26.0 + nudge, view.y * 0.42), 0.0)
	if show_truck and target != null and is_instance_valid(target):
		var rel := target.global_position - cam.get_screen_center_position()
		var half := view / 2.0
		if absf(rel.x) > half.x - 10.0 or absf(rel.y) > half.y - 10.0:
			if fmod(_t, 1.0) < 0.7:
				var at := half + rel * minf((half.x - 24.0) / maxf(absf(rel.x), 1.0), (half.y - 24.0) / maxf(absf(rel.y), 1.0))
				var angle := 0.0 if rel.x > 0.0 else PI
				if absf(rel.y) * view.x > absf(rel.x) * view.y:  # mostly above or below him
					angle = PI / 2.0 if rel.y > 0.0 else -PI / 2.0
				_arrow(at.round(), angle, Color.WHITE, 6, 6, 8)  # short and fat


## A blocky arrow pointing along `angle` (a multiple of a quarter turn, so it stays pixel-clean), `at` is its middle.
## `shaft` is how long the stem is, `thick` how wide it is, `head` the half size of the point.
func _arrow(at: Vector2, angle: float, fill := FILL, shaft := 12, thick := 4, head := 6) -> void:
	draw_set_transform(at, angle, Vector2.ONE)
	for pass_index in 2:
		var outline := pass_index == 0
		var color := EDGE if outline else fill
		var g := 1.0 if outline else 0.0  # the dark outline is a pixel bigger all round
		var half := thick / 2.0
		draw_rect(Rect2(-shaft - g, -half - g, shaft + 2 + 2 * g, thick + 2 * g), color)  # the shaft
		for i in head:  # the head, a column at a time
			draw_rect(Rect2(2 + i - g, -head + i - g, 1 + 2 * g, 2 * head - 2 * i + 2 * g), color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
