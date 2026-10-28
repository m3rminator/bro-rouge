class_name WindGust
extends Node2D
## The gust of wind that bursts off the upper body when a sprint begins: pale streaks that fly back and fade, so it
## reads at once that he is running now. Every gust is different (how many streaks, where, how long, how fast, a slight
## tilt or curve). Drawn in code, no art.

var _t := 0.0
var _life := 0.4
var _side := 1
var _streaks: Array[Dictionary] = []


static func spawn(parent: Node, at: Vector2, side: int) -> void:
	var gust := WindGust.new()
	gust.position = at
	gust._side = side
	gust._life = randf_range(0.28, 0.55)
	gust.z_index = 4
	var count := randi_range(3, 9)
	for i in count:
		gust._streaks.append({
			"y": randf_range(-11.0, 9.0),
			"x": -side * randf_range(0.0, 8.0),  # a head start
			"len": randf_range(6.0, 22.0),
			"speed": randf_range(70.0, 200.0),
			"tilt": randf_range(-0.35, 0.35),  # drifts up or down as it flies
			"curve": randf_range(-6.0, 6.0),  # the tip bends
			"alpha": randf_range(0.45, 0.9),
			"delay": randf_range(0.0, 0.12),
			"width": 1.0 if randf() < 0.75 else 2.0,
		})
	parent.add_child(gust)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life + 0.12:
		queue_free()
	queue_redraw()


func _draw() -> void:
	for s in _streaks:
		var t: float = _t - s.delay
		if t <= 0.0 or t >= _life:
			continue
		var fade := 1.0 - t / _life
		var tail: float = s.x - _side * s.speed * t  # moves back, away from where he is heading
		var reach: float = s.len * (1.0 + t)
		var y: float = s.y + s.tilt * s.speed * t * 0.3
		var col := Color(1, 1, 1, fade * s.alpha)
		var tip := Vector2(tail + _side * reach, y + s.curve * t)
		draw_line(Vector2(tail, y), Vector2(tail + _side * reach * 0.5, y + s.curve * t * 0.3), col, s.width)
		draw_line(Vector2(tail + _side * reach * 0.5, y + s.curve * t * 0.3), tip, col, s.width)
