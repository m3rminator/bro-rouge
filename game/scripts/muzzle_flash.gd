class_name MuzzleFlash
extends AnimatedSprite2D
## Gun-tip flash shared by the Bro and enemies. Add as a child, then call fire() on every shot.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")


func _ready() -> void:
	sprite_frames = FX_FRAMES
	visible = false
	z_index = 1
	animation_finished.connect(func(): visible = false)


## Where the barrel of `sprite_name` ends in the frame that `sprite` is showing right now
## (GameData.MUZZLES, found by tools/build.py), relative to the sprite's parent body.
static func gun_tip(sprite: AnimatedSprite2D, sprite_name: String, direction: int) -> Vector2:
	var tips: Dictionary = GameData.MUZZLES[sprite_name]
	var frames: Array = tips.get(String(sprite.animation), [])
	var tip = frames[sprite.frame] if sprite.frame < frames.size() else null
	if tip == null:
		tip = tips["idle"][0]
	return sprite.position + Vector2(tip.x * direction, tip.y)


func fire(muzzle: Vector2, direction: int) -> void:
	position = muzzle + Vector2(3 * direction, 0)
	flip_h = direction < 0
	visible = true
	play("muzzle")
	frame = 0
