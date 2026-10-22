class_name Ember
extends Node2D
## A glowing speck of a blast: thrown out, falls, lands on whatever is below, glows there for a
## few seconds and fades (design/entities/explosion.yaml: embers, ember_life). Pure decoration.

const GRAVITY := 520.0
const COLORS := [Color("fff6c8"), Color("ffd23e"), Color("f07c22"), Color("c43a1a")]  # master: fire_white -> fire_red

var velocity := Vector2.ZERO
var size := 2.0
var life := 3.0
var _color: Color
var _landed := false
var _age := 0.0


static func scatter(parent: Node, at: Vector2, count: int, speed: float) -> void:
	for i in count:
		var e := Ember.new()
		e.position = at + Vector2(randf_range(-6, 6), randf_range(-6, 4))
		e.velocity = Vector2.from_angle(randf_range(-PI, 0.0)) * speed * randf_range(0.3, 1.0)
		e.size = float(randi_range(1, 3))
		e.life = GameData.EXPLOSION.ember_life * randf_range(0.6, 1.2)
		e._color = COLORS[randi() % COLORS.size()]
		parent.add_child(e)


func _ready() -> void:
	z_index = 3


func _physics_process(delta: float) -> void:
	if not _landed:
		velocity.y += GRAVITY * delta
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + velocity * delta, 1)
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			position += velocity * delta
		else:
			position = get_parent().to_local(hit.position) - Vector2(0, size / 2.0)
			_landed = true
			_age = 0.0
	else:
		_age += delta
		var left := 1.0 - _age / life
		if left <= 0.0:
			queue_free()
			return
		modulate.a = minf(1.0, left * 2.0)
		_color = _color.lerp(COLORS[3], delta * 0.8)  # cools to dark red while it lies there
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-size / 2.0, -size / 2.0, size, size), _color)
