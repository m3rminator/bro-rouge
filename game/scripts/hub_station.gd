class_name HubStation
extends Node2D
## A station in the safe house between boss levels: stand next to it and press Interact (E).
## "A" restocks ammo, "H" refills hearts and lives, "G" refills grenades (main.gd does the work
## when `used` fires). Placeholder look, drawn in code: a coloured crate with a label.

signal used(kind: String)

const KINDS := {
	"A": {"title": "AMMO", "prompt": "E RESTOCK AMMO", "color": Color("ffd23e")},
	"H": {"title": "LIVES", "prompt": "E REFILL LIVES", "color": Color("e85a50")},
	"G": {"title": "GRENADES", "prompt": "E REFILL GRENADES", "color": Color("7cc04e")},
}
const OUTLINE := Color("14101e")
const REACH := Vector2(26, 30)

var kind := "A"
var _label := PixelText.make(Vector2(0, -42), PixelText.Align.CENTER)
var _title := PixelText.make(Vector2(0, -30), PixelText.Align.CENTER)
var _flash := 0.0


func _ready() -> void:
	z_index = 1
	var info: Dictionary = KINDS[kind]
	_title.text = info.title
	_title.color = info.color
	add_child(_title)
	add_child(_label)
	queue_redraw()


func _draw() -> void:
	var color: Color = KINDS[kind].color
	var base := Block.SIZE / 2.0  # bottom of the tile
	draw_rect(Rect2(-12, base - 22, 24, 22), OUTLINE)
	draw_rect(Rect2(-10, base - 20, 20, 18), color.darkened(0.35))
	draw_rect(Rect2(-10, base - 20, 20, 5), color)
	draw_rect(Rect2(-3, base - 12, 6, 6), OUTLINE)


func _process(delta: float) -> void:
	_flash -= delta
	var p := get_tree().get_first_node_in_group("player")
	var near: bool = p != null and not p.dead and absf(p.global_position.x - global_position.x) < REACH.x \
			and absf(p.global_position.y - global_position.y) < REACH.y
	if _flash > 0.0:
		_label.text = "DONE"
		_label.color = Color("7cc04e")
	elif near:
		_label.text = KINDS[kind].prompt
		_label.color = Color("f4f2e8")
	else:
		_label.text = ""
	if near and Input.is_action_just_pressed("interact"):
		_flash = 1.0
		used.emit(kind)
