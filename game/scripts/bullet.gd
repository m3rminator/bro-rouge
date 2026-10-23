class_name Bullet
extends Area2D
## Glowing bullet used by the Bro and by enemies. Damages the first body with a hit() method
## that it touches, then sparks. Stats come from GameData.BULLET / ENEMY_BULLET / MINIGUN_BULLET.

const FRAMES := preload("res://assets/sprites/projectiles_frames.tres")

var direction := 1
var angle := 0.0  # degrees off straight ahead (minigun spread); + is downward when facing right
var stats: Dictionary
var anim := "bro_shot"
var _velocity := Vector2.ZERO
var _age := 0.0
var _sprite: AnimatedSprite2D


## Fires a bullet from `pos` (in `parent`'s space). `mask` = physics layers it can hit.
static func spawn(parent: Node, pos: Vector2, dir: int, bullet_stats: Dictionary, animation: String, mask: int,
		angle_deg := 0.0) -> void:
	var bullet := Bullet.new()
	bullet.position = pos
	bullet.direction = dir
	bullet.angle = angle_deg
	bullet.stats = bullet_stats
	bullet.anim = animation
	bullet.collision_mask = mask
	parent.add_child(bullet)


func _ready() -> void:
	add_to_group("bullets")  # flying heads feel them pass (head.gd)
	collision_layer = 0
	z_index = 3
	var turn := deg_to_rad(angle)
	_velocity = Vector2(direction, 0).rotated(turn) * stats.speed
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.flip_h = direction < 0
	_sprite.rotation = turn
	add_child(_sprite)
	_sprite.play(anim)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(stats.size[0], stats.size[1])
	shape.shape = rect
	shape.rotation = turn
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_age += delta
	if _age > stats.lifetime:
		queue_free()
	elif _age > stats.lifetime - GameData.BULLET.fade_time:  # thins out instead of vanishing
		_sprite.modulate.a = (stats.lifetime - _age) / GameData.BULLET.fade_time


func _on_body_entered(body: Node) -> void:
	if is_queued_for_deletion():
		return
	if body is Enemy:  # where it struck matters: a head shot can blow the head off
		body.hit(stats.damage, direction, global_position, stats.get("behead", "none"))
	elif body.has_method("hit"):
		body.hit(stats.damage, direction)
	var spark := AnimatedSprite2D.new()
	spark.sprite_frames = FRAMES
	spark.position = position + _velocity.normalized() * 4.0
	spark.z_index = 3
	get_parent().add_child(spark)
	spark.play("impact")
	spark.animation_finished.connect(spark.queue_free)
	queue_free()
