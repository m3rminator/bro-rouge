class_name Vest
extends Mook
## Vest soldier: behaves like the mook (patrol, "!", reaction, bursts, turning round) but takes
## 3 body hits, and one headshot kills him on the spot (the head flies off). Numbers:
## design/entities/vest.yaml (GameData.VEST).


func _ready() -> void:
	_use_sheet(_sheet())
	super()


## The sprite sheet this soldier starts with.
func _sheet() -> String:
	return "vest"


## Draw him with <name>_frames.tres once that sheet has been built.
func _use_sheet(sheet_name: String) -> void:
	sheet = sheet_name
	var frames := "res://assets/sprites/%s_frames.tres" % sheet_name
	if ResourceLoader.exists(frames):
		$Sprite.sprite_frames = load(frames)


func _own_stats() -> Dictionary:
	return GameData.VEST
