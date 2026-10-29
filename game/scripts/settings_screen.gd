extends Node2D
## SETTINGS (from the title screen and the pause menu): the picture quality (how many particles and how much of them can be
## alive at once, scripts/quality.gd), the frame rate and the two volumes (SFX and MUSIC, scripts/volume.gd).
## Up/Down choose, Left/Right/Enter change, a tap on a row changes it, a tap or drag on a volume bar sets it.
## Every change is saved at once. `overlay` (set by the pause menu) makes BACK close this screen instead of going to the title.

const BACKDROP := preload("res://assets/backgrounds/jungle.jpg")
const MUSIC := "res://assets/music/level_jungle.ogg"
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")
const ITEM_SIZE := Vector2(190, 24)
const COUNT := 5
const SFX_ROW := 2
const MUSIC_ROW := 3
const HINTS := [
	"FEWER PARTICLES AND LESS BLOOD. BEST FOR OLD PHONES",
	"A GOOD LOOK THAT RUNS WELL ON MOST PHONES",
	"EVERYTHING. CAN SLOW DOWN A PHONE",
]

var VIEW := Screen.view()
var overlay := false
var _index := 0
var _labels: Array[PixelText] = []
var _frames: Array[ColorRect] = []
var _fills: Array[ColorRect] = []  # the bars of the two volume rows
var _hint: PixelText
var _held := false
var _side_held := false
var _enter_held := true  # Enter may still be down from the menu that opened this screen
var _going := false
var _drag := -1
var _blip: AudioStreamPlayer
var _song: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Volume.ensure()
	Screen.relayout_on_resize(self)
	var back := Sprite2D.new()
	back.texture = BACKDROP
	back.centered = false
	back.scale = Vector2.ONE * maxf(VIEW.y / BACKDROP.get_height(), VIEW.x / BACKDROP.get_width())
	add_child(back)
	var shade := ColorRect.new()
	shade.size = VIEW
	shade.color = Color(0.05, 0.04, 0.09, 0.6)
	add_child(shade)
	var title := PixelText.make(Vector2(VIEW.x / 2.0, 24), PixelText.Align.CENTER, 4)
	title.text = "SETTINGS"
	title.color = YELLOW
	add_child(title)
	for i in COUNT:
		var r := _rect(i)
		var frame := ColorRect.new()
		frame.position = r.position - Vector2(2, 2)
		frame.size = r.size + Vector2(4, 4)
		add_child(frame)
		_frames.append(frame)
		var panel := ColorRect.new()
		panel.position = r.position
		panel.size = r.size
		panel.color = PANEL
		add_child(panel)
		var slider := i == SFX_ROW or i == MUSIC_ROW
		if slider:
			var track := ColorRect.new()
			track.position = r.position + Vector2(8, 17)
			track.size = Vector2(r.size.x - 16, 3)
			track.color = Color("0c0a14")
			add_child(track)
			var fill := ColorRect.new()
			fill.position = track.position
			fill.size = Vector2(0, 3)
			fill.color = YELLOW
			add_child(fill)
			_fills.append(fill)
		var label := PixelText.make(r.position + Vector2(r.size.x / 2.0, 5 if slider else 9), PixelText.Align.CENTER, 2 if not slider else 1)
		add_child(label)
		_labels.append(label)
	_hint = PixelText.make(Vector2(VIEW.x / 2.0, _rect(COUNT - 1).end.y + 16), PixelText.Align.CENTER, 1)
	_hint.color = Color("f4f2e8")
	add_child(_hint)
	_blip = AudioStreamPlayer.new()
	_blip.bus = Volume.SFX_BUS
	if ResourceLoader.exists("res://assets/sfx/block_hit.mp3"):
		_blip.stream = load("res://assets/sfx/block_hit.mp3")
	add_child(_blip)
	_refresh()


func _rect(i: int) -> Rect2:
	return Rect2(Vector2((VIEW.x - ITEM_SIZE.x) / 2.0, 52 + i * (ITEM_SIZE.y + 7)), ITEM_SIZE)


