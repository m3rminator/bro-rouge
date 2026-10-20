class_name PixelText
extends Node2D
## Text drawn with the HUD pixel font (art/sprites/font.yaml): 3x5 glyphs in 4x6 cells,
## tinted with `color` and outlined in the palette's outline color.

const FONT := preload("res://assets/sprites/font_frames.tres")
const NAMES := {"/": "slash", "!": "bang", ":": "colon", "-": "dash", ".": "dot", "+": "plus", ">": "gt", "<": "lt"}
const OUTLINE := Color("14101e")  # master palette: outline
const CELL := Vector2(4, 6)

enum Align { LEFT, CENTER, RIGHT }

var text := "":
	set(value):
		text = value.to_upper()
		queue_redraw()
var color := Color("f4f2e8"):  # master palette: white
	set(value):
		color = value
		queue_redraw()
var align := Align.LEFT
var size := 1  # pixel scale


static func make(at: Vector2, alignment: Align, pixel_size := 1) -> PixelText:
	var t := PixelText.new()
	t.position = at
	t.align = alignment
	t.size = pixel_size
	return t


func _draw() -> void:
	var width := (text.length() * 4 - 1) * size
	var x0 := 0.0
	if align == Align.CENTER:
		x0 = -floorf(width / 2.0)
	elif align == Align.RIGHT:
		x0 = -width
	var cell := CELL * size
	for i in text.length():
		var glyph: String = "g_" + NAMES.get(text[i], text[i])
		if not FONT.has_animation(glyph):
			continue  # space or unknown character
		var tex := FONT.get_frame_texture(glyph, 0)
		var at := Vector2(x0 + i * cell.x, 0)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_texture_rect(tex, Rect2(at + d * size, cell), false, OUTLINE)
		draw_texture_rect(tex, Rect2(at, cell), false, color)
