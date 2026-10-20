class_name Bullet
extends Area2D
## Straight-flying bullet used by the Bro and by enemies. Damages the first body with a
## hit() method that it touches. Stats come from GameData.BULLET / GameData.ENEMY_BULLET.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")

var direction := 1
var stats: Dictionary
var anim := "bullet"
var _age := 0.0


## Fires a bullet from `pos` (in `parent`'s space). `mask` = physics layers it can hit.
static func spawn(parent: Node, pos: Vector2, dir: int, bullet_stats: Dictionary, animation: String, mask: int) -> void:
	var bullet := Bullet.new()
	bullet.position = pos
	bullet.direction = dir
	bullet.stats = bullet_stats
	bullet.anim = animation
	bullet.collision_mask = mask
	parent.add_child(bullet)


func _ready() -> void:
	collision_layer = 0
	z_index = 3
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = FX_FRAMES
	sprite.animation = anim
	sprite.flip_h = direction < 0
	add_child(sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(5, 2)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position.x += stats.speed * direction * delta
	_age += delta
	if _age > stats.lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("hit"):
		body.hit(stats.damage, direction)
	queue_free()
