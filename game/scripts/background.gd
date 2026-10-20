class_name Background
extends CanvasLayer
## Distant jungle behind the level. Scaled to just cover the screen height and scrolled
## horizontally at a fraction of the camera speed (GameData.RUN.background_parallax), so it
## drifts slowly as the Bro runs. The picture doesn't tile on its own, so every second copy
## is mirrored: that way it never shows a seam however far you go.

const TEXTURE := preload("res://assets/backgrounds/jungle.jpg")

var _camera: Camera2D
var _canvas: Node2D


func _init() -> void:
	layer = -10
	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_canvas.draw.connect(_draw_background)
	add_child(_canvas)


func track(camera: Camera2D) -> void:
	_camera = camera


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _draw_background() -> void:
	var view := get_viewport().get_visible_rect().size
	var scale := view.y / TEXTURE.get_height()
	var tile_w := TEXTURE.get_width() * scale
	var cam_x := _camera.get_screen_center_position().x - view.x / 2.0 if _camera else 0.0
	var scroll := cam_x * GameData.RUN.background_parallax
	var first := floori(scroll / tile_w)
	for i in range(first, first + 3):  # tile_w >= view.x, so two tiles always cover; the third is margin
		var x := roundf(i * tile_w - scroll)
		var rect := Rect2(x, 0.0, tile_w, view.y)
		if i % 2 != 0:  # mirrored copy: negative width flips it
			rect = Rect2(x + tile_w, 0.0, -tile_w, view.y)
		_canvas.draw_texture_rect(TEXTURE, rect, false)
