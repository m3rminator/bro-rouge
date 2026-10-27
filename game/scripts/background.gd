class_name Background
extends CanvasLayer
## Backdrop behind the level, four parallax layers plus live clouds (numbers: design/run.yaml bg_*).
## Far to near: sky (bg_sky, a gradient strip, barely moves), clouds (drawn here, drift and wrap),
## hills (bg_hills), jungle (bg_jungle, lifted up behind the forest), forest (bg_forest, the nearest, reacts
## most). The higher the camera climbs above the lowest point of the level, the further the layers sink
## down the screen, so more sky shows.
## The art doesn't tile on its own, so every second copy is mirrored. Until the layers are built
## (art pipeline) the old single picture jungle.jpg is used instead.

const OLD_TEXTURE := preload("res://assets/backgrounds/jungle.jpg")
const FRAMES_PATH := "res://assets/sprites/%s_frames.tres"
const CLOUD_LIT := Color("e2f0fa")
const CLOUD_BODY := Color("bcdcf4")
const CLOUD_SHADE := Color("94bee2")

var _camera: Camera2D
var _canvas: Node2D
var _sky: Texture2D
var _hills: Texture2D
var _forest: Texture2D
var _jungle: Texture2D
var _hills_fill := Color("263e52")
var _jungle_fill := Color("0e1a24")
var _clouds: Array[Dictionary] = []  # {tex, x (layer space), y (screen, ground level), v}
var _fog: Array[Dictionary] = []  # {tex, x, lift (px above the layer's bottom), v, layer 0..2}
var _time := 0.0
const FOG_TINT := Color(0.74, 0.84, 0.88)


func _init() -> void:
	layer = -10
	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_background)
	add_child(_canvas)
	_sky = _layer("bg_sky")
	_hills = _layer("bg_hills")
	_forest = _layer("bg_forest")
	_jungle = _layer("bg_jungle")
	if _hills:
		_hills_fill = _bottom_colour(_hills, _hills_fill)
	if _jungle:
		_jungle_fill = _bottom_colour(_jungle, _jungle_fill)
	if _sky and _hills and _forest and _jungle:
		_make_clouds()
		_make_fog()
	else:
		_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func track(camera: Camera2D) -> void:
	_camera = camera


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()


func _layer(sheet: String) -> Texture2D:
	var path := FRAMES_PATH % sheet
	if not ResourceLoader.exists(path):
		return null
	var frames: SpriteFrames = load(path)
	return frames.get_frame_texture("layer", 0)


func _bottom_colour(tex: Texture2D, fallback: Color) -> Color:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return fallback
	return img.get_pixel(0, img.get_height() - 1)


func _draw_background() -> void:
	var view := get_viewport().get_visible_rect().size
	var cam_x := 0.0
	var climb := 0.0
	if _camera:
		var centre := _camera.get_screen_center_position()
		cam_x = centre.x - view.x / 2.0
		climb = maxf(0.0, (_camera.limit_bottom - view.y / 2.0) - centre.y)
	if not (_sky and _hills and _forest and _jungle):
		_draw_old(view, cam_x)
		return
	var run := GameData.RUN
	_draw_strip(_sky, floorf(cam_x * run.bg_sky_parallax), 0.0, view, true, false)
	_draw_clouds(view, cam_x * run.bg_cloud_parallax, climb * run.bg_cloud_sink)
	# A layer's bottom never rises above the bottom of the screen, so nothing flat shows under it.
	var hills_bottom: float = view.y + climb * run.bg_hills_sink
	_draw_strip(_hills, cam_x * run.bg_hills_parallax, hills_bottom - _hills.get_height(), view, false)
	_draw_fog(0, view, cam_x * run.bg_hills_parallax, hills_bottom)
	var forest_bottom: float = view.y + climb * run.bg_forest_sink
	# The jungle is lifted 80 px so its tree tops rise above the forest; the clamp keeps its solid bottom behind
	# the forest's solid part, so no flat colour or hills show through the forest's holes.
	var jungle_bottom := maxf(view.y - 80.0 + climb * run.bg_jungle_sink, forest_bottom - 80.0)
	_draw_strip(_jungle, cam_x * run.bg_jungle_parallax, jungle_bottom - _jungle.get_height(), view, false)
	_draw_fog(1, view, cam_x * run.bg_jungle_parallax, jungle_bottom)
	_draw_strip(_forest, cam_x * run.bg_forest_parallax, forest_bottom - _forest.get_height(), view, false)


