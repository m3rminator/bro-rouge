class_name BroPicker
extends CanvasLayer
## Deals Bro cards over the paused game: Left/Right (A/D) choose, Shoot / Jump / Interact / Enter take the
## highlighted one, a tap or click on a card takes it at once. Emits `chosen(id)` and goes away.
## Used when a run starts (every Bro, none random) and by crates that offer another Bro.

signal chosen(id: String)

const VIEW := Vector2(480, 270)
const GAP := 8.0
const TOP := 70.0

var _ids: Array = []
var _current := ""  # the Bro he plays now (marked), when this is an offer
var _heading := ""
var _index := 0
var _cards: Array[Node2D] = []
var _scale := 1.0  # cards shrink so all of them fit on the screen
var _age := 0.0
var _done := false


## Opens the picker under `parent`; `await picker.chosen` for the id.
static func open(parent: Node, ids: Array, heading: String, current := "") -> BroPicker:
	var picker := BroPicker.new()
	picker._ids = ids
	picker._heading = heading
	picker._current = current
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
	var title := PixelText.make(Vector2(VIEW.x / 2.0, 30), PixelText.Align.CENTER, 2)
	title.text = _heading
	title.color = CharacterCards.YELLOW
	add_child(title)
	var n := _ids.size()
	_scale = minf(1.0, (VIEW.x - 2.0 * GAP - GAP * (n - 1)) / (CharacterCards.CARD.x * n))
	var card_w := CharacterCards.CARD.x * _scale
	var left := (VIEW.x - (card_w * n + GAP * (n - 1))) / 2.0
	for i in n:
		var card := CharacterCards.build(_ids[i], Vector2(left + i * (card_w + GAP), TOP))
		card.scale = Vector2(_scale, _scale)
		add_child(card)
		_cards.append(card)
		if _ids[i] == _current:
			var tag := PixelText.make(Vector2(CharacterCards.CARD.x / 2.0, -12), PixelText.Align.CENTER, 1)
			tag.text = "YOUR BRO"
			tag.color = Color("6fd06f")
			card.add_child(tag)
	_index = _ids.size() / 2
	_refresh()


func _exit_tree() -> void:
	if not _done:
		get_tree().paused = false


func _card_rect(i: int) -> Rect2:
	return Rect2(_cards[i].position, CharacterCards.CARD * _scale)


func _process(delta: float) -> void:
	_age += delta
	if _done or _age < 0.25:
		return
	if Input.is_action_just_pressed("move_left"):
		_index = (_index - 1 + _ids.size()) % _ids.size()
		_refresh()
	elif Input.is_action_just_pressed("move_right"):
		_index = (_index + 1) % _ids.size()
		_refresh()
	elif Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_ENTER):
		_take(_index)


func _input(event: InputEvent) -> void:
	# a tap also arrives as an emulated mouse click, so only mouse clicks are handled here
	if _done or _age < 0.25 or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for i in _cards.size():
		if _card_rect(i).has_point(event.position):
			var viewport := get_viewport()
			_take(i)
			viewport.set_input_as_handled()
			return


func _take(i: int) -> void:
	_done = true
	get_tree().paused = false
	chosen.emit(_ids[i])
	queue_free()


func _refresh() -> void:
	for i in _cards.size():
		var picked := i == _index
		_cards[i].get_node("Frame").color = CharacterCards.YELLOW if picked else CharacterCards.OUTLINE
		_cards[i].modulate = Color.WHITE if picked else Color(0.62, 0.62, 0.68)
