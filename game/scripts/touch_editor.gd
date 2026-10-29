extends Node2D
## TOUCH LAYOUT (from the title screen): drag a touch button to move it, tap one and use SMALLER / BIGGER to
## resize it, RESET puts everything back, DONE goes back to the title. Every change is saved at once
## (user://touch_layout.cfg, scripts/touch_controls.gd).

const BACKDROP := preload("res://assets/backgrounds/jungle.jpg")
var VIEW := Screen.view()
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")
const STEP := 0.1
const LABELS := ["SMALLER", "BIGGER", "RESET", "DONE"]
const ITEM := Vector2(72, 18)

var _dragging := false
var _grab := Vector2.ZERO  # finger offset from the button's centre
var _hint: PixelText


func _ready() -> void:
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
	for i in LABELS.size():
		var r := _rect(i)
		var panel := ColorRect.new()
		panel.position = r.position
		panel.size = r.size
		panel.color = PANEL
		add_child(panel)
		var label := PixelText.make(r.position + Vector2(r.size.x / 2.0, 5), PixelText.Align.CENTER)
		label.text = LABELS[i]
		label.color = YELLOW if i == LABELS.size() - 1 else Color("c9c7d6")
		add_child(label)
	_hint = PixelText.make(Vector2(VIEW.x / 2.0, 40), PixelText.Align.CENTER)
	add_child(_hint)
	TouchControls.begin_edit()
	_refresh()


func _rect(i: int) -> Rect2:
	var total := LABELS.size() * ITEM.x + (LABELS.size() - 1) * 6.0
	return Rect2(Vector2((VIEW.x - total) / 2.0 + i * (ITEM.x + 6.0), 8), ITEM)


func _refresh() -> void:
	_hint.text = "DRAG A BUTTON TO MOVE IT" if TouchControls.selected == "" else "SELECTED: %s" % TouchControls.selected.to_upper().replace("_", " ")
	_hint.color = Color("f4f2e8")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_done()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			if _dragging:
				TouchControls.save_layout()
			_dragging = false
	elif event is InputEventMouseMotion and _dragging and TouchControls.selected != "":
		TouchControls.move_button(TouchControls.selected, event.position + _grab)


func _press(at: Vector2) -> void:
	for i in LABELS.size():
		if _rect(i).has_point(at):
			_action(i)
			return
	var hit := TouchControls.hit_test(at)
	TouchControls.selected = hit
	if hit != "":
		_dragging = true
		_grab = TouchControls.rect_of(hit).get_center() - at
	TouchControls.redraw()
	_refresh()


func _action(i: int) -> void:
	var sel := TouchControls.selected
	match i:
		0:
			if sel != "":
				TouchControls.scale_button(sel, -STEP)
		1:
			if sel != "":
				TouchControls.scale_button(sel, STEP)
		2:
			TouchControls.reset_layout()
		3:
			_done()
			return
	TouchControls.save_layout()


func _done() -> void:
	TouchControls.save_layout()
	TouchControls.end_edit()
	get_tree().change_scene_to_file("res://scenes/title.tscn")
