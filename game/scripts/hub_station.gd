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
	"R": {"title": "BRO BOX", "prompt": "E OPEN THE BOX", "color": Color("b07be0")},
	"W": {"title": "POWER-UP", "prompt": "E CHOOSE A POWER-UP", "color": Color("ff9a3c")},
	"U": {"title": "CRATE", "prompt": "E OPEN THE CRATE", "color": Color("4ec8d8")},
}
## The three supply stations are drawn as the crate sprites (art/sprites/crate_*.yaml), 30x27, flat bottom on the ground.
const CRATE_ART := {"A": "crate_ammo", "H": "crate_med", "G": "crate_grenade"}
const GRAVITY := 800.0
const OUTLINE := Color("14101e")
const REACH := Vector2(26, 30)

var kind := "A"
var _label := PixelText.make(Vector2(0, -42), PixelText.Align.CENTER)
var _title := PixelText.make(Vector2(0, -30), PixelText.Align.CENTER)
var _flash := 0.0
var _drop_speed := 0.0  # falling when the block under it is gone


func _ready() -> void:
	add_to_group("hub_stations")
	z_index = 1
	var info: Dictionary = KINDS[kind]
	_title.text = info.title
	_title.color = info.color
	add_child(_title)
	add_child(_label)
	if CRATE_ART.has(kind):
		var crate := AnimatedSprite2D.new()
		crate.sprite_frames = load("res://assets/sprites/%s_frames.tres" % CRATE_ART[kind])
		crate.animation = "idle"
		crate.position = Vector2(0, Block.SIZE / 2.0 - 13.5)
		add_child(crate)
	queue_redraw()


func _draw() -> void:
	if CRATE_ART.has(kind):
		return
	var color: Color = KINDS[kind].color
	var base := Block.SIZE / 2.0  # bottom of the tile
	draw_rect(Rect2(-12, base - 22, 24, 22), OUTLINE)
	draw_rect(Rect2(-10, base - 20, 20, 18), color.darkened(0.35))
	draw_rect(Rect2(-10, base - 20, 20, 5), color)
	draw_rect(Rect2(-3, base - 12, 6, 6), OUTLINE)


var in_reach := false  # the Bro stands close enough to use it (the touch fire button turns into a hand)


func _process(delta: float) -> void:
	_flash -= delta
	_fall(delta)
	var p := get_tree().get_first_node_in_group("player")
	var near: bool = p != null and not p.dead and absf(p.global_position.x - global_position.x) < REACH.x \
			and absf(p.global_position.y - global_position.y) < REACH.y
	in_reach = near
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


## The crate stands on the block under it: when that is gone it drops until it lands on something (or leaves the map).
func _fall(delta: float) -> void:
	var cell := Vector2i(floori(position.x / Block.SIZE), floori(position.y / Block.SIZE))
	if _drop_speed == 0.0 and Block.cells.has(cell + Vector2i(0, 1)):
		return
	_drop_speed = minf(_drop_speed + GRAVITY * delta, 600.0)
	var from_y := position.y
	position.y += _drop_speed * delta
	if Block.cells.has(cell + Vector2i(0, 1)) and position.y >= cell.y * Block.SIZE + Block.SIZE / 2.0 and from_y <= position.y:
		position.y = cell.y * Block.SIZE + Block.SIZE / 2.0
		_drop_speed = 0.0
		Sfx.play(self, "land", -8.0)
	elif position.y > 6000.0:
		queue_free()
