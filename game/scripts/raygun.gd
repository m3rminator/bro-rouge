class_name Raygun
extends Node2D
## The Men in Black raygun (design/entities/raygun.yaml, GameData.RAYGUN). Raygun.fire() casts a ray straight
## ahead from the muzzle, draws the blue beam to where it stops, and bursts a shockwave there: it breaks the
## blocks inside it, throws the enemies inside it back and stuns them. A direct hit on an enemy kills him.
## This node is just the beam picture; it fades and frees itself.

const STATS := GameData.RAYGUN
const WORLD := 1
const ENEMIES := 4
const BODIES := 8

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _age := 0.0


## Fires from `from` (in `parent`'s space) in direction `dir` (1 / -1). Returns where the beam ended.
static func fire(parent: Node2D, from: Vector2, dir: int) -> Vector2:
	var space := parent.get_world_2d().direct_space_state
	var to := from + Vector2(dir * STATS.range, 0)
	var query := PhysicsRayQueryParameters2D.create(parent.to_global(from), parent.to_global(to), WORLD | ENEMIES)
	var result := space.intersect_ray(query)
	var struck := false
	var end := to
	if not result.is_empty():
		struck = true
		end = parent.to_local(result.position)
	var beam := Raygun.new()
	beam._from = from
	beam._to = end
	parent.add_child(beam)
	if struck:
		var target: Object = result.collider
		if target is Enemy and not target.dead:
			target.hit(STATS.boss_damage if target.is_in_group("bosses") else STATS.direct_damage, dir, result.position, "none")
			if target.dead and not target.is_in_group("bosses"):
				target._burst_body(dir)  # a direct hit tears him into pieces
		_wave(parent, end, dir, target)
	else:
		_wave(parent, end, dir, null)  # out of range: it bursts in the air where the beam ends
	return end


## The shockwave at `at`: blocks inside break, enemies inside are thrown away and stunned.
static func _wave(parent: Node2D, at: Vector2, dir: int, direct: Object) -> void:
	Shockwave.emit(parent, at, STATS.wave_radius, STATS.wave_time)
	Sfx.play(parent, "raygun_wave", -6.0)
	var circle := CircleShape2D.new()
	circle.radius = STATS.wave_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, parent.to_global(at))
	query.collision_mask = WORLD | ENEMIES
	var seen := {}
	for result in parent.get_world_2d().direct_space_state.intersect_shape(query, 64):
		var body: Object = result.collider
		if seen.has(body):
			continue
		seen[body] = true
		if body is Block:
			body.destroy()
		elif body is Enemy:
			if body != direct or not body.dead:
				body.wave_hit(parent.to_global(at).x, STATS.knock_speed, STATS.knock_up, STATS.stun_time)
		elif body.has_method("hit"):
			body.hit(1, dir)  # barrels and the like


func _ready() -> void:
	z_index = 4


func _process(delta: float) -> void:
	_age += delta
	if _age >= STATS.beam_time:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - _age / STATS.beam_time
	draw_line(_from, _to, Color(0.25, 0.6, 1.0, 0.45 * fade), 6.0 * fade + 1.0)
	draw_line(_from, _to, Color(0.35, 0.72, 1.0, 0.9 * fade), 3.0 * fade + 1.0)
	draw_line(_from, _to, Color(0.9, 0.97, 1.0, fade), 1.0)