## The bar of a volume row (where a tap sets the value).
func _bar(i: int) -> Rect2:
	var r := _rect(i)
	return Rect2(r.position + Vector2(8, 10), Vector2(r.size.x - 16, 14))


func _refresh() -> void:
	var names := [
		"QUALITY: " + Quality.NAMES[Quality.level],
		"FRAME RATE: %d" % Quality.fps,
		"SOUND FX  %d" % roundi(Volume.sfx * 100.0),
		"MUSIC  %d" % roundi(Volume.music * 100.0),
		"BACK",
	]
	for i in COUNT:
		_labels[i].text = names[i]
		_labels[i].color = YELLOW if i == _index else Color("c9c7d6")
		_frames[i].color = YELLOW if i == _index else Color("14101e")
	_fills[0].size.x = (_rect(SFX_ROW).size.x - 16) * Volume.sfx
	_fills[1].size.x = (_rect(MUSIC_ROW).size.x - 16) * Volume.music
	if _index == 0:
		_hint.text = HINTS[Quality.level]
	elif _index == 1:
		_hint.text = "30 IS EASIER ON THE BATTERY AND THE HEAT"
	else:
		_hint.text = ""


func _process(_delta: float) -> void:
	if _going:
		return
	var down := Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)
	var up := Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)
	if (down or up) and not _held:
		_index = (_index + (1 if down else COUNT - 1)) % COUNT
		_refresh()
	_held = down or up
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
	if (right or left) and not _side_held:
		_step(1 if right else -1)
	_side_held = right or left
	var enter := Input.is_key_pressed(KEY_ENTER)
	if enter and not _enter_held:
		_change(_index)
	_enter_held = enter


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()
		return
	if _going:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag = -1
			return
		for i in COUNT:
			if _rect(i).has_point(event.position):
				_index = i
				if i == SFX_ROW or i == MUSIC_ROW:
					_drag = i
					_set_from_x(i, event.position.x)
				else:
					_change(i)
				if not _going:
					get_viewport().set_input_as_handled()
				return
	elif event is InputEventMouseMotion and _drag >= 0:
		_set_from_x(_drag, event.position.x)


func _set_from_x(i: int, x: float) -> void:
	var bar := _bar(i)
	var value := snappedf(clampf((x - bar.position.x) / bar.size.x, 0.0, 1.0), 0.05)
	_set_volume(i, value)


func _set_volume(i: int, value: float) -> void:
	if i == SFX_ROW:
		Volume.set_sfx(value)
		if _blip.stream != null and not _blip.playing:
			_blip.play()
	else:
		Volume.set_music(value)
		if _song == null and ResourceLoader.exists(MUSIC):  # a taste of the music while the bar moves
			_song = AudioStreamPlayer.new()
			var stream: AudioStreamOggVorbis = load(MUSIC)
			stream.loop = true
			_song.stream = stream
			_song.bus = Volume.MUSIC_BUS
			_song.volume_db = -12.0
			add_child(_song)
			_song.play()
	Volume.save()
	_refresh()


## Left/Right: a volume bar moves by a tenth; the other rows change like Enter.
func _step(way: int) -> void:
	if _index == SFX_ROW:
		_set_volume(SFX_ROW, snappedf(Volume.sfx + way * 0.1, 0.05))
	elif _index == MUSIC_ROW:
		_set_volume(MUSIC_ROW, snappedf(Volume.music + way * 0.1, 0.05))
	else:
		_change(_index)


func _change(i: int) -> void:
	if i == 0:
		Quality.set_level(Quality.level + 1)
	elif i == 1:
		Quality.set_fps(30 if Quality.fps == 60 else 60)
	elif i == COUNT - 1:
		_back()
		return
	_refresh()


func _back() -> void:
	_going = true
	if overlay:
		get_parent().queue_free()  # the pause menu's layer
	else:
		get_tree().change_scene_to_file("res://scenes/title.tscn")
