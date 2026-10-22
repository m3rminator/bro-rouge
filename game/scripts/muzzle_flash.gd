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
## `second`: the other gun of a two-gun sprite (GameData.MUZZLES_2); the main gun if that
## frame shows only one.
static func gun_tip(sprite: AnimatedSprite2D, sprite_name: String, direction: int, second := false) -> Vector2:
	var tips: Dictionary = GameData.MUZZLES[sprite_name]
	var frames: Array = tips.get(String(sprite.animation), [])
	var tip = frames[sprite.frame] if sprite.frame < frames.size() else null
	if second:
		var frames_2: Array = second_tips(sprite_name).get(String(sprite.animation), [])
		var tip_2 = frames_2[sprite.frame] if sprite.frame < frames_2.size() else null
		if tip_2 != null:
			tip = tip_2
	if tip == null:
		tip = tips["idle"][0]
	return sprite.position + Vector2(tip.x * direction, tip.y)


func fire(muzzle: Vector2, direction: int) -> void:
	position = muzzle + Vector2(3 * direction, 0)
	flip_h = direction < 0
	visible = true
	play("muzzle")
	frame = 0


## Second-gun tips of a two-gun sprite (GameData.MUZZLES_2), {} for a one-gun sprite.
static func second_tips(sprite_name: String) -> Dictionary:
	var all: Dictionary = (GameData as GDScript).get_script_constant_map().get("MUZZLES_2", {})
	return all.get(sprite_name, {})
