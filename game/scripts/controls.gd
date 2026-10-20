extends Node
## Registers input actions at startup (autoload), so key bindings live in one readable place.

const BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_W, KEY_UP, KEY_SPACE],
	"shoot": [KEY_J, KEY_X],
}


func _ready() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
