extends CanvasLayer
## On-screen touch buttons (autoload). Plain placeholder shapes for now. Each button presses the
## same input action the keyboard does, so the game code does not know the difference.
## Shown on a touchscreen; hidden as soon as a key or gamepad is used (so they never cover the
## view while testing on a PC); a touch shows them again. F10 toggles them by hand on a PC
## (the mouse then acts as a finger).

## action -> [rect in 480x270 screen pixels, label]
const BUTTONS := {
	"move_left": [Rect2(8, 212, 48, 48), "<"],
	"move_right": [Rect2(62, 212, 48, 48), ">"],
	"crouch": [Rect2(35, 160, 48, 44), "v"],
	"shoot": [Rect2(408, 198, 64, 62), "FIRE"],
	"jump": [Rect2(340, 214, 56, 46), "JUMP"],
	"grenade": [Rect2(416, 132, 52, 52), "NADE"],
	"knife": [Rect2(352, 160, 48, 44), "KNIFE"],
	"reload": [Rect2(290, 224, 40, 36), "R"],
	"interact": [Rect2(200, 224, 52, 36), "USE"],
}

var _canvas: Control
var _fingers := {}  # finger index -> action it is holding
var _forced := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	_canvas.visible = DisplayServer.is_touchscreen_available()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_F10:
			_forced = not _forced
			_canvas.visible = _forced
			if not _forced:
				_release_all()
			return
		if not _forced:
			_canvas.visible = false
			_release_all()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_canvas.visible = false
		_release_all()
		return
	if event is InputEventScreenTouch:
		_canvas.visible = true
		_finger(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag and _canvas.visible:
		_finger(event.index, event.position, true)
	elif _forced and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_finger(-1, event.position, event.pressed)
	elif _forced and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_finger(-1, event.position, true)


## A finger went down, moved or lifted at `at`: it holds whichever button is under it.
func _finger(index: int, at: Vector2, down: bool) -> void:
	var now := ""
	if down:
		for action in BUTTONS:
			if BUTTONS[action][0].grow(4.0).has_point(at):
				now = action
				break
	var before: String = _fingers.get(index, "")
	if now == before:
		return
	if before != "":
		_hold(before, false)
	if now != "":
		_fingers[index] = now
		_hold(now, true)
	else:
		_fingers.erase(index)
	_canvas.queue_redraw()


func _hold(action: String, held: bool) -> void:
	if held:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for index in _fingers:
		_hold(_fingers[index], false)
	_fingers.clear()
	_canvas.queue_redraw()


func _draw_buttons() -> void:
	var font := ThemeDB.fallback_font
	for action in BUTTONS:
		var rect: Rect2 = BUTTONS[action][0]
		var held := _fingers.values().has(action)
		_canvas.draw_rect(rect, Color(1, 1, 1, 0.45 if held else 0.18))
		_canvas.draw_rect(rect, Color(1, 1, 1, 0.6), false, 1.0)
		_canvas.draw_string(font, rect.position + Vector2(0, rect.size.y / 2.0 + 4.0), BUTTONS[action][1], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, Color(1, 1, 1, 0.9))
