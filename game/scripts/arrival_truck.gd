class_name ArrivalTruck
extends Node2D
## The truck that brought the Bro to the start of the next level: it drives in from the left, off-screen (nose first,
## forwards) with him under the tarp, stops where the level begins, and he hops out at the start tile (the way he hopped in at the last exit).
## Decoration after that - it stays parked. Same sprite and bed spot as level_exit.gd.

const FRAMES := preload("res://assets/sprites/truck_frames.tres")
const BED_OFFSET := Vector2(-46, -25)  # inside the open rear of the tarp, from the truck's tile centre
const DRIVE_DISTANCE := 560.0
const DRIVE_TIME := 1.8
const HOP_TIME := 0.5
const HOP_HEIGHT := 26.0

var _sprite: AnimatedSprite2D
var _rider: Node2D


func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.position = Vector2(0, 12.0 - 28.0)
	add_child(_sprite)
	_sprite.play("drive")


func _process(_delta: float) -> void:
	if _rider != null:
		_rider.global_position = global_position + BED_OFFSET


## `rider` waits invisible in the bed while the truck drives to its stop, then hops to `start`.
func arrive(rider: CharacterBody2D, start: Vector2) -> void:
	var stop := start - BED_OFFSET * Vector2(1, 0)  # the bed ends up 46 px right of the start tile
	position = stop - Vector2(DRIVE_DISTANCE, 0)
	rider.set_physics_process(false)
	rider.visible = false
	_rider = rider
	var drive := create_tween()
	drive.tween_property(self, "position:x", stop.x, DRIVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await drive.finished
	_sprite.play("open")
	_rider = null
	rider.visible = true
	rider.set("facing", -1)
	(rider.get_node("Sprite") as AnimatedSprite2D).flip_h = true
	var from := stop + BED_OFFSET
	var hop := create_tween()
	hop.tween_method(func(t: float) -> void:
		rider.global_position = from.lerp(start, t) + Vector2(0, -sin(t * PI) * HOP_HEIGHT), 0.0, 1.0, HOP_TIME)
	await hop.finished
	rider.set("facing", 1)
	(rider.get_node("Sprite") as AnimatedSprite2D).flip_h = false
	rider.set_physics_process(true)
