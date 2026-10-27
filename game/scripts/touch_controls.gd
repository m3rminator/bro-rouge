extends CanvasLayer
## On-screen touch buttons (autoload). Drawn from art/sprites/touch.yaml. Each button presses the
## same input action the keyboard does, so the game code does not know the difference.
## Shown on a touchscreen; hidden as soon as a key or gamepad is used (so they never cover the
## view while testing on a PC); a touch shows them again. F10 toggles them by hand on a PC
## (the mouse then acts as a finger).
## The player can move and resize every button (title screen, TOUCH LAYOUT: scripts/touch_editor.gd);
## the layout is saved in user://touch_layout.cfg. The buttons are drawn see-through so the game shows behind them.
## Touch is the main way to play (the game ships on phones), but the buttons only belong to the fight: they
## vanish while the tree is paused (pause menu, Bro cards) and on every screen that is not the level (title).

const FRAMES := preload("res://assets/sprites/touch_frames.tres")
const SAVE_PATH := "user://touch_layout.cfg"
const ALPHA := 0.45  # buttons at rest
const ALPHA_HELD := 0.7  # while a finger is on one
const SCALE_MIN := 0.5
const SCALE_MAX := 1.8
## button -> [default hit rect in 480x270 screen pixels, animation (the pressed look is "<name>_held"), input action].
## "fire" is the shoot button; while the Bro stands at something to use it becomes the hand and presses "interact".
## "crouch" sits above and between the two walk buttons (the left arrow turned to point down).
const BUTTONS := {
	"move_left": [Rect2(8, 214, 48, 48), "left", "move_left"],
	"move_right": [Rect2(62, 214, 48, 48), "right", "move_right"],
	"crouch": [Rect2(35, 160, 48, 48), "left", "crouch"],
	"fire": [Rect2(406, 200, 60, 60), "shoot", "shoot"],
	"jump": [Rect2(412, 146, 48, 48), "jump", "jump"],
	"knife": [Rect2(352, 168, 48, 48), "knife", "knife"],
	"grenade": [Rect2(352, 220, 48, 44), "grenade", "grenade"],
	"reload": [Rect2(390, 88, 48, 48), "reload", "reload"],
}
const VIEW := Vector2(480, 270)

var selected := ""  # the button being edited (drawn with an outline)
var editing := false  # the layout editor is open: touches move buttons instead of pressing them

var _canvas: Control
var _fingers := {}  # finger index -> [button, input action it presses]
var _forced := false
var _centers := {}  # button -> Vector2 centre the player moved it to
var _scales := {}  # button -> float size factor
var _was_visible := false
var _hidden := false  # a menu is open: no buttons drawn and no touch presses them


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	_canvas.visible = DisplayServer.is_touchscreen_available()
	_load()


## Show the buttons on a PC by hand (the mouse then acts as a finger); also F10 and the
## TOUCH button on the title screen.
func toggle_forced() -> void:
	_forced = not _forced
	_canvas.visible = _forced
	if not _forced:
		_release_all()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var menu := get_tree().paused or scene == null or not scene.scene_file_path.ends_with("main.tscn")
	var hide := menu and not editing
	if hide == _hidden:
		return
	_hidden = hide
	_canvas.modulate.a = 0.0 if hide else 1.0
	if hide:
		_release_all()


func is_shown() -> bool:
	return _canvas.visible


func release_all() -> void:
	_release_all()


# ---------------------------------------------------------------- layout

## Where `button` is now (the player's layout over the default).
func rect_of(button: String) -> Rect2:
	var base: Rect2 = BUTTONS[button][0]
	var size := base.size * float(_scales.get(button, 1.0))
	var center: Vector2 = _centers.get(button, base.get_center())
	return Rect2(center - size / 2.0, size)


## The button under `at` (screen pixels), or "".
func hit_test(at: Vector2) -> String:
	var found := ""
	for button in BUTTONS:
		if rect_of(button).grow(4.0).has_point(at):
			found = button
	return found


func move_button(button: String, center: Vector2) -> void:
	var half := rect_of(button).size / 2.0
	_centers[button] = center.clamp(half, VIEW - half)
	_canvas.queue_redraw()


func scale_button(button: String, change: float) -> void:
	var s := clampf(float(_scales.get(button, 1.0)) + change, SCALE_MIN, SCALE_MAX)
	_scales[button] = s
	move_button(button, rect_of(button).get_center())  # keep it on screen after growing


func redraw() -> void:
	_canvas.queue_redraw()


func reset_layout() -> void:
	_centers.clear()
	_scales.clear()
	save_layout()
	_canvas.queue_redraw()


func save_layout() -> void:
	var file := ConfigFile.new()
	for button in BUTTONS:
		if _centers.has(button) or _scales.has(button):
			var c: Vector2 = rect_of(button).get_center()
			file.set_value(button, "x", c.x)
			file.set_value(button, "y", c.y)
			file.set_value(button, "scale", float(_scales.get(button, 1.0)))
	file.save(SAVE_PATH)


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for button in BUTTONS:
		if file.has_section(button):
			_centers[button] = Vector2(file.get_value(button, "x"), file.get_value(button, "y"))
			_scales[button] = clampf(float(file.get_value(button, "scale", 1.0)), SCALE_MIN, SCALE_MAX)


## The editor takes over: buttons are shown whatever the device and touches no longer press them.
func begin_edit() -> void:
	_release_all()
	editing = true
	_was_visible = _canvas.visible
	_canvas.visible = true
	selected = ""
	_canvas.queue_redraw()


func end_edit() -> void:
	editing = false
	selected = ""
	_canvas.visible = _was_visible
	_canvas.queue_redraw()


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if editing or _hidden:
		return
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_F10:
			toggle_forced()
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
	var now := hit_test(at) if down else ""
	var before: String = _fingers[index][0] if _fingers.has(index) else ""
	if now == before:
		return
	if before != "":
		_hold(_fingers[index][1], false)
		_fingers.erase(index)
	if now != "":
		var action: String = BUTTONS[now][2]
		if now == "fire" and _something_to_use():
			action = "interact"
		_fingers[index] = [now, action]
		_hold(action, true)
	_canvas.queue_redraw()


## True while the Bro stands at a hub station he can use.
func _something_to_use() -> bool:
	for station in get_tree().get_nodes_in_group("hub_stations"):
		if station.in_reach:
			return true
	return false


func _hold(action: String, held: bool) -> void:
	if held:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for index in _fingers:
		_hold(_fingers[index][1], false)
	_fingers.clear()
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_buttons() -> void:
	var use := _something_to_use() and not editing
	var holding := []
	for finger in _fingers.values():
		holding.append(finger[0])
	for button in BUTTONS:
		var rect := rect_of(button)
		var anim: String = BUTTONS[button][1]
		if button == "fire" and use:
			anim = "hand"
		var held := holding.has(button)
		if held:
			anim += "_held"
		var tex := FRAMES.get_frame_texture(anim, 0)
		var factor := float(_scales.get(button, 1.0))
		var turn := -PI / 2.0 if button == "crouch" else 0.0
		_canvas.draw_set_transform(rect.get_center().round(), turn, Vector2(factor, factor))
		_canvas.draw_texture(tex, -tex.get_size() / 2.0, Color(1, 1, 1, ALPHA_HELD if held else ALPHA))
		_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if editing and button == selected:
			_canvas.draw_rect(rect.grow(2.0), Color("ffd23e"), false, 1.0)
