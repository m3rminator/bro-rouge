extends Node
## Registers input actions at startup (autoload). Bindings come from design/controls.yaml via GameData.


func _ready() -> void:
	for action in GameData.CONTROLS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in GameData.CONTROLS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
