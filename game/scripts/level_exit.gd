class_name LevelExit
extends Area2D
## Extraction truck at the end of a level (design/entities/exit.yaml). Locked until the kill quota
## is met (main.gd opens it). Emits `touched` every physics frame the Bro stands at its tailgate;
## once the level is clear main.gd calls board(): the Bro hops in the back and the truck drives off.

signal touched

const FRAMES := preload("res://assets/sprites/truck_frames.tres")
const BED_OFFSET := Vector2(-46, -25)  # inside the open rear of the tarp, from the truck's tile centre
const HOP_TIME := 0.55
const HOP_HEIGHT := 30.0
const DRIVE_DISTANCE := 560.0
const DRIVE_TIME := 2.4

var _sprite: AnimatedSprite2D
var _rider: Node2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the Bro
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.position = Vector2(0, 12.0 - 28.0)  # 120x56 frame, bottom on the bottom of its tile, centred on it
	add_child(_sprite)
	_sprite.play("locked")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(48, 56)
	shape.shape = rect
	shape.position = Vector2(-38, -16)  # the tailgate end of the truck
	add_child(shape)


func set_open(open: bool) -> void:
	_sprite.play("open" if open else "locked")


func _physics_process(_delta: float) -> void:
	if has_overlapping_bodies():
		touched.emit()


func _process(_delta: float) -> void:
	if _rider != null and _rider.get_parent() != null:
		_rider.global_position = global_position + BED_OFFSET


## The Bro hops in the back, then the truck drives off to the right with him.
func board(rider: CharacterBody2D) -> void:
	_rider = null
	rider.set_physics_process(false)
	rider.set("facing", 1)
	(rider.get_node("Sprite") as AnimatedSprite2D).flip_h = false
	var from := rider.global_position
	var to := global_position + BED_OFFSET
	var hop := create_tween()
	hop.tween_method(func(t: float) -> void:
		rider.global_position = from.lerp(to, t) + Vector2(0, -sin(t * PI) * HOP_HEIGHT), 0.0, 1.0, HOP_TIME)
	await hop.finished
	_rider = rider
	rider.visible = false  # inside under the tarp
	_sprite.play("drive")
	var drive := create_tween()
	drive.tween_property(self, "position:x", position.x + DRIVE_DISTANCE, DRIVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
