class_name LevelExit
extends Area2D
## Extraction flag at the end of a level (design/entities/exit.yaml). Locked until the kill
## quota is met (main.gd opens it). Emits `touched` every physics frame the Bro stands at it.

signal touched

const FRAMES := preload("res://assets/sprites/exit_frames.tres")

var _sprite: AnimatedSprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the Bro
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.position = Vector2(0, -8)  # 2 blocks tall, bottom on the bottom of its tile
	add_child(_sprite)
	_sprite.play("locked")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 28)
	shape.shape = rect
	shape.position = Vector2(0, -6)
	add_child(shape)


func set_open(open: bool) -> void:
	_sprite.play("open" if open else "locked")


func _physics_process(_delta: float) -> void:
	if has_overlapping_bodies():
		touched.emit()
