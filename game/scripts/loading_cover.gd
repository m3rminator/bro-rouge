class_name LoadingCover
extends CanvasLayer
## A dark cover with LOADING over the whole screen while a level is built (main.gd), so the first seconds of a fight, when
## the phone is busy, are never seen. `finish()` fades it away. Runs while the tree is paused.

const YELLOW := Color("ffd23e")

var _shade: ColorRect
var _text: PixelText
var _bar: ColorRect
var _fill: ColorRect
var _progress := 0.0
var _fading := false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color("14101e")
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_text = PixelText.make(Vector2.ZERO, PixelText.Align.CENTER, 3)
	_text.text = "LOADING"
	_text.color = YELLOW
	add_child(_text)
	_bar = ColorRect.new()
	_bar.color = Color("23202f")
	_bar.size = Vector2(120, 8)
	add_child(_bar)
	_fill = ColorRect.new()
	_fill.color = YELLOW
	_fill.size = Vector2(0, 4)
	add_child(_fill)
	_place()


## 0..1: how far the loading is.
func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	_place()


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var view := Screen.view()  # read every time: the window may still be changing size
	_text.position = Vector2(view.x / 2.0, view.y / 2.0 - 20.0)
	_bar.position = Vector2((view.x - _bar.size.x) / 2.0, view.y / 2.0 + 8.0)
	_fill.position = _bar.position + Vector2(2, 2)
	_fill.size.x = (_bar.size.x - 4.0) * _progress


func finish() -> void:
	if _fading:
		return
	_fading = true
	var tween := create_tween()
	tween.tween_property(_shade, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(_text, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(_bar, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(_fill, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
