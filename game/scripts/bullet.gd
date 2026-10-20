class_name Bullet
extends Area2D
## Rifle bullet. Hits anything on the "world" layer that has a hit() method.

## Tuning numbers live in design/entities/bullet.yaml (generated into GameData.BULLET).
const STATS := GameData.BULLET
const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")

var direction := 1
var _age := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = FX_FRAMES
	sprite.animation = "bullet"
	sprite.flip_h = direction < 0
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(5, 2)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position.x += STATS.speed * direction * delta
	_age += delta
	if _age > STATS.lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("hit"):
		body.hit(STATS.damage)
	queue_free()
