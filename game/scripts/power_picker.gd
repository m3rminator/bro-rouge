class_name PowerPicker
extends CanvasLayer
## Deals three power-up cards over the paused game (the safe house's power station): Left/Right (A/D) choose,
## Shoot / Jump / Interact / Enter take the highlighted one, a tap or click on a card takes it at once.
## Emits `chosen(kind)` and goes away. The kinds are the keys of Run.perks (see Run.bro_stats): permanent for the run.

signal chosen(kind: String)

var VIEW := Screen.view()
const CARD := Vector2(120, 110)
const GAP := 12.0
const TOP := 80.0
const YELLOW := Color("ffd23e")
const PANEL := Color("23202f")
const OUTLINE := Color("14101e")
const INFO := {
	"heart": ["EXTRA HEART", "ONE MORE", "HEART FOR", "THE RUN"],
	"spare": ["SPARE BELT", "ONE MORE", "SPARE MAG", "AND ROOM"],
	"grenade": ["GRENADE", "CARRY ONE", "MORE", "GRENADE"],
	"size": ["BIG MAGAZINE", "MAGAZINES", "HOLD 15", "PERCENT MORE"],
	"rate": ["TRIGGER", "FIRES 10", "PERCENT", "FASTER"],
	"speed": ["LEGS", "RUNS 6", "PERCENT", "FASTER"],
	"damage": ["ROUNDS", "HITS 15", "PERCENT", "HARDER"],
	"jump": ["SPRING", "JUMPS 5", "PERCENT", "HIGHER"],
	"reload": ["QUICK HANDS", "RELOAD 12", "PERCENT", "FASTER"],
}

var _kinds: Array = []
var _heading := ""
var _index := 0
var _frames: Array[ColorRect] = []
var _age := 0.0
var _done := false


## Opens the picker under `parent`; `await picker.chosen` for the kind.
static func open(parent: Node, kinds: Array, heading: String) -> PowerPicker:
	var picker := PowerPicker.new()
	picker._kinds = kinds
	picker._heading = heading
	parent.add_child(picker)
	return picker


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	TouchControls.release_all()
	var shade := ColorRect.new()
	shade.size = VIEW
	shade.color = Color(0.04, 0.03, 0.08, 0.82)
	add_child(shade)
	var title := PixelText.make(Vector2(VIEW.x / 2.0, 36), PixelText.Align.CENTER, 2)
	title.text = _heading
	title.color = YELLOW
	add_child(title)
	var n := _kinds.size()
	var left := (VIEW.x - (CARD.x * n + GAP * (n - 1))) / 2.0
	for i in n:
		var at := Vector2(left + i * (CARD.x + GAP), TOP)
		var frame := ColorRect.new()
		frame.position = at - Vector2(2, 2)
		frame.size = CARD + Vector2(4, 4)
		add_child(frame)
		_frames.append(frame)
		var panel := ColorRect.new()
		panel.position = at
		panel.size = CARD
		panel.color = PANEL
		add_child(panel)
		var lines: Array = INFO[_kinds[i]]
		var head := PixelText.make(at + Vector2(CARD.x / 2.0, 14), PixelText.Align.CENTER, 2)
		head.text = lines[0]
		head.color = YELLOW
		add_child(head)
		for k in range(1, lines.size()):
			var line := PixelText.make(at + Vector2(CARD.x / 2.0, 44 + (k - 1) * 12), PixelText.Align.CENTER, 1)
			line.text = lines[k]
			line.color = Color("c9c7d6")
			add_child(line)
	_index = n / 2
	_refresh()


func _exit_tree() -> void:
	if not _done:
		get_tree().paused = false


func _rect(i: int) -> Rect2:
	var n := _kinds.size()
	var left := (VIEW.x - (CARD.x * n + GAP * (n - 1))) / 2.0
	return Rect2(Vector2(left + i * (CARD.x + GAP), TOP), CARD)


func _process(delta: float) -> void:
	_age += delta
	if _done or _age < 0.25:
		return
	if Input.is_action_just_pressed("move_left"):
		_index = (_index - 1 + _kinds.size()) % _kinds.size()
		_refresh()
	elif Input.is_action_just_pressed("move_right"):
		_index = (_index + 1) % _kinds.size()
		_refresh()
	elif Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_ENTER):
		_take(_index)


func _input(event: InputEvent) -> void:
	# a tap also arrives as an emulated mouse click, so only mouse clicks are handled here
	if _done or _age < 0.25 or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for i in _kinds.size():
		if _rect(i).has_point(event.position):
			var viewport := get_viewport()
			_take(i)
			viewport.set_input_as_handled()
			return


func _take(i: int) -> void:
	_done = true
	get_tree().paused = false
	chosen.emit(_kinds[i])
	queue_free()


func _refresh() -> void:
	for i in _frames.size():
		_frames[i].color = YELLOW if i == _index else OUTLINE
