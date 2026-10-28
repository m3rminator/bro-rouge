extends Node2D
## The first screen: START (the starting zone), EXIT, and a switch for the on-screen touch controls.
## Up/Down (W/S) choose, Shoot / Jump / Enter take; a click or tap on a button takes it.

const BACKDROP := preload("res://assets/backgrounds/jungle.jpg")
var VIEW := Screen.view()
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")
const ITEM_SIZE := Vector2(150, 24)
const COUNT := 4

var _index := 0
var _labels: Array[PixelText] = []
var _frames: Array[ColorRect] = []
var _going := false
var _held := false


func _ready() -> void:
	var back := Sprite2D.new()
	back.texture = BACKDROP
	back.centered = false
	back.scale = Vector2.ONE * maxf(VIEW.y / BACKDROP.get_height(), VIEW.x / BACKDROP.get_width())
	add_child(back)
	var shade := ColorRect.new()
	shade.size = VIEW
	shade.color = Color(0.05, 0.04, 0.09, 0.55)
	add_child(shade)
	var title := PixelText.make(Vector2(VIEW.x / 2.0, 40), PixelText.Align.CENTER, 6)
	title.text = "BRO ROGUE"
	title.color = YELLOW
	add_child(title)
	if Run.best_level > 0:  # the furthest fight level of any run
		var best := PixelText.make(Vector2(VIEW.x / 2.0, 80), PixelText.Align.CENTER, 2)
		best.text = "BEST LEVEL %d" % Run.best_level
		best.color = Color("f4f2e8")
		add_child(best)
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
		var label := PixelText.make(r.position + Vector2(r.size.x / 2.0, 9), PixelText.Align.CENTER, 2)
		add_child(label)
		_labels.append(label)
	_refresh()


func _rect(i: int) -> Rect2:
	return Rect2(Vector2((VIEW.x - ITEM_SIZE.x) / 2.0, 100 + i * (ITEM_SIZE.y + 8)), ITEM_SIZE)


func _refresh() -> void:
	var names := ["START", "EXIT", "TOUCH: " + ("ON" if TouchControls.is_shown() else "OFF"), "TOUCH LAYOUT"]
	for i in COUNT:
		_labels[i].text = names[i]
		_labels[i].color = YELLOW if i == _index else Color("c9c7d6")
		_frames[i].color = YELLOW if i == _index else Color("14101e")


func _process(_delta: float) -> void:
	if _going:
		return
	var down := Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S)
	var up := Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)
	if (down or up) and not _held:
		_index = (_index + (1 if down else COUNT - 1)) % COUNT
		_refresh()
	_held = down or up
	if Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_ENTER):
		_choose(_index)


func _input(event: InputEvent) -> void:
	if _going or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for i in COUNT:
		if _rect(i).has_point(event.position):
			_index = i
			var viewport := get_viewport()  # _choose may switch scenes, which takes this node out of the tree
			_choose(i)
			viewport.set_input_as_handled()
			return


func _choose(i: int) -> void:
	if i == 0:
		_going = true
		Run.go_to_start()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	elif i == 1:
		_going = true
		get_tree().quit()
	elif i == 3:
		_going = true
		get_tree().change_scene_to_file("res://scenes/touch_editor.tscn")
	else:
		TouchControls.toggle_forced()
		_refresh()
