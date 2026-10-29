class_name PauseMenu
extends CanvasLayer
## Pause button in the top-right corner (click, tap, Esc or P) and its menu: resume, restart the
## run, or go back to the character select screen. Runs while the tree is paused.

var VIEW := Screen.view()
var BUTTON := Rect2(Screen.view().x - 34.0, 4, 28, 20)
const ITEMS := ["RESUME", "RESTART RUN", "SETTINGS", "TITLE SCREEN"]
const ITEM_SIZE := Vector2(160, 22)
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")

var _open := false
var _index := 0
var _canvas: Control
var _title: PixelText
var _labels: Array[PixelText] = []
var _settings: CanvasLayer  # the SETTINGS screen while it is open on top of this menu


func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	_title = PixelText.make(Vector2(VIEW.x / 2.0, 70), PixelText.Align.CENTER, 3)
	_title.text = "PAUSED"
	_title.color = YELLOW
	_title.visible = false
	_canvas.add_child(_title)
	for i in ITEMS.size():
		var label := PixelText.make(_item_rect(i).position + Vector2(ITEM_SIZE.x / 2.0, 8), PixelText.Align.CENTER, 1)
		label.text = ITEMS[i]
		label.visible = false
		_canvas.add_child(label)
		_labels.append(label)


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false


func _item_rect(i: int) -> Rect2:
	return Rect2(Vector2((VIEW.x - ITEM_SIZE.x) / 2.0, 104 + i * (ITEM_SIZE.y + 6)), ITEM_SIZE)


func _set_open(open: bool) -> void:
	_open = open
	_index = 0
	get_tree().paused = open
	_title.visible = open
	for label in _labels:
		label.visible = open
	TouchControls.release_all()
	_refresh()


func _input(event: InputEvent) -> void:
	if _settings != null and is_instance_valid(_settings):
		return  # the settings screen has the input
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key == KEY_ESCAPE or key == KEY_P:
			_set_open(not _open)
			get_viewport().set_input_as_handled()
		elif _open and (key == KEY_DOWN or key == KEY_S):
			_index = (_index + 1) % ITEMS.size()
			_refresh()
		elif _open and (key == KEY_UP or key == KEY_W):
			_index = (_index - 1 + ITEMS.size()) % ITEMS.size()
			_refresh()
		elif _open and (key == KEY_ENTER or key == KEY_J or key == KEY_SPACE):
			_choose(_index)
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_set_open(not _open)
		return
	# a tap also arrives as an emulated mouse click, so only mouse clicks are handled here
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _open:
			if BUTTON.grow(3.0).has_point(event.position):
				_set_open(true)
			return
		for i in ITEMS.size():
			if _item_rect(i).has_point(event.position):
				_choose(i)
				break
	elif _open and event is InputEventMouseMotion:
		for i in ITEMS.size():
			if _item_rect(i).has_point(event.position) and _index != i:
				_index = i
				_refresh()


func _choose(i: int) -> void:
	var tree := get_tree()
	if i == 0:
		_set_open(false)
		return
	if i == 2:
		_open_settings()
		return
	_open = false
	tree.paused = false
	if i == 1:
		Run.go_to_start()
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file("res://scenes/title.tscn")


func _open_settings() -> void:
	_settings = CanvasLayer.new()
	_settings.layer = 102
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	var screen: Node2D = load("res://scenes/settings.tscn").instantiate()
	screen.overlay = true
	_settings.add_child(screen)
	add_child(_settings)


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].color = YELLOW if i == _index else Color("c9c7d6")
	_canvas.queue_redraw()


func _draw_all() -> void:
	if _open:
		_canvas.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.04, 0.03, 0.08, 0.7))
		for i in ITEMS.size():
			var r := _item_rect(i)
			_canvas.draw_rect(r, PANEL)
			_canvas.draw_rect(r, YELLOW if i == _index else Color(1, 1, 1, 0.25), false, 1.0)
	_canvas.draw_rect(BUTTON, Color(0.08, 0.06, 0.12, 0.7))
	_canvas.draw_rect(BUTTON, Color(1, 1, 1, 0.6), false, 1.0)
	if not _open:
		_canvas.draw_rect(Rect2(BUTTON.position + Vector2(9, 5), Vector2(3, 10)), Color.WHITE)
		_canvas.draw_rect(Rect2(BUTTON.position + Vector2(16, 5), Vector2(3, 10)), Color.WHITE)
