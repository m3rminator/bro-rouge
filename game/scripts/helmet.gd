class_name HelmetSoldier
extends Vest
## Helmet soldier: the vest soldier with a steel helmet. Head hits do no damage while it is on;
## the second one knocks it off (it tumbles away, olive shards fly all over) and from then on he is
## a plain vest soldier. Body hits count toward the 3 as usual; he cannot lose his head while
## the helmet is on. Numbers: design/entities/helmet.yaml (GameData.HELMET).

const SHARD_COLORS := [Color("8a9658"), Color("5f6b3b"), Color("3e4727")]  # master: helmet_light, helmet, helmet_dark

var _helmet := true
var _head_hits := 0


func _sheet() -> String:
	return "helmet"


func _own_stats() -> Dictionary:
	return GameData.HELMET


func knife_hits_needed(base: int, plain := 1) -> int:
	return base if _helmet else plain  # helmet AND vest: the first stab only stuns; without the helmet he is a plain vest soldier


func can_behead() -> bool:
	return not _helmet and super()


func hit(damage: int, direction := 0, at := Vector2.INF, behead := "none") -> void:
	if _helmet and not dead and _on_head(at):
		_head_hits += 1
		Sfx.play(self, "block_hit", -6.0)  # a metallic clank
		sprite.modulate = Color(3, 3, 3)
		create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.08)
		if state == State.PATROL:
			_spot()
		if _head_hits >= stats.helmet_hits:
			_break_helmet(direction)
		return
	super(damage, direction, at, behead)


func _break_helmet(direction: int) -> void:
	_helmet = false
	var top := global_position + Vector2(0, Block.SIZE / 2.0 - stats.hitbox[1] + 3.0)
	var frames: SpriteFrames = sprite.sprite_frames
	if frames.has_animation("helmet_drop"):
		BodyPiece.drop(get_parent(), frames.get_frame_texture("helmet_drop", 0), top, -direction if direction != 0 else -facing, Vector2(6, 4))
	Shards.burst(get_parent(), top, SHARD_COLORS, stats.shards, 190.0)
	Sfx.play(self, "block_break", -2.0)
	var vest_frames := "res://assets/sprites/vest_frames.tres"
	if ResourceLoader.exists(vest_frames):
		var anim := sprite.animation
		var frame := sprite.frame
		sprite.sprite_frames = load(vest_frames)
		sheet = "vest"
		sprite_name = "vest"
		sprite.play(anim)
		sprite.frame = frame
