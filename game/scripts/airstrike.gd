class_name AirStrike
extends Node2D
## The Gunner's call-in (design/entities/airstrike.yaml, GameData.AIRSTRIKE): a red laser beam
## and marker on the ground in front of him, and after `delay` a line of bombs falls out of the
## sky on that spot, each exploding where it lands. The spot is far enough away that he is not
## hurt where he stands. The laser beam and marker are drawn in code; the falling missiles use the airstrike sprite.

const STATS := GameData.AIRSTRIKE
const RED := Color("e85a50")
const WHITE := Color("f4f2e8")

var _time := 0.0
var _dropped := 0
var _next_bomb := 0.0
var _delay: float = STATS.delay
var _bombs: int = STATS.bombs
var _spread: float = STATS.spread
var _through := false  # the bombs fall through blocks above the spot and still land on it (the Brute's strike)
var _warn := 0.0  # > 0: a red warning zone of this radius is drawn on the ground (the Brute's strike)


## The ground below `around` (found from a little above it down), else a bit below it.
static func ground_point(world: World2D, around: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(around + Vector2(0, -140), around + Vector2(0, 260), 1)
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else around + Vector2(0, 20)


## Marks `target` (a point on the ground) with the laser and calls the bombs in.
## `opts` (optional): bombs, spread, delay, warn_radius - the Brute calls ONE missile with a red warning zone.
static func call_in(parent: Node, target: Vector2, opts := {}) -> void:
	var strike := AirStrike.new()
	strike.position = target
	strike._bombs = opts.get("bombs", strike._bombs)
	strike._spread = opts.get("spread", strike._spread)
	strike._delay = opts.get("delay", strike._delay)
	strike._warn = opts.get("warn_radius", 0.0)
	strike._through = opts.get("through", false)
	parent.add_child(strike)


func _ready() -> void:
	z_index = 4
	Sfx.play(self, "grenade_throw", -4.0)


func _process(delta: float) -> void:
	_time += delta
	if _time >= _delay:
		_next_bomb -= delta
		if _next_bomb <= 0.0 and _dropped < _bombs:
			_next_bomb = STATS.bomb_interval
			_dropped += 1
			var bomb := Bomb.new()
			bomb.position = position + Vector2(randf_range(-_spread, _spread), -STATS.start_height)
			if _through:
				bomb.through_y = position.y
			get_parent().add_child(bomb)
		if _dropped >= _bombs:
			queue_free()
	queue_redraw()


func _draw() -> void:
	if _time >= _delay:
		return
	var blink := 0.55 + 0.45 * sin(_time * (22.0 if _warn == 0.0 else 8.0 + 20.0 * _time / _delay))  # the laser flickers, faster and faster
	if _warn > 0.0:  # red zone on the ground: run out of it
		draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, _warn, Color(RED, 0.18 + 0.2 * blink))
		draw_arc(Vector2.ZERO, _warn, 0.0, TAU, 40, Color(RED, 0.5 + 0.5 * blink), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var height: float = STATS.start_height + 40.0
	draw_line(Vector2(0, 0), Vector2(0, -height), Color(RED, 0.35 * blink), 1.0)
	draw_rect(Rect2(-7, -1, 14, 2), Color(RED, blink))
	draw_rect(Rect2(-1, -3, 2, 3), Color(WHITE, blink))


## One falling missile (sprite airstrike/missile, nose down, flame on top). Its origin is the
## nose, so it explodes where the tip touches a block or an enemy.
class Bomb extends Node2D:
	const WORLD_AND_ENEMIES := 1 | 4
	const FRAMES := preload("res://assets/sprites/airstrike_frames.tres")
	const NOSE := Vector2(2, 16)  # the nose tip in the 6x17 frame

	var through_y := INF  # set: the bomb ignores blocks on the way and explodes at this height

	func _ready() -> void:
		z_index = 4
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = FRAMES
		sprite.position = Vector2(3.0, 8.5) - NOSE  # frame centre relative to the nose
		add_child(sprite)
		sprite.play("missile")

	func _physics_process(delta: float) -> void:
		var step := Vector2(0, AirStrike.STATS.fall_speed * delta)
		if through_y < INF:
			if global_position.y + step.y >= through_y:
				var power := {"radius": AirStrike.STATS.blast_radius, "damage": AirStrike.STATS.blast_damage, "player_damage": AirStrike.STATS.blast_player_damage, "spare_bottom": true}
				var at := Vector2(global_position.x, through_y)
				Explosion.detonate(get_parent(), at, power, [at])
				queue_free()
			else:
				global_position += step
			return
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, 2), WORLD_AND_ENEMIES)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var power := {"radius": AirStrike.STATS.blast_radius, "damage": AirStrike.STATS.blast_damage, "player_damage": AirStrike.STATS.blast_player_damage, "spare_bottom": true}
			Explosion.detonate(get_parent(), hit.position, power, [hit.position])
			queue_free()
			return
		global_position += step
		if global_position.y > 6000.0:
			queue_free()
