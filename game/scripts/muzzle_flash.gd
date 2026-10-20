class_name MuzzleFlash
extends AnimatedSprite2D
## Gun-tip flash shared by the Bro and enemies. Add as a child, then call fire() on every shot.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")


func _ready() -> void:
	sprite_frames = FX_FRAMES
	visible = false
	z_index = 1
	animation_finished.connect(func(): visible = false)


func fire(muzzle: Vector2, direction: int) -> void:
	position = muzzle + Vector2(3 * direction, 0)
	flip_h = direction < 0
	visible = true
	play("muzzle")
	frame = 0
