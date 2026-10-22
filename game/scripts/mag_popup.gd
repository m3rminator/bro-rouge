class_name MagPopup
extends AnimatedSprite2D
## "+ magazine" icon over the Bro's head after a knife kill gave him a magazine
## (sprite items/mag_pickup). Fades in rising slowly, drifts, then rises further and fades
## out; the whole thing lasts Run.bro_stats().mag_popup_time. Follows the Bro (it is his child).

const FRAMES := preload("res://assets/sprites/items_frames.tres")
const FADE := 0.6  # fade-in and fade-out time


## `top` = y of the top of the Bro's frame, relative to him.
static func show_over(bro: Node2D, top: float) -> void:
	for old in bro.get_children():
		if old is MagPopup:
			old.queue_free()
	var p := MagPopup.new()
	p.sprite_frames = FRAMES
	p.animation = "mag_pickup"
	p.z_index = 5
	p.position = Vector2(0, top - 4.0)
	p.modulate.a = 0.0
	bro.add_child(p)
	var total: float = Run.bro_stats().mag_popup_time
	var t := p.create_tween()
	t.set_parallel()
	t.tween_property(p, "modulate:a", 1.0, FADE)
	t.tween_property(p, "position:y", p.position.y - 14.0, total).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(p, "modulate:a", 0.0, FADE).set_delay(total - FADE)
	t.chain().tween_callback(p.queue_free)
