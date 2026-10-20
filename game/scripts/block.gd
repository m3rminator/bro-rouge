class_name Block
extends StaticBody2D
## Destructible 16x16 terrain tile. Breaks into debris after HP hits.

const SIZE := 16
const FRAMES := preload("res://assets/sprites/terrain_frames.tres")
const DEBRIS_COLOR := Color("6e4628")  # master palette: dirt

## Tuning numbers live in design/entities/block.yaml (generated into GameData.BLOCK).
var hp: int = GameData.BLOCK.hp
var _sprite: AnimatedSprite2D


func setup(kind: String) -> Block:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = FRAMES
	_sprite.animation = kind
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(SIZE, SIZE)
	shape.shape = rect
	add_child(shape)
	collision_layer = 1
	collision_mask = 0
	return self


func hit(damage: int) -> void:
	hp -= damage
	if hp > 0:
		Sfx.play(self, "block_hit", -10.0)
		_sprite.modulate = Color(2, 2, 2)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.08)
		return
	Sfx.play(self, "block_break", -4.0)
	var debris := CPUParticles2D.new()
	debris.one_shot = true
	debris.amount = GameData.BLOCK.debris_amount
	debris.lifetime = 0.6
	debris.explosiveness = 1.0
	debris.direction = Vector2.UP
	debris.spread = 70.0
	debris.initial_velocity_min = 60.0
	debris.initial_velocity_max = 140.0
	debris.gravity = Vector2(0, 500)
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 3.0
	debris.color = DEBRIS_COLOR
	debris.position = position
	debris.finished.connect(debris.queue_free)
	get_parent().add_child(debris)
	debris.emitting = true
	queue_free()