## A layer tiled sideways at its own pixel size, every second copy mirrored. `stretch` scales it to the
## full screen height (the sky strip).
func _draw_strip(tex: Texture2D, scroll: float, top: float, view: Vector2, stretch: bool, mirror := true) -> void:
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	if stretch:  # only taller, never wider: the copies must butt exactly on whole pixels
		h = view.y
	var first := floori(scroll / w)
	var count := ceili(view.x / w) + 2
	for i in range(first, first + count):
		var x := roundf(i * w - scroll)
		if mirror and i % 2 != 0:  # mirrored copy: flip the drawing space around its right edge
			_canvas.draw_set_transform(Vector2(x + w, roundf(top)), 0.0, Vector2(-1.0, 1.0))
		else:
			_canvas.draw_set_transform(Vector2(x, roundf(top)), 0.0, Vector2.ONE)
		_canvas.draw_texture_rect(tex, Rect2(0.0, 0.0, w, h), false)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fill_below(y: float, view: Vector2, colour: Color) -> void:
	if y < view.y:
		_canvas.draw_rect(Rect2(0.0, roundf(y), view.x, view.y - roundf(y) + 1.0), colour)


func _draw_old(view: Vector2, cam_x: float) -> void:
	var scale := view.y / OLD_TEXTURE.get_height()
	var tile_w := OLD_TEXTURE.get_width() * scale
	var scroll := cam_x * GameData.RUN.background_parallax
	var first := floori(scroll / tile_w)
	for i in range(first, first + 3):  # tile_w >= view.x, so two tiles always cover; the third is margin
		var x := roundf(i * tile_w - scroll)
		var rect := Rect2(x, 0.0, tile_w, view.y)
		if i % 2 != 0:  # mirrored copy: negative width flips it
			rect = Rect2(x + tile_w, 0.0, -tile_w, view.y)
		_canvas.draw_texture_rect(OLD_TEXTURE, rect, false)


# --- clouds -------------------------------------------------------------------------------------

func _make_clouds() -> void:
	var run := GameData.RUN
	var view := Vector2(480.0, 270.0)
	for i in int(run.bg_cloud_count) + int(run.bg_wisp_count):
		var wisp: bool = i >= int(run.bg_cloud_count)
		var w := randi_range(6, 14) if wisp else randi_range(24, 110)
		var tex := _cloud_texture(w)
		var speed: float = run.bg_cloud_drift * randf_range(0.2, 1.0) * (1.0 if randf() < 0.5 else -1.0)
		var bottom: float = randf_range(run.bg_cloud_top + tex.get_height(), run.bg_cloud_bottom)
		_clouds.append({"tex": tex, "x": randf() * (view.x + 160.0), "y": bottom - tex.get_height(), "v": speed})


func _draw_clouds(view: Vector2, scroll: float, sink: float) -> void:
	var span := view.x + 160.0  # clouds wrap inside this width, so one leaves one side as another enters
	for c in _clouds:
		var tex: Texture2D = c.tex
		var x := fposmod(c.x + _time * c.v - scroll, span + tex.get_width()) - tex.get_width() - 80.0
		_canvas.draw_texture(tex, Vector2(roundf(x), roundf(c.y + sink)))


