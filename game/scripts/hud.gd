class_name Hud
extends CanvasLayer
## Top-left hearts showing the Bro's hit points. See design/entities/hud.yaml.

const FX_FRAMES := preload("res://assets/sprites/fx_frames.tres")

var _hearts: Array[AnimatedSprite2D] = []


func track(player: Node) -> void:
	for i in GameData.BRO.max_hp:
		var heart := AnimatedSprite2D.new()
		heart.sprite_frames = FX_FRAMES
		heart.animation = "heart_full"
		heart.position = Vector2(10 + i * 9, 10)
		add_child(heart)
		_hearts.append(heart)
	player.hp_changed.connect(_on_hp_changed)


func _on_hp_changed(hp: int, _max_hp: int) -> void:
	for i in _hearts.size():
		_hearts[i].animation = "heart_full" if i < hp else "heart_empty"
