class_name ShellCasing
extends Node2D
## A spent shotgun shell kicked out of the gun at every pump (Sharif). No sprite: two little
## pixels drawn in code (red body, brass base). It flies out, falls, bounces once or twice on
## the ground and fades after a few seconds. Numbers: design/entities/sharif.yaml.

const WORLD_MASK := 1
const RED := Color("b8302a")
const BRASS := Color("a88a40")
const GRAVITY := 620.0
const LIFE := 3.0
const FADE := 0.8

var velocity := Vector2.ZERO
var _spin := 0.0
var _resting := false
var _age := 0.0


## Ejects a shell from `pos` out of a gun facing `facing`.
static func eject(parent: Node, pos: Vector2, facing: int) -> void:
	var s := ShellCasing.new()
	s.position = pos
	s.velocity = Vector2(-facing * randf_range(15.0, 45.0), -randf_range(70.0, 115.0))
	s._spin = randf_range(-14.0, 14.0)
	parent.add_child(s)


func _ready() -> void:
	z_index = 3
	rotation = randf_range(0.0, TAU)


func _draw() -> void:
	draw_rect(Rect2(-2, -1, 3, 2), RED)
	draw_rect(Rect2(1, -1, 1, 2), BRASS)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFE + FADE:
		queue_free()
		return
	if _age > LIFE:
		modulate.a = (LIFE + FADE - _age) / FADE
	if _resting:
		return
	velocity.y += GRAVITY * delta
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, 2), WORLD_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += step
		rotation += _spin * delta
		return
	if hit.normal.y < -0.5 and velocity.y > 70.0:  # a small bounce, a little less each time
		global_position.y = hit.position.y - 1.0
		velocity = Vector2(velocity.x * 0.5, -velocity.y * 0.35)
		_spin *= 0.4
	elif hit.normal.y < -0.5:
		global_position.y = hit.position.y - 1.0
		_resting = true
		rotation = 0.0
	else:  # struck a wall or ceiling: drops straight down
		velocity = Vector2(0.0, 20.0)
		global_position += hit.normal * 2.0