## One cloud: a cluster of round puffs (bigger in the middle, smaller at the sides) with a flat bottom,
## in three flat tones - lit top, body, shadow band along the bottom. Hard edges, no outline.
func _cloud_texture(w: int) -> ImageTexture:
	var biggest := maxi(3, int(w * randf_range(0.22, 0.34)))
	var h := int(biggest * 1.5) + 1
	var mask := PackedByteArray()
	mask.resize(w * h)
	var puffs := maxi(2, int(w / 14.0) + randi_range(0, 2))
	for p in puffs:
		var t := (p + randf_range(-0.3, 0.3)) / maxf(1.0, puffs - 1.0)
		var cx := lerpf(biggest * 0.6, w - biggest * 0.6, clampf(t, 0.0, 1.0))
		var mid := 1.0 - absf(cx / w - 0.5) * 1.6  # bigger puffs toward the middle
		var r := maxf(2.0, biggest * clampf(mid, 0.35, 1.0) * randf_range(0.7, 1.0))
		var cy := h - r * randf_range(0.7, 1.0)  # sits on the flat bottom
		for y in h:
			for x in w:
				if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
					mask[y * w + x] = 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var shade_rows := maxi(1, int(h * 0.22))
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			var lit := true  # lit where the cloud is open to the sky 2 px above
			for k in 2:
				if y - 1 - k >= 0 and mask[(y - 1 - k) * w + x] == 1:
					lit = false
			var col := CLOUD_BODY
			if y >= h - shade_rows:
				col = CLOUD_SHADE
			elif lit:
				col = CLOUD_LIT
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# --- mist ---------------------------------------------------------------------------------------

## Mist banks for the three depth layers. The far ones sit high up behind the hills and are faint; the near
## ones hug the ground in front of the forest and are the thickest.
func _make_fog() -> void:
	var run := GameData.RUN
	var lifts := [Vector2(75.0, 125.0), Vector2(60.0, 110.0), Vector2(42.0, 92.0)]  # how far above the layer's bottom, per layer
	for layer in 2:  # only the two far layers - none in front of the nearest forest
		for i in int(run.bg_fog_count):
			var w := randi_range(200, 420)
			_fog.append({
				"tex": _fog_texture(w, randi_range(40, 70)),
				"x": randf() * (480.0 + 300.0),
				"lift": randf_range(lifts[layer].x, lifts[layer].y),
				"v": run.bg_fog_drift * randf_range(0.2, 1.0) * (1.0 if randf() < 0.5 else -1.0),
				"layer": layer,
			})


func _draw_fog(layer: int, view: Vector2, scroll: float, bottom: float) -> void:
	var run := GameData.RUN
	var span := view.x + 300.0  # banks wrap inside this width, one leaving as another enters
	var strength: float = run.bg_fog_alpha * [0.5, 0.75, 1.0][layer]
	for f in _fog:
		if f.layer != layer:
			continue
		var tex: Texture2D = f.tex
		var x := fposmod(f.x + _time * f.v - scroll, span + tex.get_width()) - tex.get_width() - 150.0
		var y: float = bottom - f.lift - tex.get_height()
		_canvas.draw_texture(tex, Vector2(roundf(x), roundf(y)), Color(FOG_TINT, strength))


## One bank: a few big overlapping ellipses that thin out smoothly toward their edges (eight steps, so there is no
## outline to see) and toward the top, so the mist lies low and has no shape of its own.
func _fog_texture(w: int, h: int) -> ImageTexture:
	var level := PackedFloat32Array()
	level.resize(w * h)
	for blob in randi_range(4, 6):
		var rx := w * randf_range(0.25, 0.45)
		var ry := h * randf_range(0.45, 0.8)
		var cx := randf_range(rx * 0.6, w - rx * 0.6)
		var cy := h * randf_range(0.6, 0.85)  # the heavy part sits low
		var weight := randf_range(0.5, 1.0)
		for y in h:
			for x in w:
				var d := pow((x + 0.5 - cx) / rx, 2.0) + pow((y + 0.5 - cy) / ry, 2.0)
				if d < 1.0:
					level[y * w + x] = maxf(level[y * w + x], pow(1.0 - d, 1.6) * weight)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var step := roundf(level[y * w + x] * 8.0)
			if step > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, step / 8.0))
	return ImageTexture.create_from_image(img)
